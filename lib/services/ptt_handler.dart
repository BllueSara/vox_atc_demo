import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'audio_settings_service.dart';

/// Hold-to-talk key listener.
///
/// Windows: global detection via [GetAsyncKeyState] polling.
/// macOS: in-app detection via [HardwareKeyboard] (window must have focus).
class PttHandler {
  PttHandler._();

  static final PttHandler instance = PttHandler._();

  VoidCallback? onPTTStart;
  VoidCallback? onPTTEnd;

  int _targetKeyId = 0;
  int _targetVk = 0;
  bool _pttActive = false;
  bool _initialized = false;
  Timer? _pollTimer;

  /// Loads [settings] and starts PTT key detection for the current platform.
  Future<void> init(AudioSettings settings) async {
    await dispose();

    _targetKeyId = settings.httKeyId;
    _targetVk = _flutterKeyIdToWindowsVk(settings.httKeyId);
    _pttActive = false;

    if (Platform.isWindows) {
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 15),
        (_) => _pollKeyStateWindows(),
      );
      _initialized = true;
      debugPrint(
        'PttHandler: global listen for "${settings.httKeyLabel}" (vk=$_targetVk)',
      );
      return;
    }

    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleMacKeyEvent);
      _initialized = true;
      debugPrint(
        'PttHandler: in-app listen for "${settings.httKeyLabel}" '
        '(keyId=$_targetKeyId)',
      );
      return;
    }

    debugPrint('PttHandler: unsupported platform');
    _initialized = true;
  }

  /// Stops detection and clears callbacks.
  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleMacKeyEvent);
    }

    onPTTStart = null;
    onPTTEnd = null;
    _pttActive = false;
    _initialized = false;
    _targetKeyId = 0;
    _targetVk = 0;
  }

  bool get isPttActive => _pttActive;

  void _pollKeyStateWindows() {
    if (!_initialized || !Platform.isWindows) return;

    final down = (GetAsyncKeyState(_targetVk) & 0x8000) != 0;

    if (down && !_pttActive) {
      _pttActive = true;
      onPTTStart?.call();
    } else if (!down && _pttActive) {
      _pttActive = false;
      onPTTEnd?.call();
    }
  }

  bool _handleMacKeyEvent(KeyEvent event) {
    if (!_initialized || !Platform.isMacOS) return false;
    if (event.logicalKey.keyId != _targetKeyId) return false;

    if (event is KeyDownEvent) {
      if (!_pttActive) {
        _pttActive = true;
        onPTTStart?.call();
      }
      return false;
    }

    if (event is KeyUpEvent) {
      if (_pttActive) {
        _pttActive = false;
        onPTTEnd?.call();
      }
      return false;
    }

    return false;
  }

  int _flutterKeyIdToWindowsVk(int keyId) {
    final lowWord = keyId & 0xFFFF;
    if (lowWord != 0) return lowWord;
    return keyId & 0xFF;
  }
}
