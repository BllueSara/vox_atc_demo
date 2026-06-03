// lib/services/audio_settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';

enum WhisperProfile { fast, auto, accurate }

class AudioSettings {
  final String micName; // dshow device name (Windows)
  final WhisperProfile profile;
  final bool enableRescuePass;
  final bool setupComplete;

  // NEW: Hold-to-talk key
  final int httKeyId; // LogicalKeyboardKey.keyId (int)
  final String httKeyLabel; // human label, e.g. "Space"

  const AudioSettings({
    required this.micName,
    required this.profile,
    required this.enableRescuePass,
    required this.setupComplete,
    required this.httKeyId,
    required this.httKeyLabel,
  });

  AudioSettings copyWith({
    String? micName,
    WhisperProfile? profile,
    bool? enableRescuePass,
    bool? setupComplete,
    int? httKeyId,
    String? httKeyLabel,
  }) {
    return AudioSettings(
      micName: micName ?? this.micName,
      profile: profile ?? this.profile,
      enableRescuePass: enableRescuePass ?? this.enableRescuePass,
      setupComplete: setupComplete ?? this.setupComplete,
      httKeyId: httKeyId ?? this.httKeyId,
      httKeyLabel: httKeyLabel ?? this.httKeyLabel,
    );
  }

  /// Stable wire value sent to ASR server. Do not change (backward compatible).
  String get profileWire => switch (profile) {
        WhisperProfile.fast => 'fast',
        WhisperProfile.auto => 'auto',
        WhisperProfile.accurate => 'accurate',
      };

  int get asrBudgetMs => switch (profile) {
        WhisperProfile.fast => 950, // still very snappy
        WhisperProfile.auto => 1350, // allows “normal slow” moments
        WhisperProfile.accurate => 1450 // still <= 1500
      };

  static AudioSettings defaults() => const AudioSettings(
        micName: '',
        profile: WhisperProfile.fast,
        enableRescuePass: true,
        setupComplete: false,
        httKeyId: 32, // Space default
        httKeyLabel: 'Space',
      );
}

class AudioSettingsService {
  static const _kMicName = 'audio.micName';
  static const _kProfile = 'audio.whisperProfile';
  static const _kRescue = 'audio.enableRescue';
  static const _kSetup = 'audio.setupComplete';

  // NEW
  static const _kHttKeyId = 'audio.httKeyId';
  static const _kHttKeyLabel = 'audio.httKeyLabel';

  Future<AudioSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    final mic = sp.getString(_kMicName) ?? '';
    final p = sp.getString(_kProfile) ?? 'fast';
    final rescue = sp.getBool(_kRescue) ?? true;
    final setup = sp.getBool(_kSetup) ?? false;

    final httKeyId = sp.getInt(_kHttKeyId) ?? 32;
    final httKeyLabel = sp.getString(_kHttKeyLabel) ?? 'Space';

    return AudioSettings(
      micName: mic,
      profile: _parseProfile(p),
      enableRescuePass: rescue,
      setupComplete: setup && mic.trim().isNotEmpty,
      httKeyId: httKeyId,
      httKeyLabel: httKeyLabel,
    );
  }

  Future<void> save(AudioSettings s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMicName, s.micName);
    await sp.setString(_kProfile, _profileToString(s.profile));
    await sp.setBool(_kRescue, s.enableRescuePass);
    await sp.setBool(_kSetup, s.setupComplete);

    // NEW
    await sp.setInt(_kHttKeyId, s.httKeyId);
    await sp.setString(_kHttKeyLabel, s.httKeyLabel);
  }

  WhisperProfile _parseProfile(String v) {
    switch (v.toLowerCase().trim()) {
      case 'accurate':
        return WhisperProfile.accurate;
      case 'auto':
        return WhisperProfile.auto;
      case 'fast':
      default:
        return WhisperProfile.fast;
    }
  }

  String _profileToString(WhisperProfile p) {
    switch (p) {
      case WhisperProfile.fast:
        return 'fast';
      case WhisperProfile.auto:
        return 'auto';
      case WhisperProfile.accurate:
        return 'accurate';
    }
  }
}
