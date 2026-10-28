"""人物照高解析（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §8）。

把 Eric 本機 upload_ready 目錄的 100 張來源 PNG 轉成長邊 1800 的 WebP（sRGB、q82、method 6、
不帶中繼資料）。來源路徑只走參數，不寫進程式（比照 convert_practice_photos.dart）。

分流（§8.2）：
1. 來源長邊 ≥ 1800：Lanczos 縮到 1800。
2. 來源長邊 < 1800：先 2× 超解析，再縮到 1800。超解析不能開臉部修復、不能用會重畫五官的生成式
   放大，所以工具不內建：用 --upscale-cmd 傳外部指令，{in}、{out} 會換成檔案路徑。沒給就用來源
   原尺寸（不放大），列進報告的例外清單。
3. 一致性檢查（只對第 2 步）：結果縮回現有 JPEG 的尺寸，跟現有 JPEG 比亮度 SSIM ≥ 0.93；
   沒過的那張改用來源原尺寸。
4. 給 Eric 目視：每頁 5 張，臉部區域（上方中間）的改前（現有 JPEG 放大到同尺寸）／改後 100% 對照。

用法（在 repo 根目錄，WSL 或雲端工作階段）：
  python3 tools/gen-practice-photos/inspect_sources.py --src <來源目錄>
  python3 tools/gen-practice-photos/make_hd_photos.py --src <來源目錄> \\
      [--out build/practice_girls_hd] [--upscale-cmd '<外部超解析指令，含 {in} {out}>']

產物先放 --out，不直接覆蓋 assets：practice_girl_NNN.webp、report.json、compare_01.jpg …。
換進 app 是另一步：把 .webp 複製到 assets/images/practice_girls/、刪掉同名 .jpg，再把
practiceGirlPhotoAsset()（practice_girl_profile.dart）的副檔名改成 .webp。
合計超過 22 MiB（§8.3）或有缺檔時結束碼 1。
測試：python3 -m unittest discover -s tools/gen-practice-photos
需要 Pillow（含 WebP、littlecms）與 numpy。
"""

from __future__ import annotations

import argparse
import io
import json
import shlex
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms, ImageDraw, ImageFont

TARGET_LONG_EDGE = 1800  # §8.1（M3 A）
WEBP_QUALITY = 82
WEBP_METHOD = 6
SSIM_MIN = 0.93  # §8.2 第 4 步
SIZE_BUDGET = 22 * 1024 * 1024  # §8.3
PER_PAGE = 5
# 臉部大約落在照片上方中間（照片是直幅、顯示時 topCenter 對齊）：相對寬高的裁切框。
FACE_BOX = (0.22, 0.10, 0.78, 0.42)


def photo_ids(count: int) -> list[str]:
    return [f'practice_girl_{n:03d}' for n in range(1, count + 1)]


def to_srgb(im: Image.Image) -> Image.Image:
    """有內嵌色彩描述檔就轉成 sRGB；最後一律是不帶中繼資料的 RGB。"""
    icc = im.info.get('icc_profile')
    if icc:
        src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
        dst = ImageCms.createProfile('sRGB')
        im = ImageCms.profileToProfile(im.convert('RGB'), src, dst, outputMode='RGB')
    out = im.convert('RGB')
    out.info = {}
    return out


def resize_long_edge(im: Image.Image, target: int) -> Image.Image:
    """長邊縮到 [target]（Lanczos）；本來就不大於 target 的不放大。"""
    w, h = im.size
    long_edge = max(w, h)
    if long_edge <= target:
        return im
    scale = target / long_edge
    return im.resize((round(w * scale), round(h * scale)), Image.LANCZOS)


def _gaussian_blur(x: np.ndarray, sigma: float = 1.5, radius: int = 5) -> np.ndarray:
    """可分離高斯（valid 區域），給 SSIM 用。"""
    k = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
    k /= k.sum()
    n = 2 * radius + 1
    rows = sum(k[i] * x[i:x.shape[0] - n + 1 + i, :] for i in range(n))
    return sum(k[i] * rows[:, i:rows.shape[1] - n + 1 + i] for i in range(n))


def ssim(a: Image.Image, b: Image.Image) -> float:
    """兩張同尺寸圖的亮度 SSIM（高斯窗 σ 1.5、11×11，Wang et al. 2004 的常數）。"""
    if a.size != b.size:
        raise ValueError(f'尺寸不同：{a.size} vs {b.size}')
    x = np.asarray(a.convert('L'), dtype=np.float64)
    y = np.asarray(b.convert('L'), dtype=np.float64)
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    mx, my = _gaussian_blur(x), _gaussian_blur(y)
    sxx = _gaussian_blur(x * x) - mx * mx
    syy = _gaussian_blur(y * y) - my * my
    sxy = _gaussian_blur(x * y) - mx * my
    num = (2 * mx * my + c1) * (2 * sxy + c2)
    den = (mx * mx + my * my + c1) * (sxx + syy + c2)
    return float(np.mean(num / den))


def run_upscaler(cmd: str, src: Path, workdir: Path) -> Image.Image:
    """跑外部 2× 超解析指令（{in}、{out} 換成路徑），讀回結果。"""
    out = workdir / f'{src.stem}_x2.png'
    args = [part.format(**{'in': str(src), 'out': str(out)}) for part in shlex.split(cmd)]
    subprocess.run(args, check=True, capture_output=True)
    with Image.open(out) as im:
        return im.copy()


def encode_webp(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=WEBP_QUALITY, method=WEBP_METHOD)
    return buf.getvalue()


def convert_one(src: Path, current: Path | None, upscale_cmd: str | None,
                workdir: Path) -> tuple[Image.Image, dict]:
    """一張來源 → (成品, 報告列)。route：downscale／upscaled／native。"""
    with Image.open(src) as raw:
        source = to_srgb(raw)
    if max(source.size) >= TARGET_LONG_EDGE:
        return resize_long_edge(source, TARGET_LONG_EDGE), {'route': 'downscale', 'ssim': None}

    if upscale_cmd is None:
        return source, {'route': 'native', 'ssim': None, 'reason': '沒給 --upscale-cmd'}

    upscaled = resize_long_edge(to_srgb(run_upscaler(upscale_cmd, src, workdir)),
                                TARGET_LONG_EDGE)
    if current is None or not current.exists():
        return source, {'route': 'native', 'ssim': None, 'reason': '沒有現有 JPEG 可比'}
    with Image.open(current) as cur:
        reference = cur.convert('RGB')
    score = ssim(upscaled.resize(reference.size, Image.LANCZOS), reference)
    if score < SSIM_MIN:
        return source, {'route': 'native', 'ssim': score, 'reason': f'SSIM {score:.3f} < {SSIM_MIN}'}
    return upscaled, {'route': 'upscaled', 'ssim': score}


def _label_font():
    try:
        return ImageFont.load_default(size=28)
    except TypeError:  # Pillow < 10.1
        return ImageFont.load_default()


def compare_pages(rows: list[tuple[str, Image.Image, Image.Image | None, str]],
                  out_dir: Path) -> list[Path]:
    """臉部區域改前／改後 100% 對照：每頁 PER_PAGE 張，左改前（現有 JPEG 放大到同尺寸）、右改後。"""
    font = _label_font()
    pages = []
    for page_no, start in enumerate(range(0, len(rows), PER_PAGE), start=1):
        tiles = []
        for photo_id, after, before, route in rows[start:start + PER_PAGE]:
            w, h = after.size
            box = (round(FACE_BOX[0] * w), round(FACE_BOX[1] * h),
                   round(FACE_BOX[2] * w), round(FACE_BOX[3] * h))
            a = after.crop(box)
            b = (before.resize(after.size, Image.LANCZOS).crop(box)
                 if before is not None else Image.new('RGB', a.size, (40, 40, 40)))
            tiles.append((f'{photo_id}  {route}  {w}x{h}', b, a))
        cw = max(t[1].size[0] for t in tiles)
        ch = max(t[1].size[1] for t in tiles)
        label = 40
        sheet = Image.new('RGB', (2 * cw + 30, len(tiles) * (ch + label + 10) + 10), (14, 13, 20))
        draw = ImageDraw.Draw(sheet)
        y = 10
        for text, b, a in tiles:
            draw.text((10, y + 4), f'{text}   (left: current JPEG, right: new)', font=font,
                      fill=(235, 235, 240))
            sheet.paste(b, (10, y + label))
            sheet.paste(a, (20 + cw, y + label))
            y += ch + label + 10
        path = out_dir / f'compare_{page_no:02d}.jpg'
        sheet.save(path, quality=88)
        pages.append(path)
    return pages


def make_all(src: Path, current_dir: Path, out_dir: Path, count: int,
             upscale_cmd: str | None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    report: dict = {'photos': {}, 'missing': [], 'total_bytes': 0}
    compare_rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for photo_id in photo_ids(count):
            source = src / f'{photo_id}.png'
            if not source.exists():
                report['missing'].append(photo_id)
                continue
            current = current_dir / f'{photo_id}.jpg'
            image, row = convert_one(source, current, upscale_cmd, Path(tmp))
            data = encode_webp(image)
            (out_dir / f'{photo_id}.webp').write_bytes(data)
            row.update({'size': list(image.size), 'bytes': len(data)})
            report['photos'][photo_id] = row
            report['total_bytes'] += len(data)
            before = None
            if current.exists():
                with Image.open(current) as cur:
                    before = cur.convert('RGB')
            compare_rows.append((photo_id, image, before, row['route']))
    report['exceptions'] = sorted(
        pid for pid, row in report['photos'].items() if max(row['size']) != TARGET_LONG_EDGE)
    report['compare_pages'] = [p.name for p in compare_pages(compare_rows, out_dir)]
    report['over_budget'] = report['total_bytes'] > SIZE_BUDGET
    (out_dir / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--src', required=True, type=Path, help='來源 PNG 目錄')
    parser.add_argument('--current', type=Path, default=Path('assets/images/practice_girls'),
                        help='現有 JPEG 目錄（一致性檢查與對照圖用）')
    parser.add_argument('--out', type=Path, default=Path('build/practice_girls_hd'))
    parser.add_argument('--count', type=int, default=100)
    parser.add_argument('--upscale-cmd', default=None,
                        help="外部 2× 超解析指令，{in}、{out} 換成檔案路徑")
    args = parser.parse_args()

    report = make_all(args.src, args.current, args.out, args.count, args.upscale_cmd)
    routes: dict[str, int] = {}
    for row in report['photos'].values():
        routes[row['route']] = routes.get(row['route'], 0) + 1
    mib = report['total_bytes'] / 1024 / 1024
    print(f'完成 {len(report["photos"])} 張 → {args.out}：' +
          '、'.join(f'{k} {v}' for k, v in sorted(routes.items())) +
          f'；合計 {mib:.1f} MiB（上限 {SIZE_BUDGET / 1024 / 1024:.0f}）')
    if report['exceptions']:
        print(f'長邊不是 {TARGET_LONG_EDGE} 的例外 {len(report["exceptions"])} 張：'
              f'{"、".join(report["exceptions"])}')
    if report['missing']:
        print(f'缺 {len(report["missing"])} 張：{"、".join(report["missing"])}')
    print(f'對照圖：{"、".join(report["compare_pages"])}（給 Eric 目視，不入庫）')
    if report['missing'] or report['over_budget']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
