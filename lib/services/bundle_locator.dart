import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves bundled runtime paths next to the Windows portable distribution.
class BundleLocator {
  BundleLocator._();

  static String? _cachedRoot;

  /// Directory containing `vox_atc_demo.exe`, `python/`, and `runtime/`.
  static String? appRoot() {
    if (_cachedRoot != null) return _cachedRoot;

    final envRoot = Platform.environment['VOX_ATC_ROOT']?.trim();
    if (envRoot != null && envRoot.isNotEmpty) {
      final normalized = p.normalize(envRoot);
      if (_looksLikeBundleRoot(normalized)) {
        return _cachedRoot = normalized;
      }
    }

    for (final root in _walkUpFromDirectory(
      File(Platform.resolvedExecutable).parent,
    )) {
      if (_looksLikeBundleRoot(root)) return _cachedRoot = root;
    }

    for (final root in _walkUpFromDirectory(Directory.current)) {
      if (_looksLikeBundleRoot(root)) return _cachedRoot = root;
    }

    return null;
  }

  static String? bundledPythonExecutable() {
    final root = appRoot();
    if (root == null) return null;
    final exe = p.join(root, 'runtime', 'python', 'python.exe');
    return File(exe).existsSync() ? exe : null;
  }

  static String? bundledFfmpegExecutable() {
    final root = appRoot();
    if (root == null) return null;
    final exe = p.join(root, 'runtime', 'ffmpeg', 'bin', 'ffmpeg.exe');
    return File(exe).existsSync() ? exe : null;
  }

  static String? bundledModelDirectory() {
    final root = appRoot();
    if (root == null) return null;
    final modelDir = p.join(root, 'runtime', 'models', 'small.en');
    return File(p.join(modelDir, 'model.bin')).existsSync() ? modelDir : null;
  }

  static String? huggingFaceHomeForRoot(String root) {
    final hf = p.join(root, 'runtime', 'cache', 'huggingface');
    return Directory(hf).existsSync() ? hf : null;
  }

  static String? pythonExecutableForRoot(String root) {
    final exe = p.join(root, 'runtime', 'python', 'python.exe');
    return File(exe).existsSync() ? exe : null;
  }

  /// Environment for bundled Python subprocesses (Whisper server).
  static Map<String, String> processEnvironmentForRoot(String root) {
    final env = Map<String, String>.from(Platform.environment);
    final pythonDir = p.join(root, 'runtime', 'python');
    final pathEntries = <String>[
      pythonDir,
      p.join(pythonDir, 'Lib', 'site-packages', 'onnxruntime', 'capi'),
      p.join(pythonDir, 'Lib', 'site-packages', 'ctranslate2'),
      if (env['PATH'] != null && env['PATH']!.isNotEmpty) env['PATH']!,
    ];
    env['PATH'] = pathEntries.join(';');
    env['PYTHONNOUSERSITE'] = '1';
    env['HF_HUB_DISABLE_SYMLINKS'] = '1';
    env.putIfAbsent('CT2_FORCE_CPU_ISA', () => 'GENERIC');

    final hfHome = huggingFaceHomeForRoot(root);
    if (hfHome != null) {
      env['HF_HOME'] = hfHome;
      env['HUGGINGFACE_HUB_CACHE'] = p.join(hfHome, 'hub');
    }
    return env;
  }

  static String? huggingFaceHome() {
    final root = appRoot();
    if (root == null) return null;
    final hf = p.join(root, 'runtime', 'cache', 'huggingface');
    return Directory(hf).existsSync() ? hf : null;
  }

  static bool _looksLikeBundleRoot(String root) {
    return File(p.join(root, 'python', 'whisper_server.py')).existsSync();
  }

  static Iterable<String> _walkUpFromDirectory(Directory start) sync* {
    var dir = start;
    for (var depth = 0; depth < 24; depth++) {
      yield p.normalize(dir.path);
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
}
