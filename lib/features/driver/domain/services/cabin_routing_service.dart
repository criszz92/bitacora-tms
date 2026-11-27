import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteIncidentMarker {
  final String type;
  final LatLng position;
  final DateTime? createdAt;

  const RouteIncidentMarker({
    required this.type,
    required this.position,
    this.createdAt,
  });
}

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

  static String buildFullRouteKey(String origin, String client, String destination) {
    final o = origin.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    final c = client.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    final d = destination.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    return '${o}__${c}__$d';
  }

  Future<List<Map<String, dynamic>>> listOfficialRoutes() async {
    final Map<String, Map<String, dynamic>> dedup = {};
    try {
      final snap = await _firestore
          .collection('rutas_oficiales')
          .orderBy('updatedAt', descending: true)
          .limit(30)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final origin = (data['originName'] ?? '').toString();
        final client = (data['clientName'] ?? '').toString();
        final dest = (data['destinationName'] ?? '').toString();
        final key = buildFullRouteKey(origin, client, dest);
        dedup[key] = {'id': d.id, 'tripCount': 1, ...data};
      }
    } catch (_) {}

    // Complementar con viajes históricos completados, deduplicando por Origen -> Cliente -> Destino
    try {
      final tripsSnap = await _firestore
          .collection('viajes')
          .orderBy('startTime', descending: true)
          .limit(80)
          .get();
      for (final doc in tripsSnap.docs) {
        final t = doc.data();
        final origin = (t['origin'] ?? '').toString().trim();
        final client = (t['client'] ?? '').toString().trim();
        final dest = (t['destination'] ?? '').toString().trim();
        if (origin.isEmpty || dest.isEmpty) continue;
        final key = buildFullRouteKey(origin, client, dest);
        if (dedup.containsKey(key)) {
          dedup[key]!['tripCount'] = ((dedup[key]!['tripCount'] as int?) ?? 1) + 1;
        } else {
          dedup[key] = {
            'id': doc.id,
            'originName': origin,
            'clientName': client,
            'destinationName': dest,
            'distanceKm': (t['distanceKm'] as num?)?.toDouble() ?? 0,
            'tripCount': 1,
            'points': const [],
          };
        }
      }
    } catch (_) {}

    return dedup.values.toList();
  }

  /// Resuelve coordenadas de un lugar/cliente/puerto:
  /// 1) Busca primero en `infraestructura_vial` de Firestore (puntos reales del TMS).
  /// 2) Fallback a Nominatim (OSM) en Chile.
  Future<LatLng?> geocodePlace(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    final qUpper = q.toUpperCase();

    try {
      final snap = await _firestore.collection('infraestructura_vial').limit(200).get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final nombre = (d['nombre'] ?? '').toString().trim().toUpperCase();
        if (nombre.isEmpty) continue;
        if (nombre == qUpper || nombre.contains(qUpper) || qUpper.contains(nombre)) {
          final lat = (d['lat'] as num?)?.toDouble() ?? (d['latitud'] as num?)?.toDouble();
          final lng = (d['lng'] as num?)?.toDouble() ?? (d['longitud'] as num?)?.toDouble();
          if (lat != null && lng != null && lat != 0 && lng != 0) {
            return LatLng(lat, lng);
          }
        }
      }
    } catch (_) {}

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

  /// Obtiene incidencias activas globales (anónimas, últimas 3 horas) para mostrarlas en el mapa.
  Future<List<RouteIncidentMarker>> fetchActiveIncidents() async {
    try {
      final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 3)));
      final snap = await _firestore
          .collection('incidencias_ruta')
          .where('active', isEqualTo: true)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .limit(50)
          .get();
      return snap.docs.map((doc) {
        final d = doc.data();
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return null;
        return RouteIncidentMarker(
          type: (d['type'] ?? 'Incidencia').toString(),
          position: LatLng(lat, lng),
          createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
        );
      }).whereType<RouteIncidentMarker>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> reportIncident({
    required String tripId,
    required String type,
    required LatLng position,
    String? idEmpresa,
  }) async {
    await _firestore.collection('incidencias_ruta').add({
      'type': type,
      'lat': position.latitude,
      'lng': position.longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'active': true,
    });
  }
}

