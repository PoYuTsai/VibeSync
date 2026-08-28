// practice-chat 台北時間情境測試（純函式）。

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { taipeiNowLabel, taipeiTimeContextFor } from "./time_context.ts";

Deno.test("taipeiTimeContextFor maps UTC to Taipei wall-clock date and weekend", () => {
  const ctx = taipeiTimeContextFor(new Date("2026-07-03T16:30:00.000Z"));

  assertEquals(ctx.isoDate, "2026-07-04");
  assertEquals(ctx.hour, 0);
  assertEquals(ctx.minute, 30);
  assertEquals(ctx.weekday, 6);
  assertEquals(ctx.isWeekend, true);
  assertEquals(ctx.dayPart, "late_night");
});

Deno.test("taipeiTimeContextFor uses stable day-part boundaries", () => {
  const cases = [
    ["2026-07-06T20:59:00.000Z", "late_night"],
    ["2026-07-06T21:00:00.000Z", "dawn"],
    ["2026-07-06T23:00:00.000Z", "morning"],
    ["2026-07-07T03:00:00.000Z", "noon"],
    ["2026-07-07T06:00:00.000Z", "afternoon"],
    ["2026-07-07T09:00:00.000Z", "early_evening"],
    ["2026-07-07T11:00:00.000Z", "evening"],
    ["2026-07-07T15:00:00.000Z", "late_night"],
  ] as const;

  for (const [iso, dayPart] of cases) {
    assertEquals(taipeiTimeContextFor(new Date(iso)).dayPart, dayPart);
  }
});

Deno.test("taipeiNowLabel 把日期、星期、平日/週末、時刻與時段攤成一行", () => {
  // 台北 2026-08-28（星期五）09:00 ＝ UTC 2026-08-28T01:00Z。
  // 這一天正是真機截圖那場練習：她把星期五講成禮拜三。
  assertEquals(
    taipeiNowLabel(taipeiTimeContextFor(new Date("2026-08-28T01:00:00.000Z"))),
    "2026-08-28（星期五・平日）09:00 早上",
  );
});

Deno.test("taipeiNowLabel 補零到兩位數，且週末標成週末", () => {
  // 台北 2026-08-30（星期日）07:05 ＝ UTC 2026-08-29T23:05Z（跨日）。
  assertEquals(
    taipeiNowLabel(taipeiTimeContextFor(new Date("2026-08-29T23:05:00.000Z"))),
    "2026-08-30（星期日・週末）07:05 早上",
  );
});

Deno.test("taipeiNowLabel 蓋到七個時段標籤與七個星期標籤", () => {
  // 2026-08-24 是星期一，往後七天剛好把星期一到星期日走完。
  const weekdays = [
    "星期一",
    "星期二",
    "星期三",
    "星期四",
    "星期五",
    "星期六",
    "星期日",
  ];
  for (const [index, weekday] of weekdays.entries()) {
    const day = String(24 + index).padStart(2, "0");
    const label = taipeiNowLabel(
      taipeiTimeContextFor(new Date(`2026-08-${day}T04:00:00.000Z`)),
    );
    assertEquals(label.includes(weekday), true, label);
  }

  const dayParts = [
    ["2026-08-27T21:30:00.000Z", "清晨"],
    ["2026-08-27T23:30:00.000Z", "早上"],
    ["2026-08-28T03:30:00.000Z", "中午"],
    ["2026-08-28T06:30:00.000Z", "下午"],
    ["2026-08-28T09:30:00.000Z", "傍晚"],
    ["2026-08-28T11:30:00.000Z", "晚上"],
    ["2026-08-28T15:30:00.000Z", "深夜"],
  ] as const;
  for (const [iso, dayPart] of dayParts) {
    const label = taipeiNowLabel(taipeiTimeContextFor(new Date(iso)));
    assertEquals(label.endsWith(dayPart), true, label);
  }
});
