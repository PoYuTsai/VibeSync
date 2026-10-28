"""量人物照來源的解析度（典藏材質規格 docs/plans/2026-10-28-card-collectible-material-spec.md §8.2 第 1 步）。

來源是 Eric 本機 upload_ready 目錄裡的 practice_girl_001.png … practice_girl_100.png，路徑只走參數、
不寫進程式（比照 convert_practice_photos.dart）。只讀檔頭，不解整張圖。

用法（在 repo 根目錄）：
  python3 tools/gen-practice-photos/inspect_sources.py --src <來源目錄> [--count 100]

印出每張的寬高、長邊與分流（≥ 1800 直接縮；< 1800 要先超解析），最後是統計與缺檔清單。
需要 Pillow。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

TARGET_LONG_EDGE = 1800  # §8.1：長邊 1800（M3 A）


def photo_ids(count: int) -> list[str]:
    return [f'practice_girl_{n:03d}' for n in range(1, count + 1)]


def inspect(src: Path, count: int) -> dict:
    """回傳 {'rows': [(id, w, h)], 'missing': [id]}；讀不了的檔也算缺。"""
    rows: list[tuple[str, int, int]] = []
    missing: list[str] = []
    for photo_id in photo_ids(count):
        path = src / f'{photo_id}.png'
        try:
            with Image.open(path) as im:
                w, h = im.size
        except (FileNotFoundError, OSError):
            missing.append(photo_id)
            continue
        rows.append((photo_id, w, h))
    return {'rows': rows, 'missing': missing}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--src', required=True, type=Path, help='來源 PNG 目錄')
    parser.add_argument('--count', type=int, default=100)
    args = parser.parse_args()

    result = inspect(args.src, args.count)
    big = small = 0
    for photo_id, w, h in result['rows']:
        long_edge = max(w, h)
        if long_edge >= TARGET_LONG_EDGE:
            route = '直接縮到 1800'
            big += 1
        else:
            route = '要先超解析'
            small += 1
        print(f'{photo_id}  {w}×{h}  長邊 {long_edge}  {route}')
    print(f'\n共 {len(result["rows"])} 張：長邊 ≥ {TARGET_LONG_EDGE} 有 {big} 張、'
          f'< {TARGET_LONG_EDGE} 有 {small} 張')
    if result['missing']:
        print(f'缺 {len(result["missing"])} 張：{"、".join(result["missing"])}')


if __name__ == '__main__':
    main()
