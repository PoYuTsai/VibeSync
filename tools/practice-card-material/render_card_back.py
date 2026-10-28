"""卡背三階材質渲染（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §5.3–§5.4）。

  python3 tools/practice-card-material/render_card_back.py [--out assets/images/practice] [--preview DIR]

讀 card_back_geometry.json → heightfield.build() → 打光、金屬、拉絲、倒角亮線、環境遮蔽、底面清漆、
SR 薄膜全息、自發光泛光 → ACES 色調 → sRGB，輸出：
  practice_card_back_v4_{n,r,sr}.webp   1200×1800 有損 q90（成品圖，四角留滿，執行時圓角裁切）
  practice_card_back_v4_light.webp      1200×1800 無損 RGB：R＝浮雕補光差（0.5＝不變）、G＝全息、B＝高光
  practice_card_back_v4_glowmask.webp   600×900 無損 RGB：R＝徽記與節點、G＝外框、B＝線路
  practice_card_back_v4_glow.webp       600×900 有損 RGBA：預先模糊好的白色泛光
  practice_card_noise.webp              128×128 無損灰階：執行時顆粒、拉絲共用的雜訊磚
同一份 JSON、同一個種子，重跑逐位元相同。只依賴 numpy＋Pillow。
"""

from __future__ import annotations

import argparse
import io
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

import geometry as g
import heightfield as hf

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/images/practice'
SEED = 20261028

L1 = np.array([-0.55, -0.62, 0.56]) / np.linalg.norm([-0.55, -0.62, 0.56])  # 左上主光
L2 = np.array([0.60, 0.50, 0.62]) / np.linalg.norm([0.60, 0.50, 0.62])  # 右下補光
L_ALT = np.array([0.55, -0.62, 0.56]) / np.linalg.norm([0.55, -0.62, 0.56])  # 浮雕補光用的右上光


def hexc(s: str) -> np.ndarray:
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def srgb_to_lin(c):
    c = np.asarray(c, np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


@dataclass(frozen=True)
class Tier:
    name: str
    plate: tuple[str, str, str]
    bar: tuple[str, str, str]
    emblem: tuple[str, str, str]
    band: tuple[str, str, str]
    field: tuple[str, str]
    brush: float
    rough: float
    glow: str
    glow_k: float
    holo: float
    base: dict = None  # 每種材質落在坡度的哪裡（calibrate.py 對 targets.json 校準）
    hi: float = 0.35  # 異向高光的強度（染成該階的亮色，金屬的反光帶自己的顏色）
    edge: float = 0.85  # 倒角亮線（凸邊朝主光那一側）
    emblem_tilt: float = 1.8  # 徽記斜面的明暗對比
    line_glow: float = 0.8  # 線路的自發光
    bar_right: tuple = None  # 右側飾條的坡度（R：陽極鈦干涉色，左藍紫 → 右天藍）；None＝同左側
    hi_color: str = None  # 高光的顏色；None＝飾板坡度的亮色


# §5.3 三階材質參數（坡度起點取自 2026-10-28 可行性試算；目標值見 §2.2）
TIERS = {
    'n': Tier('n', ('#59616C', '#AEB8C5', '#F2F6FA'), ('#4E5662', '#9AA5B3', '#E4EBF3'),
              ('#5E6672', '#C9D2DD', '#FFFFFF'), ('#2E3238', '#8C949E', '#F4F7FA'),
              ('#0C0D10', '#22242A'), 0.09, 0.55, '#DCE6F2', 0.45, 0.0,
              base={'field': 0.084, 'band': -0.01, 'plate': 0.607, 'corner': 0.24, 'bar': 0.56, 'emblem': 0.482}),
    'r': Tier('r', ('#1F3F86', '#79B4F5', '#B4E0FC'), ('#2B2F8C', '#6A8DF2', '#A9C2FF'),
              ('#2C5BA8', '#9CCBFA', '#E6F7FF'), ('#14284F', '#4E86D6', '#A8DCFF'),
              ('#090C14', '#18202E'), 0.08, 0.42, '#4FB0FF', 0.9, 0.0,
              base={'field': -0.596, 'band': 0.529, 'plate': 0.529, 'corner': 0.388, 'bar': 0.498, 'emblem': 0.365},
              hi=0.12, edge=0.15, emblem_tilt=1.1, line_glow=1.4,
              bar_right=('#1F4A9C', '#6FB6FD', '#B8E6FF'), hi_color='#A8D8FF'),
    'sr': Tier('sr', ('#6E4E1E', '#E6C46E', '#FFEC9E'), ('#6A4520', '#CFA05C', '#EDC98A'),
               ('#7A5A26', '#F4D47E', '#FFF6CC'), ('#3E2E16', '#B9A27E', '#EEE7D3'),
               ('#100C07', '#2A2117'), 0.08, 0.34, '#FFC95E', 0.85, 0.55,
               base={'field': 0.005, 'band': 0.709, 'plate': 0.779, 'corner': 0.482, 'bar': 0.459, 'emblem': 0.834},
               hi=0.15, edge=0.3, emblem_tilt=1.1, line_glow=1.2,
               bar_right=('#6A4A2C', '#D9B486', '#F3E0BC')),
}



DEFAULT_BASE = {'field': 0.35, 'band': 0.20, 'plate': 0.62, 'corner': 0.62, 'bar': 0.55,
                'emblem': 0.62, 'line': 0.80, 'node': 0.62}


# ── 小工具 ────────────────────────────────────────────────────────────────

def box_blur(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    if r <= 0:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode='edge'), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def gauss(a: np.ndarray, sigma: float) -> np.ndarray:
    """三次盒狀模糊近似高斯。"""
    if sigma <= 0:
        return a
    r = max(1, int(round(np.sqrt(12 * sigma * sigma / 3 + 1) / 2 - 0.5)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = box_blur(box_blur(out, r, 0), r, 1)
    return out


def ramp(t: np.ndarray, stops: list[np.ndarray]) -> np.ndarray:
    """t（0..1）在幾個顏色之間線性內插（線性光空間）。"""
    t = np.clip(t, 0, 1)[..., None]
    n = len(stops) - 1
    x = t * n
    i = np.clip(np.floor(x).astype(int), 0, n - 1)
    f = x - i
    cs = np.stack(stops)
    return cs[i[..., 0]] * (1 - f) + cs[np.clip(i[..., 0] + 1, 0, n)] * f


def brush_noise(shape, deg_field: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """拉絲：沿拉絲方向幾乎不變、垂直方向隨機的條紋（每個方向各一條 1D 雜訊），標準化到 ±1。"""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    out = np.zeros(shape, np.float32)
    n1d = rng.standard_normal(6000).astype(np.float32)
    k = np.exp(-0.5 * (np.arange(-3, 4) / 1.1) ** 2)
    n1d = np.convolve(n1d, k / k.sum(), mode='same')
    n1d /= n1d.std()
    coarse = rng.standard_normal(600).astype(np.float32)
    kc = np.exp(-0.5 * (np.arange(-12, 13) / 5.0) ** 2)
    coarse = np.convolve(coarse, kc / kc.sum(), mode='same')
    coarse /= coarse.std()
    for deg in np.unique(deg_field[deg_field >= 0]):
        sel = deg_field == deg
        th = np.radians(deg)
        u = -xx[sel] * np.sin(th) + yy[sel] * np.cos(th)  # 垂直拉絲方向的座標
        v = xx[sel] * np.cos(th) + yy[sel] * np.sin(th)
        fine = np.interp(u * 1.0 + 3000, np.arange(6000), n1d)
        long = np.interp(v / 40.0 + 300, np.arange(600), coarse)  # 沿拉絲方向很慢的起伏
        out[sel] = 0.8 * fine + 0.2 * long * fine
    return out


def aces(x):
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip((x * (a * x + b)) / (x * (c * x + d) + e), 0, 1)


# ── 渲染 ──────────────────────────────────────────────────────────────────

def normals(height: np.ndarray, k: float = 7.0) -> np.ndarray:
    hs = gauss(height, 0.7)
    gy, gx = np.gradient(hs)
    n = np.dstack([-k * gx, -k * gy, np.ones_like(hs)])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def smoke_texture(shape: tuple[int, int]) -> np.ndarray:
    """原卡背的煙霧質感（V3 底圖的低頻亮度，線條先挖掉再用正規化卷積補起來），標準化到約 ±1。
    只取低頻，放大到畫布不會變糊；沿用原圖的「霧」而不是另外生成。"""
    base = ROOT / 'assets/images/practice/practice_draw_card_back_v3_base.webp'
    if not base.exists():
        return np.zeros(shape, np.float32)
    lum = np.asarray(Image.open(base).convert('L'), np.float32) / 255.0
    art = np.zeros_like(lum)
    for name in ('emblem_mask', 'lines_mask', 'frame_mask'):
        a = np.asarray(Image.open(ROOT / f'assets/images/practice/practice_draw_card_back_v3_{name}.webp'))
        art = np.maximum(art, a[..., 3].astype(np.float32) / 255.0)
    keep = (art < 0.08).astype(np.float32)
    keep = 1 - np.clip(gauss(1 - keep, 2.0) * 3, 0, 1)  # 線條旁邊的光暈也挖掉
    num = gauss(lum * keep, 5.0)
    den = gauss(keep, 5.0)
    smooth = num / np.maximum(den, 1e-3)
    im = Image.fromarray(smooth.astype(np.float32), 'F').resize((shape[1], shape[0]), Image.BICUBIC)
    sm = np.asarray(im, np.float32)
    med = float(np.median(sm))
    hi = float(np.percentile(sm, 95))
    return np.clip((sm - med) / max(hi - med, 1e-3), -1.0, 2.0)


def soft_clip(x: np.ndarray, knee: float = 0.7) -> np.ndarray:
    """暗部、中間調照原值；超過 knee 的亮部平滑壓到 1 以下（只壓加上去的高光與泛光）。"""
    over = np.maximum(x - knee, 0)
    return np.where(x <= knee, x, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))))


def shade(hfm: dict, tier: Tier, rng_seed: int = SEED,
          smoke: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """回傳 (成品 sRGB 0..1, 右上光的打光差 −1..1)。顏色坡度是目標 sRGB 色，光只決定落在
    坡度的哪裡；高光、倒角亮線、泛光另外疊上去，最後只把亮部柔和壓回 1。"""
    H = hfm['height']
    mat = hfm['material']
    h, w = H.shape
    rng = np.random.default_rng(rng_seed)
    n = normals(H)
    ndl1 = np.clip(n @ L1, 0, 1)
    ndl2 = np.clip(n @ L2, 0, 1)
    ndl_alt = np.clip(n @ L_ALT, 0, 1)
    flat = float(L1[2])
    tilt = ndl1 - flat  # 平面＝0；朝光的斜面 > 0、背光 < 0

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    pos = 1.0 - (0.55 * xx / w + 0.45 * yy / h)  # 左上 1、右下 0
    softbox = np.exp(-(((xx / w) - 0.12 + 1.6 * n[..., 0]) ** 2 / 0.05 +
                       ((yy / h) - 0.10 + 1.6 * n[..., 1]) ** 2 / 0.04))
    strip = 0.6 * np.exp(-((xx / w - 0.93 - 1.2 * n[..., 0]) ** 2) / 0.002)

    brush = brush_noise(H.shape, hfm['brush'], rng)
    ao = np.clip(1 - 1.4 * (gauss(H, 10 * w / 1200) - H), 0.55, 1.0)
    lap = (np.roll(H, 1, 0) + np.roll(H, -1, 0) + np.roll(H, 1, 1) + np.roll(H, -1, 1) - 4 * H)
    edge_lit = np.clip(-lap * 14, 0, 1) * np.clip(tilt * 5, 0, 1)

    base = {**DEFAULT_BASE, **(tier.base or {})}
    hi_col = srgb_to_lin(hexc(tier.hi_color or tier.plate[2]))  # 反光染成該階的亮色

    def metal(stops, b, k_tilt, k_pos, k_env, strength):
        t = b + k_tilt * tilt + k_pos * (pos - 0.5) + k_env * (softbox + strip) + strength * brush
        c = ramp(t, [srgb_to_lin(hexc(s)) for s in stops])
        gloss = tier.hi * (1 - tier.rough) * np.clip(softbox + strip, 0, 1) * (1 + 0.8 * brush)
        return c + gloss[..., None] * hi_col[None, None]

    # 底面：兩色坡度（暗部 → 中間調），稜面高一階、原卡背的煙霧質感、左上一道清漆反光
    fd, fm = (srgb_to_lin(hexc(s)) for s in tier.field)
    sm = smoke if smoke is not None else np.zeros_like(H)
    facet = np.clip(H / 0.04, -1, 1) * (mat == hf.MAT_FIELD)
    ft = np.clip(base['field'] + 0.30 * facet + 0.85 * sm + 0.25 * (pos - 0.5), 0, 1.8)
    col = fd[None, None] * (1 - ft[..., None]) + fm[None, None] * ft[..., None]
    lacquer = np.exp(-((xx / w * 0.9 + yy / h * 0.55 - 0.42) ** 2) / 0.006)
    col += (0.012 * lacquer)[..., None]

    groups = [
        # 材質, 坡度, base, 傾斜, 位置, 環境, 拉絲
        (hf.MAT_BAND, tier.band, base['band'], 1.6, 0.20, 0.12, tier.brush * 0.6),
        (hf.MAT_PLATE, tier.plate, base['plate'], 1.6, 0.30, 0.12, tier.brush),
        (hf.MAT_CORNER, tier.plate, base['corner'], 1.6, 0.30, 0.12, tier.brush),
        (hf.MAT_BAR, tier.bar, base['bar'], 1.6, 0.10, 0.12, tier.brush),
        (hf.MAT_EMBLEM, tier.emblem, base['emblem'], tier.emblem_tilt, 0.25, 0.12, tier.brush * 0.6),
        (hf.MAT_LINE, tier.emblem, base['line'], 1.2, 0.20, 0.2, 0.0),
        (hf.MAT_NODE, tier.emblem, base['node'], 1.6, 0.20, 0.2, 0.0),
    ]
    for m, stops, b, kt, kp, ke, bs in groups:
        sel = mat == m
        if not sel.any():
            continue
        c = metal(stops, b, kt, kp, ke, bs)
        if m == hf.MAT_BAR and tier.bar_right:
            right = metal(tier.bar_right, b, kt, kp, ke, bs)
            f = np.clip(xx / w, 0, 1)[..., None]
            c = c * (1 - f) + right * f
        col[sel] = c[sel]

    etch = hfm['etch'] * (mat == hf.MAT_FIELD)
    col *= (1 - 0.45 * etch)[..., None]
    col += (0.08 * etch * np.clip(tilt * 5, 0, 1))[..., None]

    col *= ao[..., None]
    col += (tier.edge * edge_lit * (hfm['spec'] > 0))[..., None] * hi_col[None, None]

    if tier.holo > 0:
        # 膜厚：沿 115° 的平滑漸變（週期約 0.35×卡寬）加一點低頻起伏，色帶是一道道斜的光澤，不是斑點
        noise = gauss(rng.standard_normal((h, w)).astype(np.float32), 80 * w / 1200)
        noise /= max(float(noise.std()), 1e-6)
        ang = np.radians(115)
        phase = (xx * np.sin(ang) - yy * np.cos(ang)) / (0.35 * w)
        thick = 420 + 160 * np.sin(2 * np.pi * phase + 0.6 * np.clip(noise, -2, 2))
        cos_t = np.clip(n[..., 2], 0.2, 1)
        lum = col.mean(axis=2)
        rl = [0.5 + 0.5 * np.cos(2 * np.pi * 2 * 1.45 * thick * cos_t / lam) for lam in (650, 532, 450)]
        holo_c = np.dstack(rl) * (lum * 1.4 + 0.1)[..., None]
        side = 0.25 + 0.75 * np.clip((xx / w - 0.35) / 0.65, 0, 1)
        node_w = np.where(mat == hf.MAT_NODE, 0.3, 1.0)
        m = (hfm['holo'] * tier.holo * side * node_w)[..., None]
        col = col * (1 - m) + holo_c * m

    gc = srgb_to_lin(hexc(tier.glow))
    gm = hfm['glow']
    emit = (0.6 * gm[..., 0] + 0.3 * gm[..., 1] + tier.line_glow * gm[..., 2]) * tier.glow_k
    sc = w / 1200
    bloom = 0.7 * gauss(emit, 4 * sc) + 0.45 * gauss(emit, 14 * sc) + 0.25 * gauss(emit, 40 * sc)
    col += (bloom * 0.22)[..., None] * gc[None, None]

    out = lin_to_srgb(soft_clip(col))
    relief = (ndl_alt - ndl1) * (hfm['spec'] > 0)
    return out.astype(np.float32), relief.astype(np.float32)


def encode(img: Image.Image, **kw) -> bytes:
    buf = io.BytesIO()
    img.save(buf, 'WEBP', **kw)
    return buf.getvalue()


def render(out_dir: Path, preview: Path | None = None, scale: float = 1.0) -> dict[str, int]:
    """scale < 1 只給測試用（快速驗證重跑一致）；正式素材一律 1.0。"""
    hfm = hf.build(scale=scale)
    smoke = smoke_texture(hfm['height'].shape)
    sizes = {}
    relief = None
    for name, tier in TIERS.items():
        rgb, rel = shade(hfm, tier, smoke=smoke)
        relief = rel if relief is None else relief
        im = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')
        data = encode(im, quality=90, method=6)
        (out_dir / f'practice_card_back_v4_{name}.webp').write_bytes(data)
        sizes[name] = len(data)
        if preview:
            im.save(preview / f'back_{name}.png')
    light = np.dstack([np.clip(0.5 + 0.5 * relief, 0, 1), hfm['holo'], hfm['spec']])
    data = encode(Image.fromarray((light * 255 + 0.5).astype(np.uint8), 'RGB'), lossless=True)
    (out_dir / 'practice_card_back_v4_light.webp').write_bytes(data)
    sizes['light'] = len(data)
    hh, ww = hfm['height'].shape
    gm = np.asarray(Image.fromarray((np.clip(hfm['glow'], 0, 1) * 255).astype(np.uint8), 'RGB')
                    .resize((ww // 2, hh // 2), Image.LANCZOS))
    data = encode(Image.fromarray(gm, 'RGB'), lossless=True)
    (out_dir / 'practice_card_back_v4_glowmask.webp').write_bytes(data)
    sizes['glowmask'] = len(data)
    halo = gauss(hfm['glow'][..., 0], 24 * scale)
    halo = np.clip(halo / max(float(halo.max()), 1e-6), 0, 1)
    rgba = np.dstack([np.ones_like(halo)] * 3 + [halo])
    im = Image.fromarray((rgba * 255).astype(np.uint8), 'RGBA').resize((ww // 2, hh // 2),
                                                                        Image.LANCZOS)
    data = encode(im, quality=85, method=6)
    (out_dir / 'practice_card_back_v4_glow.webp').write_bytes(data)
    sizes['glow'] = len(data)
    rng = np.random.default_rng(SEED + 1)
    tile = rng.standard_normal((128, 128)).astype(np.float32)
    tile = np.clip(0.5 + 0.18 * tile, 0, 1)
    data = encode(Image.fromarray((tile * 255).astype(np.uint8), 'L'), lossless=True)
    (out_dir / 'practice_card_noise.webp').write_bytes(data)
    sizes['noise'] = len(data)
    return sizes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--out', type=Path, default=OUT)
    parser.add_argument('--preview', type=Path, default=None)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
    sizes = render(args.out, args.preview)
    for k, v in sizes.items():
        print(f'{k}: {v / 1024:.0f} KiB')


if __name__ == '__main__':
    main()
