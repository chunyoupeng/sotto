#!/usr/bin/env python3
"""
VoiceInput ASR sidecar daemon.

Loads the MLX NeMo streaming ASR model once and keeps it warm in memory,
then transcribes audio files on demand. The Swift app talks to this process
over stdin/stdout using newline-delimited JSON ("JSON Lines").

Protocol
--------
stdout (one JSON object per line):
    {"type": "ready"}                                  # model loaded, accepting work
    {"type": "result", "id": <n>, "text": "..."}       # transcription succeeded
    {"type": "error",  "id": <n>, "error": "..."}      # transcription failed
    {"type": "fatal",  "error": "..."}                 # model failed to load

stdin (one JSON object per line):
    {"id": <n>, "audio": "/path/to/file.wav", "language": "en-US"}

Anything written to stderr is treated as diagnostic logging by the host app.
"""

import json
import os
import sys
import traceback

MODEL_ID = os.environ.get(
    "VOICEINPUT_ASR_MODEL", "mlx-community/Qwen3-ASR-0.6B-8bit"
)


def log(*args):
    """Diagnostic logging -> stderr (never parsed by the host app)."""
    print("[asr_server]", *args, file=sys.stderr, flush=True)


def emit(obj):
    """Emit one protocol message -> stdout."""
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    log(f"loading model: {MODEL_ID}")
    try:
        from mlx_audio.stt.utils import load_model

        model = load_model(MODEL_ID)
    except Exception as exc:  # pragma: no cover - startup failure path
        log("model load failed:\n" + traceback.format_exc())
        emit({"type": "fatal", "error": str(exc)})
        return 1

    log("model ready")
    emit({"type": "ready"})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            req = json.loads(line)
        except json.JSONDecodeError as exc:
            emit({"type": "error", "id": None, "error": f"bad request json: {exc}"})
            continue

        req_id = req.get("id")
        audio = req.get("audio")
        language = req.get("language") or None

        if not audio or not os.path.exists(audio):
            emit({"type": "error", "id": req_id, "error": f"audio not found: {audio}"})
            continue

        try:
            kwargs = {}
            if language:
                kwargs["language"] = language
            result = model.generate(audio, **kwargs)
            text = getattr(result, "text", None)
            if text is None:
                text = str(result)
            emit({"type": "result", "id": req_id, "text": text.strip()})
        except Exception as exc:
            log("transcription failed:\n" + traceback.format_exc())
            emit({"type": "error", "id": req_id, "error": str(exc)})

    log("stdin closed, exiting")
    return 0


if __name__ == "__main__":
    # When frozen with PyInstaller, any dependency that uses multiprocessing
    # (spawn) re-launches this executable; freeze_support() makes those child
    # processes behave instead of re-running main() (which would load the model
    # twice and fight over stdin).
    import multiprocessing
    multiprocessing.freeze_support()
    sys.exit(main())
