import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'wialon_caller.dart';

final modoGpsServiceProvider = Provider<ModoGpsService>((ref) => ModoGpsService());

/// Proveedor para observar en vivo un vehículo por patente (ej: "JH-BZ-64") con autoDispose para evitar fugas de memoria
final singleVehicleGpsProvider = StreamProvider.autoDispose.family<GpsUnit?, String>((ref, plate) async* {
  final service = ref.read(modoGpsServiceProvider);
  final cleanTarget = plate.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  bool isDisposed = false;
  ref.onDispose(() {
    isDisposed = true;
  });

  while (!isDisposed) {
    try {
      final units = await service.fetchFleetData();
      final match = units.cast<GpsUnit?>().firstWhere(
        (u) => u != null && u.plate.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase() == cleanTarget,
        orElse: () => null,
      );
      if (!isDisposed) yield match;
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 8));
  }
});

class GpsGeofence {
  final int id;
  final String name;
  final String description;
  final int type; // 1: line, 2: polygon, 3: circle
  final double radiusMeters;
  final LatLng center;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  GpsGeofence({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.radiusMeters,
    required this.center,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  bool contains(LatLng point) {
    // Tolerancia espacial para bordes o caleteras (~38m)
    const latMargin = 0.00035;
    const lngMargin = 0.00045;
    final inBox = point.latitude >= (minLat - latMargin) &&
        point.latitude <= (maxLat + latMargin) &&
        point.longitude >= (minLng - lngMargin) &&
        point.longitude <= (maxLng + lngMargin);

    if (!inBox) return false;

    // Si es círculo (3) o tiene radio/ancho definido
    if (type == 3 || radiusMeters > 0) {
      final distMeters = _haversineMeters(point.latitude, point.longitude, center.latitude, center.longitude);
      final maxAllowedDist = radiusMeters < 80 ? 80.0 : radiusMeters * 1.25;
      if (distMeters <= maxAllowedDist) {
        return true;
      }
    }

    return inBox;
  }

  static double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    const toRad = 0.017453292519943295;
    final dLat = (lat2 - lat1) * toRad;
    final dLon = (lon2 - lon1) * toRad;
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(lat1 * toRad) * math.cos(lat2 * toRad) * (math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}

class GpsUnit {
  final String id;
  final String plate;
  final String driverName;
  final LatLng position;
  final double speed;
  final String status; // 'online' (en movimiento), 'detenido', 'offline'
  final DateTime lastUpdate;
  final double? course;
  final bool? isIgnitionOn;
  final double? externalPower;
  final int? satellites;
  final String? currentGeofence; // Nombre de la geocerca actual (ej: "CASA-Base", "PUERTO_CORONEL")
  final double? altitude;
  final double? hardwareMileageKm;
  final int? internalBattery;
  final int? gsmSignal;

  bool get isRalenti => (isIgnitionOn == true) && (speed < 2.0);
  bool get isMoving => (isIgnitionOn == true) && (speed >= 2.0);
  bool get isEngineOff => (isIgnitionOn == false);

  GpsUnit({
    required this.id,
    required this.plate,
    required this.driverName,
    required this.position,
    required this.speed,
    required this.status,
    required this.lastUpdate,
    this.course,
    this.isIgnitionOn,
    this.externalPower,
    this.satellites,
    this.currentGeofence,
    this.altitude,
    this.hardwareMileageKm,
    this.internalBattery,
    this.gsmSignal,
  });
}

class GpsGeofenceStay {
  final String geofenceName;
  final DateTime entryTime;
  final DateTime exitTime;

  Duration get duration => exitTime.difference(entryTime);
  int get durationMinutes => duration.inMinutes;

  GpsGeofenceStay({
    required this.geofenceName,
    required this.entryTime,
    required this.exitTime,
  });
}

class GpsHistoricalPoint {
  final LatLng position;
  final double speed;
  final DateTime timestamp;
  final String? geofence;
  final double? altitude;

  GpsHistoricalPoint({
    required this.position,
    required this.speed,
    required this.timestamp,
    this.geofence,
    this.altitude,
  });
}

class GpsStop {
  final LatLng position;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final String? geofenceName;

  GpsStop({
    required this.position,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.geofenceName,
  });
}

/// Detección inteligente del inicio de jornada/viaje.
/// Cruza: primer GPS del día + primer movimiento real + encendido del motor.
class GpsJourneyStart {
  /// Timestamp del primer punto GPS recibido en el intervalo
  final DateTime firstGpsTime;

  /// Timestamp del primer movimiento real (speed > 3 km/h)
  final DateTime? firstMotionTime;

  /// Posición GPS donde se detectó el primer movimiento real
  final LatLng? firstMotionPosition;

  /// Si el primer mensaje del intervalo ya mostraba motor encendido (pwr_ext > 0)
  final bool engineOnAtStart;

  /// Nombre de la geocerca en el punto de inicio (si aplica)
  final String? startGeofenceName;

  /// Determinación final inteligente: el inicio "real" de la jornada
  /// Prioridad: firstMotionTime > firstGpsTime
  DateTime get determinedStartTime => firstMotionTime ?? firstGpsTime;
  LatLng? get determinedStartPosition => firstMotionPosition;

  GpsJourneyStart({
    required this.firstGpsTime,
    this.firstMotionTime,
    this.firstMotionPosition,
    required this.engineOnAtStart,
    this.startGeofenceName,
  });
}

/// Detección inteligente del término de jornada/viaje.
/// Cruza: último punto GPS reportado + última geocerca + estado final del motor/vehículo + duración total.
class GpsJourneyEnd {
  /// Timestamp del último punto GPS recibido en el intervalo
  final DateTime lastGpsTime;

  /// Posición GPS del último punto reportado
  final LatLng lastPosition;

  /// Velocidad en el último punto reportado (km/h)
  final double lastSpeed;

  /// Nombre de la geocerca donde terminó el viaje (si aplica)
  final String? endGeofenceName;

  /// Si el camión quedó detenido (speed < 3 km/h) al término
  final bool isStopped;

  /// Duración total estimada de la jornada desde el inicio determinado
  final Duration totalDuration;

  /// Determinación final de término de jornada
  DateTime get determinedEndTime => lastGpsTime;

  GpsJourneyEnd({
    required this.lastGpsTime,
    required this.lastPosition,
    required this.lastSpeed,
    this.endGeofenceName,
    required this.isStopped,
    required this.totalDuration,
  });
}

class GpsTripLeg {
  final int index;
  final String name; // ej: "Tramo 1 (Ida)", "Tramo 2 (Retorno)"
  final DateTime startTime;
  final DateTime endTime;
  final double distanceKm;
  final double maxSpeed;
  final double avgSpeed;
  final List<GpsHistoricalPoint> points;
  final Color color;

  GpsTripLeg({
    required this.index,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.distanceKm,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.points,
    required this.color,
  });
}

class GpsHistoricalTrip {
  final String plate;
  final DateTime startTime;
  final DateTime endTime;
  final double totalDistanceKm;
  final double maxSpeed;
  final double avgSpeed;
  final int totalPoints;
  final List<GpsGeofenceStay> stays;
  final List<String> routePattern;
  final List<GpsHistoricalPoint> points;
  final List<GpsTripLeg> legs;
  final List<GpsStop> stops;
  final GpsJourneyStart? journeyStart;
  final GpsJourneyEnd? journeyEnd;
  final int idleMinutes;
  final double idleFuelLiters;

  GpsHistoricalTrip({
    required this.plate,
    this.idleMinutes = 0,
    this.idleFuelLiters = 0.0,
    required this.startTime,
    required this.endTime,
    required this.totalDistanceKm,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.totalPoints,
    required this.stays,
    required this.routePattern,
    required this.points,
    this.legs = const [],
    this.stops = const [],
    this.journeyStart,
    this.journeyEnd,
  });
}

class ModoGpsService {
  static const String _defaultHost = 'https://hst-api.wialon.com';
  static const String _fallbackToken = '3aa34629428b61af8799d9e152a0f80cA3A6711FC66B570D96EDE6FD7F69065E8F2379E1';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _cachedEid;
  DateTime? _lastLoginTime;

  /// Extrae el token limpio si el usuario pegó la URL completa de ModoGPS o solo el token
  static String extractToken(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return '';

    // Si viene como URL completa: ...access_token=XXXXX&...
    final match = RegExp(r'(?:access_token|token)=([a-fA-F0-9]+)').firstMatch(trimmed);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }

    return trimmed;
  }

  /// Guarda el token en la configuración de la empresa o en secrets para multitenancy
  Future<void> saveToken(String rawInput, {String? idEmpresa}) async {
    final cleanToken = extractToken(rawInput);
    if (cleanToken.isEmpty) {
      throw Exception('El token ingresado no es válido');
    }

    if (idEmpresa != null && idEmpresa.isNotEmpty) {
      await _firestore.collection('config_empresas').doc(idEmpresa).set({
        'modogps_token': cleanToken,
        'modogps_updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    }

    // Actualizar también en secrets/modogps como respaldo
    await _firestore.collection('secrets').doc('modogps').set({
      'token': cleanToken,
      'updated_at': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    // Resetear sesión en caché para forzar re-autenticación inmediata
    _cachedEid = null;
    _lastLoginTime = null;
  }

  void resetSession() {
    _cachedEid = null;
    _lastLoginTime = null;
  }

  Future<String> _getToken({String? idEmpresa}) async {
    // 1. Intentar desde la configuración de la empresa
    if (idEmpresa != null && idEmpresa.isNotEmpty) {
      try {
        final doc = await _firestore.collection('config_empresas').doc(idEmpresa).get();
        if (doc.exists && doc.data() != null) {
          final token = doc.data()!['modogps_token'] as String?;
          if (token != null && token.trim().isNotEmpty) {
            return token.trim();
          }
        }
      } catch (_) {}
    }

    // 2. Intentar desde secrets/modogps
    try {
      final doc = await _firestore.collection('secrets').doc('modogps').get();
      if (doc.exists && doc.data() != null) {
        final token = doc.data()!['token'] as String?;
        if (token != null && token.trim().isNotEmpty) {
          return token.trim();
        }
      }
    } catch (e) {
      debugPrint("ModoGPS: No se pudo leer token de secrets/modogps: $e");
    }

    return _fallbackToken;
  }

  Future<String> _getHost() async {
    try {
      final doc = await _firestore.collection('secrets').doc('modogps').get();
      if (doc.exists && doc.data() != null) {
        final host = doc.data()!['host'] as String?;
        if (host != null && host.trim().isNotEmpty) {
          return host.trim();
        }
      }
    } catch (_) {}
    return _defaultHost;
  }

  Future<String> _ensureSession({String? idEmpresa}) async {
    if (_cachedEid != null && _lastLoginTime != null) {
      if (DateTime.now().difference(_lastLoginTime!) < const Duration(hours: 2)) {
        return _cachedEid!;
      }
    }

    final token = await _getToken(idEmpresa: idEmpresa);
    final host = await _getHost();
    final loginUrl = '$host/wialon/ajax.html?svc=token/login&params=${Uri.encodeComponent(jsonEncode({'token': token}))}';

    final res = await callWialon(loginUrl);
    if (res['error'] != null && res['error'] != 0) {
      throw Exception('Error autenticando en ModoGPS (Código: ${res['error']})');
    }

    final eid = res['eid'] as String?;
    if (eid == null || eid.isEmpty) {
      throw Exception('ModoGPS no retornó un ID de sesión válido');
    }

    _cachedEid = eid;
    _lastLoginTime = DateTime.now();
    return eid;
  }

  List<GpsGeofence>? _cachedGeofences;
  DateTime? _lastGeofencesFetch;
  List<GpsUnit>? _cachedFleet;
  DateTime? _lastFleetFetch;

  /// Obtiene las geocercas configuradas en ModoGPS (avl_resource)
  Future<List<GpsGeofence>> fetchGeofences({String? idEmpresa, bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedGeofences != null && _lastGeofencesFetch != null) {
      if (DateTime.now().difference(_lastGeofencesFetch!) < const Duration(minutes: 15)) {
        return _cachedGeofences!;
      }
    }

    try {
      final host = await _getHost();
      final eid = await _ensureSession(idEmpresa: idEmpresa);

      final spec = {
        'spec': {
          'itemsType': 'avl_resource',
          'propName': 'sys_name',
          'propValueMask': '*',
          'sortType': 'sys_name',
        },
        'force': 1,
        'flags': 4096 + 1, // 4096 = zonas (geocercas)
        'from': 0,
        'to': 0,
      };

      final url = '$host/wialon/ajax.html?svc=core/search_items&params=${Uri.encodeComponent(jsonEncode(spec))}&sid=$eid';
      final res = await callWialon(url);

      if (res['items'] is! List) return _cachedGeofences ?? [];

      final geofences = <GpsGeofence>[];
      for (final item in (res['items'] as List)) {
        if (item is! Map || item['zl'] is! Map) continue;
        final zonesMap = item['zl'] as Map;
        for (final entry in zonesMap.entries) {
          final z = entry.value;
          if (z is! Map) continue;
          final b = z['b'] as Map?;
          if (b == null) continue;

          final cenY = (b['cen_y'] as num?)?.toDouble() ?? 0.0;
          final cenX = (b['cen_x'] as num?)?.toDouble() ?? 0.0;
          final minY = (b['min_y'] as num?)?.toDouble() ?? cenY;
          final maxY = (b['max_y'] as num?)?.toDouble() ?? cenY;
          final minX = (b['min_x'] as num?)?.toDouble() ?? cenX;
          final maxX = (b['max_x'] as num?)?.toDouble() ?? cenX;
          final w = (z['w'] as num?)?.toDouble() ?? 100.0;

          geofences.add(GpsGeofence(
            id: (z['id'] as num?)?.toInt() ?? 0,
            name: z['n']?.toString() ?? 'Zona',
            description: z['d']?.toString() ?? '',
            type: (z['t'] as num?)?.toInt() ?? 3,
            radiusMeters: w,
            center: LatLng(cenY, cenX),
            minLat: minY,
            maxLat: maxY,
            minLng: minX,
            maxLng: maxX,
          ));
        }
      }

      // Cargar también las geocercas maestras de clientes locales (CSV institucional de Bitácora TMS)
      final localClientGeofences = await _loadLocalClientGeofences();
      
      // Función para normalizar nombres y comparar sin guiones bajos, espacios extras ni símbolos
      String normalize(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

      final existingNormalizedNames = geofences.map((g) => normalize(g.name)).toSet();
      const distanceCalc = Distance();

      for (final lcg in localClientGeofences) {
        final normLocal = normalize(lcg.name);
        // 1. Descartar si el nombre normalizado ya existe (ej: "FORSACCHILLAN" vs "FORSAC_CHILLAN")
        if (existingNormalizedNames.contains(normLocal)) continue;

        // 2. Descartar si geográficamente ya existe una geocerca a menos de 400 metros
        final hasProximityConflict = geofences.any((g) {
          final meters = distanceCalc.as(LengthUnit.Meter, g.center, lcg.center);
          return meters < 400.0;
        });

        if (!hasProximityConflict) {
          geofences.add(lcg);
          existingNormalizedNames.add(normLocal);
        }
      }

      _cachedGeofences = geofences;
      _lastGeofencesFetch = DateTime.now();
      debugPrint('[ModoGPS] Geocercas totales unificadas (ModoGPS + Clientes TMS): ${geofences.length}');
      return geofences;
    } catch (e) {
      debugPrint('[ModoGPS] Error cargando geocercas: $e');
      return _cachedGeofences ?? [];
    }
  }

  /// Carga y parsea el archivo de clientes institucionales CSV integrado en la app
  Future<List<GpsGeofence>> _loadLocalClientGeofences() async {
    try {
      final rawCsv = await rootBundle.loadString('assets/data/clientes_geocercas.csv');
      final lines = const LineSplitter().convert(rawCsv);
      if (lines.length <= 1) return [];

      final list = <GpsGeofence>[];
      int pseudoId = 900000;

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // Manejar posibles comillas en el nombre de cliente
        final parts = _parseCsvLine(line);
        if (parts.length >= 3) {
          final clientName = parts[0].replaceAll('"', '').trim();
          final lat = double.tryParse(parts[1].trim());
          final lng = double.tryParse(parts[2].trim());
          final conf = parts.length >= 4 ? parts[3].trim() : 'alta';

          if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
            pseudoId++;
            // Radio de geocerca según confianza y tipo de cliente (250m a 400m)
            final double radius = conf.toLowerCase() == 'alta' ? 250.0 : 350.0;
            // Aproximación de bounding box (1 grado ~ 111km)
            final latDelta = radius / 111000.0;
            final lngDelta = radius / (111000.0 * math.cos(lat * math.pi / 180.0)).abs();

            list.add(GpsGeofence(
              id: pseudoId,
              name: clientName,
              description: 'Cliente TMS (confianza: $conf)',
              type: 3, // Círculo
              radiusMeters: radius,
              center: LatLng(lat, lng),
              minLat: lat - latDelta,
              maxLat: lat + latDelta,
              minLng: lng - lngDelta,
              maxLng: lng + lngDelta,
            ));
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('[ModoGPS] Error cargando clientes locales CSV: $e');
      return [];
    }
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    final sb = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    result.add(sb.toString());
    return result;
  }

  Future<List<GpsUnit>> fetchFleetData({String? idEmpresa}) async {
    // Si se consultó hace menos de 3 segundos, retornar la caché para no saturar API
    if (_cachedFleet != null && _lastFleetFetch != null) {
      if (DateTime.now().difference(_lastFleetFetch!) < const Duration(seconds: 3)) {
        return _cachedFleet!;
      }
    }

    try {
      final host = await _getHost();
      String eid = await _ensureSession(idEmpresa: idEmpresa);

      final searchParams = {
        'spec': {
          'itemsType': 'avl_unit',
          'propName': 'sys_name',
          'propValueMask': '*',
          'sortType': 'sys_name',
        },
        'force': 1,
        'flags': 3150849, // 1 (base) + 1024 (pos) + 4096 (sensors) + 1048576 (last message & prms) + 2097152 (status)
        'from': 0,
        'to': 0,
      };

      var searchUrl = '$host/wialon/ajax.html?svc=core/search_items&params=${Uri.encodeComponent(jsonEncode(searchParams))}&sid=$eid';
      var res = await callWialon(searchUrl);

      // Si la sesión expiró (error 1 en Wialon), re-autenticar una vez
      if (res['error'] == 1) {
        _cachedEid = null;
        eid = await _ensureSession();
        searchUrl = '$host/wialon/ajax.html?svc=core/search_items&params=${Uri.encodeComponent(jsonEncode(searchParams))}&sid=$eid';
        res = await callWialon(searchUrl);
      }

      if (res['error'] != null && res['error'] != 0) {
        throw Exception('Error al consultar unidades en ModoGPS (Código: ${res['error']})');
      }

      final items = res['items'] as List?;
      if (items == null) return [];

      // Cargar geocercas en memoria para etiquetar cada unidad en vivo
      final geofences = await fetchGeofences(idEmpresa: idEmpresa);
      final units = <GpsUnit>[];

      for (final item in items) {
        if (item is! Map) continue;
        final name = item['nm']?.toString() ?? 'S/P';
        final id = item['id']?.toString() ?? '';
        final pos = item['pos'] as Map?;
        final netconn = item['netconn'] as num? ?? 0;
        final lmsg = item['lmsg'] as Map?;
        final prms = item['prms'] as Map?;
        final p = (lmsg?['p'] as Map?);

        // Alimentación externa (batería camión en voltios)
        final pwrExt = ((prms?['pwr_ext'] as Map?)?['v'] as num?)?.toDouble() ??
            (p?['pwr_ext'] as num?)?.toDouble();

        // Contacto / Motor (ACC físico del GPS)
        // NOTA CLAVE: pwr_ext > 0 solo significa energizado.
        // Motor encendido requiere estrictamente acc == 1 (o in1 == 1)
        int? accVal;
        if (prms != null && prms['acc'] is Map) {
          accVal = (prms['acc']['v'] as num?)?.toInt();
        }
        accVal ??= (p?['acc'] as num?)?.toInt();
        if (accVal == null && prms != null && prms['in1'] is Map) {
          accVal = (prms['in1']['v'] as num?)?.toInt();
        }
        accVal ??= (p?['in1'] as num?)?.toInt();

        final isIgnitionOn = accVal != null ? (accVal == 1) : null;

        // Odómetro nativo de hardware acumulado por el GPS (metros -> km)
        final mileageM = ((prms?['mileage'] as Map?)?['v'] as num?)?.toDouble() ??
            (p?['mileage'] as num?)?.toDouble();
        final hardwareKm = mileageM != null ? (mileageM / 1000.0) : null;

        // Batería interna (%) y señal GSM (barras)
        final batteryVal = ((prms?['voltage'] as Map?)?['v'] as num?)?.toInt() ??
            (p?['voltage'] as num?)?.toInt();
        final gsmVal = ((prms?['gsm'] as Map?)?['v'] as num?)?.toInt() ??
            (p?['gsm'] as num?)?.toInt();

        if (pos != null) {
          final lat = (pos['y'] as num?)?.toDouble() ?? 0.0;
          final lng = (pos['x'] as num?)?.toDouble() ?? 0.0;
          final speed = (pos['s'] as num?)?.toDouble() ?? 0.0;
          final course = (pos['c'] as num?)?.toDouble();
          final alt = (pos['z'] as num?)?.toDouble();
          final satCount = pos['sc'] as int?;
          final timestamp = pos['t'] != null
              ? DateTime.fromMillisecondsSinceEpoch((pos['t'] as int) * 1000)
              : DateTime.now();

          String status;
          if (netconn == 1) {
            status = speed > 2.0 ? 'online' : 'detenido';
          } else {
            status = 'offline';
          }

          final point = LatLng(lat, lng);
          String? currentZoneName;
          for (final zone in geofences) {
            if (zone.contains(point)) {
              currentZoneName = zone.name;
              break;
            }
          }

          units.add(GpsUnit(
            id: id,
            plate: name,
            driverName: 'Conductor Asignado',
            position: point,
            speed: speed,
            status: status,
            lastUpdate: timestamp,
            course: course,
            isIgnitionOn: isIgnitionOn,
            externalPower: pwrExt,
            satellites: satCount,
            currentGeofence: currentZoneName,
            altitude: alt,
            hardwareMileageKm: hardwareKm,
            internalBattery: batteryVal,
            gsmSignal: gsmVal,
          ));
        }
      }

      _cachedFleet = units;
      _lastFleetFetch = DateTime.now();
      return units;
    } catch (e) {
      debugPrint("ModoGPS fetchFleetData error: $e");
      rethrow;
    }
  }

  /// Descarga el recorrido exacto entre startTime y endTime para una patente
  /// y detecta automáticamente las geocercas visitadas, paradas y km reales
  Future<GpsHistoricalTrip?> fetchTripInterval({
    required String plate,
    required DateTime startTime,
    required DateTime endTime,
    String? idEmpresa,
  }) async {
    try {
      final host = await _getHost();
      final eid = await _ensureSession(idEmpresa: idEmpresa);
      final cleanTarget = plate.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

      // 1. Buscar la unidad para obtener su ID numérico en Wialon
      final specUnit = {
        'spec': {
          'itemsType': 'avl_unit',
          'propName': 'sys_name',
          'propValueMask': '*',
          'sortType': 'sys_name',
        },
        'force': 1,
        'flags': 1,
        'from': 0,
        'to': 0,
      };

      final uUrl = '$host/wialon/ajax.html?svc=core/search_items&params=${Uri.encodeComponent(jsonEncode(specUnit))}&sid=$eid';
      final uRes = await callWialon(uUrl);
      final items = uRes['items'] as List?;
      if (items == null || items.isEmpty) return null;

      dynamic matchedItem;
      for (final it in items) {
        final nm = it['nm']?.toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase() ?? '';
        if (nm == cleanTarget) {
          matchedItem = it;
          break;
        }
      }
      if (matchedItem == null) {
        debugPrint('[ModoGPS] Patente "$cleanTarget" no encontrada en Wialon (${items.length} unidades).');
        return null;
      }

      final unitId = matchedItem['id'];
      if (unitId == null) return null;

      // 2. Cargar TODOS los mensajes del intervalo mediante paginación por tiempo
      // Sin este bucle, Wialon corta a los primeros 2000 mensajes en viajes largos/multi-día.
      final timeFrom = startTime.millisecondsSinceEpoch ~/ 1000;
      final timeTo = endTime.millisecondsSinceEpoch ~/ 1000;
      const int batchSize = 2000;
      const int maxBatches = 25; // Hasta 50.000 mensajes

      final List<dynamic> rawMsgs = [];
      int currentFrom = timeFrom;
      final Set<String> seenMsgKeys = {};

      for (int batch = 0; batch < maxBatches && currentFrom <= timeTo; batch++) {
        final loadParams = {
          'itemId': unitId,
          'timeFrom': currentFrom,
          'timeTo': timeTo,
          'flags': 257,      // 1 (posición) + 256 (parámetros acc/din1)
          'flagsMask': 257,
          'loadCount': batchSize,
        };

        final mUrl = '$host/wialon/ajax.html?svc=messages/load_interval&params=${Uri.encodeComponent(jsonEncode(loadParams))}&sid=$eid';
        final mRes = await callWialon(mUrl);
        final batchMsgs = mRes['messages'] as List?;
        if (batchMsgs == null || batchMsgs.isEmpty) break;

        int? lastTsInBatch;
        for (final msg in batchMsgs) {
          if (msg is! Map) continue;
          final ts = (msg['t'] as num?)?.toInt();
          final pos = msg['pos'] as Map?;
          final key = '${ts ?? 0}_${pos?['y'] ?? 0}_${pos?['x'] ?? 0}';
          if (seenMsgKeys.add(key)) {
            rawMsgs.add(msg);
          }
          if (ts != null) {
            lastTsInBatch = ts;
          }
        }

        // Si el lote trajo menos del máximo, ya no quedan más mensajes en el intervalo
        if (batchMsgs.length < batchSize || lastTsInBatch == null) {
          break;
        }

        // Avanzar ventana evitando loop infinito si todos los mensajes tienen el mismo segundo
        currentFrom = lastTsInBatch > currentFrom ? lastTsInBatch : (currentFrom + 1);
      }

      if (rawMsgs.isEmpty) return null;

      final geofences = await fetchGeofences(idEmpresa: idEmpresa);
      final points = <GpsHistoricalPoint>[];

      double totalDistMeters = 0.0;
      double maxSpeed = 0.0;
      double speedSum = 0.0;
      int speedCount = 0;
      int idleSeconds = 0;
      DateTime? prevTs;
      LatLng? prevPos;

      String? currentZone;
      DateTime? currentZoneEntry;
      final stays = <GpsGeofenceStay>[];
      final routePattern = <String>[];

      // ── Variables para detección inteligente de inicio de jornada ──
      DateTime? firstGpsTime;
      LatLng? firstMotionPosition;
      DateTime? firstMotionTime;
      bool engineOnAtStart = false;
      String? startGeofenceName;

      for (final m in rawMsgs) {
        if (m is! Map || m['pos'] == null) continue;
        final pos = m['pos'] as Map;
        final lat = (pos['y'] as num?)?.toDouble() ?? 0.0;
        final lng = (pos['x'] as num?)?.toDouble() ?? 0.0;
        final speed = (pos['s'] as num?)?.toDouble() ?? 0.0;
        final altitude = (pos['z'] as num?)?.toDouble();
        final tsSec = (m['t'] as num?)?.toInt() ?? 0;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);

        // Ignorar puntos con coordenadas nulas o inválidas
        if (lat == 0.0 && lng == 0.0) continue;

        final point = LatLng(lat, lng);

        // ── Detección inteligente de inicio de jornada ────────────────
        if (firstGpsTime == null) {
          // Primer punto GPS del día → hora real en que el dispositivo arrancó
          firstGpsTime = timestamp;

          // Leer sensor de motor del primer mensaje:
          // Wialon puede reportar pwr_ext (energía externa) o acc en m['p']
          final msgParams = m['p'] as Map?;
          final acc = (msgParams?['acc'] as num?) ??  // sensor ACC
                      (msgParams?['ACC'] as num?) ??  // algunas configs mayúsculas
                      (msgParams?['din1'] as num?) ??
                      (msgParams?['in1'] as num?) ?? 0;  // entrada digital 1 (ignition)
          engineOnAtStart = acc > 0;

          // Geocerca del punto de partida
          for (final z in geofences) {
            if (z.contains(point)) {
              startGeofenceName = z.name;
              break;
            }
          }
        }

        // Primer movimiento real: velocidad supera umbral de ruido (> 3 km/h)
        if (firstMotionTime == null && speed > 3.0) {
          firstMotionTime = timestamp;
          firstMotionPosition = point;
        }
        // ─────────────────────────────────────────────────────────────

        if (prevPos != null) {
          final segMeters = GpsGeofence._haversineMeters(prevPos.latitude, prevPos.longitude, lat, lng);
          // Filtrar saltos irreales por pérdida/rebote de señal (> 50 km entre dos mensajes seguidos)
          if (segMeters < 50000) {
            totalDistMeters += segMeters;
          }
        }
        if (prevTs != null) {
          final msgParams = m['p'] as Map?;
          final acc = (msgParams?['acc'] as num?) ??
              (msgParams?['ACC'] as num?) ??
              (msgParams?['din1'] as num?) ??
              (msgParams?['in1'] as num?) ??
              0;
          final dtSec = timestamp.difference(prevTs).inSeconds;
          if (acc > 0 && speed <= 3.0 && dtSec > 0 && dtSec <= 600) {
            idleSeconds += dtSec;
          }
        }
        prevTs = timestamp;
        prevPos = point;

        if (speed > maxSpeed) maxSpeed = speed;
        speedSum += speed;
        speedCount++;

        String? foundZone;
        for (final z in geofences) {
          if (z.contains(point)) {
            foundZone = z.name;
            break;
          }
        }

        points.add(GpsHistoricalPoint(
          position: point,
          speed: speed,
          timestamp: timestamp,
          geofence: foundZone,
          altitude: altitude,
        ));

        // Detectar transiciones de geocerca
        if (foundZone != currentZone) {
          if (currentZone != null && currentZoneEntry != null) {
            final durMin = timestamp.difference(currentZoneEntry).inMinutes;
            // FILTRO DE GEOCERCA: Solo registrar estadía si estuvo al menos 3 minutos
            // (evita pasadas en ruta a alta velocidad como en Orizon)
            if (durMin >= 3) {
              stays.add(GpsGeofenceStay(
                geofenceName: currentZone,
                entryTime: currentZoneEntry,
                exitTime: timestamp,
              ));
            }
          }
          if (foundZone != null) {
            currentZoneEntry = timestamp;
            if (routePattern.isEmpty || routePattern.last != foundZone) {
              routePattern.add(foundZone);
            }
          }
          currentZone = foundZone;
        }
      }

      if (currentZone != null && currentZoneEntry != null && points.isNotEmpty) {
        final durMin = points.last.timestamp.difference(currentZoneEntry).inMinutes;
        if (durMin >= 3) {
          stays.add(GpsGeofenceStay(
            geofenceName: currentZone,
            entryTime: currentZoneEntry,
            exitTime: points.last.timestamp,
          ));
        }
      }

      // ── DETECCIÓN DE PARADAS / DETENCIONES Y SEGMENTACIÓN DE TRAMOS ──
      // Paleta de colores distintivos para los tramos (Ida = Azul/Cyan, Retorno = Morado/Magenta, etc.)
      const legColors = [
        Color(0xFF00E5FF), // Cyan eléctrico (Ida)
        Color(0xFFE040FB), // Magenta/Morado (Retorno)
        Color(0xFFFF9100), // Naranja (Tramo 3)
        Color(0xFF76FF03), // Verde lima (Tramo 4)
        Color(0xFFFFD600), // Amarillo
      ];

      final stops = <GpsStop>[];
      final legs = <GpsTripLeg>[];

      // Analizar secuencias de velocidad 0 o muy baja (< 3 km/h) de más de 8 minutos
      int? stopStartIndex;
      final splitIndices = <int>[]; // Índices donde se corta un tramo para iniciar el siguiente

      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final isStopped = p.speed < 3.0;

        if (isStopped) {
          stopStartIndex ??= i;
        } else {
          if (stopStartIndex != null) {
            final startP = points[stopStartIndex];
            final prevP = points[i - 1];
            final stopDurationMin = prevP.timestamp.difference(startP.timestamp).inMinutes;

            // Si estuvo detenido >= 8 minutos (ej: repostar diésel, almuerzo, carga/descarga)
            if (stopDurationMin >= 8) {
              stops.add(GpsStop(
                position: startP.position,
                startTime: startP.timestamp,
                endTime: prevP.timestamp,
                durationMinutes: stopDurationMin,
                geofenceName: startP.geofence ?? prevP.geofence,
              ));

              // Este punto de detención corta el tramo para diferenciar Ida vs Retorno
              splitIndices.add(i);
            }
            stopStartIndex = null;
          }
        }
      }

      // Si quedó detenido al final del intervalo
      if (stopStartIndex != null && stopStartIndex < points.length - 1) {
        final startP = points[stopStartIndex];
        final endP = points.last;
        final stopDurationMin = endP.timestamp.difference(startP.timestamp).inMinutes;
        if (stopDurationMin >= 8) {
          stops.add(GpsStop(
            position: startP.position,
            startTime: startP.timestamp,
            endTime: endP.timestamp,
            durationMinutes: stopDurationMin,
            geofenceName: startP.geofence ?? endP.geofence,
          ));
        }
      }

      // Construir los Tramos (Legs) a partir de los puntos de corte
      if (points.isNotEmpty) {
        int currentLegStart = 0;
        int legIdx = 0;

        for (final splitIdx in splitIndices) {
          if (splitIdx > currentLegStart) {
            final legPoints = points.sublist(currentLegStart, splitIdx);
            if (legPoints.length > 5) {
              double legDist = 0;
              double legMaxSpd = 0;
              double legSumSpd = 0;
              for (int k = 1; k < legPoints.length; k++) {
                legDist += GpsGeofence._haversineMeters(
                  legPoints[k - 1].position.latitude,
                  legPoints[k - 1].position.longitude,
                  legPoints[k].position.latitude,
                  legPoints[k].position.longitude,
                );
                if (legPoints[k].speed > legMaxSpd) legMaxSpd = legPoints[k].speed;
                legSumSpd += legPoints[k].speed;
              }

              final name = legIdx == 0 ? 'Tramo 1 (Ida)' : (legIdx == 1 ? 'Tramo 2 (Retorno)' : 'Tramo ${legIdx + 1}');
              legs.add(GpsTripLeg(
                index: legIdx + 1,
                name: name,
                startTime: legPoints.first.timestamp,
                endTime: legPoints.last.timestamp,
                distanceKm: legDist / 1000.0,
                maxSpeed: legMaxSpd,
                avgSpeed: legPoints.isNotEmpty ? (legSumSpd / legPoints.length) : 0.0,
                points: legPoints,
                color: legColors[legIdx % legColors.length],
              ));
              legIdx++;
            }
            currentLegStart = splitIdx;
          }
        }

        // Último tramo hasta el final
        if (currentLegStart < points.length) {
          final legPoints = points.sublist(currentLegStart);
          if (legPoints.length > 2) {
            double legDist = 0;
            double legMaxSpd = 0;
            double legSumSpd = 0;
            for (int k = 1; k < legPoints.length; k++) {
              legDist += GpsGeofence._haversineMeters(
                legPoints[k - 1].position.latitude,
                legPoints[k - 1].position.longitude,
                legPoints[k].position.latitude,
                legPoints[k].position.longitude,
              );
              if (legPoints[k].speed > legMaxSpd) legMaxSpd = legPoints[k].speed;
              legSumSpd += legPoints[k].speed;
            }

            final name = legIdx == 0 ? 'Tramo 1 (Completo)' : (legIdx == 1 ? 'Tramo 2 (Retorno)' : 'Tramo ${legIdx + 1}');
            legs.add(GpsTripLeg(
              index: legIdx + 1,
              name: name,
              startTime: legPoints.first.timestamp,
              endTime: legPoints.last.timestamp,
              distanceKm: legDist / 1000.0,
              maxSpeed: legMaxSpd,
              avgSpeed: legPoints.isNotEmpty ? (legSumSpd / legPoints.length) : 0.0,
              points: legPoints,
              color: legColors[legIdx % legColors.length],
            ));
          }
        }
      }

      final avgSpeed = speedCount > 0 ? (speedSum / speedCount) : 0.0;

      // Construir el objeto de inicio de jornada si se detectó al menos el primer GPS
      GpsJourneyStart? journeyStart;
      if (firstGpsTime != null) {
        journeyStart = GpsJourneyStart(
          firstGpsTime: firstGpsTime,
          firstMotionTime: firstMotionTime,
          firstMotionPosition: firstMotionPosition,
          engineOnAtStart: engineOnAtStart,
          startGeofenceName: startGeofenceName,
        );
        debugPrint('[ModoGPS] Inicio de jornada detectado: '
            'primer GPS=${firstGpsTime.toIso8601String()}, '
            'primer movimiento=${firstMotionTime?.toIso8601String() ?? "N/A"}, '
            'motor=${engineOnAtStart ? "ENCENDIDO" : "APAGADO"}, '
            'geocerca=${startGeofenceName ?? "Fuera de zona"}}');
      }

      // Construir el objeto de término de jornada si hay puntos telemétricos
      GpsJourneyEnd? journeyEnd;
      if (points.isNotEmpty) {
        final lastPoint = points.last;
        final startTimeActual = journeyStart?.determinedStartTime ?? points.first.timestamp;
        final duration = lastPoint.timestamp.isAfter(startTimeActual)
            ? lastPoint.timestamp.difference(startTimeActual)
            : Duration.zero;

        String? endZone = lastPoint.geofence;
        if (endZone == null && stops.isNotEmpty) {
          endZone = stops.last.geofenceName;
        }

        journeyEnd = GpsJourneyEnd(
          lastGpsTime: lastPoint.timestamp,
          lastPosition: lastPoint.position,
          lastSpeed: lastPoint.speed,
          endGeofenceName: endZone,
          isStopped: lastPoint.speed < 3.0,
          totalDuration: duration,
        );
        debugPrint('[ModoGPS] Término de jornada detectado: '
            'último GPS=${lastPoint.timestamp.toIso8601String()}, '
            'geocerca=${endZone ?? "Fuera de zona"}, '
            'detenido=${lastPoint.speed < 3.0}, '
            'duración=${duration.inHours}h ${duration.inMinutes % 60}m');
      }

      final idleMinutes = (idleSeconds / 60).round();
      final idleFuelLiters = (idleSeconds / 3600.0) * 2.0; // Base 2.0 L/h; la UI aplica matchedVehicle.consumoRalentiLitrosHora

      return GpsHistoricalTrip(
        plate: plate,
        startTime: startTime,
        endTime: endTime,
        totalDistanceKm: totalDistMeters / 1000.0,
        maxSpeed: maxSpeed,
        avgSpeed: avgSpeed,
        totalPoints: points.length,
        stays: stays,
        routePattern: routePattern,
        points: points,
        legs: legs,
        stops: stops,
        journeyStart: journeyStart,
        journeyEnd: journeyEnd,
        idleMinutes: idleMinutes,
        idleFuelLiters: idleFuelLiters,
      );
    } catch (e) {
      debugPrint('[ModoGPS] Error fetchTripInterval: $e');
      // Reset sesión por si Wialon la invalidó durante la consulta histórica
      // Así el próximo fetchFleetData (vista en vivo) re-autentica limpiamente
      _cachedEid = null;
      _lastLoginTime = null;
      return null;
    }
  }

  /// Retorna la distancia en km acumulada por GPS en un intervalo de tiempo para una patente
  Future<double?> getGpsDistanceForInterval({
    required String plate,
    required DateTime startTime,
    required DateTime endTime,
    String? idEmpresa,
  }) async {
    try {
      final trip = await fetchTripInterval(
        plate: plate,
        startTime: startTime,
        endTime: endTime,
        idEmpresa: idEmpresa,
      );
      return trip?.totalDistanceKm;
    } catch (e) {
      debugPrint('[ModoGPS] Error getGpsDistanceForInterval: $e');
      return null;
    }
  }
}
