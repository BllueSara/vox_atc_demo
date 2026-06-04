#!/usr/bin/env python3
"""Persistent faster-whisper server.

Loads the model once, then reads WAV file paths from stdin (one per line),
writes the transcript to stdout, and stays alive until killed.

Protocol
--------
stderr: ``READY`` once the model is loaded.
stdin:  ``<absolute-or-relative-wav-path>\\n`` per request.
stdout: ``<transcript text>\\n<<<END>>>\\n`` per response (transcript may be empty).
stderr: ``ERROR: ...\\n`` on transcription failures (stdout still ends with ``<<<END>>>``).
"""

from __future__ import annotations

import os
import sys
import traceback
from pathlib import Path

_END_MARKER = "<<<END>>>"
_ATC_PROMPT = (
    "ATC radio communication. Aircraft callsigns: SVA Saudia, UAE Emirates, "
    "GFA Gulf Air, KAC Kuwait Airways, OMA Oman Air. Numbers spoken digit by "
    "digit. Commands: taxi, pushback approved, hold position, continue taxi, "
    "cleared to, line up and wait, cleared for takeoff, contact departure, "
    "squawk, hold short, runway."
)


def _bundle_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _setup_windows_dll_paths(root: Path) -> None:
    if sys.platform != "win32":
        return

    python_dir = root / "runtime" / "python"
    candidates = [
        python_dir,
        python_dir / "Lib" / "site-packages" / "onnxruntime" / "capi",
        python_dir / "Lib" / "site-packages" / "ctranslate2",
    ]
    for directory in candidates:
        if not directory.is_dir():
            continue
        try:
            os.add_dll_directory(str(directory))
        except OSError:
            pass


def _resolve_model_path() -> str:
    bundled = _bundle_root() / "runtime" / "models" / "small.en"
    if (bundled / "model.bin").exists():
        return str(bundled)
    return "small.en"


def _transcribe(model, wav_path: str, *, vad_filter: bool) -> str:
    segments, _info = model.transcribe(
        wav_path,
        beam_size=5,
        best_of=5,
        temperature=0.0,
        condition_on_previous_text=False,
        vad_filter=vad_filter,
        vad_parameters=dict(
            min_silence_duration_ms=300,
            speech_pad_ms=400,
        ),
        initial_prompt=_ATC_PROMPT,
    )
    return " ".join(segment.text.strip() for segment in segments).strip()


def main() -> None:
    root = _bundle_root()
    _setup_windows_dll_paths(root)

    try:
        from faster_whisper import WhisperModel
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"ERROR: cannot import faster_whisper: {exc}\n")
        sys.stderr.flush()
        raise SystemExit(1) from exc

    model_path = _resolve_model_path()
    model_bin = Path(model_path) / "model.bin" if model_path != "small.en" else None
    if model_bin is not None and not model_bin.is_file():
        sys.stderr.write(f"ERROR: model.bin not found at {model_bin}\n")
        sys.stderr.flush()
        raise SystemExit(1)

    sys.stderr.write(f"Loading Whisper model from {model_path}...\n")
    sys.stderr.flush()
    model = WhisperModel(model_path, device="cpu", compute_type="int8")
    sys.stderr.write("READY\n")
    sys.stderr.flush()

    for raw_line in sys.stdin:
        wav_path = raw_line.strip()
        text = ""
        try:
            if not wav_path:
                sys.stderr.write("ERROR: empty path\n")
            else:
                text = _transcribe(model, wav_path, vad_filter=True)
                if not text:
                    text = _transcribe(model, wav_path, vad_filter=False)
        except Exception as exc:  # noqa: BLE001
            sys.stderr.write(f"ERROR: {exc}\n")

        sys.stdout.write(f"{text}\n{_END_MARKER}\n")
        sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"ERROR: {exc}\n")
        traceback.print_exc(file=sys.stderr)
        sys.stderr.flush()
        raise SystemExit(1) from exc
