# VoxATC — Windows Setup Guide

VoxATC runs on **Windows Desktop**. Use **Section 1** to test the ready-made app. Use **Section 2** if you are building or integrating from source.

---

## Section 1 — For Testing (dist/ folder)

For the client who wants to test without installing anything.

1. Download **VoxATC-Windows.zip**
2. Extract the entire folder (e.g. to `Desktop\VoxATC-Windows`)
3. Run **`runtime\Install_VC_Runtime.bat`** (one time only)
4. Double-click **`Start VoxATC.bat`**
5. Wait ~30 seconds on first launch while Whisper loads
6. The app opens — **press and hold Space** to talk, then release

**No Python, no Flutter, no ffmpeg needed.**

The portable folder includes everything: the app, Whisper model, Python runtime, and ffmpeg.

### Quick test

1. Hold **Space** and say: *"Gulf Air 387, hold position"*
2. Release **Space**
3. The transcript should appear on screen within a few seconds

You can also use the **Hold to Talk** button in the app.

---

## Section 2 — For Development (source code)

For developers who want to build or integrate VoxATC into their own app.

### Prerequisites

1. **Install Flutter for Windows**  
   https://flutter.dev/docs/get-started/install/windows

   Then verify:

   ```powershell
   flutter doctor
   flutter config --enable-windows-desktop
   ```

2. **Install Visual Studio** with **Desktop development with C++**  
   https://visualstudio.microsoft.com/

3. **Install Python 3.11**  
   https://www.python.org/downloads/  
   Check **Add python.exe to PATH** during setup.

4. **Install faster-whisper**

   ```powershell
   pip install faster-whisper
   ```

5. **Install ffmpeg** and add it to **PATH**  
   https://ffmpeg.org/download.html

   Verify:

   ```powershell
   ffmpeg -version
   python --version
   python -c "from faster_whisper import WhisperModel; print('OK')"
   ```

### Run from source

```powershell
cd C:\path\to\vox_atc_demo
flutter pub get
flutter run -d windows
```

On first launch, the Whisper model downloads (~150 MB). Model load may take 1–2 minutes.

Hold **Space** (default push-to-talk key) or use **Hold to Talk** in the UI.

### Build a portable Windows package

To create the same self-contained folder as Section 1:

```powershell
.\scripts\build_windows_portable.ps1
```

Output: `dist\VoxATC-Windows\` and `dist\VoxATC-Windows.zip`

---

## Troubleshooting

### Portable app (Section 1)

| Problem | Fix |
|---------|-----|
| App crashes on startup / exit code `-1073741819` | Run `runtime\Install_VC_Runtime.bat` once, then restart VoxATC |
| Status shows speech engine failed | Make sure you extracted the **entire** folder. Do not delete `data\`, `python\`, or `runtime\` |
| "No speech detected" | Check Windows **Settings → Privacy → Microphone** — allow desktop apps. Try a different mic in Audio Settings |
| Slow first launch | Normal — Whisper loads the model on first run (~30 seconds) |

Always start the app with **`Start VoxATC.bat`** (sets paths for bundled Python). You can also run `vox_atc_demo.exe` directly after VC++ runtime is installed.

---

### Development (Section 2)

| Problem | Fix |
|---------|-----|
| `ffmpeg` not found | Add ffmpeg `bin` folder to PATH. Open a **new** terminal and run `ffmpeg -version` |
| Python not found | Reinstall Python with **Add to PATH**. Run `pip install faster-whisper` |
| Empty mic list | ffmpeg must be on PATH. List devices: `ffmpeg -list_devices true -f dshow -i dummy` |
| Whisper timeout / no READY | First run downloads the model — wait 2–5 minutes. Check antivirus is not blocking Python |
| `flutter doctor` errors | Install Visual Studio **Desktop development with C++** workload. Run `flutter doctor -v` |
| PTT not working | Space works globally on Windows. Use **Hold to Talk** to test capture without the keyboard |

Optional: set `VOX_ATC_ROOT` to your project folder if the app cannot find `python\whisper_server.py`:

```powershell
setx VOX_ATC_ROOT "C:\path\to\vox_atc_demo"
```

---

## Related docs

- [README.md](README.md) — module overview and integration guide
- [scripts/build_windows_portable.ps1](scripts/build_windows_portable.ps1) — portable Windows build script
