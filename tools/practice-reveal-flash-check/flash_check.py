"""抽卡揭曉閃光檢查：用錄影工具的實際畫面數每秒閃光次數（WCAG 2.3.1 一般閃光的量法）。

規格 docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §3、§12.2：
- 25 cm（預設）：任一 1 秒最多 2 次閃光（比 WCAG 的 3 次嚴）。
- 20 cm（`--distance-cm 20 --cap 3`）：手機拿得更近時，最多 3 次（WCAG 的門檻）。
只看時間軸上的曲線會漏掉光刃、十字光、泛光、衝擊波、收卡光球這些疊上去的亮光，所以直接量
畫面（Codex 2026-10-18 #107 P2-1）。

量法（#107 第 2 輪改過。原本每個方框取平均亮度，會漏掉面積剛好超過門檻、或分散在同一個
10° 視野裡的閃光；一秒的窗也少一幀，而且每個窗從頭算）：
1. 每一幀換成相對亮度（sRGB → 線性 → Y＝0.2126R＋0.7152G＋0.0722B），每格 1×1 pt 取平均。
2. 每一格各自找亮度的升降段（遲滯）：跟上一個極值相比變化 ≥ 0.1 才算一段，暗的那一端要 < 0.8。
   整條錄影從頭到尾只算一次，所以窗口之前的狀態不會丟。一段只算真的在變的那幾幀，停在極值
   附近（差 0.01 以內）的平台不算。
3. 10° 視野：WCAG 的面積門檻 0.006 sr 是 10° 視野的 25%。手機照 `--distance-cm` 換算
   （6.1 吋 iPhone 1 pt ≈ 0.01657 cm）：25 cm 時門檻約 13,660 pt²，視野取一樣面積的方形
   234×234 pt；20 cm 時約 8,742 pt²、187×187 pt。視野每 8 pt 滑一次，最後一格貼齊右邊與下邊。
4. 一次轉折：某一幀，一個視野裡同一幀在升（或降）的格子面積超過門檻。
5. 一次閃光是一升一降，而且要同一片在閃：一串升降交替的轉折裡，相鄰兩次都有份的格子面積也要
   超過門檻（A 區升、B 區降不算閃光；光刃這種細線掃過去，每一幀在變的面積不夠，也不算）。
   每個視野、每個完整一秒（fps＋1 幀，60 fps 是 61 幀）找最長的一串，回報最多的轉折次數；
   超過「上限×2」就不過。

用法（在 repo 根目錄）：先用 60 fps 錄好 build/card_draw_preview/<稀有度>/
（24 fps 會錯過兩幀之間最亮與最暗的那一下）：
  RECORD_CEREMONY=1 RECORD_FPS=60 flutter test test/tools/ceremony_preview_recorder_test.dart
  python3 tools/practice-reveal-flash-check/flash_check.py --fps 60 build/card_draw_preview/{n,r,sr}
  python3 tools/practice-reveal-flash-check/flash_check.py --fps 60 --distance-cm 20 --cap 3 \\
      build/card_draw_preview/{n,r,sr}
超過的話會列出那一秒每次轉折的時間與升降，對照時間軸就知道是哪個光效。
測試：python3 -m unittest discover -s tools/practice-reveal-flash-check
需要 Pillow 與 numpy。只看畫面亮度，不判斷紅色閃光（揭曉沒有飽和紅）。
"""

from __future__ import annotations

import argparse
import math
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

FPS = 24  # 錄影的 fps（--fps）；一個完整的 1 s 窗＝FPS＋1 幀
PT_PER_CELL = 1  # 每格 1×1 pt
SCREEN_PT = 390  # 錄影畫面的寬（pt）
STERADIANS = 0.006  # WCAG 2.3.1：同時在閃的面積門檻
FIELD_FRACTION = 0.25  # 0.006 sr 是 10° 視野的 25%
CM_PER_PT = 2.54 / 153.3  # 6.1 吋 iPhone（460 ppi、@3x）
STRIDE_PT = 8
DELTA = 0.1  # WCAG：相對亮度變化 ≥ 10%
DARK_MAX = 0.8  # WCAG：暗的那一端 < 0.80
FLAT = 0.01  # 離極值這麼近就算還停在極值，平台不算在變
CAP = 2  # 規格 §3：任一秒最多 2 次閃光（--cap）
_NONE = -(1 << 30)

def _srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


_LINEAR = _srgb_to_linear(np.arange(256) / 255.0).astype(np.float32)  # 8 位元 sRGB → 線性


def luminance(path: Path, cell_px: int) -> np.ndarray:
    from PIL import Image

    lin = _LINEAR[np.asarray(Image.open(path).convert('RGB'))]
    y = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722
    h = y.shape[0] // cell_px * cell_px
    w = y.shape[1] // cell_px * cell_px
    return y[:h, :w].reshape(h // cell_px, cell_px, w // cell_px, cell_px).mean(axis=(1, 3))


def threshold_pt2(distance_cm: float) -> float:
    """WCAG 的面積門檻（0.006 sr）在 [distance_cm] 觀看距離下是多少 pt²。"""
    return STERADIANS * distance_cm**2 / CM_PER_PT**2


def field_pt(distance_cm: float) -> int:
    """10° 視野取成方形的邊長（pt）：面積是門檻的 4 倍。"""
    return round(math.sqrt(threshold_pt2(distance_cm) / FIELD_FRACTION))


def within_cap(transitions: int, cap: int) -> bool:
    """一升一降算一次閃光：轉折不超過「上限×2」才過。"""
    return transitions <= 2 * cap


def cell_runs(lum: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """每一格的升降段（遲滯 [DELTA]）。[lum] 是 (幀, 格) 的相對亮度。

    回傳 (格, 起, 迄, 方向 +1／−1)，只留暗的那一端 < [DARK_MAX] 的段。這一段在變的是 (起, 迄]：
    起＝開始變之前最後一幀還停在上一個極值附近（差 [FLAT] 以內），迄＝第一次到這一段的極值附近。"""
    frames, n = lum.shape
    direction = np.zeros(n, np.int8)
    lo, hi = lum[0].copy(), lum[0].copy()  # 還沒有方向的格：目前為止的最低、最高
    lo_last = np.zeros(n, np.int32)  # 最後一次停在最低點附近的幀
    hi_last = np.zeros(n, np.int32)
    ref = lum[0].copy()  # 這一段到目前為止的極值
    ref_first = np.zeros(n, np.int32)  # 第一次到極值附近的幀
    ref_first_v = lum[0].copy()
    ref_last = np.zeros(n, np.int32)  # 最後一次停在極值附近的幀
    start = np.zeros(n, np.int32)
    start_v = lum[0].copy()
    out: list[tuple[np.ndarray, ...]] = []

    def emit(mask: np.ndarray) -> None:
        idx = np.nonzero(mask)[0]
        if idx.size:
            out.append((idx, start[idx], ref_first[idx], direction[idx], start_v[idx], ref[idx]))

    def begin(mask: np.ndarray, d: int, t: int, v: np.ndarray, from_t: np.ndarray,
              from_v: np.ndarray) -> None:
        start[mask], start_v[mask] = from_t[mask], from_v[mask]
        direction[mask] = d
        ref[mask] = ref_first_v[mask] = v[mask]
        ref_first[mask] = ref_last[mask] = t

    for t in range(1, frames):
        v = lum[t]
        fresh = direction == 0
        moving = [(d, ~fresh & (direction == d)) for d in (1, -1)]
        # 還沒有方向：記住最低、最高點，變化夠大就開始第一段。
        np.minimum(lo, v, out=lo, where=fresh)
        np.maximum(hi, v, out=hi, where=fresh)
        lo_last[fresh & (v <= lo + FLAT)] = t
        hi_last[fresh & (v >= hi - FLAT)] = t
        up = fresh & (v - lo >= DELTA)
        down = fresh & ~up & (hi - v >= DELTA)
        begin(up, 1, t, v, lo_last, lo)
        begin(down, -1, t, v, hi_last, hi)
        # 升段：更新最高點；從最高點掉了 ≥ DELTA 就結束這一段、開始降段（反之亦然）。
        for d, cur in moving:
            better = cur & ((v - ref) * d > 0)
            ref[better] = v[better]
            jump = better & ((v - ref_first_v) * d > FLAT)
            ref_first[jump], ref_first_v[jump] = t, v[jump]
            ref_last[cur & ((ref - v) * d <= FLAT)] = t
            rev = cur & ((ref - v) * d >= DELTA)
            emit(rev)
            begin(rev, -d, t, v, ref_last, ref)
    emit(direction != 0)

    if not out:
        empty = np.zeros(0, np.int32)
        return empty, empty, empty, np.zeros(0, np.int8)
    cells, starts, ends, dirs, first, last = (np.concatenate(parts) for parts in zip(*out))
    keep = np.minimum(first, last) < DARK_MAX
    return cells[keep], starts[keep], ends[keep], dirs[keep]


def changing(cells: np.ndarray, starts: np.ndarray, ends: np.ndarray, dirs: np.ndarray,
             frames: int, n: int):
    """逐幀給出 (幀, 方向, 那一幀正在往這個方向變的格子)。陣列會重複用，拿到就要用完。"""
    bounds = np.arange(frames + 1)
    for d in (1, -1):
        m = dirs == d
        c, b, e = cells[m], starts[m] + 1, ends[m]
        order_b, order_e = np.argsort(b, kind='stable'), np.argsort(e, kind='stable')
        c_b, c_e = c[order_b], c[order_e]
        b_at, e_at = np.searchsorted(b[order_b], bounds), np.searchsorted(e[order_e], bounds)
        active = np.zeros(n, bool)
        for t in range(frames):
            active[c_b[b_at[t]:b_at[t + 1]]] = True
            yield t, d, active
            active[c_e[e_at[t]:e_at[t + 1]]] = False


def origins(size: int, field: int, stride: int) -> list[int]:
    """視野左上角的位置：每 [stride] 一格，最後一格貼齊邊。"""
    if field >= size:
        return [0]
    out = list(range(0, size - field + 1, stride))
    if out[-1] != size - field:
        out.append(size - field)
    return out


def max_transitions(lum: np.ndarray, fps: int, distance_cm: float) -> dict:
    """所有視野、所有完整一秒裡最長的一串轉折。[lum] 是 (幀, 高, 寬)，每格 [PT_PER_CELL] pt。

    回傳轉折次數、那一串從哪一幀開始、哪個視野（左上角 pt），以及每次轉折的 (幀, 方向)。"""
    frames, h, w = lum.shape
    flat = lum.reshape(frames, -1)
    busy = np.nonzero(flat.max(axis=0) - flat.min(axis=0) >= DELTA)[0]  # 變不到 0.1 的格子沒有段
    cells, starts, ends, dirs = cell_runs(flat[:, busy])
    cells = busy[cells]
    side = round(field_pt(distance_cm) / PT_PER_CELL)
    sy, sx = min(side, h), min(side, w)
    stride = max(1, round(STRIDE_PT / PT_PER_CELL))
    ys, xs = np.array(origins(h, sy, stride)), np.array(origins(w, sx, stride))
    y0, x0 = np.repeat(ys, len(xs)), np.tile(xs, len(ys))
    threshold = threshold_pt2(distance_cm) / PT_PER_CELL**2

    def over(mask: np.ndarray, r0: int = 0) -> np.ndarray:
        """每個視野裡 [mask] 的面積有沒有超過門檻。[mask] 是第 [r0] 列起的幾列，沒整個落在裡面的視野算沒有。"""
        rows = mask.shape[0]
        # 先在每個視野的欄寬內橫著加，再直著加。
        across = np.zeros((rows, w + 1), np.int32)
        np.cumsum(mask, axis=1, dtype=np.int32, out=across[:, 1:])
        down = np.zeros((rows + 1, len(xs)), np.int32)
        np.cumsum(across[:, xs + sx] - across[:, xs], axis=0, out=down[1:])
        area = np.zeros((len(ys), len(xs)), np.int32)
        inside = (ys >= r0) & (ys + sy <= r0 + rows)
        area[inside] = down[ys[inside] - r0 + sy] - down[ys[inside] - r0]
        return area.reshape(-1) > threshold

    # 轉折：那一幀至少一個視野裡，同一幀往同一個方向變的面積超過門檻。
    events = []
    for t, d, active in changing(cells, starts, ends, dirs, frames, h * w):
        present = over(active.reshape(h, w))
        if present.any():
            events.append((t, d, np.packbits(active.reshape(h, w), axis=1), present))
    events.sort(key=lambda e: e[0])

    # chains[i][k]：每個視野裡長度 k、以第 i 次轉折結尾的一串最晚從哪一幀開始（_NONE＝沒有）。
    # 接上的條件：方向相反、在前一次之後、跟第一次相隔 ≤ fps 幀，而且兩次都有份的面積超過門檻。
    # backs[i][k]：那一串的前一次轉折是第幾次，用來回報整串的時間。
    longest = fps + 1
    chains: list[np.ndarray | None] = []
    backs: list[np.ndarray | None] = []
    oldest = 0
    best = {'transitions': 0, 'window_start': None, 'field_pt': None, 'events': []}
    for i, (t, d, packed, present) in enumerate(events):
        while events[oldest][0] < t - fps:
            chains[oldest] = backs[oldest] = None
            oldest += 1
        chain = np.full((longest + 1, len(y0)), _NONE, np.int32)
        back = np.full((longest + 1, len(y0)), -1, np.int32)
        chain[1][present] = t
        for j in range(oldest, i):
            t_j, d_j, packed_j, present_j = events[j]
            only = present & present_j
            if d_j == d or t_j == t or not only.any():
                continue
            band = ys[only.reshape(len(ys), len(xs)).any(axis=1)]  # 只解開兩次都有的視野涵蓋的列
            r0, r1 = band[0], band[-1] + sy
            both = only & over(np.unpackbits(packed[r0:r1] & packed_j[r0:r1], axis=1, count=w), r0)
            if both.any():
                longer = both & (chains[j][:-1] > chain[1:])
                chain[1:][longer] = chains[j][:-1][longer]
                back[1:][longer] = j
        chain[chain < t - fps] = _NONE
        chains.append(chain)
        backs.append(back)
        k = int(np.nonzero((chain >= 0).any(axis=1))[0][-1])
        if k > best['transitions']:
            f = int(np.argmax(chain[k] >= 0))
            seq = [i]
            for length in range(k, 1, -1):
                seq.append(int(backs[seq[-1]][length][f]))
            best = {
                'transitions': k,
                'window_start': int(chain[k][f]),
                'field_pt': (int(x0[f]) * PT_PER_CELL, int(y0[f]) * PT_PER_CELL),
                'events': [(events[e][0], events[e][1]) for e in reversed(seq)],
            }
    return best


def check(folder: Path, fps: int, distance_cm: float, cap: int) -> dict:
    from PIL import Image

    paths = sorted(folder.glob('frame_*.png'))
    if not paths:
        raise SystemExit(f'{folder}: 找不到 frame_*.png')
    cell_px = round(Image.open(paths[0]).width / SCREEN_PT * PT_PER_CELL)
    with ThreadPoolExecutor() as pool:
        lum = np.stack(list(pool.map(lambda p: luminance(p, cell_px), paths)))
    result = max_transitions(lum, fps, distance_cm)
    start = result['window_start']
    return {
        'folder': str(folder),
        'frames': len(paths),
        'transitions': result['transitions'],
        'flashes': result['transitions'] / 2,
        'window_ms': None if start is None else (round(start * 1000 / fps), round((start + fps) * 1000 / fps)),
        'field_pt': result['field_pt'],
        'events_ms': [(round(t * 1000 / fps), d) for t, d in result['events']],
        'pass': within_cap(result['transitions'], cap),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('folders', nargs='+', type=Path)
    parser.add_argument('--distance-cm', type=float, default=25)
    parser.add_argument('--fps', type=int, default=FPS)
    parser.add_argument('--cap', type=int, default=CAP)
    args = parser.parse_args()
    side = field_pt(args.distance_cm)
    print(f'觀看距離 {args.distance_cm:g} cm → 門檻 {threshold_pt2(args.distance_cm):,.0f} pt²、'
          f'10° 視野 {side}×{side} pt；上限每秒 {args.cap} 次閃光（{2 * args.cap} 次轉折）')
    failed = False
    for folder in args.folders:
        r = check(folder, args.fps, args.distance_cm, args.cap)
        failed |= not r['pass']
        where = '' if r['window_ms'] is None else (
            f"，最多的一秒 {r['window_ms'][0]}–{r['window_ms'][1]} ms、視野左上 {r['field_pt']} pt")
        print(f"{r['folder']}：{r['frames']} 幀，任一秒最多 {r['transitions']} 次轉折"
              f"（{r['flashes']:g} 次閃光）{where} → {'過' if r['pass'] else '超過上限'}")
        if r['events_ms']:
            print('  轉折：' + '、'.join(f"{ms} ms {'升' if d > 0 else '降'}" for ms, d in r['events_ms']))
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
