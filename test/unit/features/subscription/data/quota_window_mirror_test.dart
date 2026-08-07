// 稽核 #1（2026-08-07）：client 直讀 subscriptions row 時必須鏡像 server
// `_shared/quota.ts` 的 UTC 窗判定——跨窗的 stale 計數視為 0，否則昨天用完
// 日額度的免費用戶，今天會被 client 守門擋進 paywall（請求到不了 server）。

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';

void main() {
  group('sameUtcDay / sameUtcMonth（鏡像 server 判定）', () {
    test('同 UTC 日／跨 UTC 日', () {
      expect(
        sameUtcDay(DateTime.utc(2026, 8, 7, 0, 1), DateTime.utc(2026, 8, 7, 23)),
        isTrue,
      );
      expect(
        sameUtcDay(DateTime.utc(2026, 8, 8), DateTime.utc(2026, 8, 7, 23, 59)),
        isFalse,
      );
    });

    test('本地時區時間先轉 UTC 再比（台北 07:00 = UTC 前一日 23:00）', () {
      // UTC+8 的 2026-08-08 07:00 == UTC 2026-08-07 23:00：同 UTC 日。
      final taipeiMorning = DateTime.utc(2026, 8, 7, 23).toLocal();
      expect(sameUtcDay(taipeiMorning, DateTime.utc(2026, 8, 7, 1)), isTrue);
    });

    test('同 UTC 月／跨 UTC 月', () {
      expect(
        sameUtcMonth(DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 31)),
        isTrue,
      );
      expect(
        sameUtcMonth(DateTime.utc(2026, 9, 1), DateTime.utc(2026, 8, 31)),
        isFalse,
      );
    });
  });

  group('usedCountRespectingWindow', () {
    test('同窗 → 保留計數（正常今日已用量不得被清）', () {
      expect(
        usedCountRespectingWindow(
          used: 7,
          resetAtRaw: '2026-08-07T01:00:00Z',
          sameWindow: sameUtcDay,
          now: DateTime.utc(2026, 8, 7, 9),
        ),
        7,
      );
    });

    test('跨窗 → 歸零（昨天用完的日額度今天不得再擋人）', () {
      expect(
        usedCountRespectingWindow(
          used: 10,
          resetAtRaw: '2026-08-06T22:00:00Z',
          sameWindow: sameUtcDay,
          now: DateTime.utc(2026, 8, 7, 1),
        ),
        0,
      );
    });

    test('跨月 → 月計數歸零；同月不同日 → 保留', () {
      expect(
        usedCountRespectingWindow(
          used: 30,
          resetAtRaw: '2026-07-31T23:00:00Z',
          sameWindow: sameUtcMonth,
          now: DateTime.utc(2026, 8, 1, 0, 5),
        ),
        0,
      );
      expect(
        usedCountRespectingWindow(
          used: 12,
          resetAtRaw: '2026-08-02T10:00:00Z',
          sameWindow: sameUtcMonth,
          now: DateTime.utc(2026, 8, 30),
        ),
        12,
      );
    });

    test('reset_at 缺失/壞值 → 0（server null 視為 never reset，全歸零）', () {
      expect(
        usedCountRespectingWindow(
          used: 9,
          resetAtRaw: null,
          sameWindow: sameUtcDay,
          now: DateTime.utc(2026, 8, 7),
        ),
        0,
      );
      expect(
        usedCountRespectingWindow(
          used: 9,
          resetAtRaw: 'not-a-date',
          sameWindow: sameUtcDay,
          now: DateTime.utc(2026, 8, 7),
        ),
        0,
      );
    });

    test('DateTime 型別的 reset_at 也吃（postgrest 可能已解析）', () {
      expect(
        usedCountRespectingWindow(
          used: 5,
          resetAtRaw: DateTime.utc(2026, 8, 7, 2),
          sameWindow: sameUtcDay,
          now: DateTime.utc(2026, 8, 7, 20),
        ),
        5,
      );
    });
  });
}
