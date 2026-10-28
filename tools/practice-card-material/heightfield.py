"""卡背高度圖與材質編號（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §5.2）。

輸入 card_back_geometry.json 的覆蓋率遮罩（geometry.rasterize），輸出 1200×1800 的：
- height：高度（任意單位，底面 0）
- material：材質編號（MAT_*）
- brush：拉絲方向（度，0..180；-1＝不拉絲）
- spec：會反光的地方（執行時高光帶的遮罩：倒角、細線、節點 1；平頂 0.25）
- holo：SR 全息遮罩（只有斜面與細線兩側，0..1）
- glow：發光遮罩三個通道（徽記與節點、外框、線路）
- etch：刻線遮罩（V 槽，0..1）
只依賴 numpy；距離場用兩趟 chamfer（1、√2）近似歐氏距離，倒角最多 8 px，誤差可以忽略。
"""

from __future__ import annotations

import numpy as np

import geometry as g

MAT_FIELD, MAT_BAND, MAT_PLATE, MAT_BAR, MAT_EMBLEM, MAT_LINE, MAT_NODE, MAT_CORNER = range(8)

# layer → (高度, 倒角寬 px, 剖面, 材質, 拉絲方向)
LAYERS = {
    'edge-band': (0.30, 4.0, 'flat', MAT_BAND, 0.0),
    'plate': (0.55, 6.0, 'flat', MAT_PLATE, 0.0),
    'plate-corner': (0.55, 6.0, 'flat', MAT_CORNER, 45.0),
    'sidebar': (0.50, 6.0, 'flat', MAT_BAR, 90.0),
    'frame-line': (0.18, 1.5, 'round', MAT_LINE, -1.0),
    'mark': (0.18, 1.5, 'round', MAT_LINE, -1.0),
    'orbit': (0.20, 1.5, 'round', MAT_LINE, -1.0),
    'circuit': (0.20, 1.5, 'round', MAT_LINE, -1.0),
    'node-square': (0.40, 0.0, 'pyramid', MAT_NODE, -1.0),
    'node-diamond': (0.45, 0.0, 'pyramid', MAT_NODE, -1.0),
    'emblem': (1.00, 8.0, 'flat', MAT_EMBLEM, None),  # 徽記依立方的面分方向
}
# 由下往上疊（高的蓋低的）
ORDER = ['edge-band', 'circuit', 'orbit', 'frame-line', 'mark', 'plate-corner', 'plate',
         'sidebar', 'node-square', 'node-diamond', 'emblem']


def chamfer_distance(cover: np.ndarray, limit: float = 16.0) -> np.ndarray:
    """形狀內部離邊緣的距離（px）：覆蓋率給邊緣的次像素起點，再做兩趟 3×3 chamfer。"""
    inside = cover > 0.5
    d = np.where(inside, limit, 0.0).astype(np.float32)
    # 邊緣像素：覆蓋率 0.5 → 距離 0、1 → 0.5（線性近似）
    edge = inside & (cover < 1.0)
    d[edge] = (cover[edge] - 0.5)
    r2 = np.float32(np.sqrt(2))
    h, w = d.shape
    pad = np.pad(d, 1, constant_values=0.0)
    for y in range(1, h + 1):  # 往下
        row = pad[y]
        row[1:-1] = np.minimum.reduce([row[1:-1], pad[y - 1, 1:-1] + 1,
                                       pad[y - 1, :-2] + r2, pad[y - 1, 2:] + r2])
        # 同一列往右（向量化：用累積最小值近似一趟由左往右的傳遞）
        idx = np.arange(row.size, dtype=np.float32)
        row[:] = np.minimum(row, np.minimum.accumulate(row - idx) + idx)
    for y in range(h, 0, -1):  # 往上
        row = pad[y]
        row[1:-1] = np.minimum.reduce([row[1:-1], pad[y + 1, 1:-1] + 1,
                                       pad[y + 1, :-2] + r2, pad[y + 1, 2:] + r2])
        idx = np.arange(row.size, dtype=np.float32)
        rev = row[::-1]
        rev[:] = np.minimum(rev, np.minimum.accumulate(rev - idx) + idx)
    return np.minimum(pad[1:-1, 1:-1], limit)


def profile(d: np.ndarray, cover: np.ndarray, bevel: float, kind: str,
            size: float | None = None) -> np.ndarray:
    """距離 → 0..1 的高度比例。flat：45° 倒角後平頂；round：半圓；pyramid：一路斜到中心。"""
    if kind == 'flat':
        p = np.clip(d / max(bevel, 1e-6), 0, 1)
    elif kind == 'round':
        p = np.sqrt(np.clip(d / max(bevel, 1e-6), 0, 1) * (2 - np.clip(d / max(bevel, 1e-6), 0, 1)))
    else:  # pyramid：size＝中心到邊的距離
        p = np.clip(d / max(size or 1.0, 1e-6), 0, 1)
    # 邊緣外半像素交給覆蓋率，反鋸齒
    return np.where(cover > 0.5, p, 0.0) + np.where(cover <= 0.5, 0.0, 0.0)


def emblem_brush(geo: dict, shape: tuple[int, int]) -> np.ndarray:
    """徽記三個面的拉絲方向：上面 90°、左面 30°、右面 150°（§5.2，依位置分面）。"""
    h, w = shape
    src = geo['source']
    cx = w / 2 + 0.0
    pts = np.array([p for e in geo['elements'] if e['layer'] == 'emblem' and not e.get('hole')
                     for p in e['points']])
    top_y = pts[:, 1].min()
    half_w = (pts[:, 0].max() - pts[:, 0].min()) / 2
    cx = (pts[:, 0].max() + pts[:, 0].min()) / 2
    cy = top_y + 2 * half_w * np.tan(np.radians(30))  # 立方中心頂點 C
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # 上面：在 C→UL、C→UR 兩條線的上方
    above = (yy - cy) < -np.abs(xx - cx) * np.tan(np.radians(30))
    out = np.where(xx < cx, 30.0, 150.0).astype(np.float32)
    out[above] = 90.0
    del src
    return out


def build(geo: dict | None = None, scale: float = 1.0) -> dict[str, np.ndarray]:
    geo = geo or g.load()
    cover = g.rasterize(geo, scale=scale)
    shape = next(iter(cover.values())).shape
    height = np.zeros(shape, np.float32)
    material = np.full(shape, MAT_FIELD, np.uint8)
    brush = np.full(shape, -1.0, np.float32)
    spec = np.zeros(shape, np.float32)
    holo = np.zeros(shape, np.float32)
    glow = np.zeros(shape + (3,), np.float32)

    # 底面稜面（±0.04，2 px 柔邊）
    if 'facet' in cover:
        for el in geo['elements']:
            if el['layer'] != 'facet':
                continue
            c = g.rasterize({'canvas': geo['canvas'], 'elements': [el]}, scale=scale)['facet']
            d = chamfer_distance(c, 4)
            height += el.get('height', 0.04) * np.clip(d / 2.0, 0, 1) * (c > 0.5)

    emblem_dir = emblem_brush(geo, shape) if 'emblem' in cover else None
    node_size = {}
    for el in geo['elements']:
        if el['layer'].startswith('node-'):
            pts = np.array(el['points']) * scale
            node_size[el['layer']] = float(np.ptp(pts[:, 0])) / 2
    for layer in ORDER:
        if layer not in cover:
            continue
        top, bevel, kind, mat, bdir = LAYERS[layer]
        c = cover[layer]
        d = chamfer_distance(c, max(bevel, node_size.get(layer, 0.0)) + 2)
        if kind == 'pyramid':
            # 菱形的中心到邊（沿法線）＝半對角線／√2；方形＝半邊
            half = node_size.get(layer, 10.0)
            reach = half / np.sqrt(2) if layer == 'node-diamond' else half
            p = profile(d, c, 0, 'pyramid', reach)
        else:
            p = profile(d, c, bevel * scale, kind)
        hgt = top * p
        on = c > 0.5
        height = np.where(on, np.maximum(height, hgt), height)
        material[on] = mat
        if layer == 'emblem':
            brush[on] = emblem_dir[on]
        else:
            brush[on] = bdir
        # 高光遮罩（執行時的高光帶，§6.4）：倒角、斜面與細線、節點這些細區 1.0；飾板、側飾條、卡緣、
        # 徽記的平頂 0.25——高光帶掃過大面積時只是一層薄光（§11），不把校準好的平面洗白。
        # 全息遮罩（SR）：只在斜面——飾板與四角的倒角、節點切面、細線兩側（權重低一點），以及側飾條
        # 外緣；徽記維持純金（示意圖的徽記沒有彩邊）
        slope = on & (p < 0.999)
        spec[on] = 0.25 if kind == 'flat' else 1.0
        spec[slope] = 1.0
        weight = {'emblem': 0.0, 'node-square': 0.35, 'node-diamond': 0.35,
                  'orbit': 0.3, 'circuit': 0.3, 'frame-line': 0.5, 'mark': 0.5}.get(layer, 1.0)
        holo[slope] = np.maximum(holo[slope], weight)
        if layer == 'sidebar':
            # 側飾條外緣：飾條寬的外側 40%（§5.2 的「外緣 3.5%」＝卡寬的 3.5%，約飾條寬的四成）
            w = shape[1]
            band = 0.40 * 55 * 1.2605 * scale
            xs = np.arange(shape[1])
            outer = (xs < band) | (xs >= w - band)
            holo[on & outer[None, :]] = 1.0
        if layer in ('emblem', 'node-diamond', 'node-square'):
            glow[..., 0] = np.maximum(glow[..., 0], c)
        elif layer in ('frame-line', 'mark', 'plate', 'plate-corner', 'sidebar', 'edge-band'):
            glow[..., 1] = np.maximum(glow[..., 1], c * (1.0 if layer in ('frame-line', 'mark') else 0.35))
        else:
            glow[..., 2] = np.maximum(glow[..., 2], c)

    etch = cover.get('etch', np.zeros(shape, np.float32))
    height -= 0.06 * etch * (material == MAT_FIELD)
    return {'height': height, 'material': material, 'brush': brush, 'spec': spec,
            'holo': holo, 'glow': glow, 'etch': etch, 'cover': cover}
