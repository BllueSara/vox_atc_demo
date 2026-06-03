# VoxATC — Windows Setup Guide

This guide walks through setting up the VoxATC demo on **Windows Desktop** for PTT capture and local speech recognition.

**Production target:** Windows  
**Development:** macOS is also supported with the same codebase (`Platform` checks)

---

## 1. Install Flutter for Windows

Follow the official guide:

https://docs.flutter.dev/get-started/install/windows

After installation, open **PowerShell** or **Command Prompt** and run:

```powershell
flutter doctor
```

Enable **Windows desktop** if needed:

```powershell
flutter config --enable-windows-desktop
```

---

## 2. Install Visual Studio (Desktop development with C++)

Flutter on Windows requires the **Desktop development with C++** workload.

Download Visual Studio:

https://visualstudio.microsoft.com/

During installation, select:

- **Desktop development with C++**
- Windows 10/11 SDK (latest available)

Run `flutter doctor` again and confirm the Visual Studio section shows no errors.

---

## 3. Install Python 3.11

Download Python 3.11:

https://www.python.org/downloads/

During setup:

- Check **Add python.exe to PATH**
- Note the install location (e.g. `C:\Users\<you>\AppData\Local\Programs\Python\Python311\`)

Verify in a **new** terminal:

```powershell
python --version
python3.11 --version
```

At least one of `python`, `python3`, or `python3.11` must work. VoxATC tries them in that order on Windows.

---

## 4. Install faster-whisper

```powershell
python -m pip install faster-whisper
```

Or with Python 3.11 explicitly:

```powershell
python3.11 -m pip install faster-whisper
```

Verify:

```powershell
python -c "from faster_whisper import WhisperModel; print('OK')"
```

The first transcription run downloads the `small.en` model (~150 MB).

---

## 5. Install ffmpeg

Download a Windows build:

https://ffmpeg.org/download.html

(Gyan.dev or BtbN builds are commonly used.)

1. Extract the archive (e.g. to `C:\ffmpeg`)
2. Add the **`bin`** folder to your system **PATH**  
   Example: `C:\ffmpeg\bin`
3. Open a **new** terminal and verify:

```powershell
ffmpeg -version
```

VoxATC calls `ffmpeg` directly (must be on PATH).

### List microphones (optional)

```powershell
ffmpeg -hide_banner -list_devices true -f dshow -i dummy
```

Use the quoted device name in Audio Settings (e.g. `Microphone (Realtek Audio)`).

---

## 6. Clone or copy the project

Copy the project folder to your machine, for example:

```
C:\Projects\vox_atc_demo
```

Ensure this file exists:

```
C:\Projects\vox_atc_demo\python\whisper_server.py
```

Optional: set `VOX_ATC_ROOT` if the app cannot find the Python script:

```powershell
setx VOX_ATC_ROOT "C:\Projects\vox_atc_demo"
```

---

## 7. Run the app

```powershell
cd C:\Projects\vox_atc_demo
flutter pub get
flutter run -d windows
```

On first launch:

- The **Whisper server** starts in the background (model load may take 1–2 minutes the first time)
- If no microphone is saved in settings, the demo uses the **first DirectShow mic** ffmpeg reports

---

## 8. Test PTT + transcription

1. Wait until the app window opens and the console shows `SpeechEngine: persistent server ready`
2. **Press and hold Space** (default hold-to-talk key) — works **globally**, even if another window is focused
3. Speak an English ATC phrase, for example:
   - *"Gulf Air 387, hold position"*
   - *"SVA123, taxi via Alpha, hold short runway 34 Left"*
4. **Release Space**
5. Wait 1–2 seconds — transcript appears on screen and in the console

Alternative: use the **Hold to Talk** button in the demo UI (press and hold with the mouse).

### Configure mic and PTT key (optional)

Open **Audio Settings** in your integrated app (or extend the demo to navigate there). Select:

- **Microphone** — must match a DirectShow device name from ffmpeg
- **Hold-to-talk key** — default is Space
- Save settings and restart if you change the PTT key at startup

---

## Platform behavior summary

| Component | Windows | macOS (dev) |
|-----------|---------|-------------|
| **Audio capture** | ffmpeg `dshow` — `audio={micName}` | ffmpeg `avfoundation` — `:0` |
| **Mic list** | `AudioDevicesService.listWindowsMics()` | Not used in demo (hardcoded `:0`) |
| **PTT** | Global `GetAsyncKeyState` polling | In-app `HardwareKeyboard` (window focused) |
| **Python** | `python3.11` → `python3` → `python` | `python3.11` |
| **Paths** | Normalized via `path` package (`\` and `/`) | Same |

---

## Troubleshooting

### `ffmpeg` not found

**Symptoms:** Empty mic list, `AudioCapture: failed to start ffmpeg`, or `ffmpeg is not recognized`.

**Fix:**

1. Confirm `ffmpeg -version` works in a **new** terminal
2. Add the ffmpeg `bin` folder to **System PATH** (not only User PATH if needed)
3. Restart the terminal and IDE
4. Re-run `flutter run -d windows`

---

### Python not found

**Symptoms:** `SpeechEngine: Python not found` or `ProcessException: The system cannot find the file specified`.

**Fix:**

1. Run `python --version` or `py -3.11 --version`
2. Reinstall Python with **Add to PATH** checked
3. Install faster-whisper: `python -m pip install faster-whisper`
4. Set `VOX_ATC_ROOT` to the project folder if the script is not found
5. Restart the app

Manual server test:

```powershell
cd C:\Projects\vox_atc_demo
echo C:\path\to\test.wav | python python\whisper_server.py
```

Expect `READY` on stderr, then transcript + `<<<END>>>` on stdout.

---

### `flutter doctor` errors

| Issue | Fix |
|-------|-----|
| Visual Studio not found | Install **Desktop development with C++** workload |
| Windows desktop disabled | `flutter config --enable-windows-desktop` |
| Chrome/Android licenses | Not required for Windows desktop |
| cmdline-tools missing | Ignore for desktop-only work |

Run:

```powershell
flutter doctor -v
```

---

### No microphone / empty recording

**Symptoms:** `AudioCapture: no microphone configured` or empty transcript.

**Fix:**

1. List devices: `ffmpeg -list_devices true -f dshow -i dummy`
2. Set the exact device name in Audio Settings (including parentheses)
3. Or let the demo pick the first device (automatic on Windows when settings are empty)
4. Check Windows **Privacy → Microphone** — allow desktop apps

---

### Whisper server timeout

**Symptoms:** `timed out waiting for READY`, slow first launch.

**Fix:**

1. First run downloads the model — wait 2–5 minutes
2. Ensure faster-whisper is installed for the Python executable VoxATC selects
3. Check antivirus is not blocking Python or the Hugging Face cache

---

### PTT not detected

**Symptoms:** No `PTT pressed` in console.

**Fix:**

1. On Windows, Space works **globally** — no need to focus the app
2. Confirm HTT key in Audio Settings (default: Space, keyId 32)
3. Restart app after changing settings (loaded at startup in demo)
4. Use the **Hold to Talk** button to verify capture independently of the keyboard

---

## Quick verification checklist

```powershell
flutter doctor
ffmpeg -version
python --version
python -c "from faster_whisper import WhisperModel; print('OK')"
cd C:\Projects\vox_atc_demo
flutter pub get
flutter run -d windows
```

---

## Related docs

- [README.md](README.md) — module overview and integration guide
- [python/whisper_server.py](python/whisper_server.py) — persistent Whisper server (cross-platform)
