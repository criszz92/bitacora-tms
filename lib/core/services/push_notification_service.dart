import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';

/// Top-level background message handler para Firebase Cloud Messaging.
/// Se ejecuta cuando la app está en segundo plano o completamente cerrada.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Si ya fue inicializado, continuar
  }

  debugPrint('FCM Background: Mensaje recibido: ${message.messageId}');
  final notification = message.notification;
  final title = notification?.title ?? message.data['title'] ?? 'Bitácora TMS';
  final body = notification?.body ?? message.data['body'] ?? '';

  if (title.isNotEmpty || body.isNotEmpty) {
    await PushNotificationService.showCustomNotification(
      id: notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
    );
  }
}

/// Resultado de la verificación de alertas y sonidos
class PushTestResult {
  final bool isWeb;
  final bool success;
  final String message;
  final String? error;

  const PushTestResult({
    required this.isWeb,
    required this.success,
    required this.message,
    this.error,
  });
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get localNotificationsPlugin => _localNotificationsPlugin;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Configurar notificaciones locales
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _localNotificationsPlugin.initialize(settings: initializationSettings);

    // 2. Crear NotificationChannel v4 de alta prioridad en Android con tono binaural
    final androidImplementation = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'bitacora_binaural_v4',
          'Alertas Inteligentes de Ruta (Binaural 528Hz)',
          description:
              'Canal prioritario para advertencias de romanas, peajes y restricciones con tono binaural 528Hz',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bitacora_alert'),
          enableVibration: true,
        ),
      );

      // Canal legacy v3 para compatibilidad con triggers en la nube ya desplegados
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'bitacora_binaural_v3',
          'Alertas Operacionales Bitácora TMS',
          description: 'Canal compatible para notificaciones push en segundo plano',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bitacora_alert'),
          enableVibration: true,
        ),
      );

      // Solicitar permisos de notificación explícitos para Android 13+ (API 33+)
      await androidImplementation.requestNotificationsPermission();
    }

    // 3. Solicitar permisos en Firebase Messaging
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('FCM AuthorizationStatus: ${settings.authorizationStatus}');

    // 4. Mostrar notificaciones como HUD/banner incluso si la app está en primer plano
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 5. Escuchar mensajes en FOREGROUND (Primer plano)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM: Mensaje recibido en FOREGROUND: ${message.messageId}');
      _showLocalNotification(message);
    });

    // 6. Escuchar cuando se refresca el token FCM
    _messaging.onTokenRefresh.listen((token) {
      debugPrint('FCM: Token refrescado: $token');
      _saveTokenToFirestore(token);
    });

    // 7. Sincronización continua de token con FirebaseAuth:
    // En cuanto el chofer se loguea o restaura su sesión, se persiste el token en su doc de Firestore
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          debugPrint('FCM: Usuario autenticado (${user.uid}), sincronizando token...');
          final token = await _messaging.getToken();
          if (token != null) {
            await _saveTokenToFirestore(token, uid: user.uid);
          }
        } catch (e) {
          debugPrint('FCM: Error al obtener token: $e');
        }
      }
    });
  }

  /// Fuerza la sincronización del token FCM para el usuario actual (usado tras login exitoso)
  static Future<void> syncToken() async {
    try {
      final token = await _messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (token != null && user != null) {
        await _saveTokenToFirestore(token, uid: user.uid);
      }
    } catch (e) {
      debugPrint('FCM: Error en syncToken: $e');
    }
  }

  /// Emite una alerta de prueba en el altavoz / notificación local y sincroniza el token FCM.
  static Future<PushTestResult> testAlertNotification() async {
    if (kIsWeb) {
      return const PushTestResult(
        isWeb: true,
        success: true,
        message: 'ℹ️ Acceso Web / PWA: Las notificaciones nativas en segundo plano y tonos con pantalla bloqueada requieren la APK instalada. Puedes descargar la APK oficial desde el menú.',
      );
    }

    try {
      final androidImpl = _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final areEnabled = await androidImpl.areNotificationsEnabled();
        if (areEnabled == false) {
          final granted = await androidImpl.requestNotificationsPermission();
          if (granted != true) {
            return const PushTestResult(
              isWeb: false,
              success: false,
              message: '⚠️ Permiso de notificaciones deshabilitado en Android. Actívalas en Ajustes > Aplicaciones > HEIRLOG-TMS.',
            );
          }
        }

        // Intentar registrar canal prioritario con tono bitacora_alert
        try {
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              'bitacora_binaural_v4',
              'Alertas Inteligentes de Ruta (Binaural 528Hz)',
              description:
                  'Canal prioritario para advertencias de romanas, peajes y restricciones con tono binaural 528Hz',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('bitacora_alert'),
              enableVibration: true,
            ),
          );
        } catch (channelErr) {
          debugPrint('Aviso: Canal con sonido personalizado no pudo crearse, usando sonido por defecto: $channelErr');
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              'bitacora_binaural_v4',
              'Alertas Inteligentes de Ruta (Binaural 528Hz)',
              description:
                  'Canal prioritario para advertencias de romanas, peajes y restricciones',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
        }
      }

      await showCustomNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '🔔 Alerta Bitácora TMS (Nativo)',
        body: 'Altavoz y canal binaural 528Hz activo. Notificación de alta prioridad verificada en tu Android.',
      );
      await syncToken();
      return const PushTestResult(
        isWeb: false,
        success: true,
        message: '✓ Alerta binaural emitida al altavoz (APK Android Nativa Activa).',
      );
    } catch (e) {
      debugPrint('Error en testAlertNotification: $e');
      return PushTestResult(
        isWeb: false,
        success: false,
        message: 'Error al emitir sonido en Android: $e',
        error: e.toString(),
      );
    }
  }

  static Future<void> _saveTokenToFirestore(String token, {String? uid}) async {
    final targetUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetUid != null) {
      try {
        final payload = kIsWeb
            ? <String, dynamic>{
                'fcmTokenWeb': token,
                'fcmWebUpdatedAt': FieldValue.serverTimestamp(),
              }
            : <String, dynamic>{
                'fcmToken': token,
                'fcmUpdatedAt': FieldValue.serverTimestamp(),
                'platform': defaultTargetPlatform.name,
              };
        await FirebaseFirestore.instance.collection('usuarios').doc(targetUid).set(
              payload,
              SetOptions(merge: true),
            );
        debugPrint('FCM Token (${kIsWeb ? "Web" : "Móvil"}) guardado en Firestore para usuario $targetUid.');
      } catch (e) {
        debugPrint('FCM Error al guardar token en Firestore: $e');
      }
    } else {
      debugPrint('FCM: No hay usuario autenticado para asociar el token todavía.');
    }
  }

  static void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'Bitácora TMS';
    final body = notification?.body ?? message.data['body'] ?? '';

    if (title.isNotEmpty || body.isNotEmpty) {
      showCustomNotification(
        id: notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
      );
    }
  }

  /// Canal exclusivo con sonido armónico binaural propio de Bitácora TMS (v4 limpio)
  static final AndroidNotificationDetails _binauralAlertChannel = AndroidNotificationDetails(
    'bitacora_binaural_v4',
    'Alertas Inteligentes de Ruta (Binaural 528Hz)',
    channelDescription:
        'Canal prioritario para advertencias de romanas, peajes y restricciones con tono binaural 528Hz',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 250, 150, 400]),
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('bitacora_alert'),
    audioAttributesUsage: AudioAttributesUsage.notification,
  );

  /// Dispara una alerta sonora y visual que activa la pantalla y suena fuerte con el tono binaural
  static Future<void> showCustomNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: _binauralAlertChannel,
      );

      await _localNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('Aviso: Falló notificación con sonido personalizado ($e), intentando con sonido estándar...');
      const fallbackDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'bitacora_general_alerts',
          'Alertas Bitácora TMS',
          channelDescription: 'Canal general de notificaciones',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await _localNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: fallbackDetails,
      );
    }
  }

  /// Suscribe el dispositivo al tópico de la empresa para Avisos Masivos ($0 de costo y 0 lecturas)
  static Future<void> subscribeToCompanyAnnouncements(String companyId) async {
    if (kIsWeb) return;
    try {
      final topic = 'empresa_${companyId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_avisos';
      await _messaging.subscribeToTopic(topic);
      debugPrint('FCM: Suscrito con éxito al tópico de avisos: $topic');
    } catch (e) {
      debugPrint('FCM Error al suscribir a tópico: $e');
    }
  }

  /// Cancela la suscripción al tópico
  static Future<void> unsubscribeFromCompanyAnnouncements(String companyId) async {
    if (kIsWeb) return;
    try {
      final topic = 'empresa_${companyId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_avisos';
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('FCM: Desuscrito del tópico de avisos: $topic');
    } catch (e) {
      debugPrint('FCM Error al desuscribir de tópico: $e');
    }
  }
}
