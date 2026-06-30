# Sotto

**Sotto** is a macOS menu-bar dictation app for Apple Silicon. Hold a hotkey,
speak, and your words are transcribed on-device and injected straight into
whatever text field is focused — no cloud round-trip for the speech, no copy and
paste. An optional LLM pass cleans up the raw transcript (fixes homophones,
normalizes numbers, keeps technical terms in English) before the text lands.

The name is Italian for *"softly / in a whisper"* — the app sits quietly in the
menu bar until you need it.

> Requires **Apple Silicon** (the speech model runs on MLX/Metal) and
> **macOS 14 (Sonoma) or later**. The overlay uses the native Liquid Glass
> effect on macOS 26+, with a graceful fallback on older releases.

## Features

- **Push-to-talk dictation** — hold a key to record, release to transcribe.
  A quick tap latches into hands-free "keep listening" mode until you tap again.
- **On-device speech recognition** — a local [Qwen3-ASR](https://huggingface.co/collections/mlx-community)
  model runs in a resident MLX sidecar, so audio never leaves your machine and
  each utterance pays only inference cost (~0.5 s), not model-load cost.
- **Optional LLM refinement** — point it at any OpenAI-compatible chat endpoint
  to polish the raw transcript. The system prompt lives in a plain-text file you
  can edit by hand and takes effect on the next utterance, no restart needed.
- **Direct text injection** — the result is typed into the frontmost app's
  focused field via the Accessibility API.
- **Dashboard** — today's stats, a 7-day chart, lifetime totals, and a scrollable
  history where every entry keeps the original audio (playable), the raw ASR
  transcript, and the refined text side by side.
- **Configurable hotkeys** — the trigger can be Fn, a bare modifier (e.g. Right ⌘),
  or any key + modifier combination.

## Architecture

```
┌──────────────────────────────┐        stdin/stdout (JSON lines)
│  Sotto.app  (Swift / AppKit)  │  ◄───────────────────────────────►  ┌────────────────────────┐
│  • global hotkey event tap    │                                     │  ASR sidecar (Python)   │
│  • AVAudioEngine capture      │   16 kHz mono WAV path  ──────────► │  • MLX Qwen3-ASR model  │
│  • overlay + dashboard UI     │   ◄──────────  transcript text      │  • stays resident       │
│  • LLM refinement (HTTP)      │                                     └────────────────────────┘
│  • Accessibility text inject  │
└──────────────────────────────┘
```

The Swift app records audio natively and hands a temporary WAV to a long-lived
Python process that runs the MLX speech model. The sidecar can be shipped as a
self-contained, PyInstaller-frozen binary (`asr_engine`) so end users need no
Python or virtualenv.

All user-owned runtime state lives under `~/.sotto`:

| Path | Purpose |
| --- | --- |
| `config.json` | structured settings (hotkeys, model path, LLM endpoint, …) |
| `prompt.txt`  | editable LLM refinement system prompt |
| `models/`     | local ASR models (symlinks into a model cache are fine) |

History and saved audio live separately under
`~/Library/Application Support/Sotto/`; logs are written to
`~/Library/Logs/Sotto.log`.

## Requirements

- Apple Silicon Mac
- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools (for `swift build`)
- For development / freezing the engine: Python 3 and the MLX speech stack
  (`mlx`, `mlx-audio`) in a local `.venv`

## Build & Run

```bash
make build    # build the Sotto.app bundle
make engine   # freeze the Python ASR sidecar into a self-contained binary
make model    # link/copy a local ASR model into ~/.sotto/models
make dist     # build the app + verify the ~/.sotto model install
make run      # build and launch
make install  # copy to /Applications
make clean    # remove build artifacts
```

A typical first run:

```bash
make model    # make a speech model available under ~/.sotto/models
make engine   # (optional) bundle a standalone Python engine
make install  # build and install into /Applications
```

On first launch, grant **Accessibility** (for the global hotkey and text
injection) and **Microphone** permissions when prompted.

## Configuration

Everything is editable from the menu-bar **Settings** window, or directly in
`~/.sotto/config.json`.

**Switching the speech model.** Drop a model (or a symlink to one) under
`~/.sotto/models/`, then set `asrModelPath` to it and relaunch Sotto so the
sidecar reloads:

```jsonc
// ~/.sotto/config.json
"asrModelPath": "/Users/you/.sotto/models/Qwen3-ASR-1.7B-4bit"
```

Larger models (e.g. 1.7B) are generally more accurate but slower and heavier;
smaller / higher-precision quants trade accuracy for speed. Pick per your taste.

**LLM refinement.** Set `llmEnabled`, `llmAPIBaseURL`, optional `llmAPIKey`, and
`llmModel`. Edit the prompt in `~/.sotto/prompt.txt` — it's read fresh on every
utterance.

## Credits

Sotto began as a fork of [yetone/voice-input-dist](https://github.com/yetone/voice-input-dist)
and has since been substantially rewritten. Thanks to the original author for
the starting point.

## License

This project does not yet declare a license. Until one is added, all rights are
reserved by the author.
