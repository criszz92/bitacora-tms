import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Servicio de voz femenina en español (TTS) y alertas acústicas para Navegador Cabina.
class CabinVoiceService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool isMuted = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('es-CL');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.08);
      final voices = await _tts.getVoices;
      if (voices is List) {
        final femaleVoice = voices.whereType<Map>().firstWhere(
          (v) {
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            final name = (v['name'] ?? '').toString().toLowerCase();
            return locale.startsWith('es') &&
                (name.contains('female') || name.contains('mujer') || name.contains('helena') || name.contains('sabina') || name.contains('paulina'));
          },
          orElse: () => {},
        );
        if (femaleVoice.isNotEmpty) {
          await _tts.setVoice({
            'name': femaleVoice['name'].toString(),
            'locale': femaleVoice['locale'].toString(),
          });
        }
      }
      _initialized = true;
    } catch (_) {
      // Silencioso en plataformas sin motor TTS
    }
  }

  Future<void> speak(String text) async {
    if (isMuted || text.trim().isEmpty) return;
    await init();
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> playAlert({String? spokenMessage}) async {
    if (isMuted) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    if (spokenMessage != null && spokenMessage.isNotEmpty) {
      await speak(spokenMessage);
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

