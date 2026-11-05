import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Solicitar permisos para iOS/Android
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('FCM: Permisos de notificación concedidos.');
      
      // 2. Obtener el token FCM del dispositivo
      String? token = await _messaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        await _saveTokenToFirestore(token);
      }

      // Escuchar si el token cambia
      _messaging.onTokenRefresh.listen(_saveTokenToFirestore);

      // 3. Configurar notificaciones locales para cuando la app está en FOREGROUND
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
      await _localNotificationsPlugin.initialize(settings: initializationSettings);

      // 4. Escuchar mensajes en FOREGROUND
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM: Mensaje recibido en FOREGROUND: ${message.messageId}');
        _showLocalNotification(message);
      });
    } else {
      debugPrint('FCM: Permisos de notificación denegados.');
    }
  }

  static Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).update({
        'fcmToken': token,
      });
      debugPrint('FCM Token actualizado en Firestore para el usuario ${user.uid}.');
    }
  }

  static void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    showCustomNotification(
      id: notification.hashCode,
      title: notification.title ?? 'Notificación Bitácora',
      body: notification.body ?? '',
    );
  }

  /// Dispara una notificación local inmediata para avisar al conductor en ruta
  /// (ej: aproximación a romana, peaje, o restricción horaria)
  static Future<void> showCustomNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'bitacora_high_importance_channel',
      'Alertas de Ruta y Telemetría',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await _localNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }
}
