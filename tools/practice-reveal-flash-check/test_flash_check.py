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
        self.assertEqual(fc.field_pt(25), 234)
        self.assertAlmostEqual(fc.threshold_pt2(20), 8742, delta=1)
        self.assertEqual(fc.field_pt(20), 187)
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
        for y, x in ((10, 10), (10, 150), (150, 10), (150, 150)):  # 4 × 3,600 ＝ 14,400 pt²
            paint(lum, y, x, 60, 60, pulse)
        self.assertEqual(transitions(lum), 2)
        lum[:, 150:210, 150:210] = BG  # 剩三塊 10,800 pt²
        self.assertEqual(transitions(lum), 0)

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
        paint(lum, 0, 0, 117, 117, levels(80, [10]))  # 第 10 幀變亮
        paint(lum, 117, 0, 117, 117, levels(80, [0, 20]))  # 另一塊第 20 幀變暗
        self.assertEqual(transitions(lum), 1)

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
