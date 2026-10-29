"""把 card_back_geometry.json 柵格化成覆蓋率遮罩（典藏材質規格 §5.1）。只依賴 numpy＋Pillow。

每個元件依 `layer` 畫進對應的遮罩：4 倍解析度用 ImageDraw 畫，再用盒狀平均縮回 1×，
得到反鋸齒的覆蓋率（0..1）。
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
GEOMETRY = HERE / 'card_back_geometry.json'
SS = 4  # 超取樣倍數


def load(path: Path = GEOMETRY) -> dict:
    return json.loads(path.read_text())


def _scaled(points, ss: int, scale: float) -> list[tuple[float, float]]:
    return [(x * scale * ss, y * scale * ss) for x, y in points]


def _draw_element(draw: ImageDraw.ImageDraw, el: dict, ss: int, scale: float, fill: int) -> None:
    kind = el['kind']
    if kind == 'polygon':
        draw.polygon(_scaled(el['points'], ss, scale), fill=fill)
    elif kind == 'polyline':
        pts = _scaled(el['points'], ss, scale)
        w = el['width'] * scale * ss
        draw.line(pts, fill=fill, width=max(1, round(w)), joint='curve')
        r = w / 2
        ends = [] if el.get('closed') else [pts[0], pts[-1]]
        # 轉角補圓，粗線的接縫才不會缺角
        for x, y in ends + pts[1:-1]:
            draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)
    elif kind in ('ring', 'arc'):
        cx, cy = el['center']
        r = el['r'] * scale * ss
        w = el['width'] * scale * ss
        cx, cy = cx * scale * ss, cy * scale * ss
        box = (cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2)
        if kind == 'ring':
            draw.ellipse(box, outline=fill, width=max(1, round(w)))
        else:
            draw.arc(box, el['a0'], el['a1'], fill=fill, width=max(1, round(w)))
    else:
        raise ValueError(f'未知的元件種類：{kind}')


def rasterize(geometry: dict, layers: list[str] | None = None, scale: float = 1.0,
              size: tuple[int, int] | None = None) -> dict[str, np.ndarray]:
    """回傳 {layer: 覆蓋率 (h, w) float32}。scale：座標乘這個倍數（例如縮回 904×1428 對位）。
    同一個 layer 裡 `hole: true` 的多邊形會挖空前面畫的部分。"""
    cw, ch = geometry['canvas']
    w, h = size or (round(cw * scale), round(ch * scale))
    out: dict[str, np.ndarray] = {}
    canvases: dict[str, tuple[Image.Image, ImageDraw.ImageDraw]] = {}
    for el in geometry['elements']:
        layer = el['layer']
        if layers is not None and layer not in layers:
            continue
        if layer not in canvases:
            im = Image.new('L', (w * SS, h * SS), 0)
            canvases[layer] = (im, ImageDraw.Draw(im))
        _draw_element(canvases[layer][1], el, SS, scale, 0 if el.get('hole') else 255)
    for layer, (im, _) in canvases.items():
        a = np.asarray(im, dtype=np.float32).reshape(h, SS, w, SS).mean(axis=(1, 3)) / 255.0
        out[layer] = a
    return out
