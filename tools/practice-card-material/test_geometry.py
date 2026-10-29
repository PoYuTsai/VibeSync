"""構圖鎖定檢查（典藏材質規格 §5.1）：新的向量構圖反推回 904×1428，跟 V3 的遮罩比；另外檢查
線路沒有碎段、線路與星軌弧左右對稱（#114 Gate-2a 第 1 輪審查）。

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


def _dense(pts, step: float = 1.5) -> np.ndarray:
    p = np.asarray(pts, float)
    out = [p[0]]
    for a, b in zip(p[:-1], p[1:]):
        n = max(1, int(np.ceil(np.hypot(*(b - a)) / step)))
        out.extend(a + (b - a) * t for t in np.linspace(0, 1, n + 1)[1:])
    return np.array(out)


def _length(pts) -> float:
    return float(np.sum(np.hypot(*np.diff(np.asarray(pts, float), axis=0).T)))


def iou(a: np.ndarray, b: np.ndarray) -> float:
    return float((a & b).sum() / max((a | b).sum(), 1))


def _seg_gap(p, a, b) -> float:
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    t = np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-9), 0, 1)
    return float(np.hypot(*(p - (a + t * ab))))


def _polyline_gap(p, pts) -> float:
    return min(_seg_gap(p, a, b) for a, b in zip(pts[:-1], pts[1:]))


def _poly_gap(p, pts) -> float:
    """點到多邊形邊界的距離，點在裡面時是負的。"""
    q = np.asarray(pts, float)
    d = min(_seg_gap(p, q[i], q[(i + 1) % len(q)]) for i in range(len(q)))
    inside = False
    for (x0, y0), (x1, y1) in zip(q, np.roll(q, -1, axis=0)):
        if (y0 > p[1]) != (y1 > p[1]) and p[0] < x0 + (p[1] - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return -d if inside else d


def _ring_gap(p, r) -> float:
    c = np.asarray(r['center'], float)
    if r['kind'] == 'arc':
        ang = np.degrees(np.arctan2(p[1] - c[1], p[0] - c[0]))
        a0, a1 = r['a0'], r['a1']
        if not any(a0 <= ang + k <= a1 for k in (-360, 0, 360)):
            ends = [c + r['r'] * np.array([np.cos(np.radians(a)), np.sin(np.radians(a))]) for a in (a0, a1)]
            return min(float(np.hypot(*(p - e))) for e in ends)
    return abs(float(np.hypot(*(p - c))) - r['r'])


def _crossing(pa: np.ndarray, close: np.ndarray) -> bool:
    """貼近的點只是交叉口附近一小段（兩條線斜著穿過彼此）：連續貼近的長度 ≤ 10 px。"""
    run = best = 0
    for c in close:
        run = run + 1 if c else 0
        best = max(best, run)
    return best <= 10


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

    def test_線路沒有碎段(self):
        """#114 Gate-2a 第 1 輪審查：節點附近的斷線、碎線。線路不得短於 20 px（畫布，約 6 pt），
        也不能整條貼在星軌上（那是描圖時把環描成線路的殘段）。"""
        circuits = [e for e in self.geo['elements'] if e['layer'] == 'circuit']
        rings = [e for e in self.geo['elements'] if e['kind'] in ('ring', 'arc')]
        shortest = min(_length(e['points']) for e in circuits)
        print(f'\n線路 {len(circuits)} 條，最短 {shortest:.1f} px')
        self.assertGreaterEqual(shortest, 20.0)
        for e in circuits:
            p = _dense(e['points'])
            for r in rings:
                d = np.hypot(*(p - np.array(r['center'])).T)
                self.assertFalse(np.all(np.abs(d - r['r']) <= 4.0), f"{e['id']} 整條貼在 {r['id']} 上")

    def test_線路與星軌弧左右對稱(self):
        """示意圖左右鏡射後幾乎完全重合（R／SR 0.89–0.94）：線路鏡射後都要落在某條線路上（≤ 1 px），
        星軌弧鏡射後要對上另一段（≤ 0.5°）。上下不對稱（示意圖本身上下就不一樣），不檢查。"""
        w = self.geo['canvas'][0]
        circuits = [e for e in self.geo['elements'] if e['layer'] == 'circuit']
        allp = np.vstack([_dense(e['points']) for e in circuits])
        worst = 0.0
        for e in circuits:
            m = _dense(e['points']) * (-1, 1) + (w, 0)
            d = np.hypot(m[:, None, 0] - allp[None, :, 0], m[:, None, 1] - allp[None, :, 1]).min(axis=1)
            worst = max(worst, float(d.max()))
        print(f'\n線路鏡射最大偏差 {worst:.2f} px')
        self.assertLessEqual(worst, 1.0)
        arcs = [e for e in self.geo['elements'] if e['kind'] == 'arc']
        for a in arcs:
            m0, m1 = 180 - a['a1'], 180 - a['a0']
            ok = any(min(abs((m0 - b['a0']) % 360), 360 - abs((m0 - b['a0']) % 360)) <= 0.5 and
                     min(abs((m1 - b['a1']) % 360), 360 - abs((m1 - b['a1']) % 360)) <= 0.5 for b in arcs)
            self.assertTrue(ok, f"{a['id']} 鏡射後對不上")

    def test_徽記沒有描圖短邊(self):
        """#114 第 3 輪：描圖把尖角磨成一小段平頭或斜切（5.9–10.7 px），倒角後變成捏起來的小三角面。
        修完最短的是鉤端那段 15.5 px 的直邊（原圖就有的鉤），不是描圖留下的。"""
        shortest = min(float(np.hypot(*(np.roll(p, -1, axis=0) - p).T).min())
                       for p in (np.asarray(e['points'], float) for e in self.geo['elements']
                                 if e['layer'] == 'emblem'))
        print(f'\n徽記最短邊 {shortest:.1f} px')
        self.assertGreaterEqual(shortest, 15.0)

    def test_線路端點不是差一點點才碰到(self):
        """#114 第 3 輪：端點跟旁邊的線、環、節點之間看得到的縫，要嘛接上（≤ 0.5 px），要嘛是刻意留的
        間隙（≥ 4 px，約 1.2 pt）；差 1–3 px 的看起來是斷線或錯接。這是回歸檢查，不拿來自動刪線。"""
        els = self.geo['elements']
        circuits = [e for e in els if e['layer'] == 'circuit']
        polys = [e for e in els if e['kind'] == 'polygon' and e['layer'] in ('node-diamond', 'node-square',
                                                                               'emblem')]
        rings = [e for e in els if e['kind'] in ('ring', 'arc') and e['layer'] == 'orbit']
        lines = circuits + [e for e in els if e['layer'] == 'frame-line']
        worst = []
        for e in circuits:
            for j in (0, -1):
                p = np.asarray(e['points'][j], float)
                gaps = [_poly_gap(p, q['points']) - e['width'] / 2 for q in polys]
                gaps += [_ring_gap(p, r) - (r['width'] + e['width']) / 2 for r in rings]
                gaps += [_polyline_gap(p, o['points']) - (o['width'] + e['width']) / 2
                         for o in lines if o is not e]
                g = min(gaps)
                if 0.5 < g < 4.0:
                    worst.append((e['id'], [round(v, 1) for v in p], round(g, 2)))
        self.assertEqual(worst, [])

    def test_沒有雙線(self):
        """#114 第 3 輪：線路彼此、線路跟外框細線、星軌弧跟線路，不能平行貼在 3 px 內超過 10 px
        （鏡射重疊、描兩次、把蓋帽橫桿描成弧，都會變成一條比旁邊粗、兩端冒頭的線）。"""
        els = self.geo['elements']
        lines = [e for e in els if e['layer'] in ('circuit', 'frame-line')]
        arcs = [e for e in els if e['kind'] == 'arc' and e['layer'] == 'orbit']
        dense = [(e, _dense(e['points'], 1.0)) for e in lines]
        dense += [(a, np.array([[a['center'][0] + a['r'] * np.cos(np.radians(t)),
                                  a['center'][1] + a['r'] * np.sin(np.radians(t))]
                                 for t in np.arange(a['a0'], a['a1'], 0.25)])) for a in arcs]
        bad = []
        for i, (a, pa) in enumerate(dense):
            for b, pb in dense[i + 1:]:
                if a['layer'] == 'frame-line' and b['layer'] == 'frame-line':
                    continue
                d = np.hypot(pa[:, None, 0] - pb[None, :, 0], pa[:, None, 1] - pb[None, :, 1]).min(axis=1)
                close = d <= 3.0
                if close.sum() > 10 and not _crossing(pa, close):
                    bad.append((a['id'], b['id'], int(close.sum())))
        self.assertEqual(bad, [])

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


class TraceFragmentsTest(unittest.TestCase):
    """#114 第 3 輪審查：描圖碎段逐一列座標拿掉，不靠長度門檻；清單以外的短線、清單裡找不到的碎段都報錯。"""

    def test_只拿掉列出的碎段_其他短線報錯(self):
        import trace_geometry as tg  # 要 scikit-image、scipy（描圖工具已裝）
        long = {'points': [[0.0, 0.0], [0.0, 40.0]]}
        frag = {'points': [[10.0, 10.0], [10.0, 15.0]]}
        frags = [((10.0, 15.0), (10.0, 10.0))]  # 不分方向
        self.assertEqual(tg.drop_fragments([long, frag], frags), [long])
        stray = {'points': [[50.0, 50.0], [50.0, 55.0]]}
        with self.assertRaisesRegex(AssertionError, '沒有登記的短線路'):
            tg.drop_fragments([long, frag, stray], frags)
        with self.assertRaisesRegex(AssertionError, '找到 0 條'):
            tg.drop_fragments([long], frags)  # 描圖結果變了：清單裡的碎段不見

    def test_重描跟提交的構圖逐位元相同(self):
        """清單每一筆都要命中現行描圖（不然描圖就報錯）、都短於門檻；拿掉後跟提交的 JSON 一樣。"""
        import json
        import trace_geometry as tg
        for a, b in tg.TRACE_FRAGMENTS:
            self.assertLess(float(np.hypot(*np.subtract(b, a))), tg.MIN_CIRCUIT_LEN, (a, b))
        got = json.dumps(tg.trace(None), ensure_ascii=False, indent=1)
        self.assertEqual(got, tg.OUT.read_text())


if __name__ == '__main__':
    unittest.main()
