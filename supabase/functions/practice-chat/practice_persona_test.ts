// practice-chat server 端翻牌選牌測試（deterministic、排除規則、self-consistent）。
// 跑法：deno test supabase/functions/practice-chat/practice_persona_test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  GIRL_PROFILES,
  getPracticeGirlProfile,
  LEGACY_CATALOG_SIZE,
  resolveDrawPoolSize,
  selectPracticeDrawProfile,
} from "./practice_persona.ts";

const NONE = new Set<string>();

/** practice_girl_042 → 42（切池斷言用）。 */
function girlIndex(profileId: string): number {
  return Number(profileId.replace("practice_girl_", ""));
}

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

// ── catalogSize 相容 gate：舊 client（catalog 只有 60 位）絕不抽到 061+ ──────

Deno.test("resolveDrawPoolSize：缺席/非正整數/非法型別一律降級 60（fail-closed 到舊池）", () => {
  assertEquals(resolveDrawPoolSize(undefined), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize(null), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize(0), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize(-1), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize(1.5), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize("abc"), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize("100"), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize(Number.NaN), LEGACY_CATALOG_SIZE);
  assertEquals(resolveDrawPoolSize(true), LEGACY_CATALOG_SIZE);
});

Deno.test("resolveDrawPoolSize：合法正整數 clamp 到 [60, 全 catalog]", () => {
  assertEquals(resolveDrawPoolSize(30), LEGACY_CATALOG_SIZE); // 低於舊池 → 抬到 60
  assertEquals(resolveDrawPoolSize(60), 60);
  assertEquals(resolveDrawPoolSize(100), Math.min(100, GIRL_PROFILES.length));
  assertEquals(resolveDrawPoolSize(999), GIRL_PROFILES.length); // 超過池長 → clamp
});

Deno.test("選牌：無 catalogSize → 多 seed 抽樣全部落在 001–060（legacy 池）", () => {
  for (let i = 0; i < 200; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: NONE,
      seed: `legacy-${i}`,
    });
    assert(
      girlIndex(g.profileId) <= LEGACY_CATALOG_SIZE,
      `無 catalogSize 不該抽到 ${g.profileId}`,
    );
  }
});

Deno.test("選牌：catalogSize=100 → 抽得到 061 以後的新池", () => {
  let sawExpanded = false;
  for (let i = 0; i < 200; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: NONE,
      seed: `full-${i}`,
      catalogSize: 100,
    });
    if (girlIndex(g.profileId) > LEGACY_CATALOG_SIZE) sawExpanded = true;
  }
  assert(sawExpanded, "catalogSize=100 抽 200 次應至少出現一位 061+");
});

Deno.test("選牌：非法 catalogSize（30/0/-1/1.5/'abc'）→ 全部降級 60 池", () => {
  const bads: unknown[] = [30, 0, -1, 1.5, "abc"];
  for (const bad of bads) {
    for (let i = 0; i < 40; i++) {
      const g = selectPracticeDrawProfile({
        excludedProfileIds: NONE,
        seed: `bad-${String(bad)}-${i}`,
        catalogSize: bad,
      });
      assert(
        girlIndex(g.profileId) <= LEGACY_CATALOG_SIZE,
        `catalogSize=${String(bad)} 不該抽到 ${g.profileId}`,
      );
    }
  }
});

Deno.test("選牌：切池後排除退避（撞號/全排除 fallback）也絕不逃出切池", () => {
  // 排除 legacy 池前 59 位 → 只剩 060 可抽（不可逃到 061+）。
  const excluded = new Set(
    GIRL_PROFILES.slice(0, LEGACY_CATALOG_SIZE - 1).map((g) => g.profileId),
  );
  const only = selectPracticeDrawProfile({
    excludedProfileIds: excluded,
    seed: "corner-1",
  });
  assertEquals(girlIndex(only.profileId), LEGACY_CATALOG_SIZE);

  // legacy 池 60 位全排除＋current 也在池內 → 退避後仍只從 001–060 選。
  const all = new Set(
    GIRL_PROFILES.slice(0, LEGACY_CATALOG_SIZE).map((g) => g.profileId),
  );
  for (let i = 0; i < 40; i++) {
    const g = selectPracticeDrawProfile({
      currentProfileId: "practice_girl_001",
      excludedProfileIds: all,
      seed: `corner-2-${i}`,
    });
    assert(
      girlIndex(g.profileId) <= LEGACY_CATALOG_SIZE,
      `退避不得逃出切池：抽到 ${g.profileId}`,
    );
  }
});
