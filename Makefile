# Display/product name is "Sotto"; the Swift executable target is still
# "VoiceInput" (kept so the bundle id / TCC permissions stay stable).
APP_NAME := Sotto
BIN_NAME := VoiceInput
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR := $(shell swift build -c release --show-bin-path 2>/dev/null || echo .build/release)

# Self-contained Python ASR engine (frozen with PyInstaller). When present it is
# bundled into the app so end users need no Python/venv. Build it with `make engine`.
ENGINE_DIR := build_pyi/dist/asr_engine

# Model installed into the user-owned Sotto home. Runtime lookup prefers this
# path (`~/.sotto/models/...`) so config, prompt, and model all live together.
MODEL_NAME := Qwen3-ASR-0.6B-8bit
MODEL_SRC  := /Users/pengchunyou/.cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0___6B-8bit
MODEL_DIR  := $(HOME)/.sotto/models
MODEL_DEST := $(MODEL_DIR)/$(MODEL_NAME)

# Stable local code-signing identity. Signing every build with the same
# self-signed cert keeps the app's Designated Requirement constant, so macOS
# preserves Accessibility/Microphone permissions across rebuilds (grant once).
# Falls back to ad-hoc ("-") if the identity isn't present.
CODESIGN_ID ?= VoiceInput Local Signing

# Re-usable signing recipe.
define SIGN
	@if security find-identity -p codesigning | grep -q "$(CODESIGN_ID)"; then \
		echo "Signing with stable identity: $(CODESIGN_ID)"; \
		codesign --force --deep --sign "$(CODESIGN_ID)" $(APP_BUNDLE); \
	else \
		echo "⚠️  '$(CODESIGN_ID)' not found; ad-hoc signing (permissions will reset each build)"; \
		codesign --force --deep --sign - $(APP_BUNDLE); \
	fi
endef

.PHONY: build engine model dist clean install run

build:
	swift build -c release
	$(eval BUILD_DIR := $(shell swift build -c release --show-bin-path))
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(BIN_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP_BUNDLE)/Contents/
	cp Resources/asr_server.py $(APP_BUNDLE)/Contents/Resources/
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@if [ -d "$(ENGINE_DIR)" ]; then \
		echo "Bundling frozen ASR engine"; \
		cp -R "$(ENGINE_DIR)" $(APP_BUNDLE)/Contents/Resources/asr_engine; \
	else \
		echo "⚠️  No frozen engine ($(ENGINE_DIR)); app will fall back to dev venv. Run 'make engine'."; \
	fi
	$(SIGN)
	@echo "\n✅ Built $(APP_BUNDLE)"

# Freeze the Python ASR sidecar into a self-contained executable.
engine:
	mkdir -p build_pyi
	.venv/bin/pyinstaller --noconfirm --onedir --name asr_engine \
		--distpath build_pyi/dist --workpath build_pyi/work --specpath build_pyi \
		--collect-all mlx --collect-all mlx_audio --collect-submodules mlx_audio \
		Resources/asr_server.py
	@echo "✅ Engine at $(ENGINE_DIR)"

# Expose the local model under ~/.sotto/models. Prefer a symlink for dev/local
# builds so we do not copy multiple GB into the repo or app bundle.
model:
	@if [ ! -d "$(MODEL_SRC)" ]; then echo "❌ Model not found: $(MODEL_SRC)"; exit 1; fi
	mkdir -p "$(MODEL_DIR)"
	@if [ -e "$(MODEL_DEST)" ]; then \
		echo "✅ Model already present: $(MODEL_DEST)"; \
	else \
		ln -s "$(MODEL_SRC)" "$(MODEL_DEST)"; \
		echo "✅ Linked model: $(MODEL_DEST) -> $(MODEL_SRC)"; \
	fi

# Distribution-style local build: app bundle + frozen engine, with the model
# installed in ~/.sotto/models instead of embedded in the app bundle.
dist: build model
	@if [ ! -d "$(APP_BUNDLE)/Contents/Resources/asr_engine" ]; then \
		echo "❌ Frozen engine missing — run 'make engine' first"; exit 1; fi
	@echo "\n✅ Built $(APP_BUNDLE); model lives at $(MODEL_DEST)"

run: build
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"
