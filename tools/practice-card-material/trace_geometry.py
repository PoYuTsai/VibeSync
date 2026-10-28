"""卡背構圖的一次性描圖（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §5.1）。

從 V3 卡背的三張遮罩（`assets/images/practice/practice_draw_card_back_v3_*_mask.webp`，904×1428，
由 V2 原圖萃取）描出向量構圖，寫進 card_back_geometry.json；之後的渲染只讀 JSON，不再碰點陣圖。
這支是開發工具：用 scikit-image／scipy 描邊，跑一次、人工檢查疊圖後提交 JSON，平常不用重跑
（render_card_back.py 只需要 numpy＋Pillow）。

  pip install scikit-image scipy   # 只有描圖要
  python3 tools/practice-card-material/trace_geometry.py [--overlay build/card_material/trace_overlay.png]

做法：
- 粗細分離：徽記遮罩做半徑 4 的開運算，留下的是粗件（徽記方塊、節點），其餘是細線。
- 徽記：描輪廓 → Douglas–Peucker → 邊的方向吸附到 90°／30°／150°（以及少數 0°），位置用原始
  輪廓點擬合（夾角處的短斜角拿掉、一串沒吸附的邊換成一條封口線、平行台階補連接線）→ 筆畫寬
  統一：同一筆的兩條對邊各移一半，距離剛好是量到的筆畫寬，中心線不動 → 頂點取相鄰兩條線的
  交點。不吸附到等角格：原圖的邊本來就不在格上，吸附上去 IoU 會掉到 0.89–0.90。
- 圓：外環、內環用穩健最小平方擬合圓心半徑；兩環之間沿圓走的弧（半徑約 209）依原圖的覆蓋率
  切成幾段圓弧。
- 節點：粗件裡的小方塊／菱形擬合中心與大小，依「種類＋相對位置」分組對稱化（軸上的對齊到軸、
  外環上的落在環上），存成正方形或正菱形。原圖跟旁邊小點黏在一起或缺了的依對稱補上
  （`synthesized`），其餘記下原圖中心（`source_center`）給構圖鎖定檢查用。
- 細線：骨架化 → 拆成路徑 → 去掉落在環上的點 → Douglas–Peucker 後方向吸附到 15° 的倍數 →
  端點接到附近的節點或環、彼此靠近的端點併成交叉口 → 貼著中軸的段鎖到中軸 → 中軸兩側的線路
  下半部改用上半部的鏡像（V3 遮罩下半部的斜線很淡、描出來是斷的）；線寬分 2.6／4.0 兩級。
- 外框：照原圖量到的尺寸參數化重建（外框細線、側邊第二道細線、上下飾板、側飾條、四角飾板、
  「//」刻記、卡緣暗帶），上下左右對稱、斜邊一律 45°；不描輪廓（V3 的外框遮罩含卡片外緣，
  執行時由拋光外框取代）。
- 收尾（#114 Gate-2a 第 1 輪審查：節點附近斷線、碎線）：左右節點群照示意圖重畫（菱形框、軸線、
  往弧環的一對斜線），清掉描成線路的環與短於 20 px（約 6 pt）的碎段，端點貼到節點的角，線路
  只留左半邊再鏡射到右邊（示意圖左右對稱、上下不對稱），星軌弧左右對齊。
- 底面稜面與內外環之間的刻度盤是照示意圖新加的裝飾，不是描出來的。
座標全部換到 1200×1800 畫布（§5.1 的對位：中心元件以外環圓心為準等比放大 s＝1800／1428，
圓心對到畫布正中；外框元件各自貼齊最近的卡緣，飾板與刻記沿卡緣置中）。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure, morphology

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/images/practice'
OUT = Path(__file__).resolve().parent / 'card_back_geometry.json'

SRC_W, SRC_H = 904, 1428
CANVAS_W, CANVAS_H = 1200, 1800
SCALE = CANVAS_H / SRC_H  # 1.2605：中心元件等比放大

C30 = np.cos(np.radians(30))


def load_mask(name: str) -> np.ndarray:
    a = np.asarray(Image.open(ASSETS / f'practice_draw_card_back_v3_{name}.webp'))
    return a[..., 3].astype(np.float32) / 255.0


# ── 座標換算 ──────────────────────────────────────────────────────────────

class Mapping:
    """904×1428 → 1200×1800。center：中心元件的基準點（外環圓心）。"""

    def __init__(self, center: tuple[float, float]):
        self.cx, self.cy = center

    def center_pt(self, p) -> list[float]:
        x, y = p
        return [round(CANVAS_W / 2 + (x - self.cx) * SCALE, 2),
                round(CANVAS_H / 2 + (y - self.cy) * SCALE, 2)]

    def edge_pt(self, p) -> list[float]:
        """外框元件：x 貼齊最近的左右緣、y 本來就是等比（1428×s＝1800）。"""
        x, y = p
        nx = x * SCALE if x < SRC_W / 2 else CANVAS_W - (SRC_W - x) * SCALE
        return [round(nx, 2), round(y * SCALE, 2)]


# ── 圓 ───────────────────────────────────────────────────────────────────

def robust_circle(mask: np.ndarray, cx: float, cy: float, r: float,
                  band: float = 12, iters: int = 8) -> tuple[float, float, float]:
    yy, xx = np.mgrid[0:mask.shape[0], 0:mask.shape[1]]
    for _ in range(iters):
        sel = (mask > 0.5) & (np.abs(np.hypot(xx - cx, yy - cy) - r) < band)
        x = xx[sel].astype(np.float64)
        y = yy[sel].astype(np.float64)
        c = np.linalg.lstsq(np.c_[2 * x, 2 * y, np.ones_like(x)], x * x + y * y, rcond=None)[0]
        cx, cy = c[0], c[1]
        r = float(np.sqrt(c[2] + cx * cx + cy * cy))
        band = max(3.0, band * 0.7)
    return float(cx), float(cy), r


def stroke_width(mask: np.ndarray, region: np.ndarray) -> float:
    """區域內線條的寬度：骨架上距離轉換的中位數×2。"""
    m = (mask > 0.5) & region
    dt = ndimage.distance_transform_edt(m)
    sk = morphology.skeletonize(m)
    return float(2 * np.median(dt[sk])) if sk.any() else 0.0


# ── 多邊形描邊與吸附 ─────────────────────────────────────────────────────

def contours(mask: np.ndarray) -> list[np.ndarray]:
    """回傳輪廓（x, y），面積大的在前；第一條是外框，其餘依序當洞。"""
    cs = measure.find_contours(np.pad(mask.astype(float), 1), 0.5)
    polys = [c[:, ::-1] - 1 for c in cs]
    polys.sort(key=lambda p: -abs(_area(p)))
    return polys


def _area(xy: np.ndarray) -> float:
    return 0.5 * float(np.sum(xy[:-1, 0] * xy[1:, 1] - xy[1:, 0] * xy[:-1, 1]))


class Line:
    """一條邊：方向 u、法線 n、位置 off（n·p＝off）、是否吸附、長度、原始段的兩端點、原始點。"""

    def __init__(self, u, off, snapped, seg):
        self.u = np.asarray(u, dtype=float)
        self.n = np.array([-self.u[1], self.u[0]])
        self.off = float(off)
        self.snapped = snapped
        self.seg = seg
        self.length = float(np.hypot(*(seg[-1] - seg[0])))

    def angle(self) -> float:
        return float(np.degrees(np.arctan2(self.u[1], self.u[0])) % 180)


def _nearest_allowed(ang: float, allowed: list[float]) -> tuple[float, float]:
    best = min(allowed, key=lambda t: min(abs(ang - t), 180 - abs(ang - t)))
    return best, min(abs(ang - best), 180 - abs(ang - best))


def _fit_line(points: np.ndarray, deg: float, chord: np.ndarray) -> Line:
    th = np.radians(deg)
    u = np.array([np.cos(th), np.sin(th)])
    if np.dot(u, chord) < 0:
        u = -u
    n = np.array([-u[1], u[0]])
    m = len(points)
    core = points[m // 5: max(m // 5 + 1, m - m // 5)] if m >= 5 else points
    return Line(u, float(np.mean(core @ n)), True, points)


def snap_lines(xy: np.ndarray, allowed: list[float], tol_px: float = 1.6,
               angle_tol: float = 12.0, cap_tol: float = 30.0, min_len: float = 3.0,
               short_corner: float = 14.0) -> list[Line]:
    """Douglas–Peucker 後把邊的方向吸附到 allowed（0..180 度），位置用原始輪廓點擬合：
    1. 長度夠、方向差 ≤ angle_tol 的邊直接吸附；
    2. 相鄰同向、位置差 < 3 px 的併成一條（原圖的直線有抖動，同一條邊常被拆成兩段）；
    3. 兩條吸附邊之間的一串沒吸附的邊：夾角處的短斜角（≤ short_corner）直接拿掉讓兩邊相交，
       其他的整串換成一條「封口」線（方向取最接近整串弦向的允許方向，差 ≤ cap_tol）；
    4. 相鄰兩條平行但位置不同（台階）時補一條連接線。"""
    simp = measure.approximate_polygon(xy, tolerance=tol_px)
    idx, j = [], 0
    for v in simp[:-1]:
        while not np.allclose(xy[j], v):
            j += 1
        idx.append(j)
    raw: list[Line] = []
    for k in range(len(idx)):
        a, b = idx[k], idx[(k + 1) % len(idx)]
        seg = xy[a:b + 1] if b > a else np.vstack([xy[a:], xy[:b + 1]])
        d = seg[-1] - seg[0]
        length = float(np.hypot(*d))
        best, diff = _nearest_allowed(float(np.degrees(np.arctan2(d[1], d[0])) % 180), allowed)
        if diff <= angle_tol and length >= min_len:
            raw.append(_fit_line(seg, best, d))
        else:
            u = d / max(length, 1e-9)
            raw.append(Line(u, float(np.mean(seg @ np.array([-u[1], u[0]]))), False, seg))
    lines = _merge_lines(raw)
    lines = _collapse_runs(lines, allowed, cap_tol, short_corner)
    lines = _merge_lines(lines)
    return _bridge_steps(lines, allowed)


def _parallel(a: Line, b: Line) -> bool:
    return abs(abs(float(np.dot(a.u, b.u))) - 1) < 1e-6


def _merge_lines(lines: list[Line], tol: float = 3.0) -> list[Line]:
    def same(a, b):
        return a.snapped and b.snapped and _parallel(a, b) and \
            abs(a.off - b.off * float(np.dot(a.n, b.n))) < tol

    def join(a, b):
        pts = np.vstack([a.seg, b.seg])
        out = Line(a.u, 0, True, pts)
        out.off = (a.off * a.length + b.off * float(np.dot(a.n, b.n)) * b.length) / \
            max(a.length + b.length, 1e-9)
        out.length = a.length + b.length
        return out

    out: list[Line] = []
    for ln in lines:
        if out and same(out[-1], ln):
            out[-1] = join(out[-1], ln)
        else:
            out.append(ln)
    while len(out) > 2 and same(out[-1], out[0]):
        out[0] = join(out[-1], out[0])
        out.pop()
    return out


def _collapse_runs(lines: list[Line], allowed, cap_tol, short_corner) -> list[Line]:
    n = len(lines)
    if n < 3 or all(not ln.snapped for ln in lines):
        return lines
    # 從一條吸附邊開始轉一圈，把沒吸附的連續一串收起來
    start = next(k for k, ln in enumerate(lines) if ln.snapped)
    order = lines[start:] + lines[:start]
    out: list[Line] = []
    run: list[Line] = []
    for ln in order + [order[0]]:
        if not ln.snapped:
            run.append(ln)
            continue
        if run:
            prev = out[-1]
            total = sum(r.length for r in run)
            pts = np.vstack([r.seg for r in run])
            chord = pts[-1] - pts[0]
            if total <= short_corner and not _parallel(prev, ln):
                pass  # 夾角處的短斜角：拿掉，兩條吸附邊直接相交
            else:
                best, diff = _nearest_allowed(
                    float(np.degrees(np.arctan2(chord[1], chord[0])) % 180), allowed)
                if diff <= cap_tol and np.hypot(*chord) >= 2:
                    out.append(_fit_line(pts, best, chord))
                else:
                    out.extend(run)
            run = []
        if ln is not order[0] or not out:
            out.append(ln)
    return out


def _bridge_steps(lines: list[Line], allowed) -> list[Line]:
    out: list[Line] = []
    n = len(lines)
    for k in range(n):
        a, b = lines[k], lines[(k + 1) % n]
        out.append(a)
        if _parallel(a, b) and abs(a.off - b.off * float(np.dot(a.n, b.n))) >= 1e-6:
            p0, p1 = a.seg[-1], b.seg[0]
            chord = p1 - p0 if np.hypot(*(p1 - p0)) > 1e-6 else b.n
            others = [t for t in allowed
                      if abs(abs(np.cos(np.radians(t - a.angle()))) - 1) > 1e-6]
            best, _ = _nearest_allowed(float(np.degrees(np.arctan2(chord[1], chord[0])) % 180),
                                       others or allowed)
            out.append(_fit_line(np.vstack([p0, (p0 + p1) / 2, p1]), best, chord))
    return out


def vertices(lines: list[Line]) -> np.ndarray:
    """頂點 k＝第 k−1 條與第 k 條線的交點；第 k 條線從頂點 k 走到頂點 k+1。"""
    pts = []
    for k in range(len(lines)):
        a, b = lines[k - 1], lines[k]
        pts.append(np.linalg.solve(np.array([a.n, b.n]), np.array([a.off, b.off])))
    return np.array(pts)


def drop_reversed(lines: list[Line]) -> list[Line]:
    """封口或連接線落在轉角外側時，那條邊算出來會反向（多邊形自己打結）：拿掉它再算。"""
    lines = list(lines)
    while len(lines) > 3:
        pts = vertices(lines)
        bad = [k for k, ln in enumerate(lines)
               if float(np.dot(pts[(k + 1) % len(pts)] - pts[k], ln.u)) < 0]
        if not bad:
            break
        lines.pop(bad[0])
    return lines


def regularize_widths(contour_lines: list[list[Line]], mask: np.ndarray, width: float,
                      lo: float = 14.0, hi: float = 36.0, min_overlap: float = 10.0) -> None:
    """筆畫寬統一：同一筆的兩條對邊（平行、彼此在對方的內側、距離 lo..hi、沿邊方向重疊夠長）
    各往外／往內移一半，讓距離剛好是 width；中心線不動。就地修改各條線的 off。"""
    edges = []  # (line, p0, p1, inside_normal)
    m = mask.astype(np.float32)
    for lines in contour_lines:
        pts = vertices(lines)
        for k, ln in enumerate(lines):
            if not ln.snapped:
                continue
            p0, p1 = pts[k], pts[(k + 1) % len(pts)]
            probe = (p0 + p1) / 2 + 3 * ln.n
            inside = 1.0 if ndimage.map_coordinates(m, [[probe[1]], [probe[0]]], order=1)[0] > 0.5 \
                else -1.0
            edges.append((ln, p0, p1, inside * ln.n))
    moves: dict[int, list[tuple[float, float]]] = {}
    for a, (la, a0, a1, na) in enumerate(edges):
        for b, (lb, b0, b1, nb) in enumerate(edges):
            if a == b or not _parallel(la, lb):
                continue
            d = float(np.dot((b0 + b1) / 2 - (a0 + a1) / 2, na))
            if not lo <= d <= hi or float(np.dot(na, nb)) > -0.99:
                continue
            ta = sorted([float(np.dot(a0, la.u)), float(np.dot(a1, la.u))])
            tb = sorted([float(np.dot(b0, la.u)), float(np.dot(b1, la.u))])
            overlap = min(ta[1], tb[1]) - max(ta[0], tb[0])
            if overlap >= min_overlap:
                # a 往自己的外側移 (width − d)／2：太細往外推、太粗往內收
                moves.setdefault(a, []).append(((width - d) / 2, overlap))
    for a, vals in moves.items():
        ln, _, _, inside = edges[a]
        move = sum(v * w for v, w in vals) / sum(w for _, w in vals)
        ln.off -= move * float(np.dot(inside, ln.n))


# ── 細線：骨架 → 路徑 → 圓弧／折線 ────────────────────────────────────────

_NB8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def skeleton_paths(sk: np.ndarray) -> list[np.ndarray]:
    """骨架拆成路徑：度數不是 2 的像素當節點，沿度數 2 的像素走到下一個節點。回傳 (x, y) 陣列。"""
    h, w = sk.shape
    on = set(map(tuple, np.argwhere(sk)))

    def nbrs(p):
        return [(p[0] + dy, p[1] + dx) for dy, dx in _NB8 if (p[0] + dy, p[1] + dx) in on]

    deg = {p: len(nbrs(p)) for p in on}
    nodes = {p for p, d in deg.items() if d != 2}
    seen_edges = set()
    paths = []
    for start in nodes:
        for nb in nbrs(start):
            if (start, nb) in seen_edges:
                continue
            path = [start, nb]
            seen_edges.add((start, nb))
            prev, cur = start, nb
            while cur not in nodes:
                nxt = [q for q in nbrs(cur) if q != prev and q not in path[-3:]]
                if not nxt:
                    break
                prev, cur = cur, nxt[0]
                path.append(cur)
            seen_edges.add((cur, prev))
            paths.append(np.array([(x, y) for y, x in path], dtype=float))
    # 沒有節點的封閉圈（整圈的環）
    visited = {tuple(map(int, (pt[1], pt[0]))) for pth in paths for pt in pth}
    for p0 in on - visited - nodes:
        if p0 in visited:
            continue
        loop = [p0]
        visited.add(p0)
        prev, cur = None, p0
        while True:
            nxt = [q for q in nbrs(cur) if q != prev and q not in visited]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            visited.add(cur)
            loop.append(cur)
        if len(loop) > 20:
            paths.append(np.array([(x, y) for y, x in loop], dtype=float))
    return paths


def _snap_polyline(pts: np.ndarray, step_deg: float = 15.0, tol_px: float = 1.5,
                   angle_tol: float = 9.0) -> np.ndarray:
    """折線：Douglas–Peucker 後每段方向吸附到 step_deg 的倍數，用原始點擬合位置，轉角取交點。
    交叉口附近骨架會歪，兩端短於 4 px 的小段先拿掉。"""
    simp = measure.approximate_polygon(pts, tolerance=tol_px)
    while len(simp) > 2 and np.hypot(*(simp[1] - simp[0])) < 4:
        simp = simp[1:]
    while len(simp) > 2 and np.hypot(*(simp[-1] - simp[-2])) < 4:
        simp = simp[:-1]
    if len(simp) < 2:
        return simp
    idx, j = [], 0
    for v in simp:
        while not np.allclose(pts[j], v):
            j += 1
        idx.append(j)
    segs = []
    for a, b in zip(idx[:-1], idx[1:]):
        seg = pts[a:b + 1]
        d = seg[-1] - seg[0]
        ang = float(np.degrees(np.arctan2(d[1], d[0])) % 180)
        best = round(ang / step_deg) * step_deg
        if abs(ang - best) <= angle_tol:
            segs.append(_fit_line(seg, best % 180, d))
        else:
            u = d / max(float(np.hypot(*d)), 1e-9)
            segs.append(Line(u, float(np.mean(seg @ np.array([-u[1], u[0]]))), False, seg))
    out = [segs[0].seg[0] - segs[0].n * (float(segs[0].seg[0] @ segs[0].n) - segs[0].off)]
    for a, b in zip(segs[:-1], segs[1:]):
        if _parallel(a, b):
            out.append((a.seg[-1] + b.seg[0]) / 2)
        else:
            out.append(np.linalg.solve(np.array([a.n, b.n]), np.array([a.off, b.off])))
    last = segs[-1]
    out.append(last.seg[-1] - last.n * (float(last.seg[-1] @ last.n) - last.off))
    return np.array(out)


def classify_paths(paths: list[np.ndarray], center: np.ndarray, width_of,
                   min_len: float = 6.0) -> tuple[list[dict], list[dict]]:
    """回傳 (arcs, polylines)。arc：{r, a0, a1, width}（角度度數、順時針、0＝右）；
    polyline：{points, width}。離圓心距離幾乎不變的路徑當圓弧。"""
    arcs, polys = [], []
    for pth in paths:
        if len(pth) < 2 or float(np.sum(np.hypot(*np.diff(pth, axis=0).T))) < min_len:
            continue
        r = np.hypot(pth[:, 0] - center[0], pth[:, 1] - center[1])
        ang = np.degrees(np.arctan2(pth[:, 1] - center[1], pth[:, 0] - center[0]))
        span = float(np.degrees(np.ptp(np.unwrap(np.radians(ang)))))
        if r.std() < 1.0 and span > 6 and r.mean() > 100:
            u = np.unwrap(np.radians(ang))
            a0, a1 = float(np.degrees(u.min())), float(np.degrees(u.max()))
            arcs.append({'r': float(r.mean()), 'a0': a0, 'a1': a1, 'width': width_of(pth),
                         'n': len(pth)})
        else:
            polys.append({'points': _snap_polyline(pth), 'width': width_of(pth)})
    return arcs, polys


def merge_arcs(arcs: list[dict], r_tol: float = 2.5, gap_deg: float = 9.0) -> list[dict]:
    """同半徑的弧依角度排序、縫隙小於 gap_deg 的接起來；蓋滿 > 330° 的變成整圈。"""
    groups: list[list[dict]] = []
    for arc in sorted(arcs, key=lambda a: a['r']):
        if groups and abs(np.average([a['r'] for a in groups[-1]],
                                     weights=[a['n'] for a in groups[-1]]) - arc['r']) < r_tol:
            groups[-1].append(arc)
        else:
            groups.append([arc])
    out = []
    for g in groups:
        r = float(np.average([a['r'] for a in g], weights=[a['n'] for a in g]))
        width = float(np.average([a['width'] for a in g], weights=[a['n'] for a in g]))
        spans = sorted(((a['a0'] % 360, (a['a0'] % 360) + (a['a1'] - a['a0'])) for a in g))
        merged: list[list[float]] = []
        for a0, a1 in spans:
            if merged and a0 - merged[-1][1] <= gap_deg:
                merged[-1][1] = max(merged[-1][1], a1)
            else:
                merged.append([a0, a1])
        if len(merged) > 1 and merged[0][0] + 360 - merged[-1][1] <= gap_deg:
            merged[0][0] = merged[-1][0] - 360
            merged.pop()
        cover = sum(a1 - a0 for a0, a1 in merged)
        if cover >= 330:
            out.append({'kind': 'ring', 'r': r, 'width': width})
        else:
            for a0, a1 in merged:
                out.append({'kind': 'arc', 'r': r, 'a0': a0, 'a1': a1, 'width': width})
    return out


def ring_coverage_arcs(art: np.ndarray, center: np.ndarray, r: float, band: float = 2.5,
                       step: float = 0.5, gap: float = 4.0, min_run: float = 6.0) -> list[tuple]:
    """沿半徑 r 每 step 度看遮罩有沒有線（±band px），連續有線的角度區間（縫隙 ≤ gap 併起來）。"""
    angs = np.arange(0, 360, step)
    rs = np.arange(r - band, r + band + 0.01, 0.5)
    th = np.radians(angs)[:, None]
    xs = np.clip(np.round(center[0] + rs[None, :] * np.cos(th)).astype(int), 0, art.shape[1] - 1)
    ys = np.clip(np.round(center[1] + rs[None, :] * np.sin(th)).astype(int), 0, art.shape[0] - 1)
    on = art[ys, xs].max(axis=1) > 0.5
    runs, start = [], None
    for k, v in enumerate(np.r_[on, False]):
        if v and start is None:
            start = k
        if not v and start is not None:
            runs.append([angs[start], angs[k - 1] + step])
            start = None
    merged = []
    for a0, a1 in runs:
        if merged and a0 - merged[-1][1] <= gap:
            merged[-1][1] = a1
        else:
            merged.append([a0, a1])
    if len(merged) > 1 and merged[0][0] + 360 - merged[-1][1] <= gap:
        merged[0][0] = merged[-1][0] - 360
        merged.pop()
    return [(a0, a1) for a0, a1 in merged if a1 - a0 >= min_run]


def strip_ring_points(paths: list[np.ndarray], center: np.ndarray, radii: list[float],
                      tol: float = 2.0, min_len: float = 6.0) -> list[np.ndarray]:
    """沿著環走的那幾段路徑交給環畫：把落在任一半徑 ±tol 的點拿掉，剩下的拆成幾段。"""
    out = []
    for pth in paths:
        r = np.hypot(pth[:, 0] - center[0], pth[:, 1] - center[1])
        keep = np.ones(len(pth), bool)
        for rad in radii:
            keep &= np.abs(r - rad) > tol
        start = None
        for k, v in enumerate(np.r_[keep, False]):
            if v and start is None:
                start = k
            if not v and start is not None:
                piece = pth[start:k]
                if len(piece) >= 2 and float(np.sum(np.hypot(*np.diff(piece, axis=0).T))) >= min_len:
                    out.append(piece)
                start = None
    return out


def join_endpoints(polys: list[np.ndarray], center: np.ndarray, radii: list[float],
                   node_centers: list[np.ndarray], node_reach: list[float],
                   cluster_tol: float = 4.0, ring_tol: float = 5.0) -> list[np.ndarray]:
    """端點收尾：伸到附近節點的中心（節點畫在上面蓋住）；靠近環的投影到環上；彼此靠近的端點
    併成同一點（交叉口）。"""
    polys = [p.copy() for p in polys]
    ends = [(i, j) for i in range(len(polys)) for j in (0, -1)]
    for i, j in ends:
        p = polys[i][j]
        for c, reach in zip(node_centers, node_reach):
            if np.hypot(*(p - c)) <= reach:
                polys[i][j] = c
                break
        else:
            r = float(np.hypot(*(p - center)))
            for rad in radii:
                if abs(r - rad) <= ring_tol:
                    polys[i][j] = center + (p - center) * rad / max(r, 1e-9)
                    break
    # 交叉口：彼此在 cluster_tol 內的端點取平均
    pts = np.array([polys[i][j] for i, j in ends])
    used = np.zeros(len(ends), bool)
    for a in range(len(ends)):
        if used[a]:
            continue
        group = [b for b in range(len(ends)) if not used[b] and np.hypot(*(pts[a] - pts[b])) <= cluster_tol]
        if len(group) > 1:
            mean = pts[group].mean(axis=0)
            for b in group:
                i, j = ends[b]
                polys[i][j] = mean
                used[b] = True
    return polys


def lock_axes(pts: np.ndarray, center: np.ndarray, tol: float = 4.0) -> np.ndarray:
    """直的段若貼著垂直中軸（|x − cx| ≤ tol）就鎖到 x＝cx；橫的段貼著水平中軸就鎖到 y＝cy。"""
    pts = pts.copy()
    for a in range(len(pts) - 1):
        d = pts[a + 1] - pts[a]
        if abs(d[0]) < 1e-6 and abs(pts[a][0] - center[0]) <= tol:
            pts[a][0] = pts[a + 1][0] = center[0]
        if abs(d[1]) < 1e-6 and abs(pts[a][1] - center[1]) <= tol:
            pts[a][1] = pts[a + 1][1] = center[1]
    return pts


def mirror_axis_circuits(polys: list[np.ndarray], widths: list[float], center: np.ndarray,
                         inner_r: float, half_width: float = 150.0,
                         margin: float = 12.0) -> tuple[list[np.ndarray], list[float]]:
    """中軸兩側的線路（|dx| < half_width、內環以外）上下本來對稱，但 V3 遮罩下半部的斜線很淡、
    描出來是斷的：下半部改用上半部的鏡像。中軸外側的刻線（上下本來就不一樣）照描。"""
    rel = [q - center for q in polys]

    def region(q, sign):
        return bool(np.all(np.abs(q[:, 0]) < half_width) and
                    np.all(sign * q[:, 1] > inner_r - margin))

    keep = [(q, w) for q, w in zip(rel, widths) if not region(q, 1)]
    top = [(q, w) for q, w in zip(rel, widths) if region(q, -1)]
    mirrored = [(q * np.array([1, -1]), w) for q, w in top]
    out = keep + mirrored
    return [q + center for q, _ in out], [w for _, w in out]


# ── 收尾：節點群、殘段、左右對稱（#114 Gate-2a 第 1 輪審查：節點附近斷線、碎線）─────────

def _dense(pts, step: float = 1.5) -> np.ndarray:
    p = np.asarray(pts, float)
    out = [p[0]]
    for a, b in zip(p[:-1], p[1:]):
        n = max(1, int(np.ceil(np.hypot(*(b - a)) / step)))
        out.extend(a + (b - a) * t for t in np.linspace(0, 1, n + 1)[1:])
    return np.array(out)


def _poly_len(pts) -> float:
    p = np.asarray(pts, float)
    return float(np.sum(np.hypot(*np.diff(p, axis=0).T)))


def _node_polys(elements) -> list[np.ndarray]:
    return [np.asarray(e['points'], float) for e in elements if e['layer'].startswith('node-')]


def _inside(pt, poly) -> bool:
    x, y = pt
    inside = False
    for (x0, y0), (x1, y1) in zip(poly, np.roll(poly, -1, axis=0)):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def side_cluster(nodes: dict[str, np.ndarray], outer_r: float, arc_r: float) -> list[dict]:
    """左側節點群（照示意圖一重畫，V3 遮罩這一塊被光暈蓋住、左右也不對稱）：
    - 外側實心菱形外圍一個完整的菱形框：上下頂點在外環上（中線 ±50），右頂點是中間的小節點，
      左頂點離上下頂點的水平距離是右半邊的 0.68 倍（示意圖量的比例）；
    - 一條貫穿三個節點的軸線；
    - 內側菱形往弧環拉一對斜線（端點在弧上、中線 ±71，同 V3 上半那一條）。
    座標是 1200×1800 畫布；右側由左右鏡射產生。"""
    cy = CANVAS_H / 2
    cx = CANVAS_W / 2
    xo, xs, xi = (nodes[k][0] for k in ('outer', 'small', 'inner'))
    dy = 50.0
    xt = cx - np.sqrt(outer_r ** 2 - dy ** 2)
    xl = xt - 0.68 * (xs - xt)
    frame = [(xl, cy), (xt, cy - dy), (xs, cy), (xt, cy + dy), (xl, cy)]
    da = 71.0
    xa = cx - np.sqrt(arc_r ** 2 - da ** 2)
    pts = [
        ('node-frame', frame, 3.28),
        ('node-axis', [(xo, cy), (xi, cy)], 5.04),
        ('node-spoke-up', [(xi, cy), (xa, cy - da)], 3.28),
        ('node-spoke-down', [(xi, cy), (xa, cy + da)], 3.28),
    ]
    return [{'id': name, 'kind': 'polyline', 'layer': 'circuit', 'points': [list(map(float, q)) for q in p],
             'width': w} for name, p, w in pts]


def _snap_to_nodes(pts: np.ndarray, node_polys, tol: float = 8.0) -> np.ndarray:
    """端點在節點外、離節點的角 tol 以內：貼到那個角（連接線剛好碰到節點，不留縫）。"""
    pts = pts.copy()
    for j in (0, -1):
        p = pts[j]
        for poly in node_polys:
            if _inside(p, poly):
                break
            d = np.hypot(*(poly - p).T)
            k = int(np.argmin(d))
            if d[k] <= tol:
                pts[j] = poly[k]
                break
    return pts


def _symmetric_arcs(arcs: list[dict]) -> None:
    """星軌弧左右對齊：左右鏡射是角度 θ → 180° − θ；鏡射後最接近的那一段（跨中軸的是自己）
    兩者取平均。就地修改，起點落在 −180°..180°。"""
    def norm(a0, a1):
        k = np.floor((a0 + 180) / 360)
        return round(float(a0 - 360 * k), 2), round(float(a1 - 360 * k), 2)

    done: set[int] = set()
    for i, a in enumerate(arcs):
        if i in done:
            continue
        m0, m1 = 180 - a['a1'], 180 - a['a0']
        mmid = (m0 + m1) / 2

        def gap(b):
            d = ((b['a0'] + b['a1']) / 2 - mmid) % 360
            return min(d, 360 - d)

        j = min(range(len(arcs)), key=lambda k: gap(arcs[k]))
        b = arcs[j]
        shift = round(((b['a0'] + b['a1']) / 2 - mmid) / 360) * 360
        n0, n1 = (b['a0'] + m0 + shift) / 2, (b['a1'] + m1 + shift) / 2
        b['a0'], b['a1'] = norm(n0, n1)
        if j != i:
            a['a0'], a['a1'] = norm(180 - n1, 180 - n0)
        done.update({i, j})


def tidy(elements: list[dict], outer_r: float, inner_r: float, arc_r: float) -> list[dict]:
    """描完以後的收尾（畫布座標）：
    1. 左右節點群換成 [side_cluster]；
    2. 清掉描成線路的環（每一點都在環或弧上 ±4 px）與短於 20 px（約 6 pt）的碎段；
    3. 連接線端點貼到節點的角；
    4. 線路只留左半邊（含跨中軸的那半段），右半邊鏡射；星軌弧左右對齊。"""
    cx, cy = CANVAS_W / 2, CANVAS_H / 2
    radii = [outer_r, inner_r, arc_r]
    circuits = [e for e in elements if e['layer'] == 'circuit']
    others = [e for e in elements if e['layer'] != 'circuit']
    nodes = [e for e in others if e['layer'] == 'node-diamond']

    def node_at(x):
        return min((np.mean(np.asarray(e['points'], float), axis=0) for e in nodes),
                   key=lambda c: np.hypot(c[0] - x, c[1] - cy))

    cluster_nodes = {'outer': node_at(cx - outer_r), 'small': node_at(cx - (outer_r + inner_r) / 2 - 20),
                     'inner': node_at(cx - inner_r - 20)}

    def in_cluster(p):
        p = np.asarray(p, float)
        return bool(np.all((p[:, 0] < cx - arc_r + 30) & (np.abs(p[:, 1] - cy) < 140)))

    def on_circle(p):
        d = np.hypot(*(_dense(p) - (cx, cy)).T)
        return any(np.all(np.abs(d - r) <= 4.0) for r in radii)

    kept = [e for e in circuits if not in_cluster(e['points']) and not in_cluster(np.array(e['points']) * (-1, 1) + (CANVAS_W, 0))
            and not on_circle(e['points'])]
    kept = [e for e in kept if _poly_len(e['points']) >= 20.0]
    kept += side_cluster(cluster_nodes, outer_r, arc_r)

    node_polys = _node_polys(others)
    left: list[dict] = []
    for e in kept:
        p = _snap_to_nodes(np.asarray(e['points'], float), node_polys)
        xs = p[:, 0]
        if np.all(np.abs(xs - cx) <= 1.0):
            left.append({**e, 'points': p.tolist()})  # 中軸上的線本身就對稱
        elif np.all(xs <= cx + 1.0):
            left.append({**e, 'points': p.tolist()})
        elif np.any(xs < cx - 1.0):
            # 跨中軸：從左端走到第一次碰到中軸為止，只留這左半段
            if p[0][0] > p[-1][0]:
                p = p[::-1]
            half = [p[0]]
            for a, b in zip(p[:-1], p[1:]):
                if (a[0] - cx) * (b[0] - cx) <= 0 and b[0] != a[0]:
                    t = (cx - a[0]) / (b[0] - a[0])
                    half.append(a + (b - a) * t)
                    break
                half.append(b)
            left.append({**e, 'points': np.array(half).tolist(), '_axis_half': True})
    out = []
    for e in left:
        p = np.asarray(e['points'], float)
        if np.all(np.abs(p[:, 0] - cx) <= 1.0):
            out.append({k: v for k, v in e.items() if k != '_axis_half'})
            continue
        m = p * (-1, 1) + (CANVAS_W, 0)
        if e.get('_axis_half'):
            # 跨中軸的線：左半段（終點在中軸上）＋鏡像倒著接回來，成一條
            joined = np.vstack([p, m[::-1][1:]])
            out.append({k: v for k, v in e.items() if k != '_axis_half'} | {'points': joined.tolist()})
        else:
            out.append(e)
            out.append({**e, 'id': e['id'] + '-m', 'points': m.tolist()})
    for k, e in enumerate(out):
        e['id'] = f'line-{k}'
        e['points'] = [[round(float(x), 2), round(float(y), 2)] for x, y in e['points']]
    arcs = [e for e in others if e['kind'] == 'arc']
    _symmetric_arcs(arcs)
    return others + out


def snap_width(w: float) -> float:
    """線寬分兩級：細線路（< 3 px）與主線（軸、連接線、節點框）。"""
    return 2.6 if w < 3.0 else 4.0


# ── 主流程 ────────────────────────────────────────────────────────────────

def _square(c, side):
    h = side / 2
    return [(c[0] - h, c[1] - h), (c[0] + h, c[1] - h), (c[0] + h, c[1] + h), (c[0] - h, c[1] + h)]


def _diamond(c, diag):
    h = diag / 2
    return [(c[0], c[1] - h), (c[0] + h, c[1]), (c[0], c[1] + h), (c[0] - h, c[1])]


def refit_radius(art: np.ndarray, center: np.ndarray, r: float, band: float = 4.0) -> float:
    yy, xx = np.mgrid[0:art.shape[0], 0:art.shape[1]]
    d = np.hypot(xx - center[0], yy - center[1])
    sel = (art > 0.5) & (np.abs(d - r) < band)
    return float(np.average(d[sel], weights=art[sel]))


def nodes_from(lab: np.ndarray, objs, skip: set[int], center: np.ndarray) -> list[dict]:
    """粗件裡徽記以外的小塊：方形（填滿外框 > 75%）或菱形，回傳相對圓心的位置與大小。"""
    out = []
    for i, s in enumerate(objs, 1):
        if i in skip:
            continue
        comp = lab == i
        yy, xx = np.nonzero(comp)
        w, h = s[1].stop - s[1].start, s[0].stop - s[0].start
        fill = comp.sum() / (w * h)
        out.append({'kind': 'square' if fill > 0.75 else 'diamond',
                    'rel': np.array([xx.mean(), yy.mean()]) - center,
                    'size': float(min(w, h)),
                    # 外框長寬差太多＝跟旁邊的小點黏在一起，中心不準
                    'merged': abs(w - h) > 4})
    return out


def symmetric_nodes(raw: list[dict], outer_r: float) -> list[tuple[str, np.ndarray, float]]:
    """節點依「種類＋相對位置」分組後對稱化：軸上的對齊到軸、成對的取同一個距離與大小；
    外環上的小方塊、外環上的菱形直接落在外環上。回傳 (layer, 相對位置, 大小)。"""
    out = []
    used = set()
    for a, na in enumerate(raw):
        if a in used:
            continue
        # 找鏡像的同類節點（上下、左右或四象限）
        group = [b for b, nb in enumerate(raw) if b not in used and nb['kind'] == na['kind'] and
                 abs(abs(nb['rel'][0]) - abs(na['rel'][0])) < 8 and
                 abs(abs(nb['rel'][1]) - abs(na['rel'][1])) < 9]
        used.update(group)
        ax = float(np.mean([abs(raw[b]['rel'][0]) for b in group]))
        ay = float(np.mean([abs(raw[b]['rel'][1]) for b in group]))
        sizes = [raw[b]['size'] for b in group if not raw[b]['merged']]
        size = float(np.mean(sizes or [raw[b]['size'] for b in group]))
        on_v_axis, on_h_axis = ax < 6, ay < 7
        if on_v_axis:
            ax = 0.0
        if on_h_axis:
            ay = 0.0
        if abs(np.hypot(ax, ay) - outer_r) < 8:  # 外環上的節點：正好落在環上
            k = outer_r / max(np.hypot(ax, ay), 1e-9)
            ax, ay = ax * k, ay * k
        signs = {(np.sign(raw[b]['rel'][0]) if not on_v_axis else 0,
                  np.sign(raw[b]['rel'][1]) if not on_h_axis else 0) for b in group}
        # 只有單邊的（例如上方的小點）照樣補對稱的另一邊
        if on_v_axis:
            signs = {(0, 1), (0, -1)}
        elif on_h_axis:
            signs = {(1, 0), (-1, 0)}
        else:
            signs = {(1, 1), (1, -1), (-1, 1), (-1, -1)}
        layer = 'node-square' if na['kind'] == 'square' else 'node-diamond'
        for sx, sy in sorted(signs):
            pos = np.array([sx * ax, sy * ay])
            src = min(group, key=lambda b: np.hypot(*(raw[b]['rel'] - pos)))
            matched = np.hypot(*(raw[src]['rel'] - pos)) < 12 and not raw[src]['merged']
            out.append((layer, pos, size, raw[src]['rel'] if matched else None))
    return out


# ── 外框、稜面、刻線（量原圖後參數化重建：外框上下左右對稱）───────────────────

CARD_RADIUS = 81.0  # 執行時的圓角裁切：24 pt ÷ 354 pt × 1200（iPhone 15）
FRAME_INSET = 38 * SCALE  # 外框細線離卡緣（原圖 38 px）
FRAME_LINE_W = 3.0
FRAME_R = CARD_RADIUS - FRAME_INSET  # 外框細線轉角跟裁切同心


def _arc_pts(cx, cy, r, a0, a1, n=12):
    return [(cx + r * np.cos(np.radians(a)), cy + r * np.sin(np.radians(a)))
            for a in np.linspace(a0, a1, n)]


def _mirror_x(pts):
    return [(CANVAS_W - x, y) for x, y in pts]


def _mirror_y(pts):
    return [(x, CANVAS_H - y) for x, y in pts]


def _cx(x_src: float) -> float:
    """中間的元件（上下飾板與旁邊的刻記）水平方向以卡片中線對位。"""
    return CANVAS_W / 2 + (x_src - SRC_W / 2) * SCALE


def _rounded_rect(inset: float, radius: float, n: int = 10) -> list[tuple[float, float]]:
    x0, y0, x1, y1 = inset, inset, CANVAS_W - inset, CANVAS_H - inset
    pts = []
    pts += _arc_pts(x0 + radius, y0 + radius, radius, 180, 270, n)
    pts += _arc_pts(x1 - radius, y0 + radius, radius, 270, 360, n)
    pts += _arc_pts(x1 - radius, y1 - radius, radius, 0, 90, n)
    pts += _arc_pts(x0 + radius, y1 - radius, radius, 90, 180, n)
    return pts


def frame_line_path() -> list[tuple[float, float]]:
    """外框細線（順時針一圈）：離卡緣 38 px，在上下飾板底下以 45° 往內退到 79 px。"""
    i, r = FRAME_INSET, FRAME_R
    step_x = _cx(286)  # 退階起點（原圖 x 286）
    deep = 79 * SCALE
    top = [(step_x, i), (step_x + (deep - i), deep),
           (CANVAS_W - step_x - (deep - i), deep), (CANVAS_W - step_x, i)]
    pts = _arc_pts(i + r, i + r, r, 180, 270)
    pts += top
    pts += _arc_pts(CANVAS_W - i - r, i + r, r, 270, 360)
    pts += _arc_pts(CANVAS_W - i - r, CANVAS_H - i - r, r, 0, 90)
    pts += _mirror_y(top)[::-1]
    pts += _arc_pts(i + r, CANVAS_H - i - r, r, 90, 180)
    return pts


def build_frame() -> list[dict]:
    els: list[dict] = []
    line = frame_line_path()
    # 卡緣暗帶：卡片外形挖掉外框細線圍起來的內部
    els.append({'id': 'band', 'kind': 'polygon', 'layer': 'edge-band',
                'points': _rounded_rect(0, CARD_RADIUS)})
    els.append({'id': 'band-hole', 'kind': 'polygon', 'layer': 'edge-band', 'hole': True,
                'points': line})
    els.append({'id': 'frame-line-outer', 'kind': 'polyline', 'layer': 'frame-line',
                'closed': True, 'points': line + [line[0]], 'width': FRAME_LINE_W})
    # 側邊第二道細線：在 y 350 從外框線 45° 分出來，貼在離卡緣 73 px 往下，對稱收回
    inner_x = 73 * SCALE
    y_branch = 350 * SCALE
    side = [(FRAME_INSET, y_branch), (inner_x, y_branch + inner_x - FRAME_INSET),
            (inner_x, CANVAS_H - y_branch - (inner_x - FRAME_INSET)),
            (FRAME_INSET, CANVAS_H - y_branch)]
    for k, pts in enumerate([side, _mirror_x(side)]):
        els.append({'id': f'frame-line-side-{k}', 'kind': 'polyline', 'layer': 'frame-line',
                    'points': pts, 'width': FRAME_LINE_W})
    # 上下飾板：卡緣上的梯形，兩端 45°（原圖上緣 x 285–620、高 57）
    half_top, height = 167 * SCALE, 57 * SCALE
    plate = [(CANVAS_W / 2 - half_top, 0), (CANVAS_W / 2 + half_top, 0),
             (CANVAS_W / 2 + half_top - height, height), (CANVAS_W / 2 - half_top + height, height)]
    els.append({'id': 'plate-top', 'kind': 'polygon', 'layer': 'plate', 'points': plate})
    els.append({'id': 'plate-bottom', 'kind': 'polygon', 'layer': 'plate',
                'points': _mirror_y(plate)})
    # 側飾條：貼左右緣，寬 55、兩端 45°，以卡片中線為中心（原圖在 y 706 附近，對齊到中線）
    bw, half_out = 55 * SCALE, 195 * SCALE
    bar = [(0, CANVAS_H / 2 - half_out), (bw, CANVAS_H / 2 - half_out + bw),
           (bw, CANVAS_H / 2 + half_out - bw), (0, CANVAS_H / 2 + half_out)]
    els.append({'id': 'sidebar-left', 'kind': 'polygon', 'layer': 'sidebar', 'points': bar})
    els.append({'id': 'sidebar-right', 'kind': 'polygon', 'layer': 'sidebar',
                'points': _mirror_x(bar)[::-1]})
    # 四角飾板：外框細線轉角內的直角三角形（腿長 73 px），轉角照細線的圓角
    leg = 73 * SCALE
    i, r = FRAME_INSET, FRAME_R
    corner = _arc_pts(i + r, i + r, r, 180, 270) + [(i + leg, i), (i, i + leg)]
    for k, pts in enumerate([corner, _mirror_x(corner), _mirror_y(corner),
                             _mirror_x(_mirror_y(corner))]):
        els.append({'id': f'corner-{k}', 'kind': 'polygon', 'layer': 'plate-corner',
                    'points': pts})
    # 刻記：飾板旁兩個 45° 的「//」與一條短橫線（上下、左右各一組）
    y0, y1 = 57 * SCALE, 71 * SCALE
    marks = []
    for x0, x1 in [(243, 256), (267, 282)]:
        a, b = _cx(x0), _cx(x1)
        slant = (y1 - y0)
        marks.append([(a, y1), (b, y1), (b + slant, y0), (a + slant, y0)])
    dash = [(_cx(168), 62 * SCALE), (_cx(231), 62 * SCALE), (_cx(231), 65 * SCALE),
            (_cx(168), 65 * SCALE)]
    k = 0
    for shape in marks + [dash]:
        for t in (lambda q: q, _mirror_x, _mirror_y, lambda q: _mirror_x(_mirror_y(q))):
            els.append({'id': f'mark-{k}', 'kind': 'polygon', 'layer': 'mark', 'points': t(shape)})
            k += 1
    return [_round_el(e) for e in els]


def build_facets() -> list[dict]:
    """底面稜面（示意圖一：四角與上半部有大塊、低對比的稜面）：左右對稱的幾塊斜切多邊形，
    高低交錯（±0.04），看起來像一片片拼起來的清漆面。"""
    left = [
        ('facet-tl-a', +1, [(60, 60), (330, 60), (470, 300), (300, 470), (60, 330)]),
        ('facet-tl-b', -1, [(300, 470), (470, 300), (560, 420), (420, 560)]),
        ('facet-ml', +1, [(100, 520), (210, 610), (210, 760), (100, 650)]),
        ('facet-bl-a', +1, [(60, 1470), (230, 1640), (60, 1740)]),
        ('facet-bl-b', -1, [(100, 1180), (230, 1300), (230, 1520), (100, 1400)]),
    ]
    els = []
    for name, sign, pts in left:
        els.append({'id': name + '-l', 'kind': 'polygon', 'layer': 'facet', 'height': 0.04 * sign,
                    'points': pts})
        els.append({'id': name + '-r', 'kind': 'polygon', 'layer': 'facet', 'height': 0.04 * sign,
                    'points': _mirror_x(pts)})
    return [_round_el(e) for e in els]


def build_etch(center_canvas, inner_r: float, outer_r: float) -> list[dict]:
    """內外環之間的刻度盤（示意圖一的底面蝕刻，#114 Gate-2a 第 2 輪照示意圖量）：內環外 8 px 到
    一圈細弧（兩環間距的 64%）之間每 2° 一條放射細線，每 4° 一條粗一點；弧本身也是細線。
    第 1 輪放在弧與內環之間的窄縫，示意圖那裡沒有。"""
    cx, cy = center_canvas
    r0 = inner_r + 8.0
    r1 = inner_r + 0.64 * (outer_r - inner_r)
    els = [{'id': 'etch-dial', 'kind': 'ring', 'layer': 'etch', 'center': [cx, cy],
            'r': round(r1, 2), 'width': 1.4}]
    for k, a in enumerate(np.arange(0, 360, 2.0)):
        th = np.radians(a)
        els.append({'id': f'etch-{k}', 'kind': 'polyline', 'layer': 'etch',
                    'width': 1.4 if k % 2 == 0 else 1.0,
                    'points': [[round(cx + r0 * np.cos(th), 2), round(cy + r0 * np.sin(th), 2)],
                               [round(cx + r1 * np.cos(th), 2), round(cy + r1 * np.sin(th), 2)]]})
    return els


def _round_el(e: dict) -> dict:
    e = dict(e)
    e['points'] = [[round(float(x), 2), round(float(y), 2)] for x, y in e['points']]
    return e


def trace(overlay: Path | None) -> dict:
    emblem_m = load_mask('emblem_mask')
    lines_m = load_mask('lines_mask')
    frame_m = load_mask('frame_mask')
    art = np.maximum(emblem_m, lines_m)

    thick = morphology.opening(emblem_m > 0.5, morphology.disk(4))
    lab, _ = ndimage.label(thick)
    objs = ndimage.find_objects(lab)
    emblem_ids = [i for i, s in enumerate(objs, 1)
                  if (lab[s] == i).sum() > 3000 and s[1].start >= 285 and s[1].stop <= 625
                  and s[0].start >= 520 and s[0].stop <= 925]

    # 圓心：外環擬合的圓心與四組對稱節點各自的中心取平均（原圖彼此差 1–3 px，統一成一個）
    ocx, ocy, _ = robust_circle(lines_m, 452, 712, 361)
    raw_nodes = nodes_from(lab, objs, set(emblem_ids), np.array([ocx, ocy]))
    sym = []
    for kind, lo, hi in [('square', 200, 300), ('square', 340, 380)]:
        g = [n for n in raw_nodes if n['kind'] == kind and lo < np.hypot(*n['rel']) < hi]
        if len(g) == 4:
            sym.append(np.mean([n['rel'] for n in g], axis=0))
    center = np.array([ocx, ocy]) + (np.mean(sym, axis=0) if sym else 0) / 2
    raw_nodes = nodes_from(lab, objs, set(emblem_ids), center)
    mapping = Mapping(tuple(center))

    outer_r = refit_radius(art, center, 361)
    inner_r = refit_radius(art, center, 234)
    arc_r = refit_radius(art, center, 209)
    elements: list[dict] = []

    # 徽記
    em = np.isin(lab, emblem_ids)
    parts = []
    for n_part, i in enumerate(emblem_ids):
        for k, xy in enumerate(contours(lab == i)):
            parts.append((n_part, k, snap_lines(xy, [90, 30, 150, 0])))
    width = stroke_width(em.astype(np.float32), np.ones_like(em, bool))
    regularize_widths([lines for _, _, lines in parts], em, width)
    for n_part, k, lines in parts:
        # 寬度調整後，同一條邊被拆成兩段的再併回去（兩段配到不同對邊時會差一點點）
        pts = vertices(drop_reversed(_bridge_steps(_merge_lines(lines), [90, 30, 150, 0])))
        elements.append({'id': f'emblem-{n_part}-{k}', 'kind': 'polygon', 'layer': 'emblem',
                         'hole': k > 0, 'points': [mapping.center_pt(p) for p in pts]})

    # 環與弧
    ring_w = {}
    for name, r in [('outer', outer_r), ('inner', inner_r)]:
        band = (np.abs(np.hypot(*np.mgrid[0:art.shape[0], 0:art.shape[1]][::-1] -
                                center[:, None, None]) - r) < 4)
        ring_w[name] = stroke_width(art, band)
        elements.append({'id': f'ring-{name}', 'kind': 'ring', 'layer': 'orbit',
                         'center': mapping.center_pt(center), 'r': round(r * SCALE, 2),
                         'width': round(ring_w[name] * SCALE, 2)})
    for k, (a0, a1) in enumerate(ring_coverage_arcs(art, center, arc_r)):
        elements.append({'id': f'arc-{k}', 'kind': 'arc', 'layer': 'orbit',
                         'center': mapping.center_pt(center), 'r': round(arc_r * SCALE, 2),
                         'a0': round(a0, 2), 'a1': round(a1, 2),
                         'width': round(ring_w['inner'] * 0.85 * SCALE, 2)})

    # 節點
    nodes = symmetric_nodes(raw_nodes, outer_r)
    for k, (layer, rel, size, src_rel) in enumerate(nodes):
        c = center + rel
        poly = _square(c, size) if layer == 'node-square' else _diamond(c, size)
        el = {'id': f'node-{k}', 'kind': 'polygon', 'layer': layer,
              'points': [mapping.center_pt(p) for p in poly]}
        if src_rel is None:
            el['synthesized'] = True  # 原圖這一顆跟旁邊的小點黏在一起或缺了，依對稱補上
        else:
            el['source_center'] = [round(float(v), 2) for v in center + src_rel]
        elements.append(el)

    # 細線
    # 細線門檻放低到 0.3：底部那幾條斜的線路在遮罩裡比較淡
    thin = (art > 0.3) & ~ndimage.binary_dilation(thick, iterations=2)
    thin = morphology.remove_small_objects(thin, max_size=30)
    # 徽記周圍（原圖的髒缺口）不出線
    thin &= ~ndimage.binary_dilation(em, iterations=6)
    dt = ndimage.distance_transform_edt(art > 0.5)

    def width_of(pth):
        ys = np.clip(pth[:, 1].astype(int), 0, dt.shape[0] - 1)
        xs = np.clip(pth[:, 0].astype(int), 0, dt.shape[1] - 1)
        return float(2 * np.median(dt[ys, xs]))

    paths = strip_ring_points(skeleton_paths(morphology.skeletonize(thin)), center,
                              [outer_r, inner_r, arc_r])
    _, polys = classify_paths(paths, center, width_of)  # 剩下的弧（若有）也當折線
    polys = [p for p in polys if len(p['points']) >= 2]
    joined = join_endpoints([p['points'] for p in polys], center, [outer_r, inner_r, arc_r],
                            [center + rel for _, rel, _, _ in nodes],
                            [size / 2 + 4 for _, _, size, _ in nodes])
    joined = [lock_axes(pts, center) for pts in joined]
    widths = [p['width'] for p in polys]
    joined, widths = mirror_axis_circuits(joined, widths, center, inner_r)
    polys = [{'width': w} for w in widths]
    for k, (p, pts) in enumerate(zip(polys, joined)):
        elements.append({'id': f'line-{k}', 'kind': 'polyline', 'layer': 'circuit',
                         'points': [mapping.center_pt(q) for q in pts],
                         'width': round(snap_width(p['width']) * SCALE, 2)})

    elements = tidy(elements, outer_r * SCALE, inner_r * SCALE, arc_r * SCALE)
    for e in elements:
        e['anchor'] = 'center'
    for e in build_frame():
        e['anchor'] = 'mid' if e['layer'] in ('plate', 'mark') else 'edge'
        elements.append(e)
    for e in build_facets() + build_etch(mapping.center_pt(center), inner_r * SCALE,
                                         outer_r * SCALE):
        e['anchor'] = 'free'
        elements.append(e)

    geometry = {
        'canvas': [CANVAS_W, CANVAS_H],
        'source': {'size': [SRC_W, SRC_H], 'center': [round(float(center[0]), 2),
                                                       round(float(center[1]), 2)],
                   'scale': round(SCALE, 6), 'outer_ring_r': round(outer_r, 2),
                   'inner_ring_r': round(inner_r, 2), 'arc_r': round(arc_r, 2),
                   'emblem_stroke': round(width, 2)},
        'elements': elements,
    }
    return geometry


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--overlay', type=Path, default=None)
    parser.add_argument('--out', type=Path, default=OUT)
    args = parser.parse_args()
    geometry = trace(args.overlay)
    args.out.write_text(json.dumps(geometry, ensure_ascii=False, indent=1))
    print(f'寫出 {args.out}：{len(geometry["elements"])} 個元件')


if __name__ == '__main__':
    main()
