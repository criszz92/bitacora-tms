import 'dart:typed_data';
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

  /// Canal exclusivo con sonido armónico binaural propio de Bitácora TMS
  static final AndroidNotificationDetails _binauralAlertChannel = AndroidNotificationDetails(
    'bitacora_binaural_alert_v2',
    'Alertas Inteligentes de Ruta (Binaural)',
    channelDescription: 'Canal prioritario para advertencias de romanas, peajes y restricciones con tono binaural 528Hz',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 250, 150, 400]),
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('bitacora_alert'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  /// Dispara una alerta sonora y visual que activa la pantalla y suena fuerte con el tono binaural
  static Future<void> showCustomNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: _binauralAlertChannel,
    );

    await _localNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }
}
