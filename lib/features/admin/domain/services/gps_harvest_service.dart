import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'modogps_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE DATOS
// ─────────────────────────────────────────────────────────────────────────────

/// Evento puntual detectado durante el monitoreo
class GpsEvent {
  final String plate;
  final String type; // engine_on|engine_off|speeding|idle_end|trip_start|trip_end
  final DateTime timestamp;
  final double lat;
  final double lng;
  final double? speed;
  final double? value;
  final String? notes;

  GpsEvent({
    required this.plate,
    required this.type,
    required this.timestamp,
    required this.lat,
    required this.lng,
    this.speed,
    this.value,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'plate': plate,
    'type': type,
    'timestamp': Timestamp.fromDate(timestamp),
    'lat': lat,
    'lng': lng,
    if (speed != null) 'speed': speed,
    if (value != null) 'value': value,
    if (notes != null) 'notes': notes,
  };
}

/// Resumen compacto de un viaje completo (lo que la IA consume)
class TripSummary {
  final String plate;
  final DateTime startTime;
  final DateTime endTime;
  final double startLat, startLng, endLat, endLng;
  final double maxSpeed, avgSpeed, totalDistanceKm;
  final int totalStops, totalIdleMinutes, durationMinutes, positionsRecorded;
  final List<GpsEvent> events;

  TripSummary({
    required this.plate,
    required this.startTime,
    required this.endTime,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.totalDistanceKm,
    required this.totalStops,
    required this.totalIdleMinutes,
    required this.durationMinutes,
    required this.positionsRecorded,
    required this.events,
  });

  String _buildAiSummary() {
    final d = startTime;
    final dateStr = '${d.day.toString().padLeft(2,'0')}-${d.month.toString().padLeft(2,'0')}-${d.year}';
    final s = '${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}';
    final e = '${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}';
    final speedingCount = events.where((ev) => ev.type == 'speeding').length;
    return 'Camion $plate | $dateStr $s->$e (${durationMinutes}min) | '
        '${totalDistanceKm.toStringAsFixed(0)}km | '
        'avg ${avgSpeed.toStringAsFixed(0)}km/h max ${maxSpeed.toStringAsFixed(0)}km/h | '
        '$totalStops paradas ${totalIdleMinutes}min ralenti | '
        '$speedingCount alertas velocidad';
  }

  Map<String, dynamic> toMap() => {
    'plate': plate,
    'start_time': Timestamp.fromDate(startTime),
    'end_time': Timestamp.fromDate(endTime),
    'start_lat': startLat,
    'start_lng': startLng,
    'end_lat': endLat,
    'end_lng': endLng,
    'max_speed_kmh': maxSpeed.toStringAsFixed(1),
    'avg_speed_kmh': avgSpeed.toStringAsFixed(1),
    'total_distance_km': totalDistanceKm.toStringAsFixed(2),
    'total_stops': totalStops,
    'total_idle_minutes': totalIdleMinutes,
    'duration_minutes': durationMinutes,
    'positions_recorded': positionsRecorded,
    'speeding_alerts': events.where((ev) => ev.type == 'speeding').length,
    'created_at': FieldValue.serverTimestamp(),
    'ai_summary': _buildAiSummary(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ESTADO INTERNO POR UNIDAD
// ─────────────────────────────────────────────────────────────────────────────

class _UnitState {
  final List<GpsUnit> positions = [];
  final List<GpsEvent> events = [];
  bool tripActive = false;
  DateTime? tripStartTime;
  double? tripStartLat, tripStartLng;
  DateTime? idleStartedAt;
  bool wasIdle = false;
  int totalIdleMinutes = 0, totalStops = 0;
  double maxSpeed = 0, speedSum = 0;
  int speedSamples = 0;
  DateTime? lastSpeedingAlert;

  static double haversineKm(double la1, double ln1, double la2, double ln2) {
    const r = 6371.0;
    double toRad(double d) => d * 3.14159265 / 180.0;
    final dLat = toRad(la2 - la1), dLng = toRad(ln2 - ln1);
    double sin(double x) => x - x*x*x/6 + x*x*x*x*x/120;
    double cos(double x) => 1 - x*x/2 + x*x*x*x/24;
    double sqrt(double x) {
      if (x <= 0) return 0;
      double g = x / 2;
      for (int i = 0; i < 10; i++) { g = (g + x / g) / 2; }
      return g;
    }
    double asin(double x) => x >= 1 ? 1.5707 : (x <= -1 ? -1.5707 : x + x*x*x/6 + 3*x*x*x*x*x/40);
    final sinDlat = sin(dLat/2), sinDlng = sin(dLng/2);
    final a = sinDlat*sinDlat + cos(toRad(la1))*cos(toRad(la2))*sinDlng*sinDlng;
    return r * 2 * asin(sqrt(a));
  }

  double get totalDistanceKm {
    if (positions.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < positions.length; i++) {
      total += haversineKm(
        positions[i-1].position.latitude, positions[i-1].position.longitude,
        positions[i].position.latitude,   positions[i].position.longitude,
      );
    }
    return total;
  }

  void reset() {
    positions.clear(); events.clear();
    tripActive = false; tripStartTime = null;
    tripStartLat = null; tripStartLng = null;
    idleStartedAt = null; wasIdle = false;
    totalIdleMinutes = 0; totalStops = 0;
    maxSpeed = 0; speedSum = 0; speedSamples = 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class GpsHarvestService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, _UnitState> _states = {};

  static const double _speedingThreshold = 90.0;
  static const Duration _minStopDuration = Duration(minutes: 2);
  static const int _rawSampleEvery = 3; // Guarda posicion cruda cada 3 ciclos (~15s)
  int _sampleCount = 0;

  /// Punto de entrada principal. Llamar en cada ciclo del stream GPS.
  Future<void> ingest(List<GpsUnit> units, {String? idEmpresa}) async {
    final empresa = idEmpresa ?? 'default';
    _sampleCount++;
    final saveRaw = (_sampleCount % _rawSampleEvery == 0);

    for (final unit in units) {
      final st = _states.putIfAbsent(unit.plate, () => _UnitState());

      // 1. Guardar posicion cruda (muestreo reducido)
      if (saveRaw) {
        _saveRaw(unit, empresa).ignore();
      }

      // 2. Metricas de velocidad
      if (unit.speed > 0) {
        st.speedSum += unit.speed;
        st.speedSamples++;
        if (unit.speed > st.maxSpeed) st.maxSpeed = unit.speed;
      }

      // 3. Inicio de viaje
      if ((unit.isIgnitionOn == true) && unit.speed > 2 && !st.tripActive) {
        st.reset();
        st.tripActive = true;
        st.tripStartTime = unit.lastUpdate;
        st.tripStartLat = unit.position.latitude;
        st.tripStartLng = unit.position.longitude;
        final ev = GpsEvent(plate: unit.plate, type: 'trip_start',
          timestamp: unit.lastUpdate, lat: unit.position.latitude, lng: unit.position.longitude, speed: unit.speed);
        st.events.add(ev);
        _saveEvent(ev, empresa).ignore();
        debugPrint('[Harvest] Viaje iniciado: ${unit.plate}');
      }

      // 4. Durante viaje activo
      if (st.tripActive) {
        st.positions.add(unit);

        // 4a. Deteccion de paradas (ralenti)
        final isIdle = (unit.isIgnitionOn == true) && unit.speed < 2;
        if (isIdle && !st.wasIdle) {
          st.idleStartedAt = unit.lastUpdate;
          st.wasIdle = true;
        } else if (!isIdle && st.wasIdle && st.idleStartedAt != null) {
          final idleDur = unit.lastUpdate.difference(st.idleStartedAt!);
          if (idleDur >= _minStopDuration) {
            st.totalStops++;
            st.totalIdleMinutes += idleDur.inMinutes;
            final ev = GpsEvent(
              plate: unit.plate, type: 'idle_end',
              timestamp: unit.lastUpdate,
              lat: unit.position.latitude, lng: unit.position.longitude,
              value: idleDur.inMinutes.toDouble(),
              notes: 'Parada ${idleDur.inMinutes} min',
            );
            st.events.add(ev);
            _saveEvent(ev, empresa).ignore();
          }
          st.wasIdle = false;
          st.idleStartedAt = null;
        }

        // 4b. Alerta exceso velocidad (max 1 alerta cada 5 min)
        if (unit.speed > _speedingThreshold) {
          final now = unit.lastUpdate;
          if (st.lastSpeedingAlert == null ||
              now.difference(st.lastSpeedingAlert!) > const Duration(minutes: 5)) {
            st.lastSpeedingAlert = now;
            final ev = GpsEvent(
              plate: unit.plate, type: 'speeding',
              timestamp: now,
              lat: unit.position.latitude, lng: unit.position.longitude,
              speed: unit.speed,
              notes: 'Velocidad ${unit.speed.toStringAsFixed(0)} km/h (limite ${_speedingThreshold.toStringAsFixed(0)})',
            );
            st.events.add(ev);
            _saveEvent(ev, empresa).ignore();
          }
        }
      }

      // 5. Fin de viaje (ignicion OFF o sin señal)
      if ((unit.isIgnitionOn == false || unit.status == 'offline') && st.tripActive) {
        st.tripActive = false;
        final startTime = st.tripStartTime;
        if (startTime != null && st.positions.length >= 3) {
          final durMin = unit.lastUpdate.difference(startTime).inMinutes;
          if (durMin >= 3) {
            final avg = st.speedSamples > 0 ? st.speedSum / st.speedSamples : 0.0;
            final summary = TripSummary(
              plate: unit.plate,
              startTime: startTime,
              endTime: unit.lastUpdate,
              startLat: st.tripStartLat!, startLng: st.tripStartLng!,
              endLat: unit.position.latitude, endLng: unit.position.longitude,
              maxSpeed: st.maxSpeed, avgSpeed: avg,
              totalDistanceKm: st.totalDistanceKm,
              totalStops: st.totalStops,
              totalIdleMinutes: st.totalIdleMinutes,
              durationMinutes: durMin,
              positionsRecorded: st.positions.length,
              events: List.from(st.events),
            );
            _saveTripSummary(summary, empresa).ignore();
            debugPrint('[Harvest] Viaje cerrado: ${unit.plate} | ${durMin}min | ${st.totalDistanceKm.toStringAsFixed(0)}km');
          }
        }
        st.reset();
      }
    }
  }

  // ─── Escrituras Firestore ──────────────────────────────────────────────────

  Future<void> _saveRaw(GpsUnit u, String empresa) async {
    await _db.collection('telemetry').doc(empresa).collection('raw_positions').add({
      'plate': u.plate, 'lat': u.position.latitude, 'lng': u.position.longitude,
      'speed_kmh': u.speed, 'course': u.course, 'ignition': u.isIgnitionOn,
      'satellites': u.satellites, 'status': u.status,
      'ts': Timestamp.fromDate(u.lastUpdate),
    });
  }

  Future<void> _saveEvent(GpsEvent ev, String empresa) async {
    await _db.collection('telemetry').doc(empresa).collection('events').add(ev.toMap());
  }

  Future<void> _saveTripSummary(TripSummary s, String empresa) async {
    await _db.collection('telemetry').doc(empresa).collection('trip_summaries').add(s.toMap());
  }

  // ─── Consultas para IA (devuelven texto compacto, NO coordenadas brutas) ──

  /// Ultimos resúmenes de viajes en formato de texto para contexto de IA
  Future<List<String>> getRecentTripSummariesForAi({
    required String empresa,
    String? plate,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('telemetry')
          .doc(empresa)
          .collection('trip_summaries')
          .orderBy('start_time', descending: true)
          .limit(limit);
      if (plate != null && plate.isNotEmpty) {
        q = q.where('plate', isEqualTo: plate);
      }
      final snap = await q.get();
      return snap.docs
          .map((d) => d.data()['ai_summary'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Harvest] getRecentTripSummariesForAi error: $e');
      return [];
    }
  }

  /// Ultimos eventos criticos en formato texto para contexto de IA
  Future<List<String>> getRecentEventsForAi({
    required String empresa,
    String? plate,
    int limit = 30,
    List<String> types = const ['speeding', 'idle_end', 'trip_start', 'trip_end'],
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('telemetry')
          .doc(empresa)
          .collection('events')
          .where('type', whereIn: types)
          .orderBy('timestamp', descending: true)
          .limit(limit);
      if (plate != null && plate.isNotEmpty) {
        q = q.where('plate', isEqualTo: plate);
      }
      final snap = await q.get();
      return snap.docs.map((d) {
        final data = d.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final dateStr = ts != null
            ? '${ts.day}/${ts.month} ${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}'
            : '?';
        return '[${data['type']}] ${data['plate']} @ $dateStr'
            '${data['notes'] != null ? " — ${data['notes']}" : ""}';
      }).toList();
    } catch (e) {
      debugPrint('[Harvest] getRecentEventsForAi error: $e');
      return [];
    }
  }

  /// Estadísticas agregadas de la flota (sin IA, solo datos calculados)
  Future<Map<String, dynamic>> getFleetStats({required String empresa}) async {
    try {
      final snap = await _db
          .collection('telemetry')
          .doc(empresa)
          .collection('trip_summaries')
          .orderBy('start_time', descending: true)
          .limit(100)
          .get();
      if (snap.docs.isEmpty) return {};

      double totalKm = 0; int totalStops = 0, totalIdleMin = 0; double maxSpeedSeen = 0;
      final plates = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        totalKm += double.tryParse(data['total_distance_km']?.toString() ?? '0') ?? 0;
        totalStops += (data['total_stops'] as int? ?? 0);
        totalIdleMin += (data['total_idle_minutes'] as int? ?? 0);
        plates.add(data['plate'] as String? ?? '');
        final ms = double.tryParse(data['max_speed_kmh']?.toString() ?? '0') ?? 0;
        if (ms > maxSpeedSeen) maxSpeedSeen = ms;
      }

      final evSnap = await _db
          .collection('telemetry').doc(empresa).collection('events')
          .where('type', isEqualTo: 'speeding').limit(500).get();

      return {
        'total_trips': snap.docs.length,
        'total_km': totalKm.toStringAsFixed(0),
        'avg_km_per_trip': snap.docs.isNotEmpty ? (totalKm / snap.docs.length).toStringAsFixed(1) : '0',
        'total_stops': totalStops,
        'total_idle_hours': (totalIdleMin / 60).toStringAsFixed(1),
        'speeding_events': evSnap.docs.length,
        'max_speed_seen_kmh': maxSpeedSeen.toStringAsFixed(0),
        'active_trucks': plates.length,
        'plates': plates.toList(),
      };
    } catch (e) {
      debugPrint('[Harvest] getFleetStats error: $e');
      return {};
    }
  }
}
