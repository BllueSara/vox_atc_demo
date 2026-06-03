import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vox_atc_demo/services/speech_engine.dart';

import 'helpers/test_process_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool ffmpegAvailable;
  late bool pythonAvailable;

  setUpAll(() async {
    ffmpegAvailable = await TestProcessHelpers.hasFfmpeg;
    pythonAvailable = await TestProcessHelpers.hasPython311;

    final script = File('python/whisper_server.py');
    if (!ffmpegAvailable ||
        !pythonAvailable ||
        !script.existsSync()) {
      return;
    }

    await SpeechEngine.instance.start();
  });

  tearDownAll(() async {
    await SpeechEngine.instance.dispose();
  });

  test('transcribe returns a String without throwing', () async {
    if (!ffmpegAvailable) {
      markTestSkipped('ffmpeg not on PATH');
    }
    if (!pythonAvailable) {
      markTestSkipped('python3.11 not on PATH');
    }

    final script = File('python/whisper_server.py');
    if (!script.existsSync()) {
      markTestSkipped('python/whisper_server.py not found (run from project root)');
    }

    final wavPath = await TestProcessHelpers.createSilentWav();
    addTearDown(() async {
      final f = File(wavPath);
      if (await f.exists()) await f.delete();
    });

    expect(File(wavPath).existsSync(), isTrue);

    final result = await SpeechEngine.instance.transcribe(wavPath);

    expect(result, isA<String>());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
