import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Información de actualización remota
class AppUpdateInfo {
  final int latestBuildNumber;
  final String latestVersionName;
  final String apkUrl;
  final String releaseNotes;
  final bool mandatory;

  const AppUpdateInfo({
    required this.latestBuildNumber,
    required this.latestVersionName,
    required this.apkUrl,
    required this.releaseNotes,
    this.mandatory = false,
  });
}

/// Estado de progreso de descarga OTA
class UpdateProgress {
  final OtaStatus status;
  final String progress; // "0" a "100"
  final String? detailText;

  const UpdateProgress({
    required this.status,
    required this.progress,
    this.detailText,
  });
}

/// Servicio que gestiona la verificación e instalación automática del APK
class AppUpdateService {
  static const String _collection = 'app_version';
  static const String _docId = 'android_driver';
  static const String _prefKeyPostponedBuild = 'postponed_update_build';
  static const String _prefKeyPostponedDate = 'postponed_update_date';

  /// Comprueba si existe una versión más nueva en Firestore
  /// [ignorePostponed]: Si es true (ej: desde "Buscar Actualizaciones" manual), ignora si el chofer pulsó "Más Tarde"
  static Future<AppUpdateInfo?> checkForUpdate({bool ignorePostponed = false}) async {
    // Solo aplica para Android nativo
    if (kIsWeb) return null;

    try {
      final snap = await FirebaseFirestore.instance.collection(_collection).doc(_docId).get();
      if (!snap.exists || snap.data() == null) return null;

      final data = snap.data()!;
      final latestBuild = (data['buildNumber'] as num?)?.toInt() ?? 1;
      final latestName = data['versionName']?.toString() ?? '1.0.0';
      final apkUrl = data['apkUrl']?.toString() ?? '';
      final notes = data['releaseNotes']?.toString() ?? 'Mejoras de estabilidad y rendimiento.';
      final mandatory = data['mandatory'] == true;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (latestBuild > currentBuild && apkUrl.isNotEmpty) {
        // Si no es obligatoria y no estamos forzando la búsqueda manual:
        if (!mandatory && !ignorePostponed) {
          final isPostponed = await _isUpdatePostponed(latestBuild);
          if (isPostponed) {
            debugPrint('[AppUpdateService] Actualización no crítica pospuesta por el usuario.');
            return null;
          }
        }

        return AppUpdateInfo(
          latestBuildNumber: latestBuild,
          latestVersionName: latestName,
          apkUrl: apkUrl,
          releaseNotes: notes,
          mandatory: mandatory,
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error al verificar versión: $e');
    }
    return null;
  }

  /// Guarda que el usuario pospuso la actualización durante el día
  static Future<void> postponeUpdate(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyPostponedBuild, buildNumber);
    await prefs.setString(_prefKeyPostponedDate, DateTime.now().toIso8601String().substring(0, 10));
  }

  /// Verifica si el usuario ya pospuso esta versión en el mismo día
  static Future<bool> _isUpdatePostponed(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBuild = prefs.getInt(_prefKeyPostponedBuild);
    final savedDate = prefs.getString(_prefKeyPostponedDate);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    return savedBuild == buildNumber && savedDate == today;
  }

  /// Inicia la descarga e instalación OTA del APK en Android
  static Stream<UpdateProgress> executeOtaUpdate(String apkUrl) async* {
    try {
      final stream = OtaUpdate().execute(apkUrl, destinationFilename: 'bitacora-tms.apk');
      await for (final event in stream) {
        yield UpdateProgress(
          status: event.status,
          progress: event.value ?? '0',
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error durante descarga OTA: $e');
      yield const UpdateProgress(status: OtaStatus.INTERNAL_ERROR, progress: '0');
    }
  }

  /// Publica o actualiza el registro de la versión oficial en Firestore
  static Future<void> publishAppVersion({
    required int buildNumber,
    required String versionName,
    required String apkUrl,
    required String releaseNotes,
    bool mandatory = false,
  }) async {
    await FirebaseFirestore.instance.collection(_collection).doc(_docId).set({
      'buildNumber': buildNumber,
      'versionName': versionName,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
      'mandatory': mandatory,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sube un APK a Firebase Storage (100% gratuito) y publica la versión en Firestore
  static Future<String> uploadAndPublishApk({
    required Uint8List apkBytes,
    required int buildNumber,
    required String versionName,
    required String releaseNotes,
    bool mandatory = false,
  }) async {
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('app_releases')
        .child('bitacora-tms-v$versionName+$buildNumber.apk');

    final metadata = SettableMetadata(
      contentType: 'application/vnd.android.package-archive',
      customMetadata: {
        'versionName': versionName,
        'buildNumber': buildNumber.toString(),
      },
    );

    final uploadTask = await storageRef.putData(apkBytes, metadata);
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    await publishAppVersion(
      buildNumber: buildNumber,
      versionName: versionName,
      apkUrl: downloadUrl,
      releaseNotes: releaseNotes,
      mandatory: mandatory,
    );

    return downloadUrl;
  }
}
