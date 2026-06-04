import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'audio_devices_service.dart';
import 'audio_settings_service.dart';
import 'ffmpeg_locator.dart';

/// Captures microphone audio to a temporary WAV file via ffmpeg.
///
/// Windows: DirectShow (`dshow`).
/// macOS: AVFoundation (`avfoundation`, e.g. `:0` for default input).
class AudioCapture {
  AudioCapture._();

  static final AudioCapture instance = AudioCapture._();

  static const int sampleRate = 16000;

  AudioSettings? _settings;
  String? _effectiveMic;
  Process? _proc;
  String? _outputPath;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<void> init(AudioSettings settings) async {
    _settings = settings;
    if (Platform.isWindows) {
      _effectiveMic = await _resolveWindowsMic(settings.micName);
    } else {
      _effectiveMic = settings.micName.trim();
    }
  }

  /// Starts ffmpeg recording. No-op if already recording or input is not configured.
  Future<void> start() async {
    if (_recording) return;

    final mic = await _micForCapture();
    if (mic.isEmpty) {
      debugPrint('AudioCapture: no audio microphone available');
      return;
    }

    if (!Platform.isWindows && !Platform.isMacOS) {
      debugPrint('AudioCapture: capture is supported on Windows and macOS only');
      return;
    }

    _outputPath = p.join(
      Directory.systemTemp.path,
      'vox_atc_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final args = _buildFfmpegArgs(mic, _outputPath!);
    if (args.isEmpty) return;

    try {
      final ffmpeg = await FfmpegLocator.executable();
      _proc = await Process.start(
        ffmpeg,
        args,
        runInShell: ffmpeg == 'ffmpeg',
      );
      _recording = true;

      _proc!.stderr.listen((data) {
        final msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) debugPrint('AudioCapture ffmpeg: $msg');
      });
    } catch (e) {
      _proc = null;
      _outputPath = null;
      _recording = false;
      debugPrint('AudioCapture: failed to start ffmpeg: $e');
    }
  }

  /// Stops recording and returns the WAV file path (empty if nothing was recorded).
  Future<String> stop() async {
    if (!_recording) return '';

    final path = _outputPath ?? '';
    final proc = _proc;

    _recording = false;
    _proc = null;
    _outputPath = null;

    if (proc == null) return '';

    try {
      proc.stdin.writeln('q');
      await proc.stdin.close();
      await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (e) {
      try {
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
      debugPrint('AudioCapture: stop error: $e');
    }

    if (path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return '';
  }

  Future<void> dispose() async {
    if (_recording) {
      await stop();
    }
    _settings = null;
    _effectiveMic = null;
  }

  Future<String> _micForCapture() async {
    if (Platform.isWindows) {
      if (_effectiveMic == null || _effectiveMic!.isEmpty) {
        _effectiveMic = await _resolveWindowsMic(_settings?.micName ?? '');
      }
      return _effectiveMic ?? '';
    }
    return _settings?.micName.trim() ?? '';
  }

  /// Uses [savedMic] from settings when it is a known audio device; otherwise
  /// the first audio device from ffmpeg (never video/camera devices).
  Future<String?> _resolveWindowsMic(String savedMic) async {
    final mics = await AudioDevicesService().listWindowsMics();
    if (mics.isEmpty) return null;

    final trimmed = savedMic.trim();
    if (trimmed.isNotEmpty && mics.contains(trimmed)) {
      return trimmed;
    }

    if (trimmed.isNotEmpty) {
      debugPrint(
        'AudioCapture: "$trimmed" is not an audio input — '
        'using "${mics.first}"',
      );
    } else {
      debugPrint('AudioCapture: auto-selected Windows mic "${mics.first}"');
    }
    return mics.first;
  }

  List<String> _buildFfmpegArgs(String mic, String outputPath) {
    final tail = [
      '-ac',
      '1',
      '-ar',
      '$sampleRate',
      '-c:a',
      'pcm_s16le',
      '-f',
      'wav',
    ];

    if (Platform.isWindows) {
      return [
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'dshow',
        '-i',
        'audio=$mic',
        ...tail,
        outputPath,
      ];
    }

    if (Platform.isMacOS) {
      return [
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'avfoundation',
        '-i',
        mic,
        ...tail,
        outputPath,
      ];
    }

    return const [];
  }
}
