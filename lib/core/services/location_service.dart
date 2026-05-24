import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationService {
  static const String _distanceKey = 'current_trip_distance';
  static const String _lastLatKey = 'last_lat';
  static const String _lastLngKey = 'last_lng';
  static const String _trackingActiveKey = 'is_tracking_active';
  static const String _currentTripIdKey = 'current_trip_id';
  static const String _currentEmpresaIdKey = 'current_empresa_id';

  static Future<bool> checkAndRequestPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // Para rastreo en segundo plano, idealmente necesitamos Always
    // pero permitimos continuar si al menos es WhileInUse por ahora, 
    // aunque lo ideal es solicitar Always explícitamente en Android 10+.
    return true;
  }


  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'telemetry_service',
      'Servicio de Telemetría',
      description: 'Rastreo de ruta para cálculo de kilómetros',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'telemetry_service',
        initialNotificationTitle: 'Bitácora Telemetría',
        initialNotificationContent: 'Preparando rastreo...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final Distance distanceCalculator = const Distance();

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    final List<Map<String, dynamic>> pointsBuffer = [];

    // Escuchar actualizaciones de ubicación
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30, // Cada 30 metros
      ),
    ).listen((Position position) async {
      await prefs.reload();
      final isTracking = prefs.getBool(_trackingActiveKey) ?? false;
      if (!isTracking) return;

      final String? tripId = prefs.getString(_currentTripIdKey);

      double lastLat = prefs.getDouble(_lastLatKey) ?? 0.0;
      double lastLng = prefs.getDouble(_lastLngKey) ?? 0.0;
      double currentDistance = prefs.getDouble(_distanceKey) ?? 0.0;

      if (lastLat != 0.0 && lastLng != 0.0) {
        final double traveled = distanceCalculator.as(
          LengthUnit.Meter,
          LatLng(lastLat, lastLng),
          LatLng(position.latitude, position.longitude),
        );

        if (traveled > 5 && traveled < 50000) {
          currentDistance += (traveled / 1000);
          await prefs.setDouble(_distanceKey, currentDistance);
        }
      }

      await prefs.setDouble(_lastLatKey, position.latitude);
      await prefs.setDouble(_lastLngKey, position.longitude);

      // AGREGAR AL BUFFER LOCAL
      pointsBuffer.add({
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'speed': position.speed,
        'accuracy': position.accuracy,
      });

      // SUBIR A FIRESTORE CADA 5 PUNTOS (Ahorro de datos)
      if (tripId != null && pointsBuffer.length >= 5) {
        try {
          final firestore = FirebaseFirestore.instance;
          final batch = firestore.batch();
          
          for (var point in pointsBuffer) {
            final docRef = firestore
                .collection('viajes')
                .doc(tripId)
                .collection('puntos')
                .doc();
            batch.set(docRef, {
              ...point,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
          
          await batch.commit();
          pointsBuffer.clear();
        } catch (e) {
          debugPrint("Error sincronizando lote GPS: $e");
          if (pointsBuffer.length > 50) pointsBuffer.removeAt(0);
        }
      }

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "Bitácora - Viaje en Progreso",
          content: "Distancia: ${currentDistance.toStringAsFixed(2)} KM",
        );
      }

      service.invoke('update', {
        "distance": currentDistance,
        "latitude": position.latitude,
        "longitude": position.longitude,
      });
    });
  }

  static Future<void> startTracking({required String tripId, required String empresaId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_distanceKey, 0.0);
    await prefs.setDouble(_lastLatKey, 0.0);
    await prefs.setDouble(_lastLngKey, 0.0);
    await prefs.setBool(_trackingActiveKey, true);
    await prefs.setString(_currentTripIdKey, tripId);
    await prefs.setString(_currentEmpresaIdKey, empresaId);
    
    _lastKnownDistance = 0.0;
    
    final service = FlutterBackgroundService();

    service.on('update').listen((event) {
      if (event != null && event['distance'] != null) {
        _lastKnownDistance = (event['distance'] as num).toDouble();
      }
    });
    
    await service.startService();
  }

  static double _lastKnownDistance = 0.0;

  static Future<double> stopTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    
    final distanceToReturn = _lastKnownDistance;
    _lastKnownDistance = 0.0;
    
    return distanceToReturn;
  }
}
