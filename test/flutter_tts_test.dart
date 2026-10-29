// The Dart side of the platform events: each event reaches the handler the
// app set, with its arguments. The native side is in the integration tests.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('speak.onComplete calls the completion handler', () async {
    final tts = FlutterTts();
    var completions = 0;
    tts.setCompletionHandler(() => completions++);
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    expect(completions, 1);
  });

  test('speak.onError passes its message to the error handler', () async {
    final tts = FlutterTts();
    Object? message;
    tts.setErrorHandler((value) => message = value);
    await tts
        .platformCallHandler(const MethodCall('speak.onError', 'no voice'));
    expect(message, 'no voice');
  });

  test('speak.onProgress passes text, range and word', () async {
    final tts = FlutterTts();
    final calls = <List<Object>>[];
    tts.setProgressHandler((text, start, end, word) {
      calls.add([text, start, end, word]);
    });
    await tts.platformCallHandler(const MethodCall('speak.onProgress', {
      'text': 'Hello there',
      'start': 6,
      'end': 11,
      'word': 'there',
    }));
    expect(calls, [
      ['Hello there', 6, 11, 'there'],
    ]);
  });
}
