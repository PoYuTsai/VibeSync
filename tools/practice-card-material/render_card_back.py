"""卡背三階材質渲染（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §5.3–§5.4）。

  python3 tools/practice-card-material/render_card_back.py [--out assets/images/practice] [--preview DIR]

讀 card_back_geometry.json → heightfield.build() → 材質、拉絲、打光、環境遮蔽、底面霧面與顆粒、
SR 薄膜全息、自發光泛光 → sRGB，輸出：
  practice_card_back_v4_{n,r,sr}.webp   1200×1800 有損（成品圖，四角留滿，執行時圓角裁切）
  practice_card_back_v4_light.webp      1200×1800 無損 RGB：R＝浮雕補光差（0.5＝不變）、G＝全息、B＝高光
  practice_card_back_v4_glowmask.webp   600×900 無損 RGB：R＝徽記與節點、G＝外框、B＝線路
  practice_card_back_v4_glow.webp       600×900 有損 RGBA：預先模糊好的白色泛光
  practice_card_noise.webp              128×128 無損灰階：執行時顆粒、拉絲共用的雜訊磚
同一份 JSON、同一個種子，重跑逐位元相同。只依賴 numpy＋Pillow。

打光（#114 第 3 輪）：攝影棚四盞燈（正前方偏左上的大柔光箱、左上主光、右側燈條、右下弱補光）＋暗棚
環境，相機在有限距離（平面上每一點的反射方向略有不同，金屬面自然有左上亮、右下暗的漸層）。每種材質
各自一組反光寬窄（反射方向的散開，沿拉絲與橫過拉絲分開給），反光寬的就柔、峰值低，窄的就銳利集中：
- 石墨底面：很寬很柔的反光，顆粒與霧面只在底面；
- 拉絲金屬（飾板、側飾條、四角、卡緣暗帶、徽記頂面）：橫過拉絲方向散開、沿拉絲方向集中，細碎的拉絲
  紋讓反光有細微的方向性變化（微法線），中間調也帶一點紋理；
- 拋光倒角、線路、節點：很窄的反光，只在對到燈的地方亮一道細線。
"""

from __future__ import annotations

import argparse
import io
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

import heightfield as hf

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/images/practice'
V3 = ROOT / 'docs/archive/practice-draw-v3'  # V3 卡背（煙霧質感的來源；已移出 app）
SEED = 20261028


def _unit(*v) -> np.ndarray:
    a = np.array(v, np.float32)
    return a / np.linalg.norm(a)


L1 = _unit(-0.55, -0.62, 0.56)  # 左上主光（浮雕補光差用）
L_ALT = _unit(0.55, -0.62, 0.56)  # 浮雕補光用的右上光


@dataclass(frozen=True)
class Light:
    """攝影棚燈：方向（x 右、y 下、z 朝觀者）、角大小（σx、σy，弧度）、強度。"""
    name: str
    direction: tuple[float, float, float]
    size: tuple[float, float]
    power: float


LIGHTS = (
    Light('front', (-0.20, -0.30, 1.0), (0.42, 0.34), 1.0),  # 相機上方偏左的大柔光箱：平面金屬的中間調
    Light('key', (-0.55, -0.62, 0.56), (0.20, 0.20), 1.4),   # 左上主光：朝左上的倒角亮
    Light('strip', (0.82, -0.08, 0.57), (0.05, 0.50), 0.9),  # 右側直立燈條：朝右的倒角一道細亮
    Light('fill', (0.30, 0.55, 0.78), (0.35, 0.35), 0.18),   # 右下弱補光：背光面不死黑
)
AMBIENT = 0.02  # 暗棚
CAM_DIST = 2.4  # 相機距離（卡片高度的倍數）


@dataclass(frozen=True)
class Lobe:
    """材質的反光：沿拉絲（along）與橫過拉絲（across）的散開（弧度），強度（gain）。"""
    along: float
    across: float
    gain: float


LOBES = {
    hf.MAT_FIELD: Lobe(0.55, 0.55, 0.012),  # 石墨霧面：寬、柔、很弱（底面要留住深黑）
    hf.MAT_BAND: Lobe(0.10, 0.32, 0.04),    # 槍鐵暗帶：拉絲，偏暗
    hf.MAT_PLATE: Lobe(0.07, 0.28, 0.55),   # 飾板：拉絲
    hf.MAT_CORNER: Lobe(0.07, 0.28, 0.55),
    hf.MAT_BAR: Lobe(0.07, 0.28, 0.50),     # 側飾條：直向拉絲
    hf.MAT_EMBLEM: Lobe(0.08, 0.30, 0.60),  # 徽記頂面：各面沿等角軸拉絲
    hf.MAT_LINE: Lobe(0.045, 0.045, 0.70),  # 線路、星軌：拋光
    hf.MAT_NODE: Lobe(0.04, 0.04, 0.55),    # 節點切面：拋光（四個面各自對不同的燈，亮暗分得出來）
}
POLISHED = Lobe(0.035, 0.035, 1.10)  # 倒角、斜面：拋光，窄而集中


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
    glow: str
    glow_k: float
    holo: float
    base: dict = None  # 每種材質落在坡度的哪裡（calibrate.py 對 targets.json 校準）
    spec: float = 1.0  # 這一階反光的整體強度（染成該階的亮色）
    line_glow: float = 0.8  # 線路的自發光
    bar_right: tuple = None  # 右側飾條的坡度（R：陽極鈦干涉色，左藍紫 → 右天藍）；None＝同左側
    corner: tuple = None  # 四角飾板的坡度（R：示意圖的四角偏青）；None＝同飾板
    hi_color: str = None  # 反光的顏色；None＝飾板坡度的亮色
    faces: tuple = (0.05, 0.13)  # 徽記上面亮多少、右面暗多少（坡度單位；左面是基準）
    grain: float = 0.22  # 底面細顆粒（乘在底面顏色上，暗部自然變弱；三個候選比過，見規格 §16.3）
    haze: float = 0.05  # 底面霧面變化（兩個候選比過：0.07＋煙霧 0.12 正常尺寸看得到雲霧斑）


# §5.3 三階材質參數（坡度取自 2026-10-28 可行性試算；base 由 calibrate.py 校準）
TIERS = {
    'n': Tier('n', ('#59616C', '#AEB8C5', '#F2F6FA'), ('#4E5662', '#9AA5B3', '#E4EBF3'),
              ('#5E6672', '#C9D2DD', '#FFFFFF'), ('#15171A', '#3A3F46', '#8E959F'),
              ('#060708', '#2A2C33'), '#DCE6F2', 0.36, 0.0,
              base={'field': 0.099, 'band': -0.596, 'plate': 0.271, 'corner': -0.596, 'bar': 0.177, 'emblem': 0.326},
              faces=(0.04, 0.20)),
    'r': Tier('r', ('#1F3F86', '#79B4F5', '#B4E0FC'), ('#2B2F8C', '#6A8DF2', '#A9C2FF'),
              ('#2C5BA8', '#9CCBFA', '#E6F7FF'), ('#0A1230', '#24387A', '#6C90D8'),
              ('#04060A', '#1C2433'), '#4FB0FF', 0.72, 0.0,
              base={'field': 0.021, 'band': -0.596, 'plate': 0.177, 'corner': -0.049, 'bar': 0.138, 'emblem': 0.154},
              spec=1.2, line_glow=1.4, bar_right=('#1F4A9C', '#6FB6FD', '#B8E6FF'), hi_color='#A8D8FF',
              corner=('#16466E', '#62CBF6', '#BDF0FF'), faces=(0.05, 0.09)),
    'sr': Tier('sr', ('#6E4E1E', '#E6C46E', '#FFEC9E'), ('#6A4520', '#CFA05C', '#EDC98A'),
               ('#7A5A26', '#F4D47E', '#FFF6CC'), ('#160F07', '#3D2F1B', '#9C7F50'),
               ('#080604', '#30261A'), '#FFC95E', 0.68, 0.32,
               base={'field': 0.162, 'band': -0.596, 'plate': 0.443, 'corner': 0.248, 'bar': 0.24, 'emblem': 0.537},
               spec=0.8, line_glow=1.2, bar_right=('#6A462A', '#E4B081', '#F7DDB5'), hi_color='#FFE9A8',
               faces=(0.04, 0.30)),
}

DEFAULT_BASE = {'field': 0.10, 'band': 0.20, 'plate': 0.62, 'corner': 0.62, 'bar': 0.55,
                'emblem': 0.62, 'line': 0.80, 'node': 0.36}


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


def _norm(a: np.ndarray, sel: np.ndarray | None = None) -> np.ndarray:
    s = float(a[sel].std()) if sel is not None and sel.any() else float(a.std())
    return (a / max(s, 1e-6)).astype(np.float32)


def smooth_noise(rng: np.random.Generator, shape, sigma: float) -> np.ndarray:
    return _norm(gauss(rng.standard_normal(shape).astype(np.float32), sigma))


def streak_tile(rng: np.random.Generator, length: float, across: float,
                shape: tuple[int, int] = (256, 2048)) -> np.ndarray:
    """拉絲紋的磚（x 沿拉絲、y 橫過拉絲，週期邊界）：白雜訊沿 x 用 σ＝長度／4 的高斯（低通，紋路
    的長度），沿 y 用 σ across 到 3×across 的帶通（只留細紋：低通的話會留下一條條寬的軟帶，看起來像
    水波而不是拉絲），FFT 濾波後標準化到單位標準差。"""
    h, w = shape
    n = rng.standard_normal(shape)
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    band = (np.exp(-2 * np.pi ** 2 * (fy * across) ** 2) -
            np.exp(-2 * np.pi ** 2 * (fy * 3 * across) ** 2))
    filt = np.exp(-2 * np.pi ** 2 * (fx * length / 4) ** 2) * band
    s = np.real(np.fft.ifft2(np.fft.fft2(n) * filt))
    return (s / s.std()).astype(np.float32)


def sample_wrap(tile: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """在週期磚上雙線性取樣（u 是 x、v 是 y）。"""
    h, w = tile.shape
    u = np.mod(u, w)
    v = np.mod(v, h)
    x0 = np.floor(u).astype(np.int32)
    y0 = np.floor(v).astype(np.int32)
    fx = (u - x0).astype(np.float32)
    fy = (v - y0).astype(np.float32)
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    return (tile[y0, x0] * (1 - fx) * (1 - fy) + tile[y0, x1] * fx * (1 - fy) +
            tile[y1, x0] * (1 - fx) * fy + tile[y1, x1] * fx * fy)


# 拉絲紋：三種長度混合（畫布 px：短 18、中 40、長 92，示意圖卡寬 784 量到 12／26／60 換算），各自
# 一點點方向差（±0.4° 以內：差太多兩層會疊出波浪狀的干涉紋）；橫向 σ 0.9 px（手機上約 0.8 px，超出顯示解析度的再細就被平均掉，不會在縮放時爬動）
STREAKS = ((18.0, 0.70, -0.4), (40.0, 0.42, 0.3), (92.0, 0.12, 0.1))
STREAK_ACROSS = 0.9


def textures(hfm: dict, seed: int = SEED) -> dict[str, np.ndarray]:
    """三階共用的紋理（固定在卡片座標、固定種子；只算一次）：
    - streak：拉絲紋（拉絲零件內單位標準差，其他地方 0）。每個零件各自一組相位（不相連的零件
      紋路不接續），方向照 hfm['brush'] 再加 ±1.2° 的緩慢飄移；乘一層慢變化的斑塊，紋路有長有短、
      局部斷續；
    - grain：底面細顆粒（σ 1–3 px 帶通）；haze：底面霧面（σ 8／22 px 的低對比起伏）。"""
    h, w = hfm['height'].shape
    sc = w / 1200
    rng = np.random.default_rng(seed + 7)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx, yy = xx / sc, yy / sc  # 畫布單位：紋理尺度不跟著解析度變
    brush, part = hfm['brush'], hfm['part']
    on = brush >= 0
    # 方向的緩慢飄移：雜訊多算一圈邊再裁掉（盒狀模糊在邊上會把邊值放大）
    m = int(3 * 150 * sc)
    wander = gauss(rng.standard_normal((h + 2 * m, w + 2 * m)).astype(np.float32), 150 * sc)[m:m + h, m:m + w]
    wander = 1.0 * wander / max(float(wander.std()), 1e-6)
    # 每個零件以自己的中心為原點旋轉（不然方向飄移乘上離原點的距離，紋路會整片歪掉），
    # 再在紋理磚上各自平移一段（相位）
    px = np.zeros((h, w), np.float32)
    py = np.zeros((h, w), np.float32)
    ou = np.zeros((h, w), np.float32)
    ov = np.zeros((h, w), np.float32)
    for pid in np.unique(part[on]):
        a, b = rng.uniform(0, 2048, 2)
        sel = part == pid
        px[sel] = xx[sel] - float(xx[sel].mean())
        py[sel] = yy[sel] - float(yy[sel].mean())
        ou[sel], ov[sel] = a, b
    base = np.radians(np.where(on, brush + wander, 0.0))
    streak = np.zeros((h, w), np.float32)
    for length, weight, jitter in STREAKS:
        tile = streak_tile(rng, length, STREAK_ACROSS)
        th = base + np.radians(jitter)
        c, s = np.cos(th), np.sin(th)
        streak += weight * sample_wrap(tile, px * c + py * s + ou, -px * s + py * c + ov)
    patch = smooth_noise(rng, (h, w), 30 * sc)
    streak *= np.clip(0.82 + 0.18 * patch, 0.4, 1.2)
    streak = np.where(on, _norm(streak, on), 0.0).astype(np.float32)
    n = rng.standard_normal((h, w)).astype(np.float32)
    grain = _norm(gauss(n, 1.0 * sc) - gauss(n, 3.0 * sc))
    haze = _norm(smooth_noise(rng, (h, w), 8 * sc) + 0.8 * smooth_noise(rng, (h, w), 22 * sc))
    return {'streak': streak, 'grain': grain, 'haze': haze}


# ── 渲染 ──────────────────────────────────────────────────────────────────

def normals(height: np.ndarray, k: float = 7.0) -> np.ndarray:
    hs = gauss(height, 0.7)
    gy, gx = np.gradient(hs)
    n = np.dstack([-k * gx, -k * gy, np.ones_like(hs)])
    return (n / np.linalg.norm(n, axis=2, keepdims=True)).astype(np.float32)


def view_vectors(shape: tuple[int, int]) -> np.ndarray:
    """相機在卡片正中前方 CAM_DIST×卡高：每一點看向相機的方向。"""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = CAM_DIST * h
    v = np.dstack([(w / 2 - xx), (h / 2 - yy), np.full((h, w), d, np.float32)])
    return v / np.linalg.norm(v, axis=2, keepdims=True)


def reflect(v: np.ndarray, n: np.ndarray) -> np.ndarray:
    return 2 * np.sum(n * v, axis=2, keepdims=True) * n - v


def environment(r: np.ndarray, along, across, theta) -> np.ndarray:
    """反射方向 r 看到的光（攝影棚燈的高斯光斑跟材質的反光散開做摺積：散開越大、光斑越寬越柔、
    峰值越低，總能量不變）。along／across／theta 可以是逐點的陣列（拉絲方向 theta，弧度）。"""
    a2, b2 = np.square(along), np.square(across)
    c, s = np.cos(theta), np.sin(theta)
    m11 = a2 * c * c + b2 * s * s
    m22 = a2 * s * s + b2 * c * c
    m12 = (a2 - b2) * c * s
    out = np.full(r.shape[:2], AMBIENT, np.float32) * (1.0 + 0.6 * np.clip(-r[..., 1], 0, 1))
    for light in LIGHTS:
        ld = _unit(*light.direction)
        sx, sy = light.size
        s11, s22, s12 = sx * sx + m11, sy * sy + m22, m12
        det = s11 * s22 - s12 * s12
        dx = r[..., 0] - ld[0]
        dy = r[..., 1] - ld[1]
        q = (s22 * dx * dx - 2 * s12 * dx * dy + s11 * dy * dy) / det
        facing = np.clip(r[..., 2] * 4 + 0.5, 0, 1)
        out += light.power * (sx * sy / np.sqrt(det)) * np.exp(-0.5 * q) * facing
    return out.astype(np.float32)


def smoke_texture(shape: tuple[int, int]) -> np.ndarray:
    """原卡背的煙霧質感（V3 底圖的低頻亮度，線條先挖掉再用正規化卷積補起來），標準化到約 ±1。
    只取低頻，放大到畫布不會變糊；沿用原圖的「霧」而不是另外生成。"""
    lum = np.asarray(Image.open(V3 / 'practice_draw_card_back_v3_base.webp').convert('L'),
                     np.float32) / 255.0
    art = np.zeros_like(lum)
    for name in ('emblem_mask', 'lines_mask', 'frame_mask'):
        a = np.asarray(Image.open(V3 / f'practice_draw_card_back_v3_{name}.webp'))
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


# 全息色序與方向（同 lib/core/theme/practice_reveal_palette.dart 的 holoRose → holoMagenta → holoPlum →
# holoSky → srHoloChampagne，與 practice_card_material.dart 的 115° 軸、週期 0.35×卡寬、停住相位 0.15）
HOLO_COLORS = ('#F6B0AC', '#F99EE6', '#8B448F', '#B1DAFE', '#FDF2AE')
HOLO_AXIS = (float(np.sin(np.radians(115))), float(-np.cos(np.radians(115))))
HOLO_PERIOD = 0.35
HOLO_PHASE = 0.15


def holo_palette(t: np.ndarray) -> np.ndarray:
    """相位 t（週期數）的全息色（sRGB），五色循環、相鄰兩色線性插值。"""
    cs = np.stack([hexc(c) for c in HOLO_COLORS])
    x = (t - np.floor(t)) * len(cs)
    i = np.floor(x).astype(int) % len(cs)
    f = (x - np.floor(x))[..., None]
    return cs[i] * (1 - f) + cs[(i + 1) % len(cs)] * f


def blend_color(base: np.ndarray, color: np.ndarray) -> np.ndarray:
    """`BlendMode.color`（W3C 非分離混色）：取 color 的色相與飽和度、base 的明度（sRGB 0..1）。"""
    lum = np.array([0.3, 0.59, 0.11], np.float32)
    c = color + (base @ lum - color @ lum)[..., None]
    lo = c.min(axis=-1, keepdims=True)
    hi = c.max(axis=-1, keepdims=True)
    l = (c @ lum)[..., None]
    c = np.where(lo < 0, l + (c - l) * l / np.maximum(l - lo, 1e-6), c)
    c = np.where(hi > 1, l + (c - l) * (1 - l) / np.maximum(hi - l, 1e-6), c)
    return np.clip(c, 0, 1)


def soft_clip(x: np.ndarray, knee: float = 0.7) -> np.ndarray:
    """暗部、中間調照原值；超過 knee 的亮部平滑壓到 1 以下（只壓加上去的高光與泛光）。"""
    over = np.maximum(x - knee, 0)
    return np.where(x <= knee, x, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))))


@dataclass
class Prepared:
    """三階共用、跟材質參數無關的中間結果（法線、反射方向、環境光、紋理）。"""
    hfm: dict
    tex: dict
    n: np.ndarray
    r_wide: np.ndarray
    env_wide: np.ndarray
    env_spec: np.ndarray
    ao: np.ndarray
    smoke: np.ndarray


# 拉絲的微法線（橫過拉絲方向的傾斜，弧度）、中間調紋理（坡度單位）
BRUSH_TILT = 0.04
BRUSH_ALBEDO = 0.025
SPEC_STREAK = 0.20
GRAIN_TILT = 0.02
ENV_K = 0.30  # 寬反光對底色坡度的影響


def prepare(hfm: dict, smoke: np.ndarray | None = None) -> Prepared:
    H = hfm['height']
    mat = hfm['material']
    h, w = H.shape
    tex = textures(hfm)
    n = normals(H)
    # 底面稜面：一片片微斜的平面
    tilt = hfm['tilt']
    n = n + np.dstack([tilt[..., 0], tilt[..., 1], np.zeros_like(tilt[..., 0])])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    v = view_vectors(H.shape)
    r_wide = reflect(v, n)
    env_wide = environment(r_wide, 0.55, 0.55, 0.0)

    # 微法線：拉絲零件橫過拉絲方向傾斜；底面加一點顆粒的起伏
    brush = hfm['brush']
    on = brush >= 0
    th = np.radians(np.where(on, brush, 0.0)).astype(np.float32)
    bx, by = -np.sin(th), np.cos(th)
    k = BRUSH_TILT * tex['streak']
    field = mat == hf.MAT_FIELD
    gk = np.where(field, GRAIN_TILT * tex['grain'], 0.0)
    nm = n + np.dstack([k * bx + gk, k * by + 0.6 * gk, np.zeros_like(k)])
    nm /= np.linalg.norm(nm, axis=2, keepdims=True)
    r = reflect(v, nm)

    along = np.zeros((h, w), np.float32)
    across = np.zeros((h, w), np.float32)
    gain = np.zeros((h, w), np.float32)
    for m, lobe in LOBES.items():
        sel = mat == m
        along[sel], across[sel], gain[sel] = lobe.along, lobe.across, lobe.gain
    slope = hfm['slope'] > 0.5
    along[slope], across[slope], gain[slope] = POLISHED.along, POLISHED.across, POLISHED.gain
    # 拉絲紋讓反光帶細微的方向性變化（沿拉絲方向一條條深淺不同），霧面、拋光面不加
    streaky = on & ~slope & (mat != hf.MAT_FIELD)
    gain = gain * np.where(streaky, np.clip(1 + SPEC_STREAK * tex['streak'], 0.2, 2.2), 1.0)
    env_spec = environment(r, along, across, th) * gain

    # 環境遮蔽：貼著零件的窄接觸陰影＋很淡的寬遮蔽（不形成黑色粗描邊）
    sc = w / 1200
    contact = gauss(H, 3.5 * sc) - H
    wide = gauss(H, 16 * sc) - H
    ao = np.clip(1 - 1.8 * contact, 0.5, 1.0) * np.clip(1 - 0.5 * wide, 0.8, 1.0)
    sm = smoke if smoke is not None else np.zeros_like(H)
    return Prepared(hfm, tex, n, r_wide, env_wide, env_spec.astype(np.float32), ao.astype(np.float32), sm)


def shade(hfm: dict, tier: Tier, smoke: np.ndarray | None = None,
          prep: Prepared | None = None) -> tuple[np.ndarray, np.ndarray]:
    """回傳 (成品 sRGB 0..1, 右上光的打光差 −1..1)。顏色坡度是目標 sRGB 色，寬反光決定落在坡度的
    哪裡（中間調）；各材質自己的反光（窄／寬、沿拉絲／橫過拉絲）另外疊上去，最後只把亮部柔和壓回 1。"""
    prep = prep or prepare(hfm, smoke)
    H = hfm['height']
    mat = hfm['material']
    h, w = H.shape
    tex = prep.tex
    n = prep.n
    base = {**DEFAULT_BASE, **(tier.base or {})}
    hi_col = srgb_to_lin(hexc(tier.hi_color or tier.plate[2]))
    sc = w / 1200
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)

    # 寬反光的相對亮度（卡片正中的平面＝0）
    ref = float(prep.env_wide[h // 2, w // 2])
    envd = prep.env_wide / max(ref, 1e-6) - 1.0

    # 徽記三個面：上面亮、右面暗（柔邊 1.5 px）
    face = hfm['face']
    w_top = gauss((face == hf.FACE_TOP).astype(np.float32), 1.5 * sc)
    w_right = gauss((face == hf.FACE_RIGHT).astype(np.float32), 1.5 * sc)
    face_t = tier.faces[0] * w_top - tier.faces[1] * w_right

    # 底面：兩色坡度（暗部 → 中間調）：稜面高一階、原卡背的煙霧（淡）、霧面起伏、寬反光
    fd, fm = (srgb_to_lin(hexc(s)) for s in tier.field)
    facet = np.clip(H / 0.04, -1, 1) * (mat == hf.MAT_FIELD)
    ft = np.clip(base['field'] + 0.18 * facet + 0.06 * prep.smoke + 0.50 * envd
                 + tier.haze * tex['haze'], 0, 1.8)
    col = fd[None, None] * (1 - ft[..., None]) + fm[None, None] * ft[..., None]
    # 細顆粒乘在底面顏色上：中間調看得出來，深黑處自然變弱
    field_m = (mat == hf.MAT_FIELD)
    col *= np.where(field_m, 1 + tier.grain * tex['grain'], 1.0)[..., None]

    groups = [
        # 材質, 坡度, base, 拉絲中間調
        (hf.MAT_BAND, tier.band, base['band'], 0.6),
        (hf.MAT_PLATE, tier.plate, base['plate'], 1.0),
        (hf.MAT_CORNER, tier.corner or tier.plate, base['corner'], 1.0),
        (hf.MAT_BAR, tier.bar, base['bar'], 1.0),
        (hf.MAT_EMBLEM, tier.emblem, base['emblem'], 0.8),
        (hf.MAT_LINE, tier.emblem, base['line'], 0.0),
        (hf.MAT_NODE, tier.emblem, base['node'], 0.0),
    ]
    for m, stops, b, bs in groups:
        sel = mat == m
        if not sel.any():
            continue
        t = b + ENV_K * envd + BRUSH_ALBEDO * bs * tex['streak']
        if m == hf.MAT_EMBLEM:
            t = t + face_t
        c = ramp(t, [srgb_to_lin(hexc(s)) for s in stops])
        if m == hf.MAT_BAR and tier.bar_right:
            right = ramp(t, [srgb_to_lin(hexc(s)) for s in tier.bar_right])
            f = np.clip(xx / w, 0, 1)[..., None]
            c = c * (1 - f) + right * f
        col[sel] = c[sel]

    # 刻度盤蝕刻：細 V 槽淡淡亮起（朝主光的槽壁），不挖暗
    etch = hfm['etch'] * field_m
    toward = np.clip((n @ L1 - float(L1[2])) * 6, 0, 1)
    col = col * (1 - 0.10 * etch)[..., None] + (etch * (0.012 + 0.03 * toward))[..., None] * hi_col

    col *= prep.ao[..., None]
    # 各材質自己的反光（拋光倒角窄而集中、拉絲沿方向散開、霧面寬而弱），染成該階的亮色
    spec = prep.env_spec * tier.spec * np.clip(prep.ao * 1.15, 0, 1)
    col += spec[..., None] * hi_col[None, None]

    if tier.holo > 0:
        # 全息：跟執行時的全息層（practice_card_material.dart `_holo`）同一組色序、同一個方向與週期
        # （沿 115° 每 0.35×卡寬一輪，相位＝停住姿態的 0.15），也用同一種疊法——只換色相與飽和度、
        # 保留原本的明暗（拉絲、倒角照樣看得到）。烘焙與執行時兩層色相一致，不會疊出第三種顏色
        # （第 1 輪用薄膜干涉公式，會出現示意圖沒有的綠）。只在全息遮罩上，右邊強、左邊弱
        srgb = lin_to_srgb(soft_clip(col))
        t = (xx * HOLO_AXIS[0] + yy * HOLO_AXIS[1]) / (HOLO_PERIOD * w) - HOLO_PHASE
        holo_c = blend_color(srgb, holo_palette(t))
        side = 0.25 + 0.75 * np.clip((xx / w - 0.35) / 0.65, 0, 1)
        node_w = np.where(mat == hf.MAT_NODE, 0.3, 1.0)
        m = (hfm['holo'] * tier.holo * side * node_w)[..., None]
        col = col * (1 - m) + srgb_to_lin(holo_c) * m

    gc = srgb_to_lin(hexc(tier.glow))
    gm = hfm['glow']
    # 節點的自發光比徽記弱（節點是金屬錐，切面要看得出來，不是一顆顆發光的燈）
    node_k = np.where(mat == hf.MAT_NODE, 0.35, 0.6)
    emit = (node_k * gm[..., 0] + 0.3 * gm[..., 1] + tier.line_glow * gm[..., 2]) * tier.glow_k
    bloom = 0.7 * gauss(emit, 4 * sc) + 0.45 * gauss(emit, 14 * sc) + 0.25 * gauss(emit, 40 * sc)
    col += (bloom * 0.22)[..., None] * gc[None, None]

    out = lin_to_srgb(soft_clip(col))
    ndl1 = np.clip(n @ L1, 0, 1)
    ndl_alt = np.clip(n @ L_ALT, 0, 1)
    relief = (ndl_alt - ndl1) * (hfm['spec'] > 0)
    return out.astype(np.float32), relief.astype(np.float32)


def spec_mask(hfm: dict, prep: Prepared) -> np.ndarray:
    """執行時高光帶的遮罩（light.B）：倒角、斜面、線路、節點 1；拉絲平頂 0.25 再乘上拉絲紋
    （高光帶掃過飾板時是一道帶方向性細紋的薄光，不是一片平的光）；底面 0。"""
    spec = hfm['spec'].copy()
    flat = (spec > 0) & (spec < 0.5) & (hfm['brush'] >= 0)
    spec[flat] = 0.25 * np.clip(1 + 0.6 * prep.tex['streak'][flat], 0.3, 1.8)
    return np.clip(spec, 0, 1)


def encode(img: Image.Image, **kw) -> bytes:
    buf = io.BytesIO()
    img.save(buf, 'WEBP', **kw)
    return buf.getvalue()


# 成品圖的 WebP 品質：q90 時底面顆粒與拉絲細紋被壓掉一部分（見規格 §16.3 的比較），q94 保留得住、
# 三張合計仍遠低於上限
QUALITY = 94


def render(out_dir: Path, preview: Path | None = None, scale: float = 1.0) -> dict[str, int]:
    """scale < 1 只給測試用（快速驗證重跑一致）；正式素材一律 1.0。"""
    hfm = hf.build(scale=scale)
    smoke = smoke_texture(hfm['height'].shape)
    prep = prepare(hfm, smoke)
    sizes = {}
    relief = None
    for name, tier in TIERS.items():
        rgb, rel = shade(hfm, tier, smoke=smoke, prep=prep)
        relief = rel if relief is None else relief
        im = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')
        data = encode(im, quality=QUALITY, method=6)
        (out_dir / f'practice_card_back_v4_{name}.webp').write_bytes(data)
        sizes[name] = len(data)
        if preview:
            im.save(preview / f'back_{name}.png')
    light = np.dstack([np.clip(0.5 + 0.5 * relief, 0, 1), hfm['holo'], spec_mask(hfm, prep)])
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
