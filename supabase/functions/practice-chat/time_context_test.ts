// practice-chat 台北時間情境測試（純函式）。

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { taipeiTimeContextFor } from "./time_context.ts";

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
