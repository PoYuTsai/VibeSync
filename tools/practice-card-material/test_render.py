"""卡背素材的檢查（典藏材質規格 §5.6、§14.2 第 10 點）：

- 提交的素材：尺寸、大小上限（§5.4）、遮罩不透明（Flutter 解碼後是預乘 alpha，遮罩不能放 alpha）；
- 三階成品圖對 targets.json 的區域色差都在門檻內（§5.5）；
- 重跑逐位元相同（用 1/4 解析度跑兩次比對，省時間）。

python3 -m unittest discover -s tools/practice-card-material -p 'test_render.py'
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import concept_match as cm
import render_card_back as rc

ASSETS = rc.OUT
LIMITS = {  # 檔名 → (寬, 高, 上限 bytes)
    'practice_card_back_v4_n.webp': (1200, 1800, 600 * 1024),
    'practice_card_back_v4_r.webp': (1200, 1800, 600 * 1024),
    'practice_card_back_v4_sr.webp': (1200, 1800, 600 * 1024),
    'practice_card_back_v4_light.webp': (1200, 1800, 300 * 1024),
    'practice_card_back_v4_glowmask.webp': (600, 900, 80 * 1024),
    'practice_card_back_v4_glow.webp': (600, 900, 60 * 1024),
    'practice_card_noise.webp': (128, 128, 20 * 1024),
}


class AssetTest(unittest.TestCase):
    def test_尺寸與大小上限(self):
        total = 0
        for name, (w, h, limit) in LIMITS.items():
            path = ASSETS / name
            self.assertTrue(path.exists(), name)
            with Image.open(path) as im:
                self.assertEqual(im.size, (w, h), name)
            size = path.stat().st_size
            total += size
            self.assertLessEqual(size, limit, f'{name} {size / 1024:.0f} KiB')
        self.assertLessEqual(total, int(2.3 * 1024 * 1024))

    def test_成品圖與遮罩不透明(self):
        for name in LIMITS:
            if name.endswith('_glow.webp'):
                continue  # 泛光貼圖本來就是 RGBA
            with Image.open(ASSETS / name) as im:
                self.assertNotIn('A', im.getbands(), name)

    def test_三階對示意圖的區域色差(self):
        for tier in ('n', 'r', 'sr'):
            img = np.asarray(Image.open(ASSETS / f'practice_card_back_v4_{tier}.webp')
                             .convert('RGB'), np.float64) / 255.0
            bad = [r for r in cm.match(img, tier) if not r['ok']]
            self.assertEqual(bad, [], tier)


class DeterminismTest(unittest.TestCase):
    def test_重跑逐位元相同(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            rc.render(Path(a), scale=0.25)
            rc.render(Path(b), scale=0.25)
            for f in sorted(Path(a).iterdir()):
                self.assertEqual(f.read_bytes(), (Path(b) / f.name).read_bytes(), f.name)


if __name__ == '__main__':
    unittest.main()
