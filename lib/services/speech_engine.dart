import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'bundle_locator.dart';

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
  String? _lastError;

  /// Whether the persistent whisper server is running.
  bool get isReady => _started;

  /// Last startup/transcription error message, if any.
  String? get lastError => _lastError;

  final Queue<Completer<void>> _busyWaiters = Queue<Completer<void>>();
  final List<String> _stderrLines = [];
  int? _exitCode;

  /// Starts the Python whisper server and waits until the model is loaded.
  Future<void> start() async {
    if (_started) return;
    if (_starting) {
      await _readyCompleter?.future;
      return;
    }

    _starting = true;
    _readyCompleter = Completer<void>();
    _stderrLines.clear();
    _exitCode = null;

    final scriptPath = _resolveScriptPath();
    if (scriptPath == null) {
      _starting = false;
      _lastError = 'whisper_server.py not found next to the app';
      debugPrint(
        'SpeechEngine: whisper_server.py not found (expected $_scriptRelative '
        'under project root; executable=${Platform.resolvedExecutable}, '
        'cwd=${Directory.current.path})',
      );
      return;
    }

    try {
      final bundleRoot = _projectRootForScript(scriptPath);
      final python = await _resolvePythonExecutable(bundleRoot);
      if (python == null) {
        _starting = false;
        _lastError ??= 'Bundled Python runtime not found';
        debugPrint('SpeechEngine: Python not found — $_lastError');
        return;
      }
      _pythonExecutable = python;

      _proc = await Process.start(
        python,
        ['-u', scriptPath],
        runInShell: _useShellForPython(python),
        workingDirectory: bundleRoot,
        environment: _processEnvironment(bundleRoot),
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
        _exitCode = code;
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
      _lastError = null;
      debugPrint('SpeechEngine: persistent server ready ($scriptPath)');
    } catch (e) {
      _lastError = _lastError ?? _formatStartupFailure('$e');
      debugPrint('SpeechEngine: failed to start server: $_lastError');
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
      _lastError ??= 'Speech engine is not running';
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
      _lastError = '$e';
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
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    _stderrLines.add(trimmed);
    if (trimmed == _readySignal) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
      return;
    }
    if (trimmed.startsWith('ERROR:')) {
      _lastError = trimmed;
    }
    debugPrint('SpeechEngine: $trimmed');
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
      _lastError = _formatStartupFailure(
        'Whisper server stopped before it was ready',
      );
      _readyCompleter!.completeError(StateError(_lastError!));
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

  String _projectRootForScript(String scriptPath) {
    return p.dirname(p.dirname(p.normalize(scriptPath)));
  }

  /// Portable bundle first, then system Python on PATH (dev machines only).
  Future<String?> _resolvePythonExecutable(String bundleRoot) async {
    if (_pythonExecutable != null) return _pythonExecutable;

    final bundled = BundleLocator.pythonExecutableForRoot(bundleRoot);
    if (bundled != null) {
      if (await _pythonCanRunWhisper(bundled, bundleRoot)) {
        return bundled;
      }
      _lastError = _formatStartupFailure(
        'Bundled Python failed to load faster-whisper',
      );
      return null;
    }

    final candidates = Platform.isMacOS
        ? const ['python3.11']
        : const ['python', 'python3', 'python3.11'];

    for (final candidate in candidates) {
      if (await _pythonCanRunWhisper(candidate, bundleRoot)) {
        return candidate;
      }
    }
    return null;
  }

  Future<bool> _pythonCanRunWhisper(
    String executable,
    String bundleRoot,
  ) async {
    try {
      final result = await Process.run(
        executable,
        ['-u', '-c', 'from faster_whisper import WhisperModel; print("OK")'],
        environment: _processEnvironment(bundleRoot),
        runInShell: _useShellForPython(executable),
      );
      final out = '${result.stdout}${result.stderr}'.trim();
      if (result.exitCode != 0) return false;
      return out.contains('OK');
    } catch (_) {
      return false;
    }
  }

  String _formatStartupFailure(String headline) {
    final details = _stderrLines
        .where((line) => line.startsWith('ERROR:') || line.startsWith('Loading'))
        .toList();
    if (_exitCode == -1073741819) {
      details.add(
        'native crash (0xC0000005) - run runtime\\Install_VC_Runtime.bat',
      );
    } else if (_exitCode != null && _exitCode != 0) {
      details.add('exit code $_exitCode');
    }
    if (details.isEmpty) {
      return headline;
    }
    return '$headline (${details.join('; ')})';
  }

  bool _useShellForPython(String executable) {
    if (!Platform.isWindows) return false;
    return !p.isAbsolute(executable);
  }

  Map<String, String> _processEnvironment(String bundleRoot) {
    if (BundleLocator.pythonExecutableForRoot(bundleRoot) != null) {
      return BundleLocator.processEnvironmentForRoot(bundleRoot);
    }

    final env = Map<String, String>.from(Platform.environment);
    env['HF_HUB_DISABLE_SYMLINKS'] = '1';
    return env;
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
