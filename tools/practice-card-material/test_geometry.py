"""構圖鎖定檢查（典藏材質規格 §5.1）：新的向量構圖反推回 904×1428，跟 V3 的遮罩比。

python3 -m unittest discover -s tools/practice-card-material -p 'test_geometry.py'
另存一張紅（舊）＋青（新）疊圖到 build/card_material/geometry_overlay.png，附在 PR。
"""

from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import geometry as g

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/images/practice'
OVERLAY = ROOT / 'build/card_material/geometry_overlay.png'
SRC_W, SRC_H = 904, 1428
FRAME_LAYERS = ['frame-line', 'plate', 'sidebar', 'plate-corner', 'mark']
CENTER_LAYERS = ['emblem', 'orbit', 'circuit', 'node-diamond', 'node-square']


def mask(name: str) -> np.ndarray:
    a = np.asarray(Image.open(ASSETS / f'practice_draw_card_back_v3_{name}.webp'))
    return a[..., 3].astype(np.float32) / 255.0


def to_source(geo: dict) -> dict:
    """畫布座標 → 904×1428（照每個元件的 anchor 反推）。"""
    cx, cy = geo['source']['center']
    s = geo['source']['scale']
    cw, ch = geo['canvas']

    def back(p, anchor):
        x, y = p
        # 外框細線在上下飾板底下那一段跟著飾板（中線對位）
        if anchor == 'edge' and abs(x - cw / 2) < 230:
            anchor = 'mid'
        if anchor == 'center':
            return [(x - cw / 2) / s + cx, (y - ch / 2) / s + cy]
        if anchor == 'mid':
            return [(x - cw / 2) / s + SRC_W / 2, y / s]
        return [x / s if x < cw / 2 else SRC_W - (cw - x) / s, y / s]

    out = []
    for el in geo['elements']:
        if el.get('anchor') == 'free':
            continue
        e = dict(el)
        a = el['anchor']
        if 'points' in e:
            e['points'] = [back(p, a) for p in el['points']]
        if 'center' in e:
            e['center'] = back(el['center'], a)
            e['r'] = el['r'] / s
        if 'width' in e:
            e['width'] = el['width'] / s
        out.append(e)
    return {'canvas': [SRC_W, SRC_H], 'elements': out}


def iou(a: np.ndarray, b: np.ndarray) -> float:
    return float((a & b).sum() / max((a | b).sum(), 1))


class GeometryLockTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.geo = g.load()
        cls.src = to_source(cls.geo)
        cls.raster = g.rasterize(cls.src)
        cls.emblem_mask = mask('emblem_mask')
        cls.frame_mask = mask('frame_mask')
        cls.lines_mask = mask('lines_mask')

    def test_徽記_IoU_至少_0_90(self):
        from scipy import ndimage  # 只有這個檢查要（描圖工具已裝）
        from skimage import morphology
        thick = morphology.opening(self.emblem_mask > 0.5, morphology.disk(4))
        lab, _ = ndimage.label(thick)
        objs = ndimage.find_objects(lab)
        ids = [i for i, s in enumerate(objs, 1)
               if (lab[s] == i).sum() > 3000 and s[1].start >= 285 and s[1].stop <= 625
               and s[0].start >= 520 and s[0].stop <= 925]
        ref = np.isin(lab, ids)
        got = self.raster['emblem'] > 0.5
        score = iou(got, ref)
        print(f'\n徽記 IoU {score:.4f}')
        self.assertGreaterEqual(score, 0.90)

    def test_星軌半徑_正負_1_5(self):
        rings = {e['id']: e for e in self.src['elements'] if e['kind'] == 'ring'}
        print(f"\n外環 {rings['ring-outer']['r']:.2f}、內環 {rings['ring-inner']['r']:.2f}")
        self.assertAlmostEqual(rings['ring-inner']['r'], 234, delta=1.5)
        self.assertAlmostEqual(rings['ring-outer']['r'], 361, delta=1.5)

    def test_節點中心(self):
        """原圖節點彼此不完全對稱（左右差 1–4 px）；對稱化以後跟原圖量到的中心差 ≤ 4.5 px。"""
        worst = 0.0
        for e in self.src['elements']:
            if not e['layer'].startswith('node-') or 'source_center' not in e:
                continue
            c = np.mean(e['points'], axis=0)
            worst = max(worst, float(np.hypot(*(c - np.array(e['source_center'])))))
        print(f'\n節點中心最大偏差 {worst:.2f} px')
        self.assertLessEqual(worst, 4.5)

    def _frame(self, layers):
        got = np.zeros((SRC_H, SRC_W), bool)
        for layer in layers:
            if layer in self.raster:
                got |= self.raster[layer] > 0.5
        return got

    def test_外框實心件_IoU(self):
        """飾板、側飾條、四角：卡緣 7 px 內不算（那一圈改由執行時的拋光外框畫）。"""
        from scipy import ndimage
        yy, xx = np.mgrid[0:SRC_H, 0:SRC_W]
        edge = np.minimum.reduce([xx, yy, SRC_W - 1 - xx, SRC_H - 1 - yy]) < 7
        ref = (self.frame_mask > 0.5) & ~edge
        # 原圖的細線不算進實心件：開運算把 ≤ 5 px 的線拿掉
        ref = ndimage.binary_opening(ref, iterations=3)
        got = self._frame(['plate', 'sidebar', 'plate-corner']) & ~edge
        score = iou(got, ref)
        print(f'\n外框實心件 IoU {score:.4f}')
        # 側飾條改成對齊卡片中線（原圖左邊高 8 px、右邊高 3 px，左右不一致）
        self.assertGreaterEqual(score, 0.85)

    def test_外框細線距離(self):
        """外框細線與刻記：新線離原圖的線中位數 ≤ 2 px，原圖的線 85% 以上在新線 3 px 內。"""
        from scipy import ndimage
        yy, xx = np.mgrid[0:SRC_H, 0:SRC_W]
        edge = np.minimum.reduce([xx, yy, SRC_W - 1 - xx, SRC_H - 1 - yy]) < 7
        ref_all = (self.frame_mask > 0.5) & ~edge
        ref = ref_all & ~ndimage.binary_opening(ref_all, iterations=3)
        got = self._frame(['frame-line', 'mark']) & ~edge
        d_to_ref = ndimage.distance_transform_edt(~ref)
        d_to_got = ndimage.distance_transform_edt(~got)
        mean_off = float(d_to_ref[got].mean())
        covered = float((d_to_got[ref] <= 3).mean())
        near = float((d_to_ref[got] <= 3).mean())
        print(f'\n外框細線：新線 {near:.1%} 在原圖的線 3 px 內（中位偏離 '
              f'{float(np.median(d_to_ref[got])):.2f} px）、原圖的線被蓋到 {covered:.1%}')
        # 新線多出來的部分是刻意的：側邊第二道線下半段（V2 原圖有、V3 遮罩漏掉）與側飾條底下那段
        # 外框線（畫在飾條下面，渲染時被蓋住）
        self.assertLessEqual(float(np.median(d_to_ref[got])), 2.0)
        self.assertGreaterEqual(covered, 0.85)

    def test_疊圖輸出(self):
        old = np.maximum.reduce([self.emblem_mask, self.frame_mask, self.lines_mask]) > 0.5
        new = np.zeros_like(old)
        for v in self.raster.values():
            new |= v > 0.5
        rgb = np.zeros(old.shape + (3,), np.uint8)
        rgb[old] = (255, 60, 60)
        rgb[new] = (60, 230, 255)
        rgb[old & new] = (235, 235, 235)
        OVERLAY.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(rgb).save(OVERLAY)
        self.assertTrue(OVERLAY.exists())


if __name__ == '__main__':
    unittest.main()
