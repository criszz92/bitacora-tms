import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_options.dart';

/// Resultado detallado de la solicitud de permisos GPS.
enum LocationPermissionResult {
  granted,        // Permiso concedido — GPS activo
  denied,         // Denegado temporalmente — se puede volver a pedir
  deniedForever,  // Denegado permanentemente — hay que ir a Ajustes
  serviceDisabled, // El servicio de ubicación está apagado en el dispositivo
}

class LocationService {
  static const String _distanceKey = 'current_trip_distance';
  static const String _lastLatKey = 'last_lat';
  static const String _lastLngKey = 'last_lng';
  static const String _trackingActiveKey = 'is_tracking_active';
  static const String _currentTripIdKey = 'current_trip_id';
  static const String _currentEmpresaIdKey = 'current_empresa_id';

  /// Verifica y solicita permisos GPS.
  /// Retorna un [LocationPermissionResult] detallado para que la UI
  /// pueda reaccionar de forma específica (ej: abrir Ajustes del sistema).
  static Future<LocationPermissionResult> checkAndRequestPermissions() async {
    // 1. Verificar si el servicio de ubicación está habilitado
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GPS] Servicio de ubicación deshabilitado en el dispositivo.');
      return LocationPermissionResult.serviceDisabled;
    }

    // 2. Verificar permiso actual
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('[GPS] Permiso actual: $permission');

    // 3. Si está denegado temporalmente, solicitamos
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[GPS] Permiso tras solicitud: $permission');
    }

    // 4. Clasificar el resultado
    if (permission == LocationPermission.deniedForever) {
      debugPrint('[GPS] Permiso denegado permanentemente — se requiere ir a Ajustes.');
      return LocationPermissionResult.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      debugPrint('[GPS] Permiso denegado temporalmente.');
      return LocationPermissionResult.denied;
    }

    // whileInUse o always → OK
    debugPrint('[GPS] Permiso concedido: $permission');
    return LocationPermissionResult.granted;
  }

  /// Abre la pantalla de ajustes del sistema para que el usuario
  /// pueda habilitar los permisos de ubicación manualmente.
  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
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
        autoStartOnBoot: false,
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

    // Inicializar Firebase en el isolate de background
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Ya podría estar inicializado
    }

    final prefs = await SharedPreferences.getInstance();
    final Distance distanceCalculator = const Distance();

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('updateNotification').listen((event) {
      if (service is AndroidServiceInstance && event != null) {
        service.setForegroundNotificationInfo(
          title: event['title']?.toString() ?? "Bitácora TMS",
          content: event['content']?.toString() ?? "Segundo plano activo",
        );
      }
    });

    final List<Map<String, dynamic>> pointsBuffer = [];

    // Actualizar notificación inmediatamente para confirmar que el servicio arrancó
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Bitácora TMS - Turno Activo",
        content: "Monitoreo de ruta y alertas activo",
      );
    }

    // Escuchar actualizaciones de ubicación
    try {
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30, // Cada 30 metros
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "Bitácora Telemetría",
            notificationText: "Rastreando ruta en segundo plano",
            enableWakeLock: true,
          ),
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
      }, onError: (error) {
        debugPrint("[GPS] Error en position stream: $error");
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "Bitácora - Error GPS",
            content: "Error al obtener ubicación: $error",
          );
        }
      });
    } catch (e) {
      debugPrint("[GPS] Error crítico al iniciar stream: $e");
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "Bitácora - Error GPS",
          content: "No se pudo iniciar el rastreo: $e",
        );
      }
    }
  }

  // Suscripción IPC para recibir actualizaciones del servicio background
  static StreamSubscription? _updateSubscription;
  static double _lastKnownDistance = 0.0;

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

    // Cancelar listener previo para evitar duplicados y memory leaks
    _updateSubscription?.cancel();

    _updateSubscription = service.on('update').listen((event) {
      if (event != null && event['distance'] != null) {
        _lastKnownDistance = (event['distance'] as num).toDouble();
      }
    });
    
    await service.startService();
  }

  static Future<double> stopTracking() async {
    final service = FlutterBackgroundService();
    
    // 1. Leer la distancia persistida ANTES de matar el servicio.
    //    SharedPreferences es la fuente de verdad (escrita por el isolate de background).
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Forzar recarga fresca desde disco
    final persistedDistance = prefs.getDouble(_distanceKey) ?? 0.0;
    
    // 2. Usar el mayor entre el valor en memoria (IPC) y el persistido (disco).
    //    Esto cubre ambos escenarios: listener activo vs listener perdido.
    final distanceToReturn = persistedDistance > _lastKnownDistance
        ? persistedDistance
        : _lastKnownDistance;
    
    // 3. Detener el servicio de background
    service.invoke('stopService');
    
    // 4. Cancelar la suscripción IPC
    _updateSubscription?.cancel();
    _updateSubscription = null;
    
    // 5. Limpiar estado en SharedPreferences y memoria
    _lastKnownDistance = 0.0;
    await prefs.setBool(_trackingActiveKey, false);
    await prefs.remove(_distanceKey);
    await prefs.remove(_lastLatKey);
    await prefs.remove(_lastLngKey);
    await prefs.remove(_currentTripIdKey);
    
    return distanceToReturn;
  }

  /// Inicia el Foreground Service para evitar que Android mate la app mientras el chofer está en turno
  static Future<void> startKeepAlive({String? title, String? content}) async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
    service.invoke('updateNotification', {
      'title': title ?? 'Bitácora TMS - Turno Activo',
      'content': content ?? 'Monitoreo de ruta y alertas activo',
    });
  }

  /// Detiene el Foreground Service cuando se cierra el turno o la sesión
  static Future<void> stopKeepAlive() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
    }
  }
}
