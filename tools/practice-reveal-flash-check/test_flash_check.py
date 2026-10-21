"""flash_check 的合成測試：直接餵 (幀, 高, 寬) 的相對亮度，每格 1 pt。

python3 -m unittest discover -s tools/practice-reveal-flash-check
"""

from __future__ import annotations

import unittest

import numpy as np

import flash_check as fc

FPS = 60
BG, LIT = 0.2, 0.305  # 亮暗差 0.105：剛好超過 0.1


def screen(frames: int = 80, h: int = 300, w: int = 300) -> np.ndarray:
    return np.full((frames, h, w), BG, np.float32)


def levels(frames: int, flips: list[int], low: float = BG, high: float = LIT) -> np.ndarray:
    """從 [low] 開始，在 [flips] 的每一幀切換一次亮暗。"""
    out = np.empty(frames, np.float32)
    lit = False
    for t in range(frames):
        lit ^= t in flips
        out[t] = high if lit else low
    return out


def paint(lum: np.ndarray, y: int, x: int, h: int, w: int, series: np.ndarray) -> None:
    lum[:, y:y + h, x:x + w] = series[:, None, None]


def transitions(lum: np.ndarray, distance_cm: float = 25) -> int:
    return fc.max_transitions(lum, FPS, distance_cm)['transitions']


class ThresholdTest(unittest.TestCase):
    def test_threshold_and_field_for_25_and_20_cm(self):
        self.assertAlmostEqual(fc.threshold_pt2(25), 13660, delta=1)
        self.assertAlmostEqual(fc.field_radius_pt(25), 132.0, delta=0.1)
        self.assertAlmostEqual(fc.threshold_pt2(20), 8742, delta=1)
        self.assertAlmostEqual(fc.field_radius_pt(20), 105.6, delta=0.1)
        # 下面測試用的方塊：117×117 剛好超過、116×117 剛好不到。
        self.assertGreater(117 * 117, fc.threshold_pt2(25))
        self.assertLess(116 * 117, fc.threshold_pt2(25))

    def test_cap_counts_a_flash_as_two_transitions(self):
        self.assertTrue(fc.within_cap(4, 2))
        self.assertFalse(fc.within_cap(5, 2))
        self.assertTrue(fc.within_cap(6, 3))
        self.assertFalse(fc.within_cap(7, 3))


class AreaTest(unittest.TestCase):
    def test_block_just_over_threshold_off_the_grid(self):
        lum = screen()
        paint(lum, 13, 21, 117, 117, levels(80, [10, 20]))
        self.assertEqual(transitions(lum), 2)

    def test_block_just_under_threshold(self):
        lum = screen()
        paint(lum, 13, 21, 116, 117, levels(80, [10, 20]))
        self.assertEqual(transitions(lum), 0)

    def test_blocks_spread_over_one_field_add_up(self):
        pulse = levels(80, [10, 20])
        lum = screen()
        for y, x in ((20, 20), (20, 140), (140, 20), (140, 140)):  # 4 × 3,600 ＝ 14,400 pt²
            paint(lum, y, x, 60, 60, pulse)
        self.assertEqual(transitions(lum), 2)
        lum[:, 140:200, 140:200] = BG  # 剩三塊 10,800 pt²
        self.assertEqual(transitions(lum), 0)

    def test_strip_between_two_field_positions(self):
        # Codex #108 第 1 輪 P2-3：從 x＝4 開始的 234×59 長條（13,806 pt²），方框只框到 230 寬。
        lum = screen()
        paint(lum, 100, 4, 59, 234, levels(80, [1, 10, 20, 30, 40, 50, 59, 60]))
        self.assertEqual(transitions(lum), 8)

    def test_two_blocks_inside_one_round_field(self):
        # Codex #108 第 1 輪 P2-3：兩塊 117×60 相隔 133 pt（合計 14,040 pt²），外框 250×60
        # 放得進 10° 的圓，但任何 234 pt 的方形都框不到兩塊全部。
        flips = levels(80, [1, 10, 20, 30, 40, 50, 59, 60])
        lum = screen()
        paint(lum, 100, 20, 60, 117, flips)
        paint(lum, 100, 20 + 133, 60, 117, flips)
        self.assertEqual(transitions(lum), 8)

    def test_block_touching_the_screen_edge(self):
        lum = screen(h=400, w=300)
        paint(lum, 400 - 117, 300 - 117, 117, 117, levels(80, [10, 20]))
        self.assertEqual(transitions(lum), 2)

    def test_closer_viewing_distance_lowers_the_threshold(self):
        lum = screen()
        paint(lum, 50, 50, 100, 100, levels(80, [10, 20]))  # 10,000 pt²
        self.assertEqual(transitions(lum, 25), 0)
        self.assertEqual(transitions(lum, 20), 2)


class ConcurrencyTest(unittest.TestCase):
    def test_areas_flashing_at_different_times_do_not_add_up(self):
        lum = screen()
        paint(lum, 0, 0, 120, 60, levels(80, [10, 20]))  # 7,200 pt²
        paint(lum, 0, 100, 120, 60, levels(80, [40, 50]))  # 7,200 pt²，晚 30 幀
        self.assertEqual(transitions(lum), 0)
        paint(lum, 0, 100, 120, 60, levels(80, [10, 20]))  # 同時閃就加起來
        self.assertEqual(transitions(lum), 2)

    def test_rise_in_one_place_and_fall_in_another_is_not_a_flash(self):
        lum = screen()
        paint(lum, 0, 0, 117, 117, levels(80, [10]))  # 第 10 幀變亮，之後不再變
        paint(lum, 117, 0, 117, 117, levels(80, [0, 20]))  # 另一塊第 20 幀變暗，之後不再變
        self.assertEqual(transitions(lum), 0)

    def test_rise_and_fall_at_the_same_time_add_up(self):
        # Codex #108 第 1 輪 P2-1：兩塊 120×60 同時切換、一塊升一塊降，各 7,200、合計 14,400 pt²。
        flips = [1, 10, 20, 30, 40, 50, 59, 60]
        lum = screen()
        paint(lum, 60, 60, 60, 120, levels(80, flips))
        paint(lum, 120, 60, 60, 120, levels(80, flips, low=LIT, high=BG))
        result = fc.max_transitions(lum, FPS, 25)
        self.assertEqual(result['transitions'], 8)
        self.assertEqual({label for _, label in result['events']}, {0})  # 每一次都是一升一降
        self.assertFalse(fc.within_cap(result['transitions'], 3))

    def test_flashes_taking_turns_in_two_places_count_by_time(self):
        # Codex #108 第 1 輪 P2-2：A 在第 1／2、21／22 幀閃，B 在第 11／12、31／32 幀閃，各 117×117。
        lum = screen()
        paint(lum, 0, 30, 117, 117, levels(80, [1, 2, 21, 22]))
        paint(lum, 117, 30, 117, 117, levels(80, [11, 12, 31, 32]))
        self.assertEqual(transitions(lum), 8)

    def test_flashes_overlapping_in_time_in_two_places_count_separately(self):
        # A 還沒閃完 B 就開始，兩塊各自超過門檻：是兩次閃光，時間重疊也分開算（Codex #108 第 2 輪
        # P2-2：不同地方的閃光不併成一次）。
        lum = screen()
        paint(lum, 0, 30, 117, 117, levels(80, [1, 21]))  # A：第 1 幀亮、第 21 幀暗
        paint(lum, 117, 30, 117, 117, levels(80, [11, 31]))  # B：第 11 幀亮、第 31 幀暗
        self.assertEqual(transitions(lum), 4)

    def test_flash_inside_a_longer_flash_counts_separately(self):
        lum = screen()
        paint(lum, 0, 30, 117, 117, levels(80, [1, 31]))  # A：第 1 幀亮、第 31 幀暗
        paint(lum, 117, 30, 117, 117, levels(80, [11, 12]))  # B 在 A 亮著的時候閃一下
        self.assertEqual(transitions(lum), 4)

    def test_falls_overlapping_in_time_in_two_halves_count_separately(self):
        # 一起在第 10 幀變亮（同一次）；上半第 20–40 幀慢慢變暗、下半第 30–45 幀才開始變暗，兩半
        # 各自超過門檻（兩次）；第 55 幀一起變亮（同一次）。
        top = np.full(80, LIT + 0.2, np.float32)
        top[:10] = BG
        top[20:41] = np.linspace(LIT + 0.2, BG, 21)
        top[41:55] = BG
        bottom = top.copy()
        bottom[20:30] = LIT + 0.2
        bottom[30:46] = np.linspace(LIT + 0.2, BG, 16)
        bottom[46:55] = BG
        lum = screen()
        paint(lum, 30, 30, 120, 240, top)
        paint(lum, 150, 30, 120, 240, bottom)
        self.assertEqual(transitions(lum), 4)
        # 兩半各只有 120×60（各不到門檻、合計超過）：變暗時間重疊，加總成同一次，共 3 次。
        lum = screen()
        paint(lum, 30, 30, 60, 120, top)
        paint(lum, 90, 30, 60, 120, bottom)
        self.assertEqual(transitions(lum), 3)

    def test_one_rise_then_falls_in_three_places(self):
        # 一起變亮後分三批在第 20、30、40 幀變暗，每批都超過門檻：三批各是一次閃光；一起變亮的那
        # 一下只算一次轉折，共 4 次。
        lum = screen()
        paint(lum, 0, 0, 300, 300, levels(80, [10]))
        for i, t in enumerate((20, 30, 40)):
            lum[t:, 100 * i:100 * i + 100, :] = BG
        self.assertEqual(transitions(lum), 4)

    def test_glow_spreading_over_two_halves_counts_each_half(self):
        # 兩半各 90×160（各自超過門檻）在 10 幀內變亮，下半晚 4 幀才開始；第 40 幀起一起變暗。
        # 兩半各算一次變亮，一起變暗算一次，共 3 次（寧可多算）。
        def glow(h):
            lum = screen()
            for i in range(2):
                series = np.full(80, BG, np.float32)
                series[10 + 4 * i:20 + 4 * i] = np.linspace(BG, 0.5, 10)
                series[20 + 4 * i:40] = 0.5
                series[40:50] = np.linspace(0.5, BG, 10)
                paint(lum, 60 + h * i, 70, h, 160, series)
            return lum

        self.assertEqual(transitions(glow(90)), 3)
        # 兩半各 45×160（各不到門檻、合計超過）：變亮時間重疊就加總成一次，共 2 次。
        self.assertEqual(transitions(glow(45)), 2)

    def test_ramps_starting_a_few_frames_apart_add_up(self):
        # Codex #108 第 2 輪 P2-1：兩塊相鄰的 120×60（各 7,200、合計 14,400 pt²），0.2↔0.5 六幀的
        # 斜坡，A 從第 1、9、…、57 幀開始，B 晚 4 幀。不是一起開始，但時間重疊，要加總。
        def ramps(starts):
            out = np.full(80, BG, np.float32)
            level, lit, t_prev = BG, False, 0
            for s in starts:
                out[t_prev:s] = level
                target = BG if lit else 0.5
                out[s:s + 6] = level + (target - level) * np.arange(1, 7, dtype=np.float32) / 6
                level, lit, t_prev = target, not lit, s + 6
            out[t_prev:] = level
            return out

        a = ramps([1, 9, 17, 25, 33, 41, 49, 57])
        b = ramps([5, 13, 21, 29, 37, 45, 53, 61])
        lum = screen()
        paint(lum, 100, 30, 60, 120, a)
        self.assertEqual(transitions(lum), 0)  # 一塊單獨不到門檻
        paint(lum, 100, 150, 60, 120, b)
        self.assertEqual(transitions(lum), 8)

    def test_overlap_counts_no_matter_how_late_the_second_starts(self):
        # A 第 1 幀起 30 幀慢慢變亮、B 第 20 幀才一下變亮（各 7,200）：第 20 幀時兩塊都在變，加總
        # 超過門檻；第 40 幀一起變暗。以前要兩塊在 2 幀內一起開始才算。
        a = np.full(80, BG, np.float32)
        a[1:31] = np.linspace(BG, 0.5, 31, dtype=np.float32)[1:]
        a[31:40] = 0.5
        b = levels(80, [20, 40], high=0.5)
        lum = screen()
        paint(lum, 100, 30, 60, 120, a)
        paint(lum, 100, 150, 60, 120, b)
        self.assertEqual(transitions(lum), 2)

    def test_independent_flashes_interleaved_in_one_field_all_count(self):
        # Codex #108 第 2 輪 P2-2：20 cm，兩塊 90×100（各 9,000，各自超過 8,742）並排在一個視野
        # 裡，A 在第 1、16、31、46 幀切換、B 在第 8、23、38、53 幀：各兩次閃光，一秒內共 4 次。
        lum = screen()
        paint(lum, 60, 40, 100, 90, levels(80, [1, 16, 31, 46]))
        paint(lum, 60, 130, 100, 90, levels(80, [8, 23, 38, 53]))
        result = fc.max_transitions(lum, FPS, 20)
        self.assertEqual(result['transitions'], 8)
        self.assertFalse(fc.within_cap(result['transitions'], 3))

    def test_turns_still_count_while_a_big_area_keeps_rising(self):
        # 同一個視野裡有一大片一直慢慢變亮（不是閃光），A、B 照樣輪流閃。
        lum = screen()
        paint(lum, 0, 0, 60, 300, np.linspace(BG, 0.6, 80, dtype=np.float32))
        paint(lum, 60, 30, 117, 117, levels(80, [1, 2, 21, 22]))
        paint(lum, 177, 30, 117, 117, levels(80, [11, 12, 31, 32]))
        self.assertEqual(transitions(lum), 8)

    def test_rise_that_falls_back_in_small_pieces_is_not_a_flash(self):
        # 20 cm：A（90×100）閃一次；B（90×100）第 30 幀變亮，之後上下兩半在第 40、50 幀各自變暗，
        # 每一半都不到門檻，B 那一下不算閃光。畫面下方遠處的 C 在第 30／35 幀另外閃一次。
        lum = screen(h=520)
        paint(lum, 30, 50, 90, 100, levels(80, [5, 15]))
        paint(lum, 120, 50, 45, 100, levels(80, [30, 40]))
        paint(lum, 165, 50, 45, 100, levels(80, [30, 50]))
        paint(lum, 410, 50, 100, 100, levels(80, [30, 35]))
        self.assertEqual(transitions(lum, 20), 2)

    def test_slow_fade_then_rise_is_not_counted_twice(self):
        # 第 5 幀變亮、第 10–40 幀慢慢變暗、第 50 幀又變亮：升、降、升三次。
        series = np.full(80, LIT + 0.1, np.float32)
        series[:5] = BG
        series[10:41] = np.linspace(LIT + 0.1, BG, 31)
        series[41:50] = BG
        lum = screen()
        paint(lum, 60, 60, 150, 150, series)
        self.assertEqual(transitions(lum), 3)

    def test_thin_bar_sweeping_across_is_not_a_flash(self):
        lum = screen(frames=40)
        for t in range(40):
            x = 10 * t - 20
            lum[t, :, max(0, x):max(0, x + 20)] = 0.9  # 20 pt 寬的亮條，每幀走 10 pt
        self.assertEqual(transitions(lum), 0)

    def test_flashes_count_while_another_area_keeps_rising(self):
        lum = screen()
        paint(lum, 0, 0, 70, 300, np.linspace(BG, 0.6, 80, dtype=np.float32))  # 一直在慢慢變亮
        paint(lum, 100, 0, 70, 300, levels(80, [5, 15, 25, 35, 45, 55]))  # 同一個視野裡閃三次
        self.assertEqual(transitions(lum), 6)


class PairedTest(unittest.TestCase):
    def test_a_run_needs_an_opposite_neighbour_within_a_second(self):
        # 格 0：升（第 1 幀）、降（第 30 幀）、升（第 100 幀，離上一段超過 60 幀）；格 1：只升一次。
        cells = np.array([0, 0, 0, 1])
        begins = np.array([1, 30, 100, 5])
        dirs = np.array([1, -1, 1, 1], np.int8)
        self.assertEqual(fc.paired(cells, begins, dirs, FPS).tolist(), [True, True, False, False])


class WindowTest(unittest.TestCase):
    def test_full_second_includes_both_end_frames(self):
        # Codex #107 第 2 輪：第 1、10、20、30、40、50、59、60 幀切換＝一秒內 8 次轉折、4 次閃光。
        lum = screen()
        paint(lum, 13, 21, 117, 117, levels(80, [1, 10, 20, 30, 40, 50, 59, 60]))
        result = fc.max_transitions(lum, FPS, 25)
        self.assertEqual(result['transitions'], 8)
        self.assertEqual(result['window_start'], 1)
        self.assertEqual(result['events'], [(1, 1), (10, -1), (20, 1), (30, -1), (40, 1), (50, -1),
                                            (59, 1), (60, -1)])
        self.assertFalse(fc.within_cap(result['transitions'], 3))

    def test_window_is_fps_plus_one_frames(self):
        lum = screen()
        paint(lum, 13, 21, 117, 117, levels(80, [1, 11, 21, 31, 41, 51, 61]))
        self.assertEqual(transitions(lum), 7)
        lum = screen()
        paint(lum, 13, 21, 117, 117, levels(80, [1, 11, 21, 31, 41, 51, 62]))
        self.assertEqual(transitions(lum), 6)

    def test_keeps_the_state_from_before_the_window(self):
        # 第 0–10 幀慢慢亮 0.105：從第 1 幀才開始看只剩 0.0945，但這次轉折還是要算進第 1–61 幀。
        series = levels(80, [11, 21, 31, 41, 51, 61], low=LIT, high=BG)
        series[:11] = np.linspace(BG, LIT, 11)
        lum = screen()
        paint(lum, 13, 21, 117, 117, series)
        self.assertEqual(transitions(lum), 7)


class LuminanceRuleTest(unittest.TestCase):
    def test_change_under_ten_percent_is_not_a_transition(self):
        lum = screen()
        paint(lum, 13, 21, 150, 150, levels(80, [10, 20, 30, 40], high=BG + 0.095))
        self.assertEqual(transitions(lum), 0)

    def test_both_ends_bright_is_not_a_flash(self):
        lum = screen()
        paint(lum, 13, 21, 150, 150, levels(80, [10, 20, 30, 40], low=0.85, high=0.97))
        self.assertEqual(transitions(lum), 0)


if __name__ == '__main__':
    unittest.main()
