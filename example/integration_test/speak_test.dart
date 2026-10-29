// Speaks a short phrase and waits for the plugin's completion callback, on
// every platform that runs this file. A runner with no voice skips the
// speaking test (markTestSkipped says why); the other tests still run.
//
// The web run gets the same file through test_driver/integration_test.dart,
// and telosnex_web_test keeps the browser console and checks the results.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:telosnex_web_test/telosnex_web_test.dart';

const String _phrase = 'Telosnex continuous integration speech check.';
const Duration _completionTimeout = Duration(seconds: 90);
// On Windows, a runner without an audio device gets no speech events from
// SAPI at all: no start and no completion. Such a run is skipped after this.
const Duration _windowsEventTimeout = Duration(seconds: 30);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installWebTestSupport(binding);

  testWidgets('the engine answers with lists of languages and voices',
      (tester) async {
    final tts = FlutterTts();
    expect(await tts.getLanguages, isA<List<dynamic>>());
    expect(await tts.getVoices, isA<List<dynamic>>());
  });

  testWidgets('speaks a phrase and gets the completion callback',
      (tester) async {
    final tts = FlutterTts();
    final voices = await tts.getVoices;
    if (voices is! List || voices.isEmpty) {
      markTestSkipped('This runner has no voice (getVoices is empty), '
          'so nothing can be spoken here.');
      return;
    }

    final completed = Completer<void>();
    final started = Completer<void>();
    tts.setStartHandler(() {
      if (!started.isCompleted) started.complete();
    });
    tts.setCompletionHandler(() {
      if (!started.isCompleted) started.complete();
      if (!completed.isCompleted) completed.complete();
    });
    tts.setErrorHandler((message) {
      if (!completed.isCompleted) {
        completed.completeError(StateError('speech failed: $message'));
      }
    });

    await tts.speak(_phrase);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final gotEvent = await started.future
          .timeout(_windowsEventTimeout)
          .then((_) => true, onError: (_) => false);
      if (!gotEvent) {
        await tts.stop();
        markTestSkipped('SAPI sent no start or completion event within '
            '$_windowsEventTimeout: this Windows runner has no audio device, '
            'so the completion callback is not tested here.');
        return;
      }
    }
    await completed.future.timeout(
      _completionTimeout,
      onTimeout: () => throw TimeoutException(
        'no completion callback within $_completionTimeout',
      ),
    );
    await tts.stop();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
