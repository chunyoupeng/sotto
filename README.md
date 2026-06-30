# Sotto

A macOS menu-bar dictation app backed by a local MLX ASR sidecar. Press a hotkey, speak, and the transcribed text is injected directly into the currently focused text field.

User-owned runtime state lives under `~/.sotto`:

- `config.json` - structured settings
- `prompt.txt` - editable LLM refinement prompt
- `models/` - local ASR model storage



https://github.com/user-attachments/assets/3228f78a-f035-447d-98ef-8826798a122c



## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools (for `swift build`)

## Build & Run

```bash
make build   # build the .app bundle
make model   # link/copy the local model into ~/.sotto/models
make dist    # build the app and verify the ~/.sotto model install
make run     # build and launch
make install # copy to /Applications
make clean   # remove build artifacts
```

## Source Code

The full source code lives at **<https://github.com/yetone/voice-input-src>**.

> **Reproducibility guarantee:** the source repository contains every file needed to produce **exactly** this distributed artifact. You can clone it and run `make build` to obtain an identical `VoiceInput.app` bundle. The build process is recorded and publicly verifiable — see the asciinema session below.

## Build Recording

A complete, unedited terminal recording of the build from source is available here:

[![asciicast](https://asciinema.org/a/cHD6XaaNvomCuysh.svg)](https://asciinema.org/a/cHD6XaaNvomCuysh)

This recording demonstrates that the source code at <https://github.com/yetone/voice-input-src> **can and does** build this exact artifact without modification.

## License

See the source repository for license details.
