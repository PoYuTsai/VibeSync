"""抽卡揭曉閃光檢查：用錄影工具的實際畫面數每秒閃光次數（WCAG 2.3.1 一般閃光的量法）。

規格 docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §3、§12.2：
- 25 cm（預設）：任一 1 秒最多 2 次閃光（比 WCAG 的 3 次嚴）。
- 20 cm（`--distance-cm 20 --cap 3`）：手機拿得更近時，最多 3 次（WCAG 的門檻）。
只看時間軸上的曲線會漏掉光刃、十字光、泛光、衝擊波、收卡光球這些疊上去的亮光，所以直接量
畫面（Codex 2026-10-18 #107 P2-1）。

量法（#108 第 2 輪改過：同時在閃的面積不分升降加總；不同次閃光不要求是同一片、照時間數；
10° 視野改成圓形。第 3 輪改過：時間重疊就加總、不要求一起開始；不同地方的閃光時間重疊也分開算）：
1. 每一幀換成相對亮度（sRGB → 線性 → Y＝0.2126R＋0.7152G＋0.0722B），每格 1×1 pt 取平均。
2. 每一格各自找亮度的升降段（遲滯）：跟上一個極值相比變化 ≥ 0.1 才算一段，暗的那一端要 < 0.8。
   整條錄影從頭到尾只算一次，所以窗口之前的狀態不會丟。一段只算真的在變的那幾幀，停在極值
   附近（差 0.01 以內）的平台不算。同一格前後一秒內沒有反向的段，就不是閃光的一部分，不算。
3. 10° 視野是圓形：25 cm 半徑 132 pt、門檻約 13,660 pt²；20 cm 半徑 106 pt、約 8,742 pt²。
   圓心每 8 pt 一個，半徑再加 8·√2／2 pt，任何位置的 10° 視野都整個落在某一個圓裡；圓用 8 pt
   高的橫條從外面包住來加總。所以只會多算、不會漏（面積多 12%，20 cm 多 15%）。
4. 一次轉折：每個視野記上一次轉折在哪一幀；這一幀正在變、而且在那之後才開始變的面積（不分升降）
   超過門檻，就是一次新的轉折。只要時間重疊就加總，不要求一起開始；同一幀一起變的算同一次。
5. 配成閃光：同一個視野裡，一秒內兩次轉折之間，組成它們的段有同一片反向（每一格可以一升一降、
   也可以一降一升，面積加在一起）超過門檻。不同地方各自的閃光，時間重疊也分開算。每個視野、每個
   完整一秒（fps＋1 幀，60 fps 是 61 幀）數配成閃光的轉折有幾次，回報最多的；超過「上限×2」就
   不過。寧可多算：慢慢擴散、分好幾批的亮光，每批自己超過門檻就各算一次。

量不出來的：細紋路在畫面上滑過去（例如卡片轉開時的照片），跟細紋路原地反向，逐格看是一樣的，
這裡都當成閃光算。

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
FIELD_DEG = 10  # WCAG 2.3.1：任一個 10° 視野
CM_PER_PT = 2.54 / 153.3  # 6.1 吋 iPhone（460 ppi、@3x）
STRIDE_PT = 8  # 視野圓心的間距
BAND_PT = 8  # 圓形視野用這麼高的橫條從外面包住
DELTA = 0.1  # WCAG：相對亮度變化 ≥ 10%
DARK_MAX = 0.8  # WCAG：暗的那一端 < 0.80
FLAT = 0.01  # 離極值這麼近就算還停在極值，平台不算在變
CAP = 2  # 規格 §3：任一秒最多 2 次閃光（--cap）

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


def field_radius_pt(distance_cm: float) -> float:
    """[distance_cm] 觀看距離下，10° 視野在螢幕上的半徑（pt）。"""
    return distance_cm * math.tan(math.radians(FIELD_DEG / 2)) / CM_PER_PT


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


def paired(cells: np.ndarray, begins: np.ndarray, dirs: np.ndarray, fps: int) -> np.ndarray:
    """每一段是不是閃光的一部分：同一格的前一段或後一段方向相反、開始的時間相隔 ≤ [fps] 幀。"""
    order = np.lexsort((begins, cells))
    c, b, d = cells[order], begins[order], dirs[order]
    with_prev = np.r_[False, (c[1:] == c[:-1]) & (d[1:] != d[:-1]) & (b[1:] - b[:-1] <= fps)]
    ok = np.empty(len(order), bool)
    ok[order] = with_prev | np.r_[with_prev[1:], False]
    return ok


def frame_states(cells: np.ndarray, begins: np.ndarray, ends: np.ndarray, dirs: np.ndarray,
                 frames: int, n: int):
    """逐幀給出 (幀, 正在升的格子, 正在降的格子, 這一段從哪一幀開始變)。陣列會重複用，拿到就要用完。

    一段在變的是 [begins, ends] 這幾幀；同一格的段不會重疊。"""
    up, down = np.zeros(n, bool), np.zeros(n, bool)
    since = np.full(n, -1, np.int32)
    bounds = np.arange(frames + 1)
    order_b, order_e = np.argsort(begins, kind='stable'), np.argsort(ends, kind='stable')
    b_at = np.searchsorted(begins[order_b], bounds)
    e_at = np.searchsorted(ends[order_e], bounds)
    for t in range(frames):
        runs = order_b[b_at[t]:b_at[t + 1]]
        c, d = cells[runs], dirs[runs]
        up[c[d == 1]] = True
        down[c[d == -1]] = True
        since[c] = t
        yield t, up, down, since
        c = cells[order_e[e_at[t]:e_at[t + 1]]]
        up[c] = down[c] = False
        since[c] = -1


def grid(size: int, stride: int) -> list[int]:
    """視野圓心的位置：每 [stride] 格一個，最後一個貼齊邊。"""
    out = list(range(0, size, stride))
    if out[-1] != size - 1:
        out.append(size - 1)
    return out


class Fields:
    """圓形視野。圓心每 [stride] 格一個，半徑多加 stride·√2／2，任何位置、半徑 [radius] 的圓都整個
    落在某一個裡面；圓再用 [band] 格高的橫條從外面包住。所以面積只會多算、不會少算。"""

    def __init__(self, h: int, w: int, radius: float, stride: int, band: int):
        self.h, self.w = h, w
        self.ys, self.xs = np.array(grid(h, stride)), np.array(grid(w, stride))
        self.count = len(self.ys) * len(self.xs)
        r = radius + stride * math.sqrt(2) / 2
        top = math.floor(r)
        cy, cx = np.repeat(self.ys, len(self.xs)), np.tile(self.xs, len(self.ys))
        corners = []
        for dy in range(-top, top + 1, band):
            dy1 = min(dy + band, top + 1)
            near = 0 if dy <= 0 < dy1 else min(abs(dy), abs(dy1 - 1))  # 這條離圓心最近的一列
            half = math.floor(math.sqrt(r * r - near * near))
            r0, r1 = np.clip(cy + dy, 0, h), np.clip(cy + dy1, 0, h)
            c0, c1 = np.clip(cx - half, 0, w), np.clip(cx + half + 1, 0, w)
            corners.append(np.stack([r1 * (w + 1) + c1, r0 * (w + 1) + c0,
                                     r0 * (w + 1) + c1, r1 * (w + 1) + c0], axis=-1))
        self._corners = np.stack(corners, axis=1)  # (視野, 橫條, 4)：＋＋－－

    def sums(self, mask: np.ndarray, which: np.ndarray | None = None) -> np.ndarray:
        """每個視野（或只有 [which] 這幾個）裡 [mask]（高×寬）的面積（格數）。"""
        integral = np.zeros((self.h + 1, self.w + 1), np.int32)
        integral[1:, 1:] = mask.cumsum(axis=0, dtype=np.int32).cumsum(axis=1)
        v = integral.ravel().take(self._corners if which is None else self._corners[which])
        return (v[..., 0] + v[..., 1] - v[..., 2] - v[..., 3]).sum(axis=1)

    def center_pt(self, f: int) -> tuple[int, int]:
        return int(self.xs[f % len(self.xs)]) * PT_PER_CELL, int(self.ys[f // len(self.xs)]) * PT_PER_CELL


def max_transitions(lum: np.ndarray, fps: int, distance_cm: float) -> dict:
    """所有視野、所有完整一秒裡最長的一串轉折。[lum] 是 (幀, 高, 寬)，每格 [PT_PER_CELL] pt。

    回傳轉折次數、那一串從哪一幀開始、哪個視野（圓心 pt），以及每次轉折的 (幀, 升／降／升降)。"""
    frames, h, w = lum.shape
    flat = lum.reshape(frames, -1)
    busy = np.nonzero(flat.max(axis=0) - flat.min(axis=0) >= DELTA)[0]  # 變不到 0.1 的格子沒有段
    cells, starts, ends, dirs = cell_runs(flat[:, busy])
    cells, begins = busy[cells], starts + 1
    keep = paired(cells, begins, dirs, fps)
    cells, begins, ends, dirs = cells[keep], begins[keep], ends[keep], dirs[keep]
    fields = Fields(h, w, field_radius_pt(distance_cm) / PT_PER_CELL,
                    max(1, round(STRIDE_PT / PT_PER_CELL)), max(1, round(BAND_PT / PT_PER_CELL)))
    threshold = threshold_pt2(distance_cm) / PT_PER_CELL**2
    n_fields = fields.count

    # 逐幀找轉折（#108 第 3 輪改過）：每個視野記上一次轉折在哪一幀（last）。這一幀正在變、而且在
    # last 之後才開始變的面積（不分升降）超過門檻，就是這個視野的一次新轉折：只要時間重疊就加總，
    # 不要求一起開始（錯開幾幀才開始的兩塊也算同時，Codex 第 2 輪 P2-1）；同一幀一起變的算同一次。
    # 一次轉折只算組成它的段：在它的前一次轉折之後才開始、這一幀還在變的。
    # 配成閃光：同一個視野裡，一秒內兩次轉折之間，組成它們的段有同一片反向（這次升、那次降，或
    # 反過來），面積超過門檻。不同地方各自的閃光，時間重疊也分開算，不併成一次（第 2 輪 P2-2）。
    # 只留最近一秒有轉折的幀的狀態，記憶體不隨錄影長度變大（第 2 輪 P3）。
    last = np.full(n_fields, -1, np.int64)
    recent: dict[int, tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]] = {}
    turns: list[list[int]] = [[] for _ in range(n_fields)]
    label: dict[tuple[int, int], int] = {}
    matched: set[tuple[int, int]] = set()
    for t, up, down, since in frame_states(cells, begins, ends, dirs, frames, h * w):
        for old in [t0 for t0 in recent if t0 < t - fps]:
            del recent[old]
        changing = up | down
        if not changing.any():
            continue
        # 比這一幀所有正在變的段都早的 last，結果都一樣，併成同一組少算幾次。
        group = np.maximum(last, int(since[changing].min()) - 1)
        fresh = np.zeros(n_fields, np.int64)
        rise = np.zeros(n_fields, np.int64)
        for g in np.unique(group):
            idx = np.nonzero(group == g)[0]
            newer = since > g
            fresh[idx] = fields.sums((changing & newer).reshape(h, w), idx)
            hit = idx[fresh[idx] > threshold]
            if hit.size:
                rise[hit] = fields.sums((up & newer).reshape(h, w), hit)
        turn = fresh > threshold
        if not turn.any():
            continue
        direction = up.astype(np.int8) - down.astype(np.int8)
        prev = last.copy()
        for f in np.nonzero(turn)[0].tolist():
            turns[f].append(t)
            r, fall = int(rise[f]), int(fresh[f] - rise[f])
            label[(f, t)] = 1 if fall * 2 < r else -1 if r * 2 < fall else 0
        for t0, (direction0, since0, turn0, prev0) in recent.items():
            both = turn & turn0
            if not both.any():
                continue
            flip = direction0 * direction == -1
            if not flip.any():
                continue
            for g0, g1 in set(zip(prev0[both].tolist(), prev[both].tolist())):
                idx = np.nonzero(both & (prev0 == g0) & (prev == g1))[0]
                area = fields.sums((flip & (since0 > g0) & (since > g1)).reshape(h, w), idx)
                for f in idx[area > threshold].tolist():
                    matched.add((f, t0))
                    matched.add((f, t))
        recent[t] = (direction, since.copy(), turn, prev)
        last[turn] = t

    # 每個視野、每個完整一秒（fps＋1 幀）裡，配成閃光的轉折有幾次，取最多的。
    best = {'transitions': 0, 'window_start': None, 'field_pt': None, 'events': []}
    for f in range(n_fields):
        hits = [t for t in turns[f] if (f, t) in matched]
        j = 0
        for i, start in enumerate(hits):
            while j < len(hits) and hits[j] <= start + fps:
                j += 1
            if j - i > best['transitions']:
                best = {
                    'transitions': j - i,
                    'window_start': start,
                    'field_pt': fields.center_pt(f),
                    'events': [(e, label[(f, e)]) for e in hits[i:j]],
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
    radius = field_radius_pt(args.distance_cm)
    print(f'觀看距離 {args.distance_cm:g} cm → 門檻 {threshold_pt2(args.distance_cm):,.0f} pt²、'
          f'10° 視野半徑 {radius:.0f} pt；上限每秒 {args.cap} 次閃光（{2 * args.cap} 次轉折）')
    failed = False
    for folder in args.folders:
        r = check(folder, args.fps, args.distance_cm, args.cap)
        failed |= not r['pass']
        where = '' if r['window_ms'] is None else (
            f"，最多的一秒 {r['window_ms'][0]}–{r['window_ms'][1]} ms、視野圓心 {r['field_pt']} pt")
        print(f"{r['folder']}：{r['frames']} 幀，任一秒最多 {r['transitions']} 次轉折"
              f"（{r['flashes']:g} 次閃光）{where} → {'過' if r['pass'] else '超過上限'}")
        if r['events_ms']:
            names = {1: '升', -1: '降', 0: '升降'}
            print('  轉折：' + '、'.join(f'{ms} ms {names[d]}' for ms, d in r['events_ms']))
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
