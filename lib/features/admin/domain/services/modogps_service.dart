import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'wialon_caller.dart';

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

  Future<List<GpsUnit>> fetchFleetData({String? idEmpresa}) async {
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
        'flags': 2102273, // 1 (base) + 1024 (pos) + 2097152 (status) + 4096 (sensors)
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

      final units = <GpsUnit>[];

      for (final item in items) {
        if (item is! Map) continue;
        final name = item['nm']?.toString() ?? 'S/P';
        final id = item['id']?.toString() ?? '';
        final pos = item['pos'] as Map?;
        final netconn = item['netconn'] as num? ?? 0;
        final lmsg = item['lmsg'] as Map?;
        final pwrExt = (lmsg?['p'] as Map?)?['pwr_ext'] as num?;

        if (pos != null) {
          final lat = (pos['y'] as num?)?.toDouble() ?? 0.0;
          final lng = (pos['x'] as num?)?.toDouble() ?? 0.0;
          final speed = (pos['s'] as num?)?.toDouble() ?? 0.0;
          final course = (pos['c'] as num?)?.toDouble();
          final satCount = pos['sc'] as int?;
          final timestamp = pos['t'] != null
              ? DateTime.fromMillisecondsSinceEpoch((pos['t'] as int) * 1000)
              : DateTime.now();

          String status;
          if (netconn == 1) {
            status = speed > 0 ? 'online' : 'detenido';
          } else {
            status = 'offline';
          }

          units.add(GpsUnit(
            id: id,
            plate: name,
            driverName: 'Conductor Asignado',
            position: LatLng(lat, lng),
            speed: speed,
            status: status,
            lastUpdate: timestamp,
            course: course,
            isIgnitionOn: pwrExt != null && pwrExt > 0,
            externalPower: pwrExt?.toDouble(),
            satellites: satCount,
          ));
        }
      }

      return units;
    } catch (e) {
      debugPrint("ModoGPS fetchFleetData error: $e");
      rethrow;
    }
  }
}
