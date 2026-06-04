import 'dart:io';

import 'bundle_locator.dart';

/// Resolves the ffmpeg executable on Windows when PATH is missing from the IDE.
class FfmpegLocator {
  FfmpegLocator._();

  static String? _cached;

  static Future<String> executable() async {
    if (_cached != null) return _cached!;

    final bundled = BundleLocator.bundledFfmpegExecutable();
    if (bundled != null) return _cache(bundled);

    final env = Platform.environment['VOX_ATC_FFMPEG']?.trim();
    if (env != null && env.isNotEmpty) {
      if (File(env).existsSync()) return _cache(env);
      final exe = env.endsWith('.exe')
          ? env
          : '$env${Platform.pathSeparator}ffmpeg.exe';
      if (File(exe).existsSync()) return _cache(exe);
    }

    if (Platform.isWindows) {
      const candidates = <String>[
        r'C:\ffmpeg\bin\ffmpeg.exe',
        r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return _cache(path);
      }
    }

    try {
      final result = await Process.run(
        'ffmpeg',
        ['-version'],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) return _cache('ffmpeg');
    } catch (_) {}

    return _cache('ffmpeg');
  }

  static String _cache(String value) => _cached = value;
}
