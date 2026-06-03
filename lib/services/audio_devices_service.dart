// lib/services/audio_devices_service.dart
import 'dart:convert';
import 'dart:io';

class AudioDevicesService {
  String? lastRaw; // optional: helps debugging

  /// Lists DirectShow audio devices using ffmpeg (Windows).
  /// Robust parsing across different ffmpeg builds.
  Future<List<String>> listWindowsMics() async {
    final args = [
      '-hide_banner',
      '-list_devices',
      'true',
      '-f',
      'dshow',
      '-i',
      'dummy',
    ];

    final p = await Process.start(
      'ffmpeg',
      args,
      runInShell: true,
    );

    final errBuf = StringBuffer();
    p.stderr.transform(utf8.decoder).listen(errBuf.write);

    // consume stdout (not needed)
    p.stdout.transform(utf8.decoder).listen((_) {});

    // ffmpeg often exits with code 1 here — that's OK
    await p.exitCode;

    final raw = errBuf.toString();
    lastRaw = raw;

    final lines = raw.split('\n');

    // 1) Primary parse: between "audio devices" header and next header
    final audioNames = <String>[];
    bool inAudio = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();

      final isAudioHeader =
          line.toLowerCase().contains('directshow audio devices');
      final isVideoHeader =
          line.toLowerCase().contains('directshow video devices');

      if (isAudioHeader) {
        inAudio = true;
        continue;
      }
      if (inAudio && isVideoHeader) {
        inAudio = false;
        continue;
      }

      if (!inAudio) continue;

      // Skip “Alternative name”
      if (line.toLowerCase().contains('alternative name')) continue;

      // Grab any quoted device name:  "Device Name"
      final m = RegExp(r'"([^"]+)"').firstMatch(line);
      if (m != null) {
        final name = m.group(1)!.trim();
        if (name.isNotEmpty) audioNames.add(name);
      }
    }

    // 2) Fallback parse: if header not found, grab ALL quoted names
    // from dshow lines (excluding "Alternative name") and return them.
    final fallbackNames = <String>[];
    if (audioNames.isEmpty) {
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (!line.toLowerCase().contains('dshow')) continue;
        if (line.toLowerCase().contains('alternative name')) continue;

        final m = RegExp(r'"([^"]+)"').firstMatch(line);
        if (m != null) {
          final name = m.group(1)!.trim();
          if (name.isNotEmpty) fallbackNames.add(name);
        }
      }
    }

    final out = audioNames.isNotEmpty ? audioNames : fallbackNames;

    // De-duplicate while keeping order
    final seen = <String>{};
    final deduped = <String>[];
    for (final n in out) {
      if (seen.add(n)) deduped.add(n);
    }

    return deduped;
  }
}
