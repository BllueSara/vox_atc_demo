import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vox_atc_demo/services/audio_lifecycle.dart';

import 'helpers/test_process_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vox_atc_lifecycle_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('deleteWavFile removes an existing file', () async {
    final path = p.join(tempDir.path, 'vox_atc_test.wav');
    await File(path).writeAsBytes([0x52, 0x49, 0x46, 0x46]); // minimal bytes

    expect(await File(path).exists(), isTrue);

    final deleted = await deleteWavFile(path);

    expect(deleted, isTrue);
    expect(await File(path).exists(), isFalse);
  });

  test('deleteWavFile ignores a missing file', () async {
    final path = p.join(tempDir.path, 'does_not_exist.wav');

    final deleted = await deleteWavFile(path);

    expect(deleted, isFalse);
    expect(await File(path).exists(), isFalse);
  });

  test('post-transcription lifecycle leaves no leftover WAV', () async {
    if (!await TestProcessHelpers.hasFfmpeg) {
      markTestSkipped('ffmpeg not on PATH');
    }

    final wavPath = await TestProcessHelpers.createSilentWav(
      directory: tempDir.path,
    );

    expect(await File(wavPath).exists(), isTrue);

    // Simulate post-transcription cleanup (same as main.dart after transcribe).
    final deleted = await deleteWavFile(wavPath);

    expect(deleted, isTrue);
    expect(await File(wavPath).exists(), isFalse);
    expect(tempDir.listSync(), isEmpty);
  });
}
