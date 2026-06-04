// lib/services/audio_devices_service.dart
import 'dart:convert';
import 'dart:io';

import 'ffmpeg_locator.dart';

class AudioDevicesService {
  String? lastRaw; // optional: helps debugging

  /// Lists DirectShow **audio** input devices using ffmpeg (Windows).
  /// Video devices (e.g. Integrated Camera) are never included.
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

    final ffmpeg = await FfmpegLocator.executable();
    final p = await Process.start(
      ffmpeg,
      args,
      runInShell: ffmpeg == 'ffmpeg',
    );

    final errBuf = StringBuffer();
    p.stderr.transform(utf8.decoder).listen(errBuf.write);

    p.stdout.transform(utf8.decoder).listen((_) {});

    // ffmpeg often exits with code 1 here — that's OK
    await p.exitCode;

    final raw = errBuf.toString();
    lastRaw = raw;

    return _parseAudioDevices(raw);
  }

  /// First available Windows audio input, or null if none found.
  Future<String?> firstWindowsMic() async {
    final mics = await listWindowsMics();
    return mics.isEmpty ? null : mics.first;
  }

  List<String> _parseAudioDevices(String raw) {
    final lines = raw.split('\n');
    final videoNames = <String>{};
    final audioNames = <String>[];

    // Collect explicit (video) devices so they can never leak in via fallbacks.
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!_isVideoLine(line)) continue;
      final name = _quotedDeviceName(line);
      if (name != null) videoNames.add(name);
    }

    // ffmpeg 8+: `"Device Name" (audio)` / `(video)` on each line
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!_isAudioLine(line)) continue;
      if (line.toLowerCase().contains('alternative name')) continue;

      final name = _quotedDeviceName(line);
      if (name != null && !videoNames.contains(name)) {
        audioNames.add(name);
      }
    }

    if (audioNames.isNotEmpty) {
      return _dedupe(audioNames);
    }

    // Legacy: between "DirectShow audio devices" and "DirectShow video devices"
    bool inAudioSection = false;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      final lower = line.toLowerCase();

      if (lower.contains('directshow audio devices')) {
        inAudioSection = true;
        continue;
      }
      if (inAudioSection && lower.contains('directshow video devices')) {
        break;
      }
      if (!inAudioSection) continue;
      if (_isVideoLine(line)) continue;
      if (line.toLowerCase().contains('alternative name')) continue;

      final name = _quotedDeviceName(line);
      if (name != null && !videoNames.contains(name)) {
        audioNames.add(name);
      }
    }

    return _dedupe(audioNames);
  }

  bool _isAudioLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('(audio)');
  }

  bool _isVideoLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('(video)');
  }

  String? _quotedDeviceName(String line) {
    final m = RegExp(r'"([^"]+)"').firstMatch(line);
    final name = m?.group(1)?.trim();
    return (name != null && name.isNotEmpty) ? name : null;
  }

  List<String> _dedupe(List<String> names) {
    final seen = <String>{};
    final deduped = <String>[];
    for (final n in names) {
      if (seen.add(n)) deduped.add(n);
    }
    return deduped;
  }
}
