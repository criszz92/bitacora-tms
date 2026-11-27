import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteManeuverStep {
  final String instruction;
  final double distanceMeters;
  final LatLng location;

  const RouteManeuverStep({
    required this.instruction,
    required this.distanceMeters,
    required this.location,
  });
}

class CabinRouteResult {
  final List<LatLng> points;
  final List<RouteManeuverStep> steps;
  final double totalDistanceKm;
  final double durationMinutes;
  final bool isOfficial;

  const CabinRouteResult({
    required this.points,
    required this.steps,
    required this.totalDistanceKm,
    required this.durationMinutes,
    required this.isOfficial,
  });
}

/// Servicio de ruteo para Navegador Cabina:
/// 1) Prioriza Rutas Oficiales homologadas en Firestore (`rutas_oficiales`).
/// 2) Fallback gratuito con OSRM + instrucciones giro a giro.
/// 3) Registra incidencias en `incidencias_ruta`.
class CabinRoutingService {
  final FirebaseFirestore _firestore;

  CabinRoutingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static String buildRouteKey(String origin, String destination) {
    final o = origin.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    final d = destination.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    return '${o}__$d';
  }

  Future<CabinRouteResult?> fetchRoute({
    required String originName,
    required String destinationName,
    required LatLng origin,
    required LatLng destination,
  }) async {
    final key = buildRouteKey(originName, destinationName);
    try {
      final doc = await _firestore.collection('rutas_oficiales').doc(key).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final rawPts = (data['points'] as List?) ?? [];
        final pts = rawPts
            .whereType<Map>()
            .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList();
        if (pts.length >= 2) {
          return CabinRouteResult(
            points: pts,
            steps: const [],
            totalDistanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
            durationMinutes: (data['durationMinutes'] as num?)?.toDouble() ?? 0,
            isOfficial: true,
          );
        }
      }
    } catch (_) {
      // Fallback a OSRM si falla lectura de Firestore
    }

    return _fetchFromOsrm(origin, destination);
  }

  Future<CabinRouteResult?> _fetchFromOsrm(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']?['coordinates'] as List?) ?? [];
      final pts = coords
          .whereType<List>()
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final steps = <RouteManeuverStep>[];
      final legs = (route['legs'] as List?) ?? [];
      for (final leg in legs) {
        final rawSteps = (leg['steps'] as List?) ?? [];
        for (final s in rawSteps) {
          final loc = s['maneuver']?['location'] as List?;
          if (loc == null || loc.length < 2) continue;
          final name = (s['name'] as String?)?.trim() ?? '';
          final modifier = (s['maneuver']?['modifier'] as String?) ?? '';
          final type = (s['maneuver']?['type'] as String?) ?? 'continue';
          final instruction = _formatSpanishInstruction(type, modifier, name);
          steps.add(RouteManeuverStep(
            instruction: instruction,
            distanceMeters: (s['distance'] as num?)?.toDouble() ?? 0,
            location: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
          ));
        }
      }

      return CabinRouteResult(
        points: pts,
        steps: steps,
        totalDistanceKm: ((route['distance'] as num?)?.toDouble() ?? 0) / 1000.0,
        durationMinutes: ((route['duration'] as num?)?.toDouble() ?? 0) / 60.0,
        isOfficial: false,
      );
    } catch (_) {
      return null;
    }
  }

  String _formatSpanishInstruction(String type, String modifier, String street) {
    final via = street.isNotEmpty ? ' hacia $street' : '';
    if (type == 'arrive') return 'Has llegado a tu destino';
    if (type == 'depart') return 'Inicia el recorrido$via';
    if (modifier.contains('right')) return 'Doble a la derecha$via';
    if (modifier.contains('left')) return 'Doble a la izquierda$via';
    return 'Continúa recto$via';
  }

  Future<List<Map<String, dynamic>>> listOfficialRoutes() async {
    try {
      final snap = await _firestore
          .collection('rutas_oficiales')
          .orderBy('updatedAt', descending: true)
          .limit(30)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  /// Geocodifica un nombre de lugar/cliente/puerto en Chile usando Nominatim (OSM).
  Future<LatLng?> geocodePlace(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent('$q, Chile')}&format=json&limit=1',
    );
    try {
      final res = await http.get(url, headers: {'User-Agent': 'cl.heirlog.bitacora'}).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List?;
      if (list == null || list.isEmpty) return null;
      final item = list.first as Map<String, dynamic>;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOfficialRoute({
    required String originName,
    required String destinationName,
    required List<LatLng> points,
    required double distanceKm,
    required double durationMinutes,
  }) async {
    if (points.length < 2) return;
    final key = buildRouteKey(originName, destinationName);
    await _firestore.collection('rutas_oficiales').doc(key).set({
      'originName': originName,
      'destinationName': destinationName,
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
      'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> reportIncident({
    required String tripId,
    required String type,
    required LatLng position,
    String? idEmpresa,
  }) async {
    await _firestore.collection('incidencias_ruta').add({
      'tripId': tripId,
      'type': type,
      'lat': position.latitude,
      'lng': position.longitude,
      'idEmpresa': idEmpresa,
      'createdAt': FieldValue.serverTimestamp(),
      'active': true,
    });
  }
}

