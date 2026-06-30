#!/usr/bin/env python3
"""对比多个 Qwen3-ASR 量化版本在 50 条中英混杂技术句上的原始识别效果。

用法: ../.venv/bin/python run_eval.py
输出: 终端打印汇总 + 写入 results.md（逐句对照）
"""
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from sentences import SENTENCES

MS = "/Users/pengchunyou/.cache/modelscope/hub/models/mlx-community"
MODELS = {
    "0.6B-4bit": f"{MS}/Qwen3-ASR-0___6B-4bit",
    "0.6B-8bit": f"{MS}/Qwen3-ASR-0___6B-8bit",
    "1.7B-4bit": f"{MS}/Qwen3-ASR-1___7B-4bit",
}
AUDIO_DIR = os.path.join(os.path.dirname(__file__), "audio")


def normalize(s: str) -> str:
    out = []
    for ch in s:
        o = ord(ch)
        if o == 0x3000:
            continue
        if 0xFF01 <= o <= 0xFF5E:
            ch = chr(o - 0xFEE0)
        out.append(ch)
    s = "".join(out).lower()
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"[，。、？！；：,.?!;:\"'`（）()\[\]【】<>《》…—\-]", "", s)
    s = s.replace("百分之", "")
    s = re.sub(r"[0-9零〇○一二三四五六七八九十百千万亿两%]", "", s)
    return s


def cer(ref: str, hyp: str) -> float:
    r, h = normalize(ref), normalize(hyp)
    n, m = len(r), len(h)
    if n == 0:
        return 0.0 if m == 0 else 1.0
    prev = list(range(m + 1))
    for i in range(1, n + 1):
        cur = [i] + [0] * m
        for j in range(1, m + 1):
            cost = 0 if r[i - 1] == h[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev = cur
    return prev[m] / n


def transcribe_all(model_path):
    from mlx_audio.stt.utils import load_model
    t0 = time.time()
    model = load_model(model_path)
    load_t = time.time() - t0
    results, total_infer = [], 0.0
    for i in range(len(SENTENCES)):
        wav = os.path.join(AUDIO_DIR, f"{i:02d}.wav")
        t = time.time()
        r = model.generate(wav, language="zh")
        total_infer += time.time() - t
        results.append(getattr(r, "text", "").strip())
    del model
    return results, load_t, total_infer


def main():
    names = [n for n in MODELS if os.path.isdir(MODELS[n])]
    outputs, stats = {}, {}
    for name in names:
        print(f"\n=== 运行 {name} ===", flush=True)
        outs, load_t, infer_t = transcribe_all(MODELS[name])
        outputs[name] = outs
        cers = [cer(SENTENCES[i], outs[i]) for i in range(len(SENTENCES))]
        exact = sum(1 for i in range(len(SENTENCES))
                    if normalize(SENTENCES[i]) == normalize(outs[i]))
        stats[name] = {"avg_cer": sum(cers) / len(cers), "exact": exact,
                       "load_t": load_t, "infer_t": infer_t, "cers": cers}
        print(f"{name}: 平均CER={stats[name]['avg_cer']*100:.2f}%  完全正确={exact}/50  "
              f"加载={load_t:.1f}s  总推理={infer_t:.1f}s", flush=True)

    with open(os.path.join(os.path.dirname(__file__), "results.md"), "w") as f:
        f.write("# Qwen3-ASR 多版本原始识别对比\n\n")
        f.write("数据集：50 条中英混杂 + 技术术语，合成语音（macOS `say` Tingting，16kHz 单声道）。"
                "CER 已做数字中性化。\n\n## 汇总\n\n")
        f.write("| 模型 | 平均 CER | 完全正确 | 加载 | 总推理(50句) |\n|---|---|---|---|---|\n")
        for name in names:
            s = stats[name]
            f.write(f"| {name} | {s['avg_cer']*100:.2f}% | {s['exact']}/50 | "
                    f"{s['load_t']:.1f}s | {s['infer_t']:.1f}s |\n")
        f.write("\n> CER 越低越好。合成语音偏“简单模式”，绝对值偏乐观；重点看相对差距。\n\n")
        f.write("## 逐句对照\n\n| # | 参考 | " + " | ".join(names) + " | "
                + " | ".join(f"CER {n}" for n in names) + " |\n")
        f.write("|---|---|" + "|".join(["---"] * (2 * len(names))) + "|\n")
        for i in range(len(SENTENCES)):
            ref = SENTENCES[i].replace("|", "\\|")
            outs = " | ".join(outputs[n][i].replace("|", "\\|") for n in names)
            cers = " | ".join(f"{stats[n]['cers'][i]*100:.0f}%" for n in names)
            f.write(f"| {i} | {ref} | {outs} | {cers} |\n")
    print("\n已写入 bench/results.md")


if __name__ == "__main__":
    main()
