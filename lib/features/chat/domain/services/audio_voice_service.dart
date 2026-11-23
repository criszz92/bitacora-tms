import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

final audioVoiceServiceProvider = Provider<AudioVoiceService>((ref) {
  return AudioVoiceService();
});

class AudioVoiceService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  bool get isRecording => _isRecording;
  AudioPlayer get player => _audioPlayer;

  /// Inicia la grabación del audio en AAC/M4A a 16kbps (Opus/Voice quality - ~15KB por 10s)
  Future<bool> startRecording() async {
    try {
      if (kIsWeb) return false;

      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        debugPrint('Permiso de micrófono denegado');
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/PTT_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Configuración de máxima compresión de voz para respetar Plan Spark ($0)
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 16000, // 16 kbps mono (Ultra liviano)
        sampleRate: 16000,
        numChannels: 1,
      );

      await _audioRecorder.start(config, path: filePath);
      _isRecording = true;
      _currentRecordingPath = filePath;
      _recordingStartTime = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('Error al iniciar grabación: $e');
      _isRecording = false;
      return false;
    }
  }

  /// Detiene la grabación y retorna el archivo y su duración
  Future<({File? file, int durationSec})> stopRecording() async {
    try {
      if (!_isRecording) return (file: null, durationSec: 0);

      final path = await _audioRecorder.stop();
      _isRecording = false;

      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds
          : 0;

      if (path != null && duration >= 1) {
        final file = File(path);
        if (await file.exists()) {
          return (file: file, durationSec: duration);
        }
      }
      return (file: null, durationSec: 0);
    } catch (e) {
      debugPrint('Error al detener grabación: $e');
      _isRecording = false;
      return (file: null, durationSec: 0);
    }
  }

  /// Cancela la grabación descartando el archivo temporal
  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _audioRecorder.stop();
        _isRecording = false;
      }
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  /// Reproduce un audio desde URL de Storage (solo bajo demanda)
  Future<void> playAudio(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Error reproduciendo audio: $e');
    }
  }

  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
  }
}

