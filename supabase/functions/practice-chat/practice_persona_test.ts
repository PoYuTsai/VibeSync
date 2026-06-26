// practice-chat server 端翻牌選牌測試（deterministic、排除規則、self-consistent）。
// 跑法：deno test supabase/functions/practice-chat/practice_persona_test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  GIRL_PROFILES,
  getPracticeGirlProfile,
  selectPracticeDrawProfile,
} from "./practice_persona.ts";

const NONE = new Set<string>();

Deno.test("選牌：回傳的 profileId 是 catalog 內合法且 self-consistent 的一位", () => {
  const g = selectPracticeDrawProfile({ excludedProfileIds: NONE, seed: "s1" });
  const looked = getPracticeGirlProfile(g.profileId);
  assertEquals(looked, g); // 反查同一物件 → ids 互相一致
  assertEquals(g.photoId, g.profileId); // builder：photoId = profileId
  assert(typeof g.nameId === "string" && g.nameId.length > 0);
  assert(typeof g.personaId === "string" && g.personaId.length > 0);
});

Deno.test("選牌：deterministic（同 seed + 同排除 → 同結果）", () => {
  const a = selectPracticeDrawProfile({ excludedProfileIds: NONE, seed: "abc" });
  const b = selectPracticeDrawProfile({ excludedProfileIds: NONE, seed: "abc" });
  assertEquals(a.profileId, b.profileId);
});

Deno.test("選牌：不同 seed 通常給不同結果（抽樣多個 seed 至少有變化）", () => {
  const ids = new Set<string>();
  for (let i = 0; i < 12; i++) {
    ids.add(
      selectPracticeDrawProfile({ excludedProfileIds: NONE, seed: `seed-${i}` })
        .profileId,
    );
  }
  assert(ids.size > 1, "12 個不同 seed 應產生多於 1 種結果");
});

Deno.test("選牌：排除 currentProfileId（有替代時絕不回同一位）", () => {
  const first = selectPracticeDrawProfile({
    excludedProfileIds: NONE,
    seed: "x",
  });
  const second = selectPracticeDrawProfile({
    currentProfileId: first.profileId,
    excludedProfileIds: NONE,
    seed: "x",
  });
  assert(second.profileId !== first.profileId);
});

Deno.test("選牌：排除 excludedProfileIds 內的所有 profile", () => {
  const excluded = new Set(
    GIRL_PROFILES.slice(0, 10).map((g) => g.profileId),
  );
  for (let i = 0; i < 20; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: excluded,
      seed: `e-${i}`,
    });
    assert(!excluded.has(g.profileId), `不該回排除中的 ${g.profileId}`);
  }
});

Deno.test("getPracticeGirlProfile：未知 id → undefined", () => {
  assertEquals(getPracticeGirlProfile("practice_girl_999"), undefined);
  assertEquals(getPracticeGirlProfile("not-a-profile"), undefined);
});
