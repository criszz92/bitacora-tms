import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

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

  const UpdateProgress({required this.status, required this.progress});
}

/// Servicio que gestiona la verificación e instalación automática del APK
class AppUpdateService {
  static const String _collection = 'app_version';
  static const String _docId = 'android_driver';

  /// Comprueba si existe una versión más nueva en Firestore
  static Future<AppUpdateInfo?> checkForUpdate() async {
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

  /// Inicia la descarga e instalación OTA del APK en Android
  static Stream<UpdateProgress> executeOtaUpdate(String apkUrl) async* {
    try {
      // ota_update descarga en background a la carpeta de descargas segura de Android
      // y dispara automáticamente el Intent del instalador nativo del sistema.
      final stream = OtaUpdate().execute(apkUrl, destinationFilename: 'bitacora-tms.apk');
      await for (final event in stream) {
        yield UpdateProgress(status: event.status, progress: event.value ?? '0');
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
    final ref = FirebaseStorage.instance.ref('releases/bitacora-tms-v$versionName.apk');
    final uploadTask = await ref.putData(
      apkBytes,
      SettableMetadata(contentType: 'application/vnd.android.package-archive'),
    );
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

