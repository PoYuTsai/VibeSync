"""抽卡揭曉 V3 卡背素材產生器（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md §6.5，D2=A）。

從現有金框紫徽記卡背 `practice_draw_card_back_base.png` 離線產出四張 webp，構圖與迷宮
立方徽記不變，只把顏色拿掉，讓 app 執行時依稀有度染色（銀 → 藍 → 金）：

- `practice_draw_card_back_v3_base.webp`：石墨拉絲底＋銀色倒角框＋銀色徽記（全中性）。
- `practice_draw_card_back_v3_emblem_mask.webp`：徽記與星軌線條的白色遮罩（透明底）。
- `practice_draw_card_back_v3_frame_mask.webp`：外框（四角、側邊、上下飾板與框線）遮罩。
- `practice_draw_card_back_v3_glow.webp`：預先模糊好的徽記＋外框光暈（白，透明底）。

全部預先做好，app 只染色、不在逐幀 painter 裡做模糊（規格 §12）。

用法（在 repo 根目錄）：
  python3 tools/practice-draw-card-back-v3/make_card_back_v3.py
需要 Pillow（含 webp）與 numpy。
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'assets/images/practice/practice_draw_card_back_base.png'
OUT_DIR = ROOT / 'assets/images/practice'

# 線條強度：卡背底（拉絲面板）亮度約 0.12–0.35，金框、徽記與星軌線約 0.6–0.95。
LINE_LO = 0.36
LINE_HI = 0.66

# 外框帶（相對卡寬／卡高）：四角飾板、側邊飾條、上下飾板與框線都落在這一圈內。
FRAME_BAND_X = (0.075, 0.095)
FRAME_BAND_Y = (0.050, 0.066)

# 中性底的冷調（石墨銀，不帶金紫）與對比曲線。
BASE_TINT = np.array([0.93, 0.96, 1.0], dtype=np.float32)
BASE_GAMMA = 1.15

# 光暈：窄＋寬兩層高斯（以卡寬 904 px 為基準的半徑）。外框飾板是大片實心，
# 權重壓低，光暈才會以徽記為主。
GLOW_NEAR_RADIUS = 14
GLOW_FAR_RADIUS = 40
GLOW_FRAME_WEIGHT = 0.55


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def to_rgba(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    data = np.concatenate([rgb, alpha[..., None]], axis=-1)
    return Image.fromarray(np.round(np.clip(data, 0, 1) * 255).astype(np.uint8), 'RGBA')


def white_mask(alpha: np.ndarray) -> Image.Image:
    return to_rgba(np.ones(alpha.shape + (3,), dtype=np.float32), alpha)


def blur(mask: np.ndarray, radius: float) -> np.ndarray:
    im = Image.fromarray(np.round(np.clip(mask, 0, 1) * 255).astype(np.uint8), 'L')
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--src', type=Path, default=SRC)
    parser.add_argument('--out', type=Path, default=OUT_DIR)
    args = parser.parse_args()

    src = np.asarray(Image.open(args.src).convert('RGBA')).astype(np.float32) / 255.0
    rgb = src[..., :3]
    alpha = src[..., 3]
    h, w = alpha.shape
    value = rgb.max(axis=-1)

    # 1) 中性底：用亮度（max 通道）保留金飾板的倒角明暗與徽記漸層，染成冷調石墨銀。
    lum = np.power(value, BASE_GAMMA)
    base_rgb = lum[..., None] * BASE_TINT

    # 2) 會發光的線條（金框＋徽記＋星軌）。
    line = smoothstep(LINE_LO, LINE_HI, value) * alpha

    # 3) 外框帶：靠近卡緣的一圈算外框，其餘算徽記與星軌。
    xs = np.arange(w, dtype=np.float32)
    ys = np.arange(h, dtype=np.float32)
    dx = np.minimum(xs, w - 1 - xs) / w
    dy = np.minimum(ys, h - 1 - ys) / h
    band_x = 1.0 - smoothstep(*FRAME_BAND_X, dx)[None, :]
    band_y = 1.0 - smoothstep(*FRAME_BAND_Y, dy)[:, None]
    band = np.maximum(band_x, band_y)
    frame = line * band
    emblem = line * (1.0 - band)

    # 4) 光暈：線條的窄＋寬高斯，夾在卡片 alpha 內，峰值正規化到 1。
    scale = w / 904.0
    lines = np.clip(GLOW_FRAME_WEIGHT * frame + emblem, 0, 1)
    glow = 0.85 * blur(lines, GLOW_NEAR_RADIUS * scale) + 0.65 * blur(lines, GLOW_FAR_RADIUS * scale)
    glow = glow / max(float(glow.max()), 1e-6)
    glow = np.clip(glow, 0, 1) * alpha

    args.out.mkdir(parents=True, exist_ok=True)
    outputs = {
        'practice_draw_card_back_v3_base.webp': (to_rgba(base_rgb, alpha), dict(quality=88, method=6)),
        'practice_draw_card_back_v3_emblem_mask.webp': (white_mask(emblem), dict(lossless=True, method=6)),
        'practice_draw_card_back_v3_frame_mask.webp': (white_mask(frame), dict(lossless=True, method=6)),
        'practice_draw_card_back_v3_glow.webp': (white_mask(glow), dict(quality=80, alpha_quality=80, method=6)),
    }
    total = 0
    for name, (image, options) in outputs.items():
        path = args.out / name
        image.save(path, 'WEBP', **options)
        size = path.stat().st_size
        total += size
        print(f'{name}: {image.width}x{image.height}, {size / 1024:.1f} KB')
    print(f'total: {total / 1024:.1f} KB')


if __name__ == '__main__':
    main()
