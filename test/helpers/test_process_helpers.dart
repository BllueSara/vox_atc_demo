import 'dart:io';

import 'package:path/path.dart' as p;

/// Shared helpers for unit tests that invoke ffmpeg / python3.11.
class TestProcessHelpers {
  static Future<bool> hasExecutable(String name, List<String> args) async {
    try {
      final result = await Process.run(name, args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> get hasFfmpeg =>
      hasExecutable('ffmpeg', ['-version']);

  static Future<bool> get hasPython311 =>
      hasExecutable('python3.11', ['--version']);

  /// Creates a 2-second silent WAV (16 kHz mono) via ffmpeg.
  static Future<String> createSilentWav({String? directory}) async {
    final dir = directory ?? Directory.systemTemp.path;
    final path = p.join(
      dir,
      'vox_test_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final result = await Process.run('ffmpeg', [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=16000:cl=mono',
      '-t',
      '2',
      '-c:a',
      'pcm_s16le',
      path,
    ]);

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw StateError('ffmpeg failed to create test WAV: $err');
    }

    return path;
  }
}
