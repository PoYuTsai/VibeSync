"""抽卡揭曉 V3.1 光效貼圖產生器（規格 docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5.1、§5.4、§5.7、§9）。

離線算出三張白色、透明底的貼圖，app 執行時只染色＋疊加混色，不在逐幀 painter 裡做模糊：

- `practice_reveal_bloom.webp`：512×512 柔光（高斯衰減，邊緣歸零），卡片前後兩層泛光、徽記白光用。
- `practice_reveal_sparkle.webp`：256×256 四芒星光（上下左右四道漸細光芒＋中心柔光），
  星星點亮與落位爆光用。
- `practice_reveal_particle.webp`：64×64 光點（實心核＋外暈），星塵以 `Canvas.drawRawAtlas` 一次畫完。

全部是純數學（numpy），同一份程式重跑逐位元相同。

用法（在 repo 根目錄）：
  python3 tools/practice-reveal-sprites/make_sprites.py
需要 Pillow（含 webp）與 numpy。
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / 'assets/images/practice'

# 泛光：σ（以半邊長為 1）；扣掉邊緣的值讓外圈正好透明，不會有方形邊。
BLOOM_SIZE = 512
BLOOM_SIGMA = 0.35

# 四芒星：光芒在尖端的半寬、在中心的半寬（以半邊長為 1）、沿光芒的衰減指數、中心柔光 σ。
SPARKLE_SIZE = 256
SPARKLE_TIP_WIDTH = 0.010
SPARKLE_BASE_WIDTH = 0.060
SPARKLE_FALLOFF = 1.6
SPARKLE_CORE_SIGMA = 0.10

# 光點：實心核半徑、核邊緣柔化寬度、外暈 σ 與強度。
PARTICLE_SIZE = 64
PARTICLE_CORE = 0.22
PARTICLE_EDGE = 0.08
PARTICLE_HALO_SIGMA = 0.32
PARTICLE_HALO = 0.55


def grid(size: int) -> tuple[np.ndarray, np.ndarray]:
    # 像素中心座標，正規化到 −1..1（半邊長為 1）。
    c = (np.arange(size, dtype=np.float64) + 0.5) / size * 2.0 - 1.0
    return np.meshgrid(c, c)


def white(alpha: np.ndarray) -> Image.Image:
    a = np.round(np.clip(alpha, 0.0, 1.0) * 255.0).astype(np.uint8)
    rgb = np.full(a.shape + (3,), 255, dtype=np.uint8)
    return Image.fromarray(np.concatenate([rgb, a[..., None]], axis=-1), 'RGBA')


def bloom() -> np.ndarray:
    x, y = grid(BLOOM_SIZE)
    r2 = x * x + y * y
    edge = np.exp(-1.0 / (2.0 * BLOOM_SIGMA**2))
    a = (np.exp(-r2 / (2.0 * BLOOM_SIGMA**2)) - edge) / (1.0 - edge)
    return np.where(r2 < 1.0, a, 0.0)


def sparkle() -> np.ndarray:
    x, y = grid(SPARKLE_SIZE)

    def ray(along: np.ndarray, across: np.ndarray) -> np.ndarray:
        t = np.clip(1.0 - np.abs(along), 0.0, 1.0)  # 中心 1、尖端 0
        half = SPARKLE_TIP_WIDTH + (SPARKLE_BASE_WIDTH - SPARKLE_TIP_WIDTH) * t**3
        return np.exp(-((across / half) ** 2)) * t**SPARKLE_FALLOFF

    rays = np.maximum(ray(x, y), ray(y, x))
    core = np.exp(-(x * x + y * y) / (2.0 * SPARKLE_CORE_SIGMA**2))
    a = np.maximum(rays, core)
    return a / a.max()


def particle() -> np.ndarray:
    x, y = grid(PARTICLE_SIZE)
    r = np.sqrt(x * x + y * y)
    t = np.clip((PARTICLE_CORE + PARTICLE_EDGE - r) / PARTICLE_EDGE, 0.0, 1.0)
    core = t * t * (3.0 - 2.0 * t)
    halo = PARTICLE_HALO * np.exp(-(r * r) / (2.0 * PARTICLE_HALO_SIGMA**2))
    a = np.maximum(core, halo)
    return np.where(r < 1.0, a, 0.0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--out', type=Path, default=OUT_DIR)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    outputs = {
        'practice_reveal_bloom.webp': bloom(),
        'practice_reveal_sparkle.webp': sparkle(),
        'practice_reveal_particle.webp': particle(),
    }
    total = 0
    for name, alpha in outputs.items():
        path = args.out / name
        image = white(alpha)
        image.save(path, 'WEBP', lossless=True, method=6)
        size = path.stat().st_size
        total += size
        print(f'{name}: {image.width}x{image.height}, {size / 1024:.1f} KB')
    print(f'total: {total / 1024:.1f} KB')


if __name__ == '__main__':
    main()
