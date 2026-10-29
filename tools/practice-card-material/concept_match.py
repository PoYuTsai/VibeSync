"""成品圖對示意圖目標色的區域色差表（典藏材質規格 §5.5）。

  python3 tools/practice-card-material/concept_match.py --still build/card_back_stills/back_sr.png [--tier sr]
      [--concept <示意圖單張卡背，本機私有>]

一定輸出：各區域的實測色、目標色、CIEDE2000 色差，超過門檻標 ✗；再加紋理指標（#114 Gate-2a
第 2 輪：色差只管顏色接近，管不到質感）：底面細顆粒、霧面、平均亮度，徽記三面明暗比，拉絲連續性。
有給 --concept 時另外輸出並排對照圖（不入庫）。門檻只是提示，最後以 Eric 目視為準。
只依賴 numpy＋Pillow。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
TARGETS = HERE / 'targets.json'
LIGHT = HERE.parents[1] / 'assets/images/practice/practice_card_back_v4_light.webp'
LUMA = np.array([0.2126, 0.7152, 0.0722])


def hex_rgb(s: str) -> np.ndarray:
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float64) / 255.0


def to_hex(c) -> str:
    c = np.clip(np.round(np.asarray(c) * 255), 0, 255).astype(int)
    return '#' + ''.join(f'{v:02X}' for v in c)


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB（0..1）→ CIELAB（D65）。"""
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > (6 / 29) ** 3, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])], axis=-1)


def delta_e2000(lab1: np.ndarray, lab2: np.ndarray) -> float:
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    dhp = h2p - h1p
    if C1p * C2p == 0:
        dhp = 0
    elif dhp > 180:
        dhp -= 360
    elif dhp < -180:
        dhp += 360
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp / 2))
    Lpm, Cpm = (L1 + L2) / 2, (C1p + C2p) / 2
    hpm = h1p + h2p
    if C1p * C2p != 0:
        hpm = (h1p + h2p + 360) / 2 if abs(h1p - h2p) > 180 else (h1p + h2p) / 2
        if abs(h1p - h2p) > 180 and h1p + h2p >= 360:
            hpm -= 360
    T = (1 - 0.17 * np.cos(np.radians(hpm - 30)) + 0.24 * np.cos(np.radians(2 * hpm)) +
         0.32 * np.cos(np.radians(3 * hpm + 6)) - 0.20 * np.cos(np.radians(4 * hpm - 63)))
    dtheta = 30 * np.exp(-(((hpm - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cpm ** 7 / (Cpm ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lpm - 50) ** 2 / np.sqrt(20 + (Lpm - 50) ** 2)
    Sc = 1 + 0.045 * Cpm
    Sh = 1 + 0.015 * Cpm * T
    Rt = -np.sin(np.radians(2 * dtheta)) * Rc
    return float(np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 +
                         Rt * (dCp / Sc) * (dHp / Sh)))


def region_stat(img: np.ndarray, rect, stat: str) -> np.ndarray:
    h, w = img.shape[:2]
    x0, y0, x1, y1 = rect
    px = img[int(y0 * h):max(int(y1 * h), int(y0 * h) + 1),
             int(x0 * w):max(int(x1 * w), int(x0 * w) + 1)].reshape(-1, 3)
    lum = px @ np.array([0.2126, 0.7152, 0.0722])
    order = np.argsort(lum)
    if stat == 'median':
        return np.median(px, axis=0)
    if stat in ('top3', 'top15'):
        k = max(1, int(len(px) * (0.03 if stat == 'top3' else 0.15)))
        return px[order[-k:]].mean(axis=0)
    if stat == 'p35':
        i = int(len(px) * 0.35)
        return px[order[max(0, i - len(px) // 20):i + len(px) // 20 + 1]].mean(axis=0)
    raise ValueError(stat)


def match(still: np.ndarray, tier: str, targets: dict | None = None) -> list[dict]:
    targets = targets or json.loads(TARGETS.read_text())
    rows = []
    for name, reg in targets['regions'].items():
        got = region_stat(still, reg['rect'], reg['stat'])
        want = hex_rgb(targets['targets'][tier][name])
        de = delta_e2000(rgb_to_lab(got), rgb_to_lab(want))
        rows.append({'region': name, 'got': to_hex(got), 'want': to_hex(want),
                     'de': round(de, 2), 'ok': de <= reg['limit'], 'limit': reg['limit']})
    return rows


def holo_region(size: tuple[int, int]) -> np.ndarray:
    """全息區＝`light` 素材的 G 通道（倒角、側飾條外緣、節點切面、細線兩側；§5.3），縮到 [size]（寬, 高）
    後取 > 0.5。"""
    g = Image.open(LIGHT).convert('RGB').getchannel('G').resize(size, Image.BILINEAR)
    return np.asarray(g) > 127


def hue_between(hue: np.ndarray, start: float, end: float) -> np.ndarray:
    """色相（度）落在從 [start] 往上走到 [end] 的範圍；end 比 start 小時跨過 360°。"""
    return (hue >= start) & (hue <= end) if start <= end else (hue >= start) | (hue <= end)


def holo_hues(still: np.ndarray, targets: dict | None = None, region: np.ndarray | None = None) -> dict:
    """SR 全息（§5.5）：全息區裡有顏色（飽和度 > 0.25、亮度 > 0.45；§2.2 的四個全息色飽和度 0.30–0.52，
    玫瑰與天空藍最淡）而且色相落在 targets.json `holo.hue_range_deg`（天空藍往上繞到玫瑰）的像素，佔全息區
    的比例，對 `holo.share` 判定；另回傳全息區裡有顏色的像素的色相分布（每格 30°，香檳金也在裡面）。
    [region] 預設 [holo_region]。"""
    targets = targets or json.loads(TARGETS.read_text())
    holo = targets['holo']
    hsv = np.asarray(Image.fromarray((still * 255).astype(np.uint8)).convert('HSV'), np.float64)
    hue = hsv[..., 0] / 255 * 360
    if region is None:
        region = holo_region((still.shape[1], still.shape[0]))
    colored = region & (hsv[..., 1] / 255 > 0.25) & (hsv[..., 2] / 255 > 0.45)
    share = float((colored & hue_between(hue, *holo['hue_range_deg'])).sum() / max(1, region.sum()))
    lo, hi = holo['share']
    return {'share': share, 'want': [lo, hi], 'ok': lo <= share <= hi,
            'hues': np.histogram(hue[colored], bins=12, range=(0, 360))[0].tolist()}


# ── 紋理指標（§5.5，#114 Gate-2a 第 2 輪）────────────────────────────────────

def _blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """可分離高斯（邊緣反射）。"""
    r = max(1, int(np.ceil(3 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = np.pad(a, r, mode='reflect')
    out = sum(k[i] * out[i:i + a.shape[0], :] for i in range(2 * r + 1))
    return sum(k[i] * out[:, i:i + a.shape[1]] for i in range(2 * r + 1))


def luma(img: np.ndarray, width: int) -> np.ndarray:
    """sRGB（0..1）→ 卡寬縮到 width px 的亮度（0..255）。"""
    h = round(width * img.shape[0] / img.shape[1])
    im = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((width, h), Image.LANCZOS)
    return np.asarray(im, np.float64) @ LUMA


def field_texture(img: np.ndarray, regions, width: int = 410) -> dict:
    """純底面區域（卡寬 410 px，約手機上卡片的 pt 寬）：細顆粒＝σ1 高通的標準差、霧面＝σ1–σ8 帶通的
    標準差、平均亮度；三個區域取平均。"""
    lum = luma(img, width)
    h, w = lum.shape
    fine, haze, mean = [], [], []
    for x0, y0, x1, y1 in regions:
        r = lum[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)]
        b1, b8 = _blur(r, 1.0), _blur(r, 8.0)
        fine.append((r - b1)[4:-4, 4:-4].std())
        haze.append((b1 - b8)[8:-8, 8:-8].std())
        mean.append(r.mean())
    return {'fine': float(np.mean(fine)), 'haze': float(np.mean(haze)), 'mean': float(np.mean(mean))}


def _masks(size: tuple[int, int]) -> dict[str, np.ndarray]:
    """量測用遮罩（畫布 1200×1800 算好再縮）：徽記三面的平頂（倒角內縮 3 px）、上飾板、左右側飾條、
    卡緣暗帶左右兩段的內部。示意圖跟向量構圖的邊有幾 px 的落差，飾板、飾條、暗帶都往內縮 12–14 px，
    邊上的亮線（飾板上緣、SR 的金邊）才不會算進拉絲。"""
    import geometry as g
    import heightfield as hf
    geo = g.load()
    cover = g.rasterize(geo, layers=['emblem', 'plate', 'sidebar', 'edge-band', 'frame-line'])
    hgt, wid = cover['emblem'].shape
    yy, xx = np.mgrid[0:hgt, 0:wid]
    face = hf.emblem_face_map(geo, (hgt, wid))
    inner = hf.chamfer_distance(cover['emblem'], 12) >= 11  # 倒角 8 px＋3 px
    plate = (hf.chamfer_distance(cover['plate'], 16) >= 14) & (yy < hgt / 2)
    bar = (hf.chamfer_distance(cover['sidebar'], 14) >= 12) & (cover['plate'] < 0.5)
    band = (hf.chamfer_distance(cover['edge-band'], 14) >= 12) & (cover['frame-line'] < 0.5) & \
        (cover['sidebar'] < 0.5) & (np.abs(yy - hgt / 2) < 0.38 * hgt) & (np.abs(yy - hgt / 2) > 0.16 * hgt)
    raw = {'face-top': inner & (face == hf.FACE_TOP), 'face-left': inner & (face == hf.FACE_LEFT),
           'face-right': inner & (face == hf.FACE_RIGHT), 'plate': plate, 'bar': bar, 'band': band}
    out = {}
    for k, m in raw.items():
        im = Image.fromarray(m.astype(np.uint8) * 255).resize(size, Image.BILINEAR)
        out[k] = np.asarray(im) > 250
    return out


def emblem_faces(img: np.ndarray) -> dict:
    """徽記三個面平頂的平均亮度（0..255）與左面、右面對上面的比值。"""
    lum = img @ LUMA * 255
    m = _masks((img.shape[1], img.shape[0]))
    top, left, right = (float(lum[m[k]].mean()) for k in ('face-top', 'face-left', 'face-right'))
    return {'top': top, 'left': left, 'right': right, 'ratio': [left / top, right / top]}


def brush_continuity(img: np.ndarray, width: int = 784) -> dict:
    """拉絲連續性：上飾板、側飾條、卡緣暗帶的細節（σ3 高通），往 12 個方向各平移 6 px 的相關係數取
    最大——整條連續的直紋（第 1 輪）接近 1，示意圖那種細碎的短拉絲很低。卡寬 784 px（示意圖原圖 2 倍）；
    另回傳細節的標準差（拉絲對比）。"""
    lum = luma(img, width)
    det = lum - _blur(lum, 3.0)
    m = _masks((lum.shape[1], lum.shape[0]))
    out = {}
    for name in ('plate', 'bar', 'band'):
        sel = m[name]
        best = -1.0
        for th in np.radians(np.arange(0, 180, 15)):
            dx, dy = int(round(6 * np.cos(th))), int(round(6 * np.sin(th)))
            sh = np.roll(np.roll(det, -dy, 0), -dx, 1)
            both = sel & np.roll(np.roll(sel, -dy, 0), -dx, 1)
            a, b = det[both], sh[both]
            best = max(best, float(np.corrcoef(a, b)[0, 1]))
        out[name] = {'continuity': best, 'contrast': float(det[sel].std())}
    return out


def texture(img: np.ndarray, targets: dict | None = None) -> dict:
    targets = targets or json.loads(TARGETS.read_text())
    tex = targets['texture']
    return {'field': field_texture(img, tex['field']['regions'], tex['field']['width']),
            'faces': emblem_faces(img), 'brush': brush_continuity(img)}


def texture_rows(img: np.ndarray, tier: str, targets: dict | None = None) -> list[dict]:
    """紋理指標對示意圖：底面細顆粒、霧面在示意圖的 ±35% 內，平均亮度 ±10；徽記左右面比值 ±0.05；
    拉絲連續性 ≤ 0.6（示意圖 0.2–0.5、第 1 輪 0.97–0.99），拉絲對比在示意圖的 0.5–1.6 倍。"""
    targets = targets or json.loads(TARGETS.read_text())
    want = targets['texture']['targets'][tier]
    got = texture(img, targets)
    rows = []
    f = got['field']
    for k, tol in (('fine', 0.35), ('haze', 0.35)):
        rows.append({'name': f'field-{k}', 'got': f[k], 'want': want['field'][k],
                     'ok': abs(f[k] / want['field'][k] - 1) <= tol})
    rows.append({'name': 'field-mean', 'got': f['mean'], 'want': want['field']['mean'],
                 'ok': abs(f['mean'] - want['field']['mean']) <= 10})
    for i, side in enumerate(('left', 'right')):
        rows.append({'name': f'emblem-{side}/top', 'got': got['faces']['ratio'][i],
                     'want': want['faces'][i], 'ok': abs(got['faces']['ratio'][i] - want['faces'][i]) <= 0.05})
    for part in ('plate', 'bar', 'band'):
        b = got['brush'][part]
        rows.append({'name': f'{part}-continuity', 'got': b['continuity'], 'want': want['brush'][part][0],
                     'ok': b['continuity'] <= 0.6})
        target = want['brush'][part][1]
        if target is None:  # 示意圖沒有量到：只印實測值
            rows.append({'name': f'{part}-contrast', 'got': b['contrast'], 'want': float('nan'), 'ok': True})
            continue
        ratio = b['contrast'] / target
        rows.append({'name': f'{part}-contrast', 'got': b['contrast'], 'want': target,
                     'ok': 0.5 <= ratio <= 1.6})
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--still', type=Path, required=True)
    parser.add_argument('--tier', choices=['n', 'r', 'sr'], default=None)
    parser.add_argument('--concept', type=Path, default=None)
    parser.add_argument('--out', type=Path, default=None, help='並排對照圖（有給 --concept 時）')
    args = parser.parse_args()
    tier = args.tier or next((t for t in ('sr', 'r', 'n') if f'_{t}.' in args.still.name), 'n')
    img = np.asarray(Image.open(args.still).convert('RGB'), np.float64) / 255.0
    rows = match(img, tier)
    print(f'{args.still.name}（{tier}）')
    print(f'{"區域":<16}{"實測":>9}{"目標":>9}{"ΔE2000":>9}')
    for r in rows:
        print(f'{r["region"]:<16}{r["got"]:>9}{r["want"]:>9}{r["de"]:>9.2f} {"✓" if r["ok"] else "✗"}')
    if 'texture' in json.loads(TARGETS.read_text()):
        print(f'{"紋理":<20}{"實測":>9}{"示意圖":>9}')
        for r in texture_rows(img, tier):
            print(f'{r["name"]:<20}{r["got"]:>9.2f}{r["want"]:>9.2f} {"✓" if r["ok"] else "✗"}')
    if tier == 'sr':
        h = holo_hues(img)
        print(f'全息：玫瑰到天空藍佔全息區 {h["share"]:.1%}（示意圖 {h["want"][0]:.0%}–{h["want"][1]:.0%}）'
              f'{" ✓" if h["ok"] else " ✗"}；全息區有顏色的像素色相分布（每 30°）{h["hues"]}')
    if args.concept:
        a = Image.open(args.still).convert('RGB')
        b = Image.open(args.concept).convert('RGB')
        b = b.resize((round(b.size[0] * a.size[1] / b.size[1]), a.size[1]), Image.LANCZOS)
        sheet = Image.new('RGB', (a.size[0] + b.size[0] + 20, a.size[1]), (20, 20, 20))
        sheet.paste(a, (0, 0))
        sheet.paste(b, (a.size[0] + 20, 0))
        out = args.out or args.still.with_name(args.still.stem + '_vs_concept.jpg')
        sheet.save(out, quality=88)
        print('並排對照：', out)


if __name__ == '__main__':
    main()
