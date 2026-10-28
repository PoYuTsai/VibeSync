"""成品圖對示意圖目標色的區域色差表（典藏材質規格 §5.5）。

  python3 tools/practice-card-material/concept_match.py --still build/card_back_stills/back_sr.png [--tier sr]
      [--concept <示意圖單張卡背，本機私有>]

一定輸出：各區域的實測色、目標色、CIEDE2000 色差，超過門檻標 ✗。
有給 --concept 時另外輸出並排對照圖（不入庫）。門檻只是提示，最後以 Eric 目視為準。
只依賴 numpy＋Pillow。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
TARGETS = HERE / 'targets.json'


def hex_rgb(s: str) -> np.ndarray:
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float64) / 255.0


def to_hex(c) -> str:
    c = np.clip(np.round(np.asarray(c) * 255), 0, 255).astype(int)
    return '#' + ''.join(f'{v:02X}' for v in c)


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB（0..1）→ CIELAB（D65）。"""
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > (6 / 29) ** 3, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])], axis=-1)


def delta_e2000(lab1: np.ndarray, lab2: np.ndarray) -> float:
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    dhp = h2p - h1p
    if C1p * C2p == 0:
        dhp = 0
    elif dhp > 180:
        dhp -= 360
    elif dhp < -180:
        dhp += 360
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp / 2))
    Lpm, Cpm = (L1 + L2) / 2, (C1p + C2p) / 2
    hpm = h1p + h2p
    if C1p * C2p != 0:
        hpm = (h1p + h2p + 360) / 2 if abs(h1p - h2p) > 180 else (h1p + h2p) / 2
        if abs(h1p - h2p) > 180 and h1p + h2p >= 360:
            hpm -= 360
    T = (1 - 0.17 * np.cos(np.radians(hpm - 30)) + 0.24 * np.cos(np.radians(2 * hpm)) +
         0.32 * np.cos(np.radians(3 * hpm + 6)) - 0.20 * np.cos(np.radians(4 * hpm - 63)))
    dtheta = 30 * np.exp(-(((hpm - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cpm ** 7 / (Cpm ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lpm - 50) ** 2 / np.sqrt(20 + (Lpm - 50) ** 2)
    Sc = 1 + 0.045 * Cpm
    Sh = 1 + 0.015 * Cpm * T
    Rt = -np.sin(np.radians(2 * dtheta)) * Rc
    return float(np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 +
                         Rt * (dCp / Sc) * (dHp / Sh)))


def region_stat(img: np.ndarray, rect, stat: str) -> np.ndarray:
    h, w = img.shape[:2]
    x0, y0, x1, y1 = rect
    px = img[int(y0 * h):max(int(y1 * h), int(y0 * h) + 1),
             int(x0 * w):max(int(x1 * w), int(x0 * w) + 1)].reshape(-1, 3)
    lum = px @ np.array([0.2126, 0.7152, 0.0722])
    order = np.argsort(lum)
    if stat == 'median':
        return np.median(px, axis=0)
    if stat in ('top3', 'top15'):
        k = max(1, int(len(px) * (0.03 if stat == 'top3' else 0.15)))
        return px[order[-k:]].mean(axis=0)
    if stat == 'p35':
        i = int(len(px) * 0.35)
        return px[order[max(0, i - len(px) // 20):i + len(px) // 20 + 1]].mean(axis=0)
    raise ValueError(stat)


def match(still: np.ndarray, tier: str, targets: dict | None = None) -> list[dict]:
    targets = targets or json.loads(TARGETS.read_text())
    rows = []
    for name, reg in targets['regions'].items():
        got = region_stat(still, reg['rect'], reg['stat'])
        want = hex_rgb(targets['targets'][tier][name])
        de = delta_e2000(rgb_to_lab(got), rgb_to_lab(want))
        rows.append({'region': name, 'got': to_hex(got), 'want': to_hex(want),
                     'de': round(de, 2), 'ok': de <= reg['limit'], 'limit': reg['limit']})
    return rows


def holo_hues(still: np.ndarray, mask: np.ndarray | None = None) -> dict:
    """SR 全息：飽和度夠高的像素佔比與色相分布（示意圖：玫瑰到天空藍、佔全息區 2–8%）。"""
    hsv = np.asarray(Image.fromarray((still * 255).astype(np.uint8)).convert('HSV'), np.float64)
    sat = hsv[..., 1] / 255
    val = hsv[..., 2] / 255
    sel = (sat > 0.35) & (val > 0.45)
    if mask is not None:
        sel &= mask
    hue = hsv[..., 0][sel] / 255 * 360
    return {'share': float(sel.mean()), 'hues': np.histogram(hue, bins=12, range=(0, 360))[0].tolist()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--still', type=Path, required=True)
    parser.add_argument('--tier', choices=['n', 'r', 'sr'], default=None)
    parser.add_argument('--concept', type=Path, default=None)
    parser.add_argument('--out', type=Path, default=None, help='並排對照圖（有給 --concept 時）')
    args = parser.parse_args()
    tier = args.tier or next((t for t in ('sr', 'r', 'n') if f'_{t}.' in args.still.name), 'n')
    img = np.asarray(Image.open(args.still).convert('RGB'), np.float64) / 255.0
    rows = match(img, tier)
    print(f'{args.still.name}（{tier}）')
    print(f'{"區域":<16}{"實測":>9}{"目標":>9}{"ΔE2000":>9}')
    for r in rows:
        print(f'{r["region"]:<16}{r["got"]:>9}{r["want"]:>9}{r["de"]:>9.2f} {"✓" if r["ok"] else "✗"}')
    if tier == 'sr':
        print('全息：', holo_hues(img))
    if args.concept:
        a = Image.open(args.still).convert('RGB')
        b = Image.open(args.concept).convert('RGB')
        b = b.resize((round(b.size[0] * a.size[1] / b.size[1]), a.size[1]), Image.LANCZOS)
        sheet = Image.new('RGB', (a.size[0] + b.size[0] + 20, a.size[1]), (20, 20, 20))
        sheet.paste(a, (0, 0))
        sheet.paste(b, (a.size[0] + 20, 0))
        out = args.out or args.still.with_name(args.still.stem + '_vs_concept.jpg')
        sheet.save(out, quality=88)
        print('並排對照：', out)


if __name__ == '__main__':
    main()
