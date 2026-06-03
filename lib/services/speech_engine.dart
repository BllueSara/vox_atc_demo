import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Runs a persistent faster-whisper server ([python/whisper_server.py]).
class SpeechEngine {
  SpeechEngine._();

  static final SpeechEngine instance = SpeechEngine._();

  static const _scriptRelative = 'python/whisper_server.py';
  static const _endMarker = '<<<END>>>';
  static const _readySignal = 'READY';

  String? _pythonExecutable;

  String? _cachedScriptPath;
  Process? _proc;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  IOSink? _stdin;

  final Queue<String> _stdoutQueue = Queue<String>();
  Completer<void>? _stdoutWaiter;
  Completer<void>? _readyCompleter;
  bool _started = false;
  bool _starting = false;
  bool _busy = false;
  final Queue<Completer<void>> _busyWaiters = Queue<Completer<void>>();

  /// Starts the Python whisper server and waits until the model is loaded.
  Future<void> start() async {
    if (_started) return;
    if (_starting) {
      await _readyCompleter?.future;
      return;
    }

    _starting = true;
    _readyCompleter = Completer<void>();

    final script = _resolveScriptPath();
    if (script == null) {
      _starting = false;
      debugPrint(
        'SpeechEngine: whisper_server.py not found (expected $_scriptRelative '
        'under project root; executable=${Platform.resolvedExecutable}, '
        'cwd=${Directory.current.path})',
      );
      return;
    }

    try {
      final python = await _resolvePythonExecutable();
      if (python == null) {
        _starting = false;
        debugPrint(
          'SpeechEngine: Python not found '
          '(macOS: python3.11, Windows: python3.11 / python3 / python)',
        );
        return;
      }
      _pythonExecutable = python;

      _proc = await Process.start(
        python,
        [script],
        runInShell: Platform.isWindows,
        workingDirectory: _projectRootForScript(script),
      );

      _stdin = _proc!.stdin;

      _stdoutSub = _proc!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStdoutLine, onError: _onProcessError);

      _stderrSub = _proc!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine, onError: _onProcessError);

      _proc!.exitCode.then((code) {
        if (code != 0) {
          debugPrint('SpeechEngine: whisper_server exited with code $code');
        }
        _handleProcessExit();
      });

      await _readyCompleter!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException('SpeechEngine: timed out waiting for READY');
        },
      );

      _started = true;
      debugPrint('SpeechEngine: persistent server ready ($script)');
    } catch (e) {
      debugPrint('SpeechEngine: failed to start server: $e');
      await _shutdownProcess();
    } finally {
      _starting = false;
    }
  }

  /// Sends [wavPath] to the server and returns the transcript (empty on failure).
  Future<String> transcribe(String wavPath) async {
    final wav = File(wavPath);
    if (!wav.existsSync()) {
      debugPrint('SpeechEngine: WAV not found: $wavPath');
      return '';
    }

    if (!_started) {
      await start();
    }
    if (!_started || _stdin == null) {
      return '';
    }

    await _acquire();

    try {
      final wavForServer = p.normalize(File(wavPath).absolute.path);
      _stdin!.writeln(wavForServer);
      await _stdin!.flush();

      final lines = <String>[];
      while (true) {
        final line = await _readStdoutLine();
        if (line == _endMarker) break;
        lines.add(line);
      }

      return lines.join(' ').trim();
    } catch (e) {
      debugPrint('SpeechEngine: transcribe error: $e');
      return '';
    } finally {
      _release();
    }
  }

  /// Stops the background Python server.
  Future<void> dispose() async {
    await _shutdownProcess();
    _cachedScriptPath = null;
    _pythonExecutable = null;
  }

  void _onStdoutLine(String line) {
    _stdoutQueue.add(line);
    _stdoutWaiter?.complete();
    _stdoutWaiter = null;
  }

  void _onStderrLine(String line) {
    if (line == _readySignal) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
      return;
    }
    if (line.isNotEmpty) {
      debugPrint('SpeechEngine: $line');
    }
  }

  void _onProcessError(Object error) {
    debugPrint('SpeechEngine: stream error: $error');
  }

  void _handleProcessExit() {
    _started = false;
    _starting = false;
    _busy = false;
    for (final waiter in _busyWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _busyWaiters.clear();
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(
        StateError('SpeechEngine: server exited before READY'),
      );
    }
    _proc = null;
    _stdin = null;
  }

  Future<void> _shutdownProcess() async {
    _started = false;
    _starting = false;

    try {
      await _stdin?.close();
    } catch (_) {}

    _proc?.kill(ProcessSignal.sigterm);
    try {
      await _proc?.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      _proc?.kill(ProcessSignal.sigkill);
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _proc = null;
    _stdin = null;
    _stdoutQueue.clear();
    _stdoutWaiter = null;
    _busy = false;
    for (final waiter in _busyWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _busyWaiters.clear();
  }

  Future<void> _acquire() async {
    while (_busy) {
      final waiter = Completer<void>();
      _busyWaiters.add(waiter);
      await waiter.future;
    }
    _busy = true;
  }

  void _release() {
    _busy = false;
    if (_busyWaiters.isNotEmpty) {
      _busyWaiters.removeFirst().complete();
    }
  }

  Future<String> _readStdoutLine() async {
    if (_stdoutQueue.isNotEmpty) {
      return _stdoutQueue.removeFirst();
    }

    _stdoutWaiter = Completer<void>();
    await _stdoutWaiter!.future;
    if (_stdoutQueue.isEmpty) {
      throw StateError('SpeechEngine: stdout closed unexpectedly');
    }
    return _stdoutQueue.removeFirst();
  }

  String? _resolveScriptPath() {
    if (_cachedScriptPath != null && File(_cachedScriptPath!).existsSync()) {
      return _cachedScriptPath;
    }

    for (final root in _projectRootCandidates()) {
      final candidate = p.normalize(p.join(root, _scriptRelative));
      if (File(candidate).existsSync()) {
        _cachedScriptPath = candidate;
        return candidate;
      }
    }

    return null;
  }

  String? _projectRootForScript(String scriptPath) {
    return p.dirname(p.dirname(p.normalize(scriptPath)));
  }

  /// macOS: `python3.11`. Windows: first available of `python3.11`, `python3`, `python`.
  Future<String?> _resolvePythonExecutable() async {
    if (_pythonExecutable != null) return _pythonExecutable;

    final candidates = Platform.isMacOS
        ? const ['python3.11']
        : const ['python3.11', 'python3', 'python'];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate,
          ['--version'],
          runInShell: Platform.isWindows,
        );
        if (result.exitCode == 0) {
          return candidate;
        }
      } catch (_) {
        // Try next candidate.
      }
    }
    return null;
  }

  Iterable<String> _projectRootCandidates() sync* {
    final envRoot = Platform.environment['VOX_ATC_ROOT'];
    if (envRoot != null && envRoot.isNotEmpty) {
      yield p.normalize(envRoot);
    }

    yield* _walkUpFromDirectory(File(Platform.resolvedExecutable).parent);
    yield* _walkUpFromDirectory(Directory.current);
  }

  Iterable<String> _walkUpFromDirectory(Directory start) sync* {
    var dir = start;
    for (var depth = 0; depth < 24; depth++) {
      yield p.normalize(dir.path);
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
}
