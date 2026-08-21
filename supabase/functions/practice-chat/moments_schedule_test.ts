// 練習室動態貼文每日排程測試（純函式、零 DB）。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MAX_MOMENT_SLOTS_PER_DAY,
  momentPlanFor,
  momentPostPropensityFor,
  momentQuietDayPartsFor,
  PROFESSION_SCHEDULE_COVERAGE,
  professionsWithoutPostableDayParts,
} from "./moments_schedule.ts";
import { isMomentImageId, SCENE_IMAGE_COUNT } from "./moments_image_catalog.ts";
import { getPracticeGirlProfile, GIRL_PROFILES } from "./practice_persona.ts";
import { taipeiTimeContextFor } from "./time_context.ts";

const girl = getPracticeGirlProfile("practice_girl_001")!;

/** 台北時間某日中午（UTC+8）。日期只用到 isoDate，時分不影響計畫。 */
function taipeiDay(isoDate: string) {
  return taipeiTimeContextFor(new Date(`${isoDate}T04:00:00.000Z`));
}

/** 連續 days 天，把整份 catalog 的計畫攤平。 */
function planEveryGirlOver(days: number) {
  const plans = [];
  for (let day = 0; day < days; day++) {
    const date = new Date(Date.UTC(2026, 8, 1 + day, 4, 0, 0));
    const time = taipeiTimeContextFor(date);
    for (const profile of GIRL_PROFILES) {
      plans.push(momentPlanFor({ girl: profile, time }));
    }
  }
  return plans;
}

Deno.test("momentPlanFor is deterministic for the same profile and date", () => {
  const time = taipeiDay("2026-09-03");
  assertEquals(
    momentPlanFor({ girl, time }),
    momentPlanFor({ girl, time }),
  );
});

Deno.test("momentPlanFor never depends on the caller's clock within a day", () => {
  const morning = taipeiTimeContextFor(new Date("2026-09-03T01:00:00.000Z"));
  const midnight = taipeiTimeContextFor(new Date("2026-09-03T15:00:00.000Z"));

  assertEquals(morning.isoDate, midnight.isoDate);
  assertEquals(
    momentPlanFor({ girl, time: morning }),
    momentPlanFor({ girl, time: midnight }),
  );
});

Deno.test("momentPlanFor produces both quiet days and posting days", () => {
  let quietDays = 0;
  let postingDays = 0;
  for (let day = 1; day <= 60; day++) {
    const time = taipeiTimeContextFor(new Date(Date.UTC(2026, 8, day, 4)));
    const plan = momentPlanFor({ girl, time });
    if (plan.slots.length === 0) quietDays++;
    else postingDays++;
  }

  assert(quietDays > 0, "she should have days without any post");
  assert(postingDays > 0, "she should have days with a post");
});

Deno.test("a second post in one day stays rarer than the first", () => {
  const plans = planEveryGirlOver(30);
  const firstSlots =
    plans.filter((plan) => plan.slots.some((slot) => slot.slot === 0)).length;
  const secondSlots =
    plans.filter((plan) => plan.slots.some((slot) => slot.slot === 1)).length;

  assert(secondSlots > 0, "two-post days should exist at all");
  assert(
    secondSlots * 2 < firstSlots,
    `second slot ${secondSlots} should be far rarer than first ${firstSlots}`,
  );
});

Deno.test("catalog-wide posting volume stays in the designed band", () => {
  const days = 30;
  const plans = planEveryGirlOver(days);
  const posts = plans.reduce((sum, plan) => sum + plan.slots.length, 0);
  const perGirlPerDay = posts / (GIRL_PROFILES.length * days);

  // 設計報告預估平均約 0.7 則／角色／天；上界由 slot 數硬鎖在 2。
  assert(
    perGirlPerDay > 0.45 && perGirlPerDay < 0.95,
    `expected ~0.7 posts per girl per day, got ${perGirlPerDay}`,
  );
});

Deno.test("plans never exceed the daily slot cap and keep slots ordered", () => {
  for (const plan of planEveryGirlOver(14)) {
    assert(plan.slots.length <= MAX_MOMENT_SLOTS_PER_DAY);
    const slotNumbers = plan.slots.map((slot) => slot.slot);
    assertEquals(slotNumbers, [...slotNumbers].sort((a, b) => a - b));
    assertEquals(new Set(slotNumbers).size, slotNumbers.length);
  }
});

Deno.test("nobody is scheduled to post at dawn", () => {
  for (const plan of planEveryGirlOver(21)) {
    for (const slot of plan.slots) {
      assert(slot.dayPart !== "dawn", `${plan.profileId} planned a dawn post`);
    }
  }
});

Deno.test("nobody is ever scheduled during their own working hours", () => {
  // 複審 2026-08-21 P2：原本只具體驗醫院護理師一種職業，而作息表當時只覆蓋
  // 43 種裡的 9 種。現在作息表對全部職業 exhaustive，測試也掃全 catalog。
  for (const profile of GIRL_PROFILES) {
    const quiet = momentQuietDayPartsFor(profile.professionId);
    for (let day = 1; day <= 60; day++) {
      const time = taipeiTimeContextFor(new Date(Date.UTC(2026, 8, day, 4)));
      for (const slot of momentPlanFor({ girl: profile, time }).slots) {
        assert(
          !quiet.includes(slot.dayPart),
          `${profile.profileId} (${profile.professionId}) planned a post ` +
            `during a working ${slot.dayPart}`,
        );
      }
    }
  }
});

Deno.test("the working-hours table covers every profession in the catalog", () => {
  // 型別是 Record<ProfessionId, ...> 已經保證 exhaustive；這一行擋的是有人
  // 之後改回 Partial<> 讓沒填的職業默默變成「全天都有空」。
  assertEquals(PROFESSION_SCHEDULE_COVERAGE, 43);
  for (const profile of GIRL_PROFILES) {
    assert(
      Array.isArray(momentQuietDayPartsFor(profile.professionId)),
      `${profile.professionId} has no working-hours entry`,
    );
  }
});

Deno.test("weekend-only themes never appear on weekdays", () => {
  const weekendThemeIds = new Set([
    "weekend_brunch",
    "weekend_outing",
    "weekend_slow",
  ]);

  for (let day = 1; day <= 60; day++) {
    const time = taipeiTimeContextFor(new Date(Date.UTC(2026, 8, day, 4)));
    if (time.isWeekend) continue;
    for (const profile of GIRL_PROFILES) {
      for (const slot of momentPlanFor({ girl: profile, time }).slots) {
        assert(
          !weekendThemeIds.has(slot.themeId),
          `${slot.themeId} leaked into a weekday`,
        );
      }
    }
  }
});

Deno.test("image candidates are allowlisted and only present when wanted", () => {
  let withImage = 0;
  let textOnly = 0;

  for (const plan of planEveryGirlOver(21)) {
    for (const slot of plan.slots) {
      if (slot.wantsImage) {
        withImage++;
        assert(slot.imageCandidates.length > 0);
        for (const id of slot.imageCandidates) {
          assert(isMomentImageId(id), `${id} is not in the image allowlist`);
        }
      } else {
        textOnly++;
        assertEquals(slot.imageCandidates.length, 0);
      }
    }
  }

  // 兩種貼文型態都要真的出現（純文字／圖＋文）。
  assert(withImage > 0, "image posts should exist");
  assert(textOnly > 0, "text-only posts should exist");
});

Deno.test("scene image budget stays at the agreed 20 assets", () => {
  // 超過就要重新評估 App 體積（設計報告決定 D）；改動時請同步更新報告。
  assertEquals(SCENE_IMAGE_COUNT, 20);
});

Deno.test("every profile keeps a usable theme pool and a real brief", () => {
  for (const profile of GIRL_PROFILES) {
    let sawSlot = false;
    for (let day = 1; day <= 21; day++) {
      const time = taipeiTimeContextFor(new Date(Date.UTC(2026, 8, day, 4)));
      for (const slot of momentPlanFor({ girl: profile, time }).slots) {
        sawSlot = true;
        assert(slot.themeId.length > 0);
        assert(slot.brief.length > 0);
      }
    }
    assert(sawSlot, `${profile.profileId} never posts in three weeks`);
  }
});

Deno.test("post propensity stays inside the clamped range", () => {
  for (const profile of GIRL_PROFILES) {
    const propensity = momentPostPropensityFor(profile);
    assert(
      propensity >= 0.15 && propensity <= 0.85,
      `${profile.profileId} propensity ${propensity} escaped the clamp`,
    );
  }
});

// 複審 2026-08-21 的非阻擋提醒：原本 momentPlanFor 有一段「可用時段被濾空就
// 退回未過濾時段」的 fallback，與 PROFESSION_QUIET_DAY_PARTS 的硬規則矛盾。
// 那段已移除（可用時段現在跟題材綁在一起回傳，沒有那個分支可寫），改成在
// 題材池真的空掉時大聲丟錯。以下兩個測試守住這個新契約。

Deno.test("no profession has its whole postable window marked quiet", () => {
  // 這是最可能的未來破壞方式：有人擴充作息表時把某個職業所有時段都標成上班。
  assertEquals(professionsWithoutPostableDayParts(), []);
});

Deno.test("planning never throws for any profile across a long window", () => {
  for (const profile of GIRL_PROFILES) {
    for (let day = 1; day <= 60; day++) {
      const time = taipeiTimeContextFor(new Date(Date.UTC(2026, 8, day, 4)));
      momentPlanFor({ girl: profile, time });
    }
  }
});
