# VoxATC — Voice Communication Module

## Overview

VoxATC is a Flutter Desktop voice module for ATC training simulators. It lets a controller trainee hold a push-to-talk (PTT) key, speak an instruction, and release — the module captures the audio, transcribes it locally, and (in future phases) will parse it into structured ATC commands.

This repository is a **demo app** that validates the module end-to-end. The client integrates the services from `lib/services/` into their existing Flutter app; the demo `main.dart` shows one possible wiring pattern.

**Production target:** Windows Desktop  
**Development:** macOS is supported for UI and pipeline testing

---

## Project Structure

```
vox_atc_demo/
├── lib/
│   ├── main.dart                          # Demo app — wires PTT → capture → transcription
│   ├── services/
│   │   ├── ptt_handler.dart               # PTT key listener (Phase 1)
│   │   ├── audio_capture.dart             # ffmpeg microphone capture (Phase 1)
│   │   ├── speech_engine.dart             # faster-whisper transcription (Phase 2)
│   │   ├── audio_settings_service.dart    # Client — settings model + persistence
│   │   └── audio_devices_service.dart     # Client — Windows mic enumeration
│   └── ui/pages/
│       └── audio_settings_page.dart       # Client — Audio Settings UI
├── python/
│   └── whisper_server.py                  # Whisper CLI script (Phase 2)
├── macos/                                 # macOS desktop runner
├── windows/                               # Windows desktop runner
└── pubspec.yaml
```

| Path | Role |
|------|------|
| `ptt_handler.dart` | Detects PTT press/release from the key configured in Audio Settings |
| `audio_capture.dart` | Records microphone audio to a temporary WAV file via ffmpeg |
| `speech_engine.dart` | Sends the WAV to `whisper_server.py` and returns transcribed text |
| `whisper_server.py` | Local faster-whisper transcription (offline, English) |
| `audio_settings_*.dart` | Your existing Audio Settings layer (mic, HTT key, Whisper profile) |
| `audio_settings_page.dart` | Your existing settings UI (not required for headless integration) |
| `main.dart` | Reference integration only — replace with your app entry point |

---

## Phase 1 — PTT + Audio Capture ✅

### What was built

- Global PTT detection on **Windows** (configured key from Audio Settings)
- In-app PTT detection on **macOS** (window must have focus)
- Microphone recording via **ffmpeg** while PTT is held
- WAV output: **16 kHz, mono, 16-bit PCM**

### How it works

```
User holds PTT key
       ↓
PttHandler.onPTTStart
       ↓
AudioCapture.start()  →  ffmpeg records to temp WAV
       ↓
User releases PTT key
       ↓
PttHandler.onPTTEnd
       ↓
AudioCapture.stop()  →  returns WAV file path
```

### Files

**`ptt_handler.dart`**  
Reads `httKeyId` / `httKeyLabel` from `AudioSettings`. Fires callbacks when the PTT key is pressed and released. Does not process commands when PTT is inactive.

- **Windows:** `GetAsyncKeyState` polling — works globally, even when the app is unfocused
- **macOS:** `HardwareKeyboard` — works when the app window has focus

**`audio_capture.dart`**  
Reads `micName` from `AudioSettings`. Starts/stops ffmpeg capture on demand.

- **Windows:** DirectShow (`dshow`) — `audio={micName}`
- **macOS:** AVFoundation (`avfoundation`) — e.g. `:0` for default input

### API

```dart
import 'services/audio_settings_service.dart';
import 'services/ptt_handler.dart';
import 'services/audio_capture.dart';

// 1. Load settings (from your existing Audio Settings screen)
final settings = await AudioSettingsService().load();

// 2. Initialize
await PttHandler.instance.init(settings);
await AudioCapture.instance.init(settings);

// 3. Wire PTT → capture
PttHandler.instance.onPTTStart = () => AudioCapture.instance.start();

PttHandler.instance.onPTTEnd = () async {
  final wavPath = await AudioCapture.instance.stop();
  if (wavPath.isNotEmpty) {
    // Pass wavPath to SpeechEngine (Phase 2) or your handler
  }
};

// 4. Cleanup on app exit
await PttHandler.instance.dispose();
await AudioCapture.instance.dispose();
```

### Audio file lifecycle

| Step | Detail |
|------|--------|
| **Where saved** | OS temp directory — `Directory.systemTemp` |
| **macOS example** | `/var/folders/.../T/vox_atc_1717438123456.wav` |
| **Windows example** | `C:\Users\<user>\AppData\Local\Temp\vox_atc_1717438123456.wav` |
| **Naming** | `vox_atc_<millisecondsSinceEpoch>.wav` (timestamp set when recording starts) |
| **When deleted** | After transcription completes (see Phase 2 demo wiring in `main.dart`) |
| **If not transcribed** | File remains until manually removed or the OS cleans temp |

---

## Phase 2 — Speech Recognition ✅

### What was built

- Local offline transcription via **faster-whisper** (`base.en` model)
- Python CLI script invoked as a subprocess from Dart
- Demo UI shows transcript and a loading state while transcribing
- WAV file is **deleted after transcription** to free disk space

### How it works

```
WAV path from AudioCapture.stop()
       ↓
SpeechEngine.transcribe(wavPath)
       ↓
python3.11 python/whisper_server.py {wavPath}
       ↓
Transcript text returned from stdout
       ↓
WAV file deleted (demo wiring in main.dart)
```

### Files

**`python/whisper_server.py`**  
Accepts a WAV path as a command-line argument, loads `base.en`, transcribes, and prints **only** the transcript text to stdout.

**`speech_engine.dart`**  
Runs `python3.11 whisper_server.py {path}` as a subprocess, captures stdout, and returns `Future<String>`. Resolves the script path by walking up from `Platform.resolvedExecutable` to find `python/whisper_server.py` in the project root.

### API

```dart
import 'services/speech_engine.dart';

final text = await SpeechEngine.instance.transcribe(wavPath);
// text is the transcript, or '' on failure

// Delete WAV after transcription (recommended)
final file = File(wavPath);
if (await file.exists()) await file.delete();
```

**Note:** The first run downloads the `base.en` model (~150 MB). Subsequent runs are faster.

---

## Phase 3 — Command Parser

**Coming in Phase 3**

Will parse transcribed text into normalized ATC instructions and structured data, for example:

| Spoken | Normalized | Action |
|--------|------------|--------|
| "saudi one two three pushback approved face west" | SVA123, pushback approved, face west | Pushback |
| "gulf air three eight seven hold position" | GFA387, hold position | Hold Position |

Planned output: callsign, action type, parameters — for your simulator to drive virtual pilot readback and aircraft logic.

---

## Phase 4 — Final Delivery

**Coming in Phase 4**

- Self-contained Dart package for drop-in integration
- Persistent Whisper process (optional) for lower latency
- Windows production hardening
- README and integration guide updates
- Standalone demo app for client validation

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Flutter Desktop** | Windows (production), macOS (development) |
| **Python 3.11** | Must be `python3.11` on PATH (not `python3`) |
| **ffmpeg** | On PATH — used for mic capture and device listing |
| **faster-whisper** | `pip install faster-whisper` for Python 3.11 |
| **win32** | Dart package — already in `pubspec.yaml` (Windows PTT) |
| **shared_preferences** | Dart package — used by client Audio Settings |

### Verify setup

```bash
python3.11 --version
python3.11 -c "from faster_whisper import WhisperModel; print('OK')"
ffmpeg -version
flutter doctor
```

---

## Integration Guide

### 1. Copy module files into your app

Copy into your existing project:

```
lib/services/ptt_handler.dart
lib/services/audio_capture.dart
lib/services/speech_engine.dart
python/whisper_server.py
```

Your app already has (or equivalent):

```
lib/services/audio_settings_service.dart
lib/services/audio_devices_service.dart
lib/ui/pages/audio_settings_page.dart
```

Add to `pubspec.yaml`:

```yaml
dependencies:
  path: ^1.9.1
  shared_preferences: ^2.5.3
  win32: ^5.15.0   # Windows only — PTT global key detection
```

### 2. Ensure Audio Settings are configured

The user must select a **microphone** and **hold-to-talk key** in your Audio Settings screen and save. The voice module reads:

| Field | Used by |
|-------|---------|
| `micName` | `AudioCapture` |
| `httKeyId` / `httKeyLabel` | `PttHandler` |
| `profileWire` / `asrBudgetMs` | Reserved for future ASR tuning |

### 3. Initialize on app start

After `WidgetsFlutterBinding.ensureInitialized()` and after loading settings:

```dart
final settings = await AudioSettingsService().load();

await PttHandler.instance.init(settings);
await AudioCapture.instance.init(settings);

PttHandler.instance.onPTTStart = () async {
  await AudioCapture.instance.start();
};

PttHandler.instance.onPTTEnd = () async {
  final wavPath = await AudioCapture.instance.stop();
  if (wavPath.isEmpty) return;

  final transcript = await SpeechEngine.instance.transcribe(wavPath);

  // Delete temp WAV
  try {
    final f = File(wavPath);
    if (await f.exists()) await f.delete();
  } catch (_) {}

  if (transcript.isNotEmpty) {
    // Phase 3: pass to command parser
    // Your simulator: trigger readback, validate instruction, etc.
  }
};
```

Reload settings if the user changes mic or PTT key in Audio Settings (call `init()` again with updated settings).

### 4. Bundle `python/` with your app

For production, ship `python/whisper_server.py` alongside the executable, or set `VOX_ATC_ROOT` to the directory that contains the `python/` folder. `SpeechEngine` walks up from `Platform.resolvedExecutable` to locate it automatically.

### 5. Run the demo app

```bash
cd vox_atc_demo
flutter run -d macos    # development
flutter run -d windows  # production target
```

Hold **Space** (default HTT key) or the **Hold to Talk** button, speak an English ATC phrase, and release. The transcript appears on screen and in the console.

---

## License / Handoff

This module is delivered for integration into the client's ATC training simulator. For questions about scope, phases, or integration support, refer to the project scope of work.
