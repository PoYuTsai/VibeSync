// practice-chat 生活事件情境測試（純函式）。

import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildPracticeSceneContext } from "./life_schedule.ts";
import { taipeiTimeContextFor } from "./time_context.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";

const profile = resolvePracticeProfile({
  profileId: "practice_girl_001",
  difficulty: "easy",
});

Deno.test("buildPracticeSceneContext is deterministic for the same profile, date, day-part, and thread", () => {
  const time = taipeiTimeContextFor(new Date("2026-07-07T11:30:00.000Z"));
  const first = buildPracticeSceneContext({
    profile,
    time,
    visiblePracticeThreadId: "thread-a",
  });
  const second = buildPracticeSceneContext({
    profile,
    time,
    visiblePracticeThreadId: "thread-a",
  });

  assertEquals(first, second);
  assert(first.id.length > 0);
  assert(first.statusLine.length > 0);
  assert(first.promptLine.length > 0);
});

Deno.test("buildPracticeSceneContext changes across day-parts without storing DB state", () => {
  const evening = buildPracticeSceneContext({
    profile,
    time: taipeiTimeContextFor(new Date("2026-07-07T11:30:00.000Z")),
    visiblePracticeThreadId: "thread-a",
  });
  const lateNight = buildPracticeSceneContext({
    profile,
    time: taipeiTimeContextFor(new Date("2026-07-07T15:30:00.000Z")),
    visiblePracticeThreadId: "thread-a",
  });

  assertNotEquals(evening.id, lateNight.id);
  assertEquals(lateNight.replyTempo, "short");
});

Deno.test("buildPracticeSceneContext keeps late-night scenes short even on weekends", () => {
  const lateNightWeekend = taipeiTimeContextFor(
    new Date("2026-07-10T16:30:00.000Z"),
  );

  for (let index = 0; index < 30; index++) {
    const scene = buildPracticeSceneContext({
      profile,
      time: lateNightWeekend,
      visiblePracticeThreadId: `weekend-late-${index}`,
    });

    assertEquals(scene.replyTempo, "short");
  }
});

Deno.test("buildPracticeSceneContext can use interest-tag events as natural topic hooks", () => {
  const yogaProfile = resolvePracticeProfile({
    profileId: "practice_girl_012",
    difficulty: "normal",
  });
  const time = taipeiTimeContextFor(new Date("2026-07-11T08:00:00.000Z"));
  const scene = buildPracticeSceneContext({
    profile: yogaProfile,
    time,
    visiblePracticeThreadId: "interest-thread",
  });

  assert(
    scene.promptLine.includes("如果對方問") === false,
    "promptLine should describe her current life state, not usage instructions",
  );
  assert(["short", "normal", "engaged"].includes(scene.replyTempo));
});
