import 'package:latlong2/latlong.dart';

class RouteIntelligenceReport {
  final double estimatedTruckMinutes;
  final double congestionFactor; // 1.0 = fluido, >1.25 = congestión
  final int activeIncidentsCount;
  final double routeScore; // 0 a 100
  final bool recommendAlternative;

  const RouteIntelligenceReport({
    required this.estimatedTruckMinutes,
    required this.congestionFactor,
    required this.activeIncidentsCount,
    required this.routeScore,
    required this.recommendAlternative,
  });
}

/// Motor de análisis inteligente de rutas para transporte pesado:
/// - Calcula ETA real de camión según franja horaria y día.
/// - Penaliza score según incidencias activas en la ruta.
/// - Detecta desvíos reales respecto a la polilínea oficial.
class RouteIntelligenceService {
  static const Distance _distance = Distance();

  /// Evalúa una ruta según distancia, hora del día e incidencias activas.
  RouteIntelligenceReport evaluateRoute({
    required double distanceKm,
    required DateTime departureTime,
    required int activeIncidentsOnRoute,
    double? historicalAvgSpeedKmh,
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

    return RouteIntelligenceReport(
      estimatedTruckMinutes: etaMinutes,
      congestionFactor: congestion,
      activeIncidentsCount: activeIncidentsOnRoute,
      routeScore: score,
      recommendAlternative: score < 60.0 || activeIncidentsOnRoute >= 2,
    );
  }

  /// Retorna true si el camión se alejó más de [thresholdMeters] de la ruta oficial.
  bool isOffRoute({
    required LatLng truckPosition,
    required List<LatLng> routePoints,
    double thresholdMeters = 180.0,
  }) {
    if (routePoints.isEmpty) return false;
    double minMeters = double.infinity;
    for (final pt in routePoints) {
      final d = _distance.as(LengthUnit.Meter, truckPosition, pt);
      if (d < minMeters) minMeters = d;
      if (minMeters <= thresholdMeters) return false;
    }
    return minMeters > thresholdMeters;
  }
}

