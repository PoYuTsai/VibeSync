"""抽卡揭曉閃光檢查：用錄影工具的實際畫面數每秒閃光次數（WCAG 2.3.1 一般閃光的簡化量法）。

規格 docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §3、§12.2：
- 25 cm（預設）：任一 1 s 窗內的閃光最多 2 次（比 WCAG 的 3 次嚴）。
- 20 cm（`--distance-cm 20 --cap 3`）：手機拿得更近時，最多 3 次（WCAG 的門檻）。
只看時間軸上的曲線會漏掉光刃、十字光、泛光、衝擊波、收卡光球這些疊上去的亮光，所以直接量
畫面（Codex 2026-10-18 #107 P2-1）。

量法：
1. 每一幀換成相對亮度（sRGB → 線性 → Y＝0.2126R＋0.7152G＋0.0722B），平均縮成每格 2×2 pt。
2. 閃光要夠大才算：WCAG 的定義是同時閃的面積超過 0.006 立體弧度（典型觀看距離下 10° 視野的
   25%）。手機照 `--distance-cm`（預設 25 cm）換算：6.1 吋 iPhone 1 pt ≈ 0.01657 cm，
   25 cm 約 13,500 pt²，取 116×116 pt 的方框在畫面上滑動（每 16 pt 一格），每個方框取平均亮度。
   拿得更近就給更近的距離（20 cm 約 94 pt 方框）。
3. 每個方框、每個 1 s 的窗（--fps 幀）各自從頭找轉折：跟上一個極值相比變化 ≥ 0.1 就算一次（遲滯），
   一升一降算一次閃光，而且暗的那一端要 < 0.8。每個窗從頭找，窗外的變化不會吃掉窗內的轉折。
4. 回報所有方框、所有窗裡最多的閃光次數。

用法（在 repo 根目錄）：先用 60 fps 錄好 build/card_draw_preview/<稀有度>/
（24 fps 會錯過兩幀之間最亮與最暗的那一下）：
  RECORD_CEREMONY=1 RECORD_FPS=60 flutter test test/tools/ceremony_preview_recorder_test.dart
  python3 tools/practice-reveal-flash-check/flash_check.py --fps 60 build/card_draw_preview/{n,r,sr}
  python3 tools/practice-reveal-flash-check/flash_check.py --fps 60 --distance-cm 20 --cap 3 \
      build/card_draw_preview/{n,r,sr}
需要 Pillow 與 numpy。只看畫面亮度，不判斷紅色閃光（揭曉沒有飽和紅）。
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

FPS = 24  # 錄影的 fps（--fps）；一個 1 s 窗＝FPS 幀
PT_PER_CELL = 2  # 降解析度後每格 2×2 pt
STERADIANS = 0.006  # WCAG 2.3.1：10° 視野的 25%
CM_PER_PT = 2.54 / 153.3  # 6.1 吋 iPhone（460 ppi、@3x）
STRIDE_PT = 16
DELTA = 0.1  # WCAG：相對亮度變化 ≥ 10%
DARK_MAX = 0.8  # WCAG：暗的那一端 < 0.80
CAP = 2  # 規格 §3：任一秒最多 2 次（--cap）


def luminance(path: Path, cell_px: int) -> np.ndarray:
    rgb = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32) / 255.0
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    y = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722
    h = y.shape[0] // cell_px * cell_px
    w = y.shape[1] // cell_px * cell_px
    return y[:h, :w].reshape(h // cell_px, cell_px, w // cell_px, cell_px).mean(axis=(1, 3))


def box_means(frames: np.ndarray, box: int, stride: int) -> tuple[np.ndarray, list]:
    # 積分影像：每個方框的平均一次算完。
    t, h, w = frames.shape
    integral = np.zeros((t, h + 1, w + 1), dtype=np.float64)
    integral[:, 1:, 1:] = frames.cumsum(axis=1).cumsum(axis=2)
    ys = list(range(0, h - box + 1, stride))
    xs = list(range(0, w - box + 1, stride))
    means = np.empty((len(ys) * len(xs), t))
    origins = []
    k = 0
    for y0 in ys:
        for x0 in xs:
            y1, x1 = y0 + box, x0 + box
            s = integral[:, y1, x1] - integral[:, y0, x1] - integral[:, y1, x0] + integral[:, y0, x0]
            means[k] = s / (box * box)
            origins.append((y0, x0))
            k += 1
    return means, origins


def transitions(series: np.ndarray) -> list[tuple[int, int, float]]:
    """遲滯 [DELTA] 找亮度轉折：回傳 (幀, 方向 +1 升／−1 降, 這次轉折暗的那一端)。方向一定交替。"""
    out = []
    direction = 0
    lo = hi = ref = float(series[0])
    for i, value in enumerate(series[1:], start=1):
        v = float(value)
        if direction == 0:
            lo, hi = min(lo, v), max(hi, v)
            if v - lo >= DELTA:
                out.append((i, +1, lo))
                direction, ref = +1, v
            elif hi - v >= DELTA:
                out.append((i, -1, v))
                direction, ref = -1, v
        elif direction > 0:
            ref = max(ref, v)
            if ref - v >= DELTA:
                out.append((i, -1, v))
                direction, ref = -1, v
        else:
            ref = min(ref, v)
            if v - ref >= DELTA:
                out.append((i, +1, ref))
                direction, ref = +1, v
    return out


def flashes(series: np.ndarray) -> list[tuple[int, int]]:
    """一升一降（或一降一升）算一次閃光，兩兩配對不重疊，暗的那一端要 < [DARK_MAX]。
    回傳每次閃光的（開始幀, 結束幀）。"""
    events = transitions(series)
    out = []
    k = 0
    while k + 1 < len(events):
        a, b = events[k], events[k + 1]
        if min(a[2], b[2]) < DARK_MAX:
            out.append((a[0], b[0]))
            k += 2
        else:
            k += 1
    return out


def box_pt_for(distance_cm: float) -> int:
    """WCAG 面積門檻（0.006 sr）在 [distance_cm] 觀看距離下的方框邊長（pt，取偶數）。"""
    area_pt2 = STERADIANS * distance_cm**2 / CM_PER_PT**2
    return max(PT_PER_CELL, round(area_pt2**0.5 / PT_PER_CELL) * PT_PER_CELL)


BOX_PT = box_pt_for(25)


def check(folder: Path) -> dict:
    paths = sorted(folder.glob('frame_*.png'))
    if not paths:
        raise SystemExit(f'{folder}: 找不到 frame_*.png')
    first = Image.open(paths[0])
    cell_px = round(first.width / 390 * PT_PER_CELL)
    frames = np.stack([luminance(p, cell_px) for p in paths])
    box = BOX_PT // PT_PER_CELL
    stride = STRIDE_PT // PT_PER_CELL
    means, origins = box_means(frames, box, stride)
    worst = (0, None, None)
    for k, series in enumerate(means):
        # 只看窗內亮度變化有到門檻的窗（其他窗不可能有閃光），省下大部分時間。
        windows = np.lib.stride_tricks.sliding_window_view(series, FPS)
        busy = np.nonzero(windows.max(axis=1) - windows.min(axis=1) >= DELTA)[0]
        for start in busy.tolist():
            n = len(flashes(series[start:start + FPS]))
            if n > worst[0]:
                worst = (n, start, origins[k])
    count, start, origin = worst
    return {
        'folder': str(folder),
        'frames': len(paths),
        'max_flashes_per_second': count,
        'window_ms': None if start is None else (round(start * 1000 / FPS), round((start + FPS) * 1000 / FPS)),
        'box_pt': None if origin is None else (origin[1] * PT_PER_CELL, origin[0] * PT_PER_CELL),
        'pass': count <= CAP,
    }


def main() -> None:
    global BOX_PT, FPS, CAP
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('folders', nargs='+', type=Path)
    parser.add_argument('--distance-cm', type=float, default=25)
    parser.add_argument('--fps', type=int, default=24)
    parser.add_argument('--cap', type=int, default=CAP)
    args = parser.parse_args()
    BOX_PT = box_pt_for(args.distance_cm)
    FPS = args.fps
    CAP = args.cap
    print(f'觀看距離 {args.distance_cm:g} cm → 方框 {BOX_PT}×{BOX_PT} pt（{BOX_PT * BOX_PT:,} pt²）')
    failed = False
    for folder in args.folders:
        r = check(folder)
        failed |= not r['pass']
        where = '' if r['window_ms'] is None else f"，最多的一秒 {r['window_ms'][0]}–{r['window_ms'][1]} ms、方框左上 {r['box_pt']} pt"
        print(f"{r['folder']}：{r['frames']} 幀，任一秒最多 {r['max_flashes_per_second']} 次閃光{where} → "
              f"{'過' if r['pass'] else '超過上限'}（上限 {CAP}）")
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
