import 'dart:async';
import 'dart:collection';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dart:js_interop';

enum TtsState { playing, stopped, paused, continued }

@JS('SpeechSynthesisUtterance')
external JSFunction get SpeechSynthesisUtterance;

@JS('speechSynthesis')
external SpeechSynthesisType get speechSynthesis;

extension type SpeechSynthesisUtteranceType._(JSObject _) implements JSObject {
  external set text(String text);
  external set rate(num rate);
  external set volume(num volume);
  external set pitch(num pitch);
  external set lang(String lang);
  external set voice(JSObject? voice);
  external set onstart(JSFunction callback);
  external set onend(JSFunction callback);
  external set onpause(JSFunction callback);
  external set onresume(JSFunction callback);
  external set onerror(JSFunction callback);

  external JSObject? get voice;
}

extension type SpeechSynthesisType._(JSObject _) implements JSObject {
  external void speak(SpeechSynthesisUtteranceType utterance);
  external void pause();
  external void resume();
  external void cancel();
  external JSArray<JSObject> getVoices();
}

class FlutterTtsPlugin {
  static const String platformChannel = "flutter_tts";
  static late MethodChannel channel;
  bool awaitSpeakCompletion = false;

  TtsState ttsState = TtsState.stopped;

  Completer<dynamic>? _speechCompleter;

  bool get isPlaying => ttsState == TtsState.playing;
  bool get isStopped => ttsState == TtsState.stopped;
  bool get isPaused => ttsState == TtsState.paused;
  bool get isContinued => ttsState == TtsState.continued;

  static void registerWith(Registrar registrar) {
    channel =
        MethodChannel(platformChannel, const StandardMethodCodec(), registrar);
    final instance = FlutterTtsPlugin();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  late SpeechSynthesisUtteranceType utterance;
  late SpeechSynthesisType synth;
  List<JSObject>? voices;
  List<String?>? languages;
  Timer? t;
  bool supported = false;

  FlutterTtsPlugin() {
    try {
      utterance = SpeechSynthesisUtterance.callAsConstructor([''.toJS].toJS);
      synth = speechSynthesis;
      _listeners();
      supported = true;
    } catch (e) {
      print('Initialization of TTS failed. Functions are disabled. Error: $e');
    }
  }

  void _listeners() {
    utterance.onstart = ((JSObject e) {
      ttsState = TtsState.playing;
      channel.invokeMethod("speak.onStart", null);
      var voiceObj = utterance.voice;
      var bLocal =
          voiceObj?.getProperty<JSBoolean?>('localService'.toJS)?.toDart ??
              false;
      if (!bLocal) {
        t = Timer.periodic(Duration(seconds: 14), (t) {
          if (ttsState == TtsState.playing) {
            synth.pause();
            synth.resume();
          } else {
            t.cancel();
          }
        });
      }
    }).toJS;

    utterance.onend = ((JSAny e) {
      ttsState = TtsState.stopped;
      if (_speechCompleter != null) {
        _speechCompleter?.complete();
        _speechCompleter = null;
      }
      t?.cancel();
      channel.invokeMethod("speak.onComplete", null);
    }).toJS;

    utterance.onpause = ((JSAny e) {
      ttsState = TtsState.paused;
      channel.invokeMethod("speak.onPause", null);
    }).toJS;

    utterance.onresume = ((JSAny e) {
      ttsState = TtsState.continued;
      channel.invokeMethod("speak.onContinue", null);
    }).toJS;

    utterance.onerror = ((JSObject e) {
      ttsState = TtsState.stopped;
      var event = e;
      if (_speechCompleter != null) {
        _speechCompleter = null;
      }
      t?.cancel();
      print(event);
      channel.invokeMethod(
          "speak.onError", event.getProperty<JSString?>('error'.toJS)?.toDart);
    }).toJS;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    if (!supported) return;
    switch (call.method) {
      case 'speak':
        final text = call.arguments as String?;
        if (awaitSpeakCompletion) {
          _speechCompleter = Completer();
        }
        _speak(text);
        if (awaitSpeakCompletion) {
          return _speechCompleter?.future;
        }
        break;
      case 'awaitSpeakCompletion':
        awaitSpeakCompletion = (call.arguments as bool?) ?? false;
        return 1;
      case 'stop':
        _stop();
        return 1;
      case 'pause':
        _pause();
        return 1;
      case 'setLanguage':
        final language = call.arguments as String?;
        _setLanguage(language);
        return 1;
      case 'getLanguages':
        return _getLanguages();
      case 'getVoices':
        return getVoices();
      case 'setVoice':
        final tmpVoiceMap =
            Map<String, String>.from(call.arguments as LinkedHashMap);
        return _setVoice(tmpVoiceMap);
      case 'setSpeechRate':
        final rate = call.arguments as num;
        _setRate(rate);
        return 1;
      case 'setVolume':
        final volume = call.arguments as num?;
        _setVolume(volume);
        return 1;
      case 'setPitch':
        final pitch = call.arguments as num?;
        _setPitch(pitch);
        return 1;
      case 'isLanguageAvailable':
        final lang = call.arguments as String?;
        return _isLanguageAvailable(lang);
      default:
        throw PlatformException(
            code: 'Unimplemented',
            details: "The flutter_tts plugin for web doesn't implement "
                "the method '${call.method}'");
    }
  }

  void _speak(String? text) {
    if (ttsState == TtsState.stopped || ttsState == TtsState.paused) {
      utterance.text = text ?? '';
      if (ttsState == TtsState.paused) {
        synth.resume();
      } else {
        synth.speak(utterance);
      }
    }
  }

  void _stop() {
    if (ttsState != TtsState.stopped) {
      synth.cancel();
    }
  }

  void _pause() {
    if (ttsState == TtsState.playing || ttsState == TtsState.continued) {
      synth.pause();
    }
  }

  void _setRate(num rate) => utterance.rate = rate;
  void _setVolume(num? volume) => utterance.volume = volume ?? 1.0;
  void _setPitch(num? pitch) => utterance.pitch = pitch ?? 1.0;
  void _setLanguage(String? language) => utterance.lang = language ?? 'en-US';

  void _setVoice(Map<String?, String?> voice) {
    var tmpVoices = synth.getVoices();
    final targetList = tmpVoices.toDart.where((JSObject e) {
      var voiceObj = e;
      return voice["name"] ==
              voiceObj.getProperty<JSString?>('name'.toJS)?.toDart &&
          voice["locale"] ==
              voiceObj.getProperty<JSString?>('lang'.toJS)?.toDart;
    });
    if (targetList.isNotEmpty) {
      utterance.voice = targetList.first;
    }
  }

  bool _isLanguageAvailable(String? language) {
    if (voices?.isEmpty ?? true) _setVoices();
    if (languages?.isEmpty ?? true) _setLanguages();
    for (var lang in languages!) {
      if (!language!.contains('-')) {
        lang = lang!.split('-').first;
      }
      if (lang!.toLowerCase() == language.toLowerCase()) return true;
    }
    return false;
  }

  List<String?>? _getLanguages() {
    if (voices?.isEmpty ?? true) _setVoices();
    if (languages?.isEmpty ?? true) _setLanguages();
    return languages;
  }

  void _setVoices() {
    voices = synth.getVoices().toDart;
  }

  Future<List<Map<String, String>>> getVoices() async {
    var tmpVoices = synth.getVoices();
    var voiceList = <Map<String, String>>[];
    for (var voice in tmpVoices.toDart) {
      voiceList.add({
        "name": voice.getProperty<JSString>('lang'.toJS).toDart,
        "locale": voice.getProperty<JSString>('lang'.toJS).toDart,
      });
    }
    return voiceList;
  }

  void _setLanguages() {
    var langs = <String?>{};
    for (var v in voices!) {
      langs.add(v.getProperty<JSString?>('lang'.toJS)?.toDart);
    }
    languages = langs.toList();
  }
}
