// 貼文的具體時刻（設計報告與 PR #22 之間的真實缺口 #1／#2）。
//
// MomentSlotPlan 只有 dayPart（時段桶），沒有具體時間。feed 要顯示「下午
// 3:20」這種相對時間，也要判斷「這則到時間了沒」——早上 8 點不該看到她
// 今晚 23:30 的貼文。所以需要一個決定論純函式把
// (profileId, isoDate, slot, dayPart) 映成具體台北時刻。
//
// late_night 特別處理：time_context 的 dayPartFor 把 23 點與 0-4 點都算成
// late_night，但 isoDate 在 00:00 就翻頁了，所以「post_date = D 的 late_night
// 這一則」只能落在 D 的 23:00-23:59，否則會出現 post_date 與顯示時間對不
// 起來的貼文。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { MOMENT_DAY_PART_WINDOWS, momentPostedAtFor } from "./moments_time.ts";
import { MOMENT_SLOT_COUNT } from "./moments_constants.ts";
import { type TaipeiDayPart, taipeiTimeContextFor } from "./time_context.ts";
import { GIRL_PROFILES } from "./practice_persona.ts";
import { momentPlanFor } from "./moments_schedule.ts";

const POSTABLE: readonly TaipeiDayPart[] = [
  "morning",
  "noon",
  "afternoon",
  "early_evening",
  "evening",
  "late_night",
];

function taipeiPartsOf(at: Date): { isoDate: string; hour: number } {
  const ctx = taipeiTimeContextFor(at);
  return { isoDate: ctx.isoDate, hour: ctx.hour };
}

Deno.test("同輸入永遠同輸出", () => {
  for (const dayPart of POSTABLE) {
    const a = momentPostedAtFor({
      profileId: "practice_girl_007",
      isoDate: "2026-08-22",
      slot: 0,
      dayPart,
    });
    const b = momentPostedAtFor({
      profileId: "practice_girl_007",
      isoDate: "2026-08-22",
      slot: 0,
      dayPart,
    });
    assertEquals(a.getTime(), b.getTime());
  }
});

Deno.test("時刻一定落在該 dayPart 的台北小時區間內", () => {
  for (const girl of GIRL_PROFILES) {
    for (const dayPart of POSTABLE) {
      for (let slot = 0; slot < MOMENT_SLOT_COUNT; slot += 1) {
        const at = momentPostedAtFor({
          profileId: girl.profileId,
          isoDate: "2026-08-22",
          slot,
          dayPart,
        });
        const { hour } = taipeiPartsOf(at);
        const window = MOMENT_DAY_PART_WINDOWS[dayPart];
        assert(
          hour >= window.startHour && hour < window.endHourExclusive,
          `${girl.profileId} ${dayPart} slot${slot} 落在台北 ${hour} 點，` +
            `不在 [${window.startHour}, ${window.endHourExclusive})`,
        );
      }
    }
  }
});

Deno.test("台北日不會漂移：算出來的時刻仍在 post_date 當天", () => {
  for (const isoDate of ["2026-01-01", "2026-08-22", "2026-12-31"]) {
    for (const dayPart of POSTABLE) {
      for (let slot = 0; slot < MOMENT_SLOT_COUNT; slot += 1) {
        const at = momentPostedAtFor({
          profileId: "practice_girl_042",
          isoDate,
          slot,
          dayPart,
        });
        assertEquals(
          taipeiPartsOf(at).isoDate,
          isoDate,
          `${isoDate} ${dayPart}`,
        );
      }
    }
  }
});

Deno.test("late_night 收斂在 post_date 當天的 23:00-23:59，不會跑到隔天凌晨", () => {
  assertEquals(MOMENT_DAY_PART_WINDOWS.late_night, {
    startHour: 23,
    endHourExclusive: 24,
  });
  for (const girl of GIRL_PROFILES) {
    for (let slot = 0; slot < MOMENT_SLOT_COUNT; slot += 1) {
      const at = momentPostedAtFor({
        profileId: girl.profileId,
        isoDate: "2026-08-22",
        slot,
        dayPart: "late_night",
      });
      const { isoDate, hour } = taipeiPartsOf(at);
      assertEquals(isoDate, "2026-08-22");
      assertEquals(hour, 23);
    }
  }
});

Deno.test("同一天同一時段的兩個 slot 時刻嚴格遞增", () => {
  for (const girl of GIRL_PROFILES) {
    for (const dayPart of POSTABLE) {
      let previous = -Infinity;
      for (let slot = 0; slot < MOMENT_SLOT_COUNT; slot += 1) {
        const at = momentPostedAtFor({
          profileId: girl.profileId,
          isoDate: "2026-08-22",
          slot,
          dayPart,
        }).getTime();
        assert(
          at > previous,
          `${girl.profileId} ${dayPart}：slot${slot} 的時刻沒有比前一個 slot 晚`,
        );
        previous = at;
      }
    }
  }
});

Deno.test("dawn 不排貼文，但仍有定義好的區間（防呆，不得丟例外）", () => {
  const at = momentPostedAtFor({
    profileId: "practice_girl_001",
    isoDate: "2026-08-22",
    slot: 0,
    dayPart: "dawn",
  });
  const { hour } = taipeiPartsOf(at);
  assert(hour >= 5 && hour < 7);
});

Deno.test("不同角色在同一時段不會全部擠在同一分鐘", () => {
  const minutes = new Set(
    GIRL_PROFILES.map((girl) =>
      momentPostedAtFor({
        profileId: girl.profileId,
        isoDate: "2026-08-22",
        slot: 0,
        dayPart: "evening",
      }).getTime()
    ),
  );
  assert(minutes.size > 20, `100 位角色只散在 ${minutes.size} 個時刻，太集中`);
});

Deno.test("排程真的產出的每一個 slot 都算得出時刻", () => {
  let checked = 0;
  for (const girl of GIRL_PROFILES.slice(0, 20)) {
    for (let day = 0; day < 7; day += 1) {
      const at = new Date(Date.UTC(2026, 7, 22 + day, 3, 0, 0));
      const time = taipeiTimeContextFor(at);
      const plan = momentPlanFor({ girl, time });
      for (const slotPlan of plan.slots) {
        const postedAt = momentPostedAtFor({
          profileId: plan.profileId,
          isoDate: plan.isoDate,
          slot: slotPlan.slot,
          dayPart: slotPlan.dayPart,
        });
        assertEquals(taipeiPartsOf(postedAt).isoDate, plan.isoDate);
        checked += 1;
      }
    }
  }
  assert(checked > 0, "抽樣視窗內應該至少有一則貼文");
});
