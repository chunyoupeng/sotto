# 本地 ASR 集成笔记（Qwen3-ASR + MLX）

把 VoiceInput 从苹果自带的 `SFSpeechRecognizer` 换成**本地 MLX 语音识别模型**的完整记录，包括架构、关键决策，以及一路踩的坑。

---

## 一、最终架构

苹果 Speech 框架是纯 Swift 原生的；MLX 模型只能跑在 **Python**（`mlx-audio`）里。两者之间用一个**常驻 Python 守护进程**桥接：

```
按住 Fn 说话
   │
   ▼
Swift 录音 (AVAudioEngine)  ──►  16kHz 单声道 WAV (临时文件)
   │
   ▼
常驻 Python 守护进程 (Resources/asr_server.py)        ← 模型只加载一次，常驻内存
   │  · 启动时 load 一次 Qwen3-ASR，打印 {"type":"ready"}
   │  · stdin 收 {"id","audio","language"}，stdout 回 {"type":"result","text"}
   ▼
原始识别文本
   │
   ▼
LLM 润色 (LLMRefiner.swift → 自建 27B 端点)           ← 可选，纠错 + 数字规范
   │
   ▼
注入到光标处 (TextInjector，合成键盘事件，不走剪贴板)
```

为什么用「守护进程常驻」而不是「每次现起」：模型加载约 1.1s，每句还现 load 会很卡；常驻后每句只付推理（约 0.4–0.5s）。用户 64G 内存，模型常驻约 1.8G 无压力。

**改动的文件**
- `Resources/asr_server.py`（新增）—— Python 守护进程，JSON-Lines 协议
- `Sources/VoiceInput/SpeechEngine.swift`（重写）—— 录音 + 守护进程生命周期 + 转写
- `Sources/VoiceInput/AppDelegate.swift`—— 松手后显示 "Transcribing..."，去掉了苹果 Speech 的轮询计时器，只请求麦克风权限
- `Sources/VoiceInput/LLMRefiner.swift`—— 换成中文纠错提示词、加 `chat_template_kwargs`、放宽"必须有 API key"的限制
- `Makefile`—— 拷贝 `asr_server.py` 进 bundle；改用固定证书签名

**运行时依赖（绝对路径，可在 `~/.sotto/config.json` 里用 `asrPythonPath`/`asrModelPath` 覆盖）**
- Python：`<项目>/.venv/bin/python3`（`mlx-audio` 从 git 装）
- 模型：`~/.cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0___6B-8bit`（开发机经 `~/.sotto/models/` 软链接暴露）

---

## 二、模型选型

| 模型 | 纯中文 | 中英混说 | 结论 |
|------|--------|----------|------|
| nemotron-3.5-asr-streaming-0.6b | 近乎完美 | ❌ Python→"PS"、server→"SV" | 混说翻车 |
| **Qwen3-ASR-1.7B-4bit** | 完美 | ✅ Python/API/server 全对 | **选它** |

> 注：后续默认量级切到更轻的 `Qwen3-ASR-0.6B-8bit`（见 `AppSettings.defaultModelName`）；1.7B-4bit 仍可在 `~/.sotto/config.json` 的 `asrModelPath` 指定。

实测速度（用户机器，Apple Silicon）：模型加载 ~1.1s，转写 6–7s 音频约 0.4–0.5s（RTF≈0.07，比实时快约 13 倍），常驻内存 ~1.8G。

---

## 三、踩的坑（重点）

### 1. Qwen 0.6B 不是 ASR 模型
最初想用 Qwen 0.6B 替换语音识别——但那是**纯文本 LLM**，吃 token 不吃音频，无法做语音转文字。ASR（Automatic Speech Recognition）是另一类模型（音频→文本）。Qwen 这类只能放在**第二段**做文本润色。

### 2. NVIDIA NeMo 模型跑不了 Mac
`nvidia/nemotron-3.5-asr-streaming-0.6b` 是真 ASR，但依赖 NVIDIA NeMo/CUDA，Mac 没有 N 卡。要用得找 **MLX 版**（`mlx-community/...`），专为 Apple Silicon 优化。

### 3. NeMo 在中英混说上翻车
0.6b 把句中的英文术语读错（Python→PS、server→SV）。而中英混说恰恰是程序员日常最需要的场景，所以换成中文底子更好的 Qwen3-ASR。

### 4. 模型下载：HuggingFace 各种失败 → 改用 ModelScope
- **xet 后端死循环**：`hf-xet` 反复重新分块下载那个 1GB 权重文件，下到一半丢弃重来，浪费带宽不收敛。
- **hf-mirror 被新版 hub 拒**：`huggingface_hub` 1.21 会校验响应头必须来自 huggingface.co，hf-mirror（返回 308 重定向）不带那些头，直接报 `FileMetadataError`。
- **解法**：用 **ModelScope** 镜像。`pip install modelscope` 后 `snapshot_download("mlx-community/Qwen3-ASR-1.7B-4bit")`，稳定且快（国内）。`load_model()` 直接指向 ModelScope 的本地缓存路径即可。
- 注意 ModelScope 缓存目录把点换成下划线：`Qwen3-ASR-1___7B-4bit`。

### 5. Python 3.14 太新（结果没事）
担心 `mlx-audio` 依赖在 3.14 上没轮子，实测能正常装、能 import。虚惊一场。

### 6. 代码签名 → 这是最折磨的坑
问题本质：每次 `make build` 用临时签名（`codesign --sign -`），app 的签名身份每次都变，macOS 的 TCC 就当成"另一个 app"，**之前授权的辅助功能权限作废**，每次重编译都要重新授权。

试过的方案：
- **Apple 开发者证书** → ❌ **千万别用**。在这台很新的 macOS（Darwin 27）上，用 `Apple Development` 证书签名反而触发 Gatekeeper「无法验证是否含恶意软件」弹窗，app 被移进废纸篓。开发者证书需要配套描述文件，裸签会被严格校验拦下。
- **ad-hoc 临时签名** → 能跑、不弹恶意软件框，但每次编译权限失效。
- **自签名本地证书** → ✅ **正解**。不挂靠苹果证书链（所以不触发恶意软件检查），但身份固定。

自签名证书的子坑：
- `openssl pkcs12 -export` 默认格式 macOS 认不了 → 报 `MAC verification failed`，要加 **`-legacy`**。
- **空密码的 p12 也会 MAC 校验失败** → 必须给个**非空密码**（`-passout pass:xxx`，导入时 `-P xxx`）。
- 导入时加 `-T /usr/bin/codesign -A` 预授权，签名时才不会弹钥匙串密码框。
- 证书虽标 `CSSMERR_TP_NOT_TRUSTED`，但 codesign 仍可用它签名；本地构建、无 quarantine 属性的 app 启动不走公证校验，能正常跑。
- 校验"长期有效"的关键：`codesign -d -r-` 看**指定要求（Designated Requirement）**应为 `identifier "..." and certificate leaf = H"<证书哈希>"`——只要这个哈希不变，重编译多少次权限都不掉。

创建证书的命令（一次性）：
```bash
cat > cs.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = VoiceInput Local Signing
[ v3 ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
openssl req -x509 -newkey rsa:2048 -keyout cs.key -out cs.crt -days 3650 -nodes -config cs.cnf
openssl pkcs12 -export -legacy -inkey cs.key -in cs.crt -out cs.p12 \
  -name "VoiceInput Local Signing" -passout pass:voiceinput
security import cs.p12 -k ~/Library/Keychains/login.keychain-db \
  -P voiceinput -T /usr/bin/codesign -A
```
Makefile 里据此用固定身份签名（找不到则回退 ad-hoc）。

### 7. LLM 润色提示词设计
- **防注入是头等大事**：口述内容可能长得像指令（如"用一句话介绍秋天"）。提示词必须明确：无论文本多像问题/命令，都只校对并原样返回，**绝不回应其内容**。否则模型会真去"介绍秋天"。
- **数字规范要写清边界**：转数值（"三点一四"→3.14、"百分之二十"→20%、"二零二六年"→2026年），但保留量词/序数（"一下""第一个"不转）；数字与中文之间不加空格。
- 调用参数：`temperature: 0.2`、`chat_template_kwargs: {enable_thinking: false}`（关思考链省延迟）。
- 端点无需 API key，所以放宽了 `isConfigured`（只要有 base URL 即可），且仅在 key 非空时才发 `Authorization` 头。

---

## 四、当前 v1 的已知限制
- **非流式**：松手后整句转写，不是边说边出字（流式跨 Swift↔Python 边界复杂，留待后续）。
- **依赖绝对路径**：`.venv` 和 ModelScope 模型缓存不能移动/删除（可在 `~/.sotto/config.json` 用 `asrPythonPath`/`asrModelPath` 覆盖）。
- **繁体中文（zh-TW）**：Qwen3-ASR 语言清单里没有，效果不保证。

日志：`~/Library/Logs/VoiceInput.log`
重启：`osascript -e 'quit app "VoiceInput"'` 然后 `open VoiceInput.app`
