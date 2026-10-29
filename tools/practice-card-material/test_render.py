"""卡背素材的檢查（典藏材質規格 §5.6、§14.2 第 10 點）：

- 提交的素材：尺寸、大小上限（§5.4）、遮罩不透明（Flutter 解碼後是預乘 alpha，遮罩不能放 alpha）；
- 三階成品圖對 targets.json 的區域色差都在門檻內（§5.5）、紋理指標（拉絲連續性、徽記三面明暗、底面顆粒）；
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


    def test_紋理指標(self):
        """#114 第 3 輪：色差只管顏色接近，這裡守住質感的幾個量（回歸檢查，不能代替目視）：
        - 拉絲沒有整條長紋：上飾板、側飾條、卡緣暗帶的連續性 ≤ 0.6（示意圖 0.3–0.5，第 1 輪 0.97–0.99）；
        - 徽記三面有明暗：右面／上面 ≤ 0.93、左面／上面 0.92–1.02（示意圖 0.85–0.94、0.96–0.99）；
        - 底面不是平滑塑膠：細顆粒 ≥ 1.0（第 1 輪 0.2–0.3）。"""
        for tier in ('n', 'r', 'sr'):
            img = np.asarray(Image.open(ASSETS / f'practice_card_back_v4_{tier}.webp')
                             .convert('RGB'), np.float64) / 255.0
            got = cm.texture(img)
            for part in ('plate', 'bar', 'band'):
                self.assertLessEqual(got['brush'][part]['continuity'], 0.6, f'{tier} {part}')
            left, right = got['faces']['ratio']
            self.assertLessEqual(right, 0.93, tier)
            self.assertTrue(0.92 <= left <= 1.02, f'{tier} {left:.3f}')
            self.assertGreaterEqual(got['field']['fine'], 1.0, tier)


    def test_全息量測只算全息區的玫瑰到天空藍(self):
        """#114 第 3 輪審查：以前分母是整張圖、香檳金也算全息。現在分母是全息區，色相從天空藍往上繞到玫瑰。"""
        still = np.zeros((4, 10, 3))
        region = np.zeros((4, 10), bool)
        region[:2] = True  # 全息區 20 格
        for x, c in enumerate(['#F6B0AC', '#F99EE6', '#8B448F', '#B1DAFE']):  # §2.2 的四個全息色
            still[0, x] = cm.hex_rgb(c)
        still[1] = cm.hex_rgb('#FDE38C')  # 全息區裡的香檳金：不算
        still[2] = cm.hex_rgb('#F99EE6')  # 全息區外的洋紅：不算
        got = cm.holo_hues(still, region=region)
        self.assertAlmostEqual(got['share'], 4 / 20)
        self.assertFalse(got['ok'])  # 20% 超過示意圖的 2–8%
        self.assertEqual(sum(got['hues']), 14)  # 有顏色的：四個全息色＋十格香檳金


class DeterminismTest(unittest.TestCase):
    def test_重跑逐位元相同(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            rc.render(Path(a), scale=0.25)
            rc.render(Path(b), scale=0.25)
            for f in sorted(Path(a).iterdir()):
                self.assertEqual(f.read_bytes(), (Path(b) / f.name).read_bytes(), f.name)


if __name__ == '__main__':
    unittest.main()
