"""把各階、各材質的坡度起點 base 對 targets.json 校準（典藏材質規格 §5.5）。

  python3 tools/practice-card-material/calibrate.py [--scale 0.5]

每一輪用半解析度渲染一次，所有材質同時二分搜尋，讓區域的亮度（CIELAB L*）對到目標色；
印出建議的 base，手動寫回 render_card_back.TIERS（成品渲染不在執行時校準，重跑才會逐位元相同）。
"""

from __future__ import annotations

import argparse
import json

import numpy as np

import concept_match as cm
import heightfield as hf
import render_card_back as rc

# 材質 → 用哪些區域量（取平均 L*）
PROBES = {
    'plate': ['top-plate'],
    'corner': ['corner-plate'],
    'bar': ['side-bar-left', 'side-bar-right'],
    'band': ['edge-band'],
    'emblem': ['emblem'],
    'field': ['field-mid'],
}


def measure(img: np.ndarray, tier: str, targets: dict) -> dict[str, tuple[float, float]]:
    out = {}
    for key, regions in PROBES.items():
        got, want = [], []
        for r in regions:
            reg = targets['regions'][r]
            got.append(cm.rgb_to_lab(cm.region_stat(img, reg['rect'], reg['stat']))[0])
            want.append(cm.rgb_to_lab(cm.hex_rgb(targets['targets'][tier][r]))[0])
        out[key] = (float(np.mean(got)), float(np.mean(want)))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--scale', type=float, default=0.5)
    parser.add_argument('--iters', type=int, default=9)
    args = parser.parse_args()
    targets = json.loads(cm.TARGETS.read_text())
    hfm = hf.build(scale=args.scale)
    smoke = rc.smoke_texture(hfm['height'].shape)
    prep = rc.prepare(hfm, smoke)  # 法線、反射、環境光、紋理跟 base 無關，只算一次
    result = {}
    for name, tier in rc.TIERS.items():
        lo = {k: -0.6 for k in PROBES}
        hi = {k: 1.4 for k in PROBES}
        base = dict(rc.DEFAULT_BASE, **(tier.base or {}))
        for _ in range(args.iters):
            for k in PROBES:
                base[k] = (lo[k] + hi[k]) / 2
            t = rc.Tier(**{**tier.__dict__, 'base': base})
            img, _ = rc.shade(hfm, t, smoke=smoke, prep=prep)
            for k, (got, want) in measure(img.astype(np.float64), name, targets).items():
                if got < want:
                    lo[k] = base[k]
                else:
                    hi[k] = base[k]
        result[name] = {k: round(v, 3) for k, v in base.items()}
        t = rc.Tier(**{**tier.__dict__, 'base': result[name]})
        img, _ = rc.shade(hfm, t, smoke=smoke, prep=prep)
        rows = cm.match(img.astype(np.float64), name, targets)
        print(name, result[name])
        for r in rows:
            print(f'   {r["region"]:<16}{r["got"]:>9}{r["want"]:>9}{r["de"]:>7.2f} {"✓" if r["ok"] else "✗"}')
    print(json.dumps(result, indent=1))


if __name__ == '__main__':
    main()
