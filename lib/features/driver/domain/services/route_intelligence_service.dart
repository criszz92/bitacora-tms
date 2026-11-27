import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class RouteIntelligenceReport {
  final double estimatedTruckMinutes;
  final double congestionFactor; // 1.0 = fluido, >1.25 = congestión
  final int activeIncidentsCount;
  final int historicalSamplesCount;
  final double routeScore; // 0 a 100
  final bool recommendAlternative;
  final String summaryReason;

  const RouteIntelligenceReport({
    required this.estimatedTruckMinutes,
    required this.congestionFactor,
    required this.activeIncidentsCount,
    this.historicalSamplesCount = 0,
    required this.routeScore,
    required this.recommendAlternative,
    this.summaryReason = '',
  });
}

/// Motor de análisis inteligente de rutas para transporte pesado:
/// - Aprende velocidad real de camiones desde `viajes` históricos.
/// - Consulta incidencias activas de la flota en `incidencias_ruta`.
/// - Calcula ETA real de camión según franja horaria, día e incidencias.
/// - Detecta desvíos reales midiendo distancia perpendicular por segmento.
class RouteIntelligenceService {
  static const Distance _distance = Distance();
  final FirebaseFirestore _firestore;

  RouteIntelligenceService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Consulta la velocidad media histórica (km/h) de la flota para un corredor.
  Future<({double? avgSpeedKmh, int samples})> fetchHistoricalSpeedKmh({
    required String originName,
    required String destinationName,
  }) async {
    try {
      final snap = await _firestore
          .collection('viajes')
          .where('destination', isEqualTo: destinationName.trim())
          .limit(20)
          .get();

      double sumSpeed = 0;
      int count = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        final km = (d['distanceKm'] as num?)?.toDouble() ?? 0;
        final start = (d['startTime'] as Timestamp?)?.toDate();
        final end = (d['endTime'] as Timestamp?)?.toDate();
        if (km <= 2 || start == null || end == null) continue;
        final hours = end.difference(start).inMinutes / 60.0;
        if (hours <= 0.1) continue;
        final spd = km / hours;
        if (spd >= 15 && spd <= 95) {
          sumSpeed += spd;
          count++;
        }
      }
      if (count == 0) return (avgSpeedKmh: null, samples: 0);
      return (avgSpeedKmh: sumSpeed / count, samples: count);
    } catch (_) {
      return (avgSpeedKmh: null, samples: 0);
    }
  }

  /// Cuenta incidencias activas (últimas 3 horas) a menos de 500 m de la polilínea.
  Future<int> countActiveIncidentsNearRoute(List<LatLng> routePoints) async {
    if (routePoints.isEmpty) return 0;
    try {
      final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 3)));
      final snap = await _firestore
          .collection('incidencias_ruta')
          .where('active', isEqualTo: true)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .limit(30)
          .get();

      int nearby = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        if (!isOffRoute(truckPosition: LatLng(lat, lng), routePoints: routePoints, thresholdMeters: 500.0)) {
          nearby++;
        }
      }
      return nearby;
    } catch (_) {
      return 0;
    }
  }

  /// Evaluación completa asíncrona con datos reales de flota + incidencias en vivo.
  Future<RouteIntelligenceReport> evaluateRouteAsync({
    required String originName,
    required String destinationName,
    required double distanceKm,
    required List<LatLng> routePoints,
    DateTime? departureTime,
  }) async {
    final now = departureTime ?? DateTime.now();
    final histFuture = fetchHistoricalSpeedKmh(originName: originName, destinationName: destinationName);
    final incFuture = countActiveIncidentsNearRoute(routePoints);

    final hist = await histFuture;
    final incidents = await incFuture;

    return evaluateRoute(
      distanceKm: distanceKm,
      departureTime: now,
      activeIncidentsOnRoute: incidents,
      historicalAvgSpeedKmh: hist.avgSpeedKmh,
      historicalSamplesCount: hist.samples,
    );
  }

  /// Evalúa una ruta según distancia, hora del día, histórico e incidencias activas.
  RouteIntelligenceReport evaluateRoute({
    required double distanceKm,
    required DateTime departureTime,
    required int activeIncidentsOnRoute,
    double? historicalAvgSpeedKmh,
    int historicalSamplesCount = 0,
  }) {
    final hour = departureTime.hour;
    final isWeekday = departureTime.weekday <= 5;

    // Factor de congestión por franja horaria en corredores industriales/portuarios
    double congestion = 1.0;
    if (isWeekday && ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 20))) {
      congestion = 1.28;
    } else if (isWeekday && hour >= 12 && hour <= 14) {
      congestion = 1.12;
    }

    // Penalización por incidencias reportadas por la flota
    congestion += (activeIncidentsOnRoute * 0.15);

    final baseTruckSpeedKmh = (historicalAvgSpeedKmh != null && historicalAvgSpeedKmh > 15)
        ? historicalAvgSpeedKmh
        : 58.0;

    final effectiveSpeed = (baseTruckSpeedKmh / congestion).clamp(18.0, 85.0);
    final etaMinutes = (distanceKm / effectiveSpeed) * 60.0;

    final rawScore = 100.0 - ((congestion - 1.0) * 65.0) - (activeIncidentsOnRoute * 18.0);
    final score = rawScore.clamp(10.0, 100.0);
    final recommendAlt = score < 60.0 || activeIncidentsOnRoute >= 2;

    final reasonParts = <String>[
      'Score ${score.round()}/100',
      if (historicalSamplesCount > 0) '$historicalSamplesCount viajes hist.',
      if (activeIncidentsOnRoute > 0) '$activeIncidentsOnRoute inc. activas',
    ];

    return RouteIntelligenceReport(
      estimatedTruckMinutes: etaMinutes,
      congestionFactor: congestion,
      activeIncidentsCount: activeIncidentsOnRoute,
      historicalSamplesCount: historicalSamplesCount,
      routeScore: score,
      recommendAlternative: recommendAlt,
      summaryReason: reasonParts.join(' · '),
    );
  }

  /// Retorna true si el camión se alejó más de [thresholdMeters] de cualquier segmento de la ruta.
  bool isOffRoute({
    required LatLng truckPosition,
    required List<LatLng> routePoints,
    double thresholdMeters = 180.0,
  }) {
    if (routePoints.isEmpty) return false;
    if (routePoints.length == 1) {
      return _distance.as(LengthUnit.Meter, truckPosition, routePoints.first) > thresholdMeters;
    }

    double minMeters = double.infinity;
    for (int i = 0; i < routePoints.length - 1; i++) {
      final d = _pointToSegmentMeters(truckPosition, routePoints[i], routePoints[i + 1]);
      if (d < minMeters) minMeters = d;
      if (minMeters <= thresholdMeters) return false;
    }
    return minMeters > thresholdMeters;
  }

  double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) {
      return _distance.as(LengthUnit.Meter, p, a);
    }

    final t = (((px - ax) * dx) + ((py - ay) * dy)) / (dx * dx + dy * dy);
    final clampedT = math.max(0.0, math.min(1.0, t));
    final proj = LatLng(ay + clampedT * dy, ax + clampedT * dx);
    return _distance.as(LengthUnit.Meter, p, proj);
  }
}
