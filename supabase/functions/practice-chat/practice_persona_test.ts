// practice-chat server 端翻牌選牌測試（deterministic、排除規則、self-consistent）。
// 跑法：deno test supabase/functions/practice-chat/practice_persona_test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  DIFFICULTIES,
  difficultyTuningFor,
  DIFFICULTY_TUNING,
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

// ── 稀有度資料層：server 為唯一真相源，每 persona 20 位 = 4 SR / 8 R / 8 N ──

Deno.test("稀有度：每位 profile 都帶合法 rarity（'sr' | 'r' | 'n'）", () => {
  for (const g of GIRL_PROFILES) {
    assert(
      g.rarity === "sr" || g.rarity === "r" || g.rarity === "n",
      `${g.profileId} rarity=${String(g.rarity)} 不合法`,
    );
  }
});

Deno.test("稀有度：每 persona 4 SR / 8 R / 8 N；總量 SR20 / R40 / N40", () => {
  const perPersona = new Map<string, { sr: number; r: number; n: number }>();
  const total = { sr: 0, r: 0, n: 0 };
  for (const g of GIRL_PROFILES) {
    const c = perPersona.get(g.personaId) ?? { sr: 0, r: 0, n: 0 };
    c[g.rarity]++;
    perPersona.set(g.personaId, c);
    total[g.rarity]++;
  }
  assertEquals(total, { sr: 20, r: 40, n: 40 });
  for (const [personaId, c] of perPersona) {
    assertEquals(c, { sr: 4, r: 8, n: 8 }, `persona ${personaId} 配比不對`);
  }
});

Deno.test("稀有度：既有錨點不漂移（001=N、004=SR；圖鑑測試同錨）", () => {
  assertEquals(getPracticeGirlProfile("practice_girl_001")?.rarity, "n");
  assertEquals(getPracticeGirlProfile("practice_girl_004")?.rarity, "sr");
});

// ── 加權真 gacha：SR 10% / R 30% / N 60%（層內均勻、deterministic）──────────

Deno.test("加權：全池大樣本分布 SR 10%±2% / R 30%±4% / N 60%±5%", () => {
  const counts = { sr: 0, r: 0, n: 0 };
  const total = 5000;
  for (let i = 0; i < total; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: NONE,
      seed: `dist-${i}`,
      catalogSize: 100,
    });
    counts[g.rarity]++;
  }
  const sr = counts.sr / total;
  const r = counts.r / total;
  const n = counts.n / total;
  assert(sr >= 0.08 && sr <= 0.12, `SR 實得 ${sr}，應在 10%±2%`);
  assert(r >= 0.26 && r <= 0.34, `R 實得 ${r}，應在 30%±4%`);
  assert(n >= 0.55 && n <= 0.65, `N 實得 ${n}，應在 60%±5%`);
});

Deno.test("加權：legacy 60 池分布同樣 SR≈10%（切池 gate 與加權正交）", () => {
  const counts = { sr: 0, r: 0, n: 0 };
  const total = 5000;
  for (let i = 0; i < total; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: NONE,
      seed: `legacy-dist-${i}`,
    });
    assert(girlIndex(g.profileId) <= LEGACY_CATALOG_SIZE);
    counts[g.rarity]++;
  }
  const sr = counts.sr / total;
  assert(sr >= 0.08 && sr <= 0.12, `legacy 池 SR 實得 ${sr}，應在 10%±2%`);
});

Deno.test("加權退避：SR 層全排除 → 落層 SR→R（R 實得 ≈ 40%），絕不抽回 SR", () => {
  const srExcluded = new Set(
    GIRL_PROFILES.filter((g) => g.rarity === "sr").map((g) => g.profileId),
  );
  const counts = { sr: 0, r: 0, n: 0 };
  const total = 5000;
  for (let i = 0; i < total; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: srExcluded,
      seed: `fb-sr-${i}`,
      catalogSize: 100,
    });
    counts[g.rarity]++;
  }
  assertEquals(counts.sr, 0);
  const r = counts.r / total;
  assert(r >= 0.36 && r <= 0.44, `SR 空層退到 R：R 實得 ${r}，應在 40%±4%`);
});

Deno.test("加權退避：SR+R 層全排除 → 全部落 N；永遠抽得出人", () => {
  const excluded = new Set(
    GIRL_PROFILES.filter((g) => g.rarity !== "n").map((g) => g.profileId),
  );
  for (let i = 0; i < 200; i++) {
    const g = selectPracticeDrawProfile({
      excludedProfileIds: excluded,
      seed: `fb-srr-${i}`,
      catalogSize: 100,
    });
    assertEquals(g.rarity, "n");
  }
});

Deno.test("加權：deterministic（同 seed + 同池 + 同排除 → 同一位）", () => {
  for (let i = 0; i < 50; i++) {
    const args = {
      excludedProfileIds: new Set(["practice_girl_002"]),
      seed: `det-${i}`,
      catalogSize: 100,
    };
    const a = selectPracticeDrawProfile(args);
    const b = selectPracticeDrawProfile(args);
    assertEquals(a.profileId, b.profileId);
  }
});

// ── 難度調參表（槓桿 A）：起始溫度＋正負 delta 倍率 ─────────────────────

Deno.test("DIFFICULTY_TUNING：三檔精確數值（easy/normal/challenge）", () => {
  assertEquals(DIFFICULTY_TUNING.easy, {
    startTemperature: 35,
    positiveDeltaMultiplier: 1.25,
    negativeDeltaMultiplier: 0.75,
  });
  assertEquals(DIFFICULTY_TUNING.normal, {
    startTemperature: 28,
    positiveDeltaMultiplier: 1.0,
    negativeDeltaMultiplier: 1.0,
  });
  assertEquals(DIFFICULTY_TUNING.challenge, {
    startTemperature: 20,
    positiveDeltaMultiplier: 0.7,
    negativeDeltaMultiplier: 1.3,
  });
});

Deno.test("DIFFICULTY_TUNING：每個 DIFFICULTIES id 都有對應 tuning", () => {
  for (const d of DIFFICULTIES) {
    const tuning = DIFFICULTY_TUNING[d.id];
    assert(tuning, `難度 ${d.id} 缺少 tuning`);
    assert(typeof tuning.startTemperature === "number");
    assert(typeof tuning.positiveDeltaMultiplier === "number");
    assert(typeof tuning.negativeDeltaMultiplier === "number");
  }
});

Deno.test("difficultyTuningFor：合法難度回傳對應 tuning", () => {
  assertEquals(difficultyTuningFor("easy"), DIFFICULTY_TUNING.easy);
  assertEquals(difficultyTuningFor("normal"), DIFFICULTY_TUNING.normal);
  assertEquals(difficultyTuningFor("challenge"), DIFFICULTY_TUNING.challenge);
});

Deno.test("difficultyTuningFor：未知/缺席一律 fallback 到 normal", () => {
  assertEquals(difficultyTuningFor("bogus"), DIFFICULTY_TUNING.normal);
  assertEquals(difficultyTuningFor(undefined), DIFFICULTY_TUNING.normal);
  assertEquals(difficultyTuningFor(""), DIFFICULTY_TUNING.normal);
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
