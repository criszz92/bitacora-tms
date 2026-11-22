import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

/// Modal interactivo que muestra las novedades y la barra de descarga del APK
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (ctx) => PopScope(
        canPop: !info.mandatory,
        child: AppUpdateDialog(updateInfo: info),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progressValue = 0.0;
  String _statusText = 'Listo para actualizar';
  String? _errorMessage;

  void _startUpdate() {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _statusText = 'Conectando con el servidor de descargas...';
    });

    AppUpdateService.executeOtaUpdate(widget.updateInfo.apkUrl).listen(
      (event) {
        if (!mounted) return;
        debugPrint('[OTA] Event status: ${event.status}, progress: ${event.progress}');
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            final pct = double.tryParse(event.progress) ?? 0.0;
            setState(() {
              _progressValue = (pct / 100.0).clamp(0.01, 1.0);
              _statusText = 'Descargando paquete oficial: ${pct.toStringAsFixed(0)}%';
            });
            break;
          case OtaStatus.INSTALLING:
            setState(() {
              _progressValue = 1.0;
              _statusText = '📦 Verificando paquete e iniciando instalador Android...';
            });
            break;
          case OtaStatus.INSTALLATION_DONE:
            setState(() {
              _progressValue = 1.0;
              _statusText = '✅ Actualización completada con éxito.';
            });
            break;
          case OtaStatus.ALREADY_RUNNING_ERROR:
            setState(() {
              _errorMessage = 'Ya hay una descarga en curso en tu dispositivo.';
              _isDownloading = false;
            });
            break;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            setState(() {
              _errorMessage = 'Permiso para instalar aplicaciones desconocido denegado en Ajustes de Android.';
              _isDownloading = false;
            });
            break;
          case OtaStatus.CANCELED:
            setState(() {
              _statusText = 'Actualización pausada.';
              _isDownloading = false;
            });
            break;
          case OtaStatus.INTERNAL_ERROR:
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.CHECKSUM_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
            setState(() {
              _errorMessage = 'Hubo una interrupción en la descarga (${event.status.name}). Pulsa "Reintentar Descarga".';
              _isDownloading = false;
            });
            break;
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Error de conexión: $err';
          _isDownloading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMandatory = widget.updateInfo.mandatory;

    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isMandatory ? AppColors.error : AppColors.primary).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isMandatory ? Icons.warning_rounded : Icons.system_update_rounded,
              color: isMandatory ? AppColors.error : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMandatory ? 'Actualización Crítica' : '¡Nueva Versión Disponible!',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Versión ${widget.updateInfo.latestVersionName} (Build ${widget.updateInfo.latestBuildNumber})',
                  style: TextStyle(
                    color: isMandatory ? AppColors.error : const Color(0xFF60A5FA),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMandatory) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.error, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta actualización contiene cambios obligatorios en cálculos o seguridad de ruta.',
                        style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Text(
              'NOVEDADES & MEJORAS:',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                widget.updateInfo.releaseNotes,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progressValue > 0 ? _progressValue : null,
                  backgroundColor: Colors.white12,
                  color: AppColors.primary,
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _statusText,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_progressValue > 0)
                      Text(
                        '${(_progressValue * 100).toInt()}%',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!isMandatory && !_isDownloading)
          TextButton(
            onPressed: () async {
              await AppUpdateService.postponeUpdate(widget.updateInfo.latestBuildNumber);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Más Tarde', style: TextStyle(color: Colors.white54)),
          ),
        ElevatedButton.icon(
          onPressed: _isDownloading ? null : _startUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _isDownloading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : const Icon(Icons.download, size: 18),
          label: Text(
            _isDownloading
                ? 'Descargando...'
                : (_errorMessage != null ? 'Reintentar Descarga' : 'Actualizar Ahora'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
