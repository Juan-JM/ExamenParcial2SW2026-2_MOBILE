import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voz de Nova en el celular: habla las respuestas y escucha preguntas.
///
/// Usa la misma voz que la web: la **masculina de Google en español de
/// España**. En la web es "Google español" (Chrome); en Android es una voz
/// es-ES del motor de Google ("Speech Services by Google"). La de Estados
/// Unidos no se usa porque es de mujer.
class NovaVoice {
  NovaVoice._();

  static final instance = NovaVoice._();

  static const _googleEngine = 'com.google.android.tts';

  /// Voces masculinas es-ES del motor de Google, de la preferida a la menos.
  /// Las "-network" suenan como la de Chrome; las "-local" funcionan sin red.
  static const _preferredVoices = [
    'es-es-x-eed-network',
    'es-es-x-eed-local',
    'es-es-x-eef-network',
    'es-es-x-eef-local',
  ];

  final _tts = FlutterTts();
  final _stt = SpeechToText();

  bool _ttsReady = false;
  bool _sttReady = false;

  /// Si Nova lee en voz alta sus respuestas (botón de parlante).
  final enabled = ValueNotifier<bool>(true);

  /// Id del mensaje que se está leyendo, o null.
  final speaking = ValueNotifier<String?>(null);

  /// Si el micrófono está escuchando.
  final listening = ValueNotifier<bool>(false);

  Future<void> _prepareTts() async {
    if (_ttsReady) return;
    _ttsReady = true;

    try {
      final engines = (await _tts.getEngines as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (engines.contains(_googleEngine)) await _tts.setEngine(_googleEngine);

      await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.5); // 0.5 en Android = velocidad normal (la web usa rate 1)
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      final voices = ((await _tts.getVoices) as List? ?? const [])
          .whereType<Map>()
          .map((v) => {'name': '${v['name']}', 'locale': '${v['locale']}'})
          .toList();
      final voice = pickVoice(voices);
      if (voice != null) await _tts.setVoice(voice);
      debugPrint('NovaVoice: voz ${voice?['name'] ?? 'por defecto es-ES'}');

      _tts.setCompletionHandler(() => speaking.value = null);
      _tts.setCancelHandler(() => speaking.value = null);
      _tts.setErrorHandler((_) => speaking.value = null);
    } catch (error) {
      debugPrint('NovaVoice: no se pudo preparar la voz: $error');
    }
  }

  /// La voz masculina es-ES de Google; si no está, cualquier es-ES masculina; si no, cualquier es-ES.
  @visibleForTesting
  static Map<String, String>? pickVoice(List<Map<String, String>> voices) {
    final spain = voices.where((v) => v['locale']!.toLowerCase().replaceAll('_', '-').startsWith('es-es')).toList();

    for (final name in _preferredVoices) {
      final match = spain.where((v) => v['name']!.toLowerCase() == name).firstOrNull;
      if (match != null) return match;
    }

    final male = spain.where((v) => RegExp(r'male|hombre|eed|eef', caseSensitive: false).hasMatch(v['name']!));
    return male.firstOrNull ?? spain.firstOrNull;
  }

  /// Lee [text] en voz alta (corta lo que estuviera leyendo).
  Future<void> speak(String id, String text) async {
    final clean = _forSpeech(text);
    if (clean.isEmpty) return;

    await _prepareTts();
    await _tts.stop();
    speaking.value = id;
    await _tts.speak(clean);
    if (speaking.value == id) speaking.value = null;
  }

  Future<void> stopSpeaking() async {
    speaking.value = null;
    await _tts.stop();
  }

  /// Escucha una pregunta en español. [onWords] recibe el texto parcial;
  /// [onDone] el texto final (vacío si no se entendió nada).
  Future<bool> listen({required ValueChanged<String> onWords, required ValueChanged<String> onDone}) async {
    await stopSpeaking();

    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) listening.value = false;
        },
        onError: (_) => listening.value = false,
      );
    }
    if (!_sttReady) return false;

    final locales = await _stt.locales();
    final spain = locales.where((l) => l.localeId.toLowerCase().replaceAll('_', '-') == 'es-es').firstOrNull;
    final spanish = spain ?? locales.where((l) => l.localeId.toLowerCase().startsWith('es')).firstOrNull;

    var delivered = false;
    listening.value = true;
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: spanish?.localeId ?? 'es_ES',
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 60),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
      onResult: (SpeechRecognitionResult result) {
        onWords(result.recognizedWords);
        if (result.finalResult && !delivered) {
          delivered = true;
          listening.value = false;
          onDone(result.recognizedWords.trim());
        }
      },
    );
    return true;
  }

  Future<void> stopListening() async {
    await _stt.stop();
    listening.value = false;
  }

  /// Sin markdown ni símbolos que el motor leería en voz alta.
  static String _forSpeech(String text) => text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'[*_`#>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
