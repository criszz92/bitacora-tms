import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../services/app_update_service.dart';

/// Modal interactivo que muestra las novedades y la barra de descarga del APK
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (ctx) => AppUpdateDialog(updateInfo: info),
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
      _statusText = 'Conectando con el servidor...';
    });

    AppUpdateService.executeOtaUpdate(widget.updateInfo.apkUrl).listen(
      (event) {
        if (!mounted) return;
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            final pct = double.tryParse(event.progress) ?? 0.0;
            setState(() {
              _progressValue = (pct / 100.0).clamp(0.0, 1.0);
              _statusText = 'Descargando actualización: ${pct.toStringAsFixed(0)}%';
            });
            break;
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            setState(() {
              _progressValue = 1.0;
              _statusText = 'Iniciando instalador nativo de Android...';
            });
            break;
          case OtaStatus.ALREADY_RUNNING_ERROR:
            setState(() {
              _errorMessage = 'Ya hay una descarga en curso.';
              _isDownloading = false;
            });
            break;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            setState(() {
              _errorMessage = 'Permiso para instalar aplicaciones denegado.';
              _isDownloading = false;
            });
            break;
          case OtaStatus.CANCELED:
            setState(() {
              _statusText = 'Actualización cancelada';
              _isDownloading = false;
            });
            break;
          case OtaStatus.INTERNAL_ERROR:
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.CHECKSUM_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
            setState(() {
              _errorMessage = 'Error al descargar o instalar el paquete. Inténtalo de nuevo.';
              _isDownloading = false;
            });
            break;
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Error: $err';
          _isDownloading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.system_update_alt_rounded, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¡Nueva Versión Disponible!',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Versión ${widget.updateInfo.latestVersionName} (Build ${widget.updateInfo.latestBuildNumber})',
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w600),
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
                  color: Colors.blueAccent,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _statusText,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
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
        if (!widget.updateInfo.mandatory && !_isDownloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Más Tarde', style: TextStyle(color: Colors.white54)),
          ),
        ElevatedButton.icon(
          onPressed: _isDownloading ? null : _startUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _isDownloading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : const Icon(Icons.download, size: 18),
          label: Text(
            _isDownloading ? 'Descargando...' : 'Actualizar Ahora',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

