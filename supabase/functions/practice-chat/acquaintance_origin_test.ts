// practice-chat 認識管道背景測試（純函式）。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ACQUAINTANCE_ORIGINS,
  type AcquaintanceOriginId,
  buildAcquaintanceOrigin,
  eligibleAcquaintanceOrigins,
  getAcquaintanceOrigin,
  isAcquaintanceOriginId,
} from "./acquaintance_origin.ts";
import { GIRL_PROFILES, resolvePracticeProfile } from "./practice_persona.ts";

const profile = resolvePracticeProfile({
  profileId: "practice_girl_001",
  difficulty: "normal",
});

Deno.test("每個認識管道都填滿 prompt 需要的欄位，且標籤唯一", () => {
  const ids = new Set<string>();
  const labels = new Set<string>();
  for (const origin of ACQUAINTANCE_ORIGINS) {
    assert(!ids.has(origin.id), `duplicate id: ${origin.id}`);
    assert(!labels.has(origin.label), `duplicate label: ${origin.label}`);
    ids.add(origin.id);
    labels.add(origin.label);
    for (
      const field of [
        origin.label,
        origin.sharedFact,
        origin.stancePrompt,
        origin.unverifiedGuard,
        origin.hintFocus,
        origin.debriefStandard,
      ]
    ) {
      assert(field.trim().length > 0, `${origin.id} has an empty prompt field`);
    }
    assert(
      ["low", "medium", "high"].includes(origin.guardLevel),
      `${origin.id} guardLevel`,
    );
  }
  assert(ACQUAINTANCE_ORIGINS.length >= 7, "場景池要夠隨機才有練習價值");
});

Deno.test("同一個 thread 永遠解析到同一個認識管道（跨輪不變）", () => {
  const first = buildAcquaintanceOrigin({ profile, threadId: "thread-a" });
  const second = buildAcquaintanceOrigin({ profile, threadId: "thread-a" });
  assertEquals(first, second);
});

Deno.test("不同 thread / 不同對象會抽到不同場景（整體有分佈）", () => {
  const seen = new Set<string>();
  for (let index = 0; index < 60; index++) {
    seen.add(
      buildAcquaintanceOrigin({ profile, threadId: `thread-${index}` }).id,
    );
  }
  assert(seen.size >= 5, `expected varied origins, got ${seen.size}`);

  const perProfile = new Set<string>();
  for (const girl of GIRL_PROFILES.slice(0, 40)) {
    perProfile.add(
      buildAcquaintanceOrigin({
        profile: resolvePracticeProfile({
          profileId: girl.profileId,
          difficulty: "normal",
        }),
        threadId: "same-thread-id",
      }).id,
    );
  }
  assert(
    perProfile.size >= 4,
    `expected varied origins, got ${perProfile.size}`,
  );
});

Deno.test("校園認識只發給還在學校的對象，其餘管道對所有人開放", () => {
  for (const girl of GIRL_PROFILES) {
    const pool = eligibleAcquaintanceOrigins(girl);
    assert(pool.length > 0, `${girl.profileId} has no eligible origin`);
    const hasCampus = pool.some((origin) => origin.id === "campus");
    const isStudent = girl.professionId === "college_student" ||
      girl.professionId === "graduate_student";
    assertEquals(hasCampus, isStudent, `${girl.profileId} campus eligibility`);
  }
});

Deno.test("選出的管道一定在該對象的候選池內", () => {
  for (const girl of GIRL_PROFILES.slice(0, 30)) {
    const girlProfile = resolvePracticeProfile({
      profileId: girl.profileId,
      difficulty: "challenge",
    });
    const pool = eligibleAcquaintanceOrigins(girl).map((origin) => origin.id);
    for (const threadId of ["t1", "t2", "t3", "t4", "t5"]) {
      const origin = buildAcquaintanceOrigin({
        profile: girlProfile,
        threadId,
      });
      assert(
        pool.includes(origin.id),
        `${girl.profileId} got ineligible origin ${origin.id}`,
      );
    }
  }
});

Deno.test("認識管道素材不含真實品牌／店名這類禁用專名", () => {
  const forbidden = ["Tinder", "探探", "Bumble", "Instagram限動", "臉書"];
  for (const origin of ACQUAINTANCE_ORIGINS) {
    const text = [
      origin.sharedFact,
      origin.stancePrompt,
      origin.unverifiedGuard,
      origin.hintFocus,
      origin.debriefStandard,
    ].join("\n");
    for (const brand of forbidden) {
      assertEquals(
        text.includes(brand),
        false,
        `${origin.id} mentions ${brand}`,
      );
    }
  }
});

// Codex Q3（2026-08-04）：buildAcquaintanceOrigin 是 pool[fnv1a(seed) %
// pool.length] 現場推導、不落庫。同一個 seed 能不能算出同一個管道，完全
// 依賴 ACQUAINTANCE_ORIGINS 的陣列順序與長度——若日後重排、插入中間、或
// 刪除既有項目，既有進行中的 thread 會突然換場景（她的說法會前後矛盾）。
// 這顆測試把既有十項的順序鎖死：只允許在陣列尾端新增新管道（不影響前面
// 索引），重排/插入中間/刪除都會讓這裡失敗。
const EXPECTED_ACQUAINTANCE_ORIGIN_ORDER: readonly AcquaintanceOriginId[] = [
  "friend_intro",
  "dating_app",
  "street_approach",
  "ig_cold_dm",
  "nightclub",
  "social_gathering",
  "campus",
  "hobby_class",
  "work_encounter",
  "travel_trip",
];

Deno.test("ACQUAINTANCE_ORIGINS 既有管道順序鎖死，只能在陣列尾端新增", () => {
  const actualOrder = ACQUAINTANCE_ORIGINS.map((origin) => origin.id);
  assertEquals(
    actualOrder.slice(0, EXPECTED_ACQUAINTANCE_ORIGIN_ORDER.length),
    EXPECTED_ACQUAINTANCE_ORIGIN_ORDER,
    "既有管道的順序或成員被改動了——這會讓進行中的舊 thread 換場景。" +
      "若是刻意新增管道，請確認新項目加在陣列最後面，再把新 id 補進" +
      "EXPECTED_ACQUAINTANCE_ORIGIN_ORDER 尾端。",
  );
});

Deno.test("id 型別守衛與查表 fallback", () => {
  assert(isAcquaintanceOriginId("friend_intro"));
  assertEquals(isAcquaintanceOriginId("friend_intro_2"), false);
  assertEquals(isAcquaintanceOriginId(42), false);
  assertEquals(getAcquaintanceOrigin("nightclub").id, "nightclub");
});
