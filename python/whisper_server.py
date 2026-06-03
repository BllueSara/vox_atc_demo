#!/usr/bin/env python3.11
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

import sys

from faster_whisper import WhisperModel

_END_MARKER = "<<<END>>>"


def _transcribe(model: WhisperModel, wav_path: str) -> str:
    segments, info = model.transcribe(
        wav_path,
        beam_size=5,
        best_of=5,
        temperature=0.0,
        condition_on_previous_text=False,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=300,
            speech_pad_ms=400,
        ),
        initial_prompt="ATC radio communication. Aircraft callsigns: SVA Saudia, UAE Emirates, GFA Gulf Air, KAC Kuwait Airways, OMA Oman Air. Numbers spoken digit by digit. Commands: taxi, pushback approved, hold position, continue taxi, cleared to, line up and wait, cleared for takeoff, contact departure, squawk, hold short, runway.",
    )
    return " ".join(segment.text.strip() for segment in segments).strip()


def main() -> None:
    model = WhisperModel("small.en", device="cpu", compute_type="int8")
    sys.stderr.write("READY\n")
    sys.stderr.flush()

    for raw_line in sys.stdin:
        wav_path = raw_line.strip()
        text = ""
        try:
            if not wav_path:
                sys.stderr.write("ERROR: empty path\n")
            else:
                text = _transcribe(model, wav_path)
        except Exception as exc:  # noqa: BLE001 — return error to client via protocol
            sys.stderr.write(f"ERROR: {exc}\n")

        sys.stdout.write(f"{text}\n{_END_MARKER}\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
