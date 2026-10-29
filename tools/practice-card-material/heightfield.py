"""卡背高度圖與材質編號（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §5.2）。

輸入 card_back_geometry.json 的覆蓋率遮罩（geometry.rasterize），輸出 1200×1800 的：
- height：高度（任意單位，底面 0）
- material：材質編號（MAT_*）
- brush：拉絲方向（度，0..180；-1＝不拉絲）：上下飾板 0°、側飾條 90°、四角沿斜邊、卡緣暗帶沿卡緣
  （轉角照圓弧切線）、徽記三個面各自沿等角軸（上 150°、左 30°、右 90°）
- part：零件編號（拉絲的相位用：不相連的零件各自一組，紋路不會一條線貫穿好幾個零件）
- face：徽記三個面（0 上、1 左、2 右；不是徽記 -1），Y 字三筆沿中線分屬兩側的面
- slope：倒角與斜面（拋光，窄而集中的反光）
- tilt：底面稜面的法線傾斜（x、y 兩個通道；稜面是一片片微斜的平面，各自接到不同的光）
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
    'edge-band': (0.30, 4.0, 'flat', MAT_BAND, None),  # 沿卡緣（轉角照圓弧切線）
    'plate': (0.55, 6.0, 'flat', MAT_PLATE, 0.0),
    'plate-corner': (0.55, 6.0, 'flat', MAT_CORNER, None),  # 四角沿各自的斜邊
    'sidebar': (0.50, 6.0, 'flat', MAT_BAR, 90.0),
    'frame-line': (0.18, 1.5, 'round', MAT_LINE, -1.0),
    'mark': (0.18, 1.5, 'round', MAT_LINE, -1.0),
    'orbit': (0.20, 1.5, 'round', MAT_LINE, -1.0),
    'circuit': (0.20, 1.5, 'round', MAT_LINE, -1.0),
    'node-square': (0.40, 0.0, 'pyramid', MAT_NODE, -1.0),
    'node-diamond': (0.45, 0.0, 'pyramid', MAT_NODE, -1.0),
    'emblem': (1.00, 8.0, 'flat', MAT_EMBLEM, None),  # 徽記依立方的面分方向
}
NODE_SLOPE = 0.055  # 節點四面錐的坡度（每 px 升高多少；法線強度 7 時切面約傾斜 21°）
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
    """距離 → 0..1 的高度比例。flat：倒角後平頂（倒角上緣微微收圓：坡度從底部往上緣由陡變緩，
    拋光倒角的反光收成上緣一道細亮線，不是整條倒角一樣亮）；round：半圓；pyramid：一路斜到中心。"""
    if kind == 'flat':
        u = np.clip(d / max(bevel, 1e-6), 0, 1)
        p = 0.6 * u + 0.4 * (1 - (1 - u) ** 2)
    elif kind == 'round':
        p = np.sqrt(np.clip(d / max(bevel, 1e-6), 0, 1) * (2 - np.clip(d / max(bevel, 1e-6), 0, 1)))
    else:  # pyramid：size＝中心到邊的距離
        p = np.clip(d / max(size or 1.0, 1e-6), 0, 1)
    # 邊緣外半像素交給覆蓋率，反鋸齒
    return np.where(cover > 0.5, p, 0.0) + np.where(cover <= 0.5, 0.0, 0.0)


FACE_TOP, FACE_LEFT, FACE_RIGHT = 0, 1, 2
# 徽記三個面的拉絲方向：各取該面的一條等角軸（上面 150°、左面 30°、右面 90°），三面方向都不同
FACE_BRUSH = {FACE_TOP: 150.0, FACE_LEFT: 30.0, FACE_RIGHT: 90.0}
CARD_RADIUS = 81.0  # 執行時的圓角裁切（同 trace_geometry.CARD_RADIUS）


def _poly_mask(geo: dict, el: dict, scale: float) -> np.ndarray:
    return g.rasterize({'canvas': geo['canvas'], 'elements': [el]}, scale=scale)[el['layer']]


def emblem_face_map(geo: dict, shape: tuple[int, int], scale: float = 1.0) -> np.ndarray:
    """徽記每一點屬於立方的哪個面（0 上、1 左、2 右；-1＝不是徽記）。
    - 頂面的兩個人字（emblem-0、emblem-1）→ 上；左側面的迴紋（emblem-2）→ 左；
    - Y 字與右側面（emblem-3）：以 Y 的中心為原點，Y 的三筆是三個面的分界——左臂（150° 方向往
      左上）以上是上面、中柱以左是左面、其餘是右面。Y 的每一筆沿中線分屬兩側的面，看起來是立方
      的稜線。Y 中心＝中柱中線（中柱左緣＋半筆寬）與左臂中線（左臂上緣往下半筆寬）的交點。"""
    h, w = shape
    face = np.full(shape, -1, np.int8)
    stroke = geo['source'].get('emblem_stroke', 26.0) * geo['source']['scale']
    t30 = np.tan(np.radians(30))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx, yy = (xx + 0.5) / scale, (yy + 0.5) / scale  # 畫布座標
    for el in geo['elements']:
        if el['layer'] != 'emblem' or el.get('hole'):
            continue
        part = int(el['id'].split('-')[1])
        m = _poly_mask(geo, el, scale) > 0.5
        holes = [e for e in geo['elements'] if e['layer'] == 'emblem' and e.get('hole')
                 and e['id'].split('-')[1] == str(part)]
        for hole in holes:
            m &= ~(_poly_mask(geo, {**hole, 'hole': False}, scale) > 0.5)
        if part in (0, 1):
            face[m] = FACE_TOP
            continue
        if part == 2:
            face[m] = FACE_LEFT
            continue
        p = np.asarray(el['points'], float)
        n = len(p)
        # 中柱左緣：離卡片中線最近的長垂直邊；左臂上緣：中柱左上方最上面那條 30° 邊
        edges = [(p[i], p[(i + 1) % n]) for i in range(n)]
        ang = [np.degrees(np.arctan2(b[1] - a[1], b[0] - a[0])) % 180 for a, b in edges]
        cx = geo['canvas'][0] / 2
        vert = min((e for e, a in zip(edges, ang) if abs(a - 90) < 1 and abs(e[1][1] - e[0][1]) > 100),
                   key=lambda e: abs(e[0][0] - cx))
        xs = vert[0][0] + stroke / 2
        arm = [e for e, a in zip(edges, ang) if abs(a - 30) < 1 and min(e[0][1], e[1][1]) < 880
               and max(e[0][0], e[1][0]) < xs + 5]
        upper = min(arm, key=lambda e: e[0][1] - t30 * e[0][0])  # 截距最小＝最上面那條
        c0 = upper[0][1] - t30 * upper[0][0] + stroke / 2 / np.cos(np.radians(30))
        yc = c0 + t30 * xs
        ang_px = np.degrees(np.arctan2(yy - yc, xx - xs))  # −180..180，y 往下
        top = (ang_px > -150) & (ang_px < -30)
        left = (ang_px >= 90) | (ang_px <= -150)
        face[m & top] = FACE_TOP
        face[m & left & ~top] = FACE_LEFT
        face[m & ~top & ~left] = FACE_RIGHT
    return face


def emblem_brush(geo: dict, shape: tuple[int, int], scale: float = 1.0) -> np.ndarray:
    """徽記三個面的拉絲方向（度）；不是徽記的地方 -1。"""
    face = emblem_face_map(geo, shape, scale)
    out = np.full(shape, -1.0, np.float32)
    for k, deg in FACE_BRUSH.items():
        out[face == k] = deg
    return out


def band_brush(shape: tuple[int, int], scale: float = 1.0) -> np.ndarray:
    """卡緣暗帶的拉絲方向：沿卡緣走（左右垂直、上下水平，轉角照圓弧切線）。"""
    h, w = shape
    r = CARD_RADIUS * scale
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    qx = np.clip(xx, r, w - r)
    qy = np.clip(yy, r, h - r)
    # 卡片中間（離四邊都遠）用離最近的邊判斷；轉角區照圓弧
    dx, dy = xx - qx, yy - qy
    edge = (dx == 0) & (dy == 0)
    d_lr = np.minimum(xx, w - xx)
    d_tb = np.minimum(yy, h - yy)
    dx = np.where(edge, np.where(d_lr < d_tb, np.sign(xx - w / 2), 0), dx)
    dy = np.where(edge, np.where(d_lr < d_tb, 0, np.sign(yy - h / 2)), dy)
    return ((np.degrees(np.arctan2(dy, dx)) + 90) % 180).astype(np.float32)


def band_side(shape: tuple[int, int]) -> np.ndarray:
    """卡緣暗帶分四段（上 0、右 1、下 2、左 3）：拉絲相位各自一組。"""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    d = np.stack([yy / h, (w - xx) / w, (h - yy) / h, xx / w])  # 依卡片比例換算，轉角斜切對半
    return np.argmin(d, axis=0).astype(np.int16)


# 底面稜面的傾斜（法線 x、y 分量）：凸的那幾塊朝最近的光（左半邊朝左上的主光、右半邊鏡射後朝
# 右上的燈條），凹的那幾塊反過來；四角因此比中間亮，一片片高低交錯（示意圖一的大塊低對比稜面）。
FACET_TILT = {'facet-tl-a': (-0.13, -0.15), 'facet-tl-b': (0.10, 0.08), 'facet-ml': (-0.15, -0.04),
              'facet-bl-a': (-0.10, -0.16), 'facet-bl-b': (0.08, 0.09)}


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
    slope_m = np.zeros(shape, np.float32)
    part = np.zeros(shape, np.int32)
    tilt = np.zeros(shape + (2,), np.float32)

    # 底面稜面（±0.04，2 px 柔邊）＋各自的傾斜（4 px 柔邊）
    if 'facet' in cover:
        for el in geo['elements']:
            if el['layer'] != 'facet':
                continue
            c = _poly_mask(geo, el, scale)
            d = chamfer_distance(c, 6)
            height += el.get('height', 0.04) * np.clip(d / 2.0, 0, 1) * (c > 0.5)
            name, side = el['id'].rsplit('-', 1)
            tx, ty = FACET_TILT.get(name, (0.0, 0.0))
            if side == 'r':
                tx = -tx
            soft = np.clip(d / 4.0, 0, 1) * (c > 0.5)
            tilt[..., 0] += tx * soft
            tilt[..., 1] += ty * soft

    emblem_dir = emblem_brush(geo, shape, scale) if 'emblem' in cover else None
    face = emblem_face_map(geo, shape, scale) if 'emblem' in cover else np.full(shape, -1, np.int8)
    band_dir = band_brush(shape, scale)
    side = band_side(shape)
    # 零件編號：會拉絲的元件各自一號（四角、飾板、側飾條、徽記各塊×面），卡緣分四段
    elem_part = np.zeros(shape, np.int32)
    corner_dir = np.full(shape, -1.0, np.float32)
    for k, el in enumerate(geo['elements']):
        if el['layer'] in ('plate', 'plate-corner', 'sidebar') or (
                el['layer'] == 'emblem' and not el.get('hole')):
            m = _poly_mask(geo, el, scale) > 0.5
            elem_part[m] = k + 1
            if el['layer'] == 'plate-corner':
                p = np.asarray(el['points'], float)
                # 斜邊：最後兩個點（腿的兩端）
                a, b = p[-2], p[-1]
                corner_dir[m] = np.degrees(np.arctan2(b[1] - a[1], b[0] - a[0])) % 180
    for layer in ORDER:
        if layer not in cover:
            continue
        top, bevel, kind, mat, bdir = LAYERS[layer]
        c = cover[layer]
        if kind == 'pyramid':
            # 節點一顆一顆算（大小不一樣：第 1 輪整層共用最後一顆的大小，大節點中間變成一片平頂、
            # 打光後一片白）。四面錐一路斜到中心，坡度固定（高度＝NODE_SLOPE×中心到邊的距離），
            # 大小節點的切面一樣斜，四個面各自對到不同的燈。菱形的中心到邊（沿法線）＝半對角線／√2；
            # 方形＝半邊
            p = np.zeros(shape, np.float32)
            hgt = np.zeros(shape, np.float32)
            for el in geo['elements']:
                if el['layer'] != layer:
                    continue
                ce = _poly_mask(geo, el, scale)
                half = float(np.ptp(np.asarray(el['points'], float)[:, 0])) / 2 * scale
                reach = half / np.sqrt(2) if layer == 'node-diamond' else half
                pe = profile(chamfer_distance(ce, reach + 2), ce, 0, 'pyramid', reach)
                p = np.maximum(p, pe)
                hgt = np.maximum(hgt, NODE_SLOPE * reach / scale * pe)
        else:
            d = chamfer_distance(c, bevel + 2)
            p = profile(d, c, bevel * scale, kind)
            hgt = top * p
        on = c > 0.5
        height = np.where(on, np.maximum(height, hgt), height)
        material[on] = mat
        if layer == 'emblem':
            brush[on] = emblem_dir[on]
            part[on] = 1000 + elem_part[on] * 3 + np.clip(face[on], 0, 2)
        elif layer == 'edge-band':
            brush[on] = band_dir[on]
            part[on] = 900 + side[on]
        elif layer == 'plate-corner':
            brush[on] = corner_dir[on]
            part[on] = elem_part[on]
        else:
            brush[on] = bdir
            part[on] = elem_part[on] if bdir >= 0 else 0
        # 高光遮罩（執行時的高光帶，§6.4）：倒角、斜面與細線、節點這些細區 1.0；飾板、側飾條、卡緣、
        # 徽記的平頂 0.25——高光帶掃過大面積時只是一層薄光（§11），不把校準好的平面洗白。
        # 全息遮罩（SR）：只在斜面——飾板與四角的倒角、節點切面、細線兩側（權重低一點），以及側飾條
        # 外緣；徽記維持純金（示意圖的徽記沒有彩邊）
        slope = on & (p < 0.999)
        spec[on] = 0.25 if kind == 'flat' else 1.0
        spec[slope] = 1.0
        slope_m[on] = 0.0
        slope_m[slope] = 1.0
        weight = {'emblem': 0.0, 'node-square': 0.35, 'node-diamond': 0.35,
                  'orbit': 0.3, 'circuit': 0.3, 'frame-line': 0.5, 'mark': 0.5}.get(layer, 1.0)
        holo[slope] = np.maximum(holo[slope], weight)
        if layer == 'sidebar':
            # 側飾條外緣：飾條寬的外側 40%（§5.2 的「外緣 3.5%」＝卡寬的 3.5%，約飾條寬的四成）。
            # 平頂只給一半（倒角仍是 1）：飾條本身維持古銅金，全息是外緣的一道光澤，不蓋掉金屬色
            w = shape[1]
            band = 0.40 * 55 * 1.2605 * scale
            xs = np.arange(shape[1])
            outer = (xs < band) | (xs >= w - band)
            holo[on & outer[None, :]] = np.maximum(holo[on & outer[None, :]], 0.5)
        if layer in ('emblem', 'node-diamond', 'node-square'):
            glow[..., 0] = np.maximum(glow[..., 0], c)
        elif layer in ('frame-line', 'mark', 'plate', 'plate-corner', 'sidebar', 'edge-band'):
            glow[..., 1] = np.maximum(glow[..., 1], c * (1.0 if layer in ('frame-line', 'mark') else 0.35))
        else:
            glow[..., 2] = np.maximum(glow[..., 2], c)

    etch = cover.get('etch', np.zeros(shape, np.float32))
    height -= 0.06 * etch * (material == MAT_FIELD)
    return {'height': height, 'material': material, 'brush': brush, 'spec': spec,
            'holo': holo, 'glow': glow, 'etch': etch, 'cover': cover, 'part': part,
            'face': np.where(material == MAT_EMBLEM, face, -1).astype(np.int8),
            'slope': slope_m, 'tilt': tilt} | {'height': height.astype(np.float32)}
