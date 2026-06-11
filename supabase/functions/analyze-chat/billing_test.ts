// ADR #19 r3 計費測試矩陣（規格凍結版 @ ad10718 + 4000 字補遺）。
//
// 覆蓋：
//   - 分段帶閉區間（1~40=1 / 41~400=ceil/40 / 401~2000=10 / 2001~4000=20 / 4001+=reject）
//   - capability contract（billingProtocolVersion:3，定案 #6 / Codex r3-P1-1）
//   - legacy precedence：clipped floor 1 永不被 cap 覆蓋（定案 #6b / r3-P1-2）
//   - legacy >2000 → cap 10 + log 訊號（定案 #6c）
//   - 4001+ 新舊 client 一視同仁 reject（補遺）
//   - 確認綁定 payload hash + billableChars（定案 #5 / r3-P1-3）
//   - r2 三層 compat fallback 保留（規格 #1）
import {
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  BILLING_PROTOCOL_VERSION,
  bandForBillableChars,
  CHARS_PER_MESSAGE_UNIT,
  computeBillingPayloadHash,
  countPayloadChars,
  MAX_BILLABLE_CHARS,
  OVERCHARGE_UNITS,
  parseBillingProtocolVersion,
  parseConfirmedOvercharge,
  resolveBilling,
  SOFT_CAP_BAND_MAX_CHARS,
  SOFT_CAP_UNITS,
  validateOverchargeConfirmation,
} from "./billing.ts";

const msg = (content: string) => ({ content });
const ofChars = (n: number) => [msg("a".repeat(n))];

Deno.test("billing constants match ADR #19 r3 frozen spec", () => {
  assertEquals(CHARS_PER_MESSAGE_UNIT, 40);
  assertEquals(SOFT_CAP_UNITS, 10);
  assertEquals(SOFT_CAP_BAND_MAX_CHARS, 2000);
  assertEquals(OVERCHARGE_UNITS, 20);
  assertEquals(MAX_BILLABLE_CHARS, 4000);
  assertEquals(BILLING_PROTOCOL_VERSION, 3);
});

// ---------------------------------------------------------------------------
// 分段帶（整數閉區間，Codex r3-P2：40/400 邊界重疊已消除）
// ---------------------------------------------------------------------------

Deno.test("band: 1~40 chars = 1 unit (閉區間)", () => {
  assertEquals(bandForBillableChars(1), { band: "standard", units: 1 });
  assertEquals(bandForBillableChars(40), { band: "standard", units: 1 });
});

Deno.test("band: 41~400 chars = ceil(chars/40)", () => {
  assertEquals(bandForBillableChars(41), { band: "standard", units: 2 });
  assertEquals(bandForBillableChars(80), { band: "standard", units: 2 });
  assertEquals(bandForBillableChars(81), { band: "standard", units: 3 });
  assertEquals(bandForBillableChars(400), { band: "standard", units: 10 });
});

Deno.test("band: 401~2000 chars = 緩衝帶一律 10 units", () => {
  assertEquals(bandForBillableChars(401), { band: "standard", units: 10 });
  assertEquals(bandForBillableChars(1234), { band: "standard", units: 10 });
  assertEquals(bandForBillableChars(2000), { band: "standard", units: 10 });
});

Deno.test("band: 2001~4000 chars = 固定 20 units 確認帶（乙案）", () => {
  assertEquals(bandForBillableChars(2001), { band: "overcharge", units: 20 });
  assertEquals(bandForBillableChars(4000), { band: "overcharge", units: 20 });
});

Deno.test("band: 4001+ chars = reject（4000 字硬上限補遺）", () => {
  assertEquals(bandForBillableChars(4001), { band: "reject" });
  assertEquals(bandForBillableChars(50000), { band: "reject" });
});

Deno.test("band: 0 chars = floor 1（每按一次分析最少扣 1 則）", () => {
  assertEquals(bandForBillableChars(0), { band: "standard", units: 1 });
});

// ---------------------------------------------------------------------------
// countPayloadChars（r2 規格 #4 不重開：UTF-16、trim、不 normalize）
// ---------------------------------------------------------------------------

Deno.test("countPayloadChars: trims each message and sums UTF-16 lengths", () => {
  assertEquals(countPayloadChars([msg(" ab "), msg("c")]), 3);
  // emoji = 2 UTF-16 code units（pricing 文案「1 emoji ≈ 2 字」）
  assertEquals(countPayloadChars([msg("😀")]), 2);
  // zero-width 照算、不 normalize
  assertEquals(countPayloadChars([msg("a​b")]), 3);
});

// ---------------------------------------------------------------------------
// 新 client（billingProtocolVersion: 3）— capability ruleset
// ---------------------------------------------------------------------------

Deno.test("new client: first analysis ≤40 chars charges 1 unit", () => {
  const r = resolveBilling({
    messages: ofChars(35),
    billingProtocolVersion: 3,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 1);
  assertEquals(r.billingPath, "full_no_baseline");
  assertEquals(r.isLegacyClient, false);
});

Deno.test("new client: incremental diff bills only the char delta", () => {
  // soft_cap 每次各自算（定案 #7）：上次滿 10 不影響本次 3
  const r = resolveBilling({
    messages: ofChars(2100),
    billingProtocolVersion: 3,
    previousAnalyzedCharCount: 2000,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 3);
  assertEquals(r.billableChars, 100);
  assertEquals(r.billingPath, "char_baseline");
});

Deno.test("new client: baseline > payload (clipped) clamps to floor 1", () => {
  const r = resolveBilling({
    messages: ofChars(500),
    billingProtocolVersion: 3,
    previousAnalyzedCharCount: 3000,
    hasClippedContextSignal: true,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 1);
  assertEquals(r.billableChars, 0);
});

Deno.test("new client: re-analysis with zero new chars still charges 1", () => {
  const r = resolveBilling({
    messages: ofChars(800),
    billingProtocolVersion: 3,
    previousAnalyzedCharCount: 800,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 1);
});

Deno.test("new client: first analysis >2000 requires confirmation at fixed 20", () => {
  // Codex r3-P1-1 回歸測試：首次分析沒有 baseline 欄位，
  // 不得因此被誤判為 legacy 而繞過 20 則確認。
  const r = resolveBilling({
    messages: ofChars(2500),
    billingProtocolVersion: 3,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "requires_confirmation");
  assertEquals(r.chargedMessageCount, 20);
  assertEquals(r.billingPath, "full_no_baseline");
  assertEquals(r.isLegacyClient, false);
});

Deno.test("new client: incremental diff >2000 also requires confirmation", () => {
  const r = resolveBilling({
    messages: ofChars(5000),
    billingProtocolVersion: 3,
    previousAnalyzedCharCount: 2000,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "requires_confirmation");
  assertEquals(r.chargedMessageCount, 20);
  assertEquals(r.billableChars, 3000);
});

Deno.test("new client: legacy-only baseline field still gets new-client rules", () => {
  // capability contract（定案 #6）：ruleset 由 billingProtocolVersion 決定，
  // baseline 推導層級（previousAnalyzedCount）只決定 baseline，不降級 ruleset。
  const r = resolveBilling({
    messages: [msg("a".repeat(100)), msg("b".repeat(2500))],
    billingProtocolVersion: 3,
    previousAnalyzedCount: 1,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "requires_confirmation");
  assertEquals(r.chargedMessageCount, 20);
  assertEquals(r.billingPath, "legacy_count_derived");
  assertEquals(r.isLegacyClient, false);
});

Deno.test("new client: billable chars 4001+ rejects, never charges", () => {
  const r = resolveBilling({
    messages: ofChars(4001),
    billingProtocolVersion: 3,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "reject_too_long");
  assertEquals(r.chargedMessageCount, 0);
});

Deno.test("new client: future protocol versions are still capability-bearing", () => {
  const r = resolveBilling({
    messages: ofChars(2500),
    billingProtocolVersion: 4,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "requires_confirmation");
  assertEquals(r.isLegacyClient, false);
});

// ---------------------------------------------------------------------------
// 舊 client（無 capability 訊號）— legacy precedence（定案 #6b/#6c）
// ---------------------------------------------------------------------------

Deno.test("legacy: derived baseline bills char delta", () => {
  const r = resolveBilling({
    messages: [msg("a".repeat(200)), msg("b".repeat(100))],
    previousAnalyzedCount: 1,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 3);
  assertEquals(r.billableChars, 100);
  assertEquals(r.billingPath, "legacy_count_derived");
  assertEquals(r.isLegacyClient, true);
  assertEquals(r.legacyOver2000Capped, false);
});

Deno.test("legacy: 401~2000 buffer band = 10, same as new client, no cap log", () => {
  const r = resolveBilling({
    messages: ofChars(450),
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 10);
  assertEquals(r.legacyOver2000Capped, false);
});

Deno.test("legacy: >2000 cannot confirm → user-safe cap 10 + log signal", () => {
  // 定案 #6c：legacy cap 僅適用 2001~4000 確認帶，往便宜方向錯。
  const r = resolveBilling({
    messages: ofChars(2500),
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 10);
  assertEquals(r.billingPath, "full_no_baseline");
  assertEquals(r.isLegacyClient, true);
  assertEquals(r.legacyOver2000Capped, true);
});

Deno.test("legacy: 4001+ rejects — 新舊 client 一視同仁（補遺）", () => {
  const r = resolveBilling({
    messages: ofChars(4200),
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "reject_too_long");
  assertEquals(r.chargedMessageCount, 0);
});

Deno.test("legacy clipped: floor 1 is NEVER overridden by any cap", () => {
  // Codex r3-P1-2 回歸測試：cap 10 是上限不是下限，
  // clipped 合法路徑（N > payload.length + summary 訊號）永遠 floor 1，
  // 就算 payload 總字數落在 2001~4000 確認帶也不得抬成 10 或 20。
  const r = resolveBilling({
    messages: ofChars(3000),
    previousAnalyzedCount: 30,
    hasClippedContextSignal: true,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 1);
  assertEquals(r.billingPath, "legacy_count_exceeds_payload_clipped");
  assertEquals(r.legacyOver2000Capped, false);
});

Deno.test("legacy clipped: huge payload still floor 1, never reject", () => {
  // precedence (b) 先於 (c)：clipped 的 billable diff = 0，
  // 4000 上限作用在 billable chars，clipped 路徑天然不觸發。
  const r = resolveBilling({
    messages: ofChars(5000),
    previousAnalyzedCount: 40,
    hasClippedContextSignal: true,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 1);
  assertEquals(r.billingPath, "legacy_count_exceeds_payload_clipped");
});

Deno.test("legacy: N exceeds payload WITHOUT clipped signal → full charge + warn path", () => {
  const r = resolveBilling({
    messages: ofChars(300),
    previousAnalyzedCount: 30,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 8);
  assertEquals(r.billingPath, "legacy_invalid_full");
});

Deno.test("legacy: invalid N full charge respects cap 10 above 2000", () => {
  const r = resolveBilling({
    messages: ofChars(3000),
    previousAnalyzedCount: -2,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "charge");
  assertEquals(r.chargedMessageCount, 10);
  assertEquals(r.billingPath, "legacy_invalid_full");
  assertEquals(r.legacyOver2000Capped, true);
});

Deno.test("legacy: invalid N full charge above 4000 rejects", () => {
  const r = resolveBilling({
    messages: ofChars(4500),
    previousAnalyzedCount: 1.5,
    hasClippedContextSignal: false,
  });
  assertEquals(r.outcome, "reject_too_long");
  assertEquals(r.chargedMessageCount, 0);
});

// ---------------------------------------------------------------------------
// 確認綁定（定案 #5 / Codex r3-P1-3：hash 優先，billableChars 留作比對）
// ---------------------------------------------------------------------------

Deno.test("payload hash: deterministic 64-char hex over trimmed contents", async () => {
  const a = await computeBillingPayloadHash([msg(" ab "), msg("c")]);
  const b = await computeBillingPayloadHash([msg("ab"), msg("c")]);
  assertEquals(a, b);
  assertEquals(a.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(a), true);
});

Deno.test("payload hash: message boundaries matter", async () => {
  const a = await computeBillingPayloadHash([msg("ab"), msg("c")]);
  const b = await computeBillingPayloadHash([msg("a"), msg("bc")]);
  assertNotEquals(a, b);
});

Deno.test("payload hash: separator never collides with in-content whitespace", async () => {
  // U+0000 分隔：["a b"] 與 ["a","b"] 必須不同 hash。
  const a = await computeBillingPayloadHash([msg("a b")]);
  const b = await computeBillingPayloadHash([msg("a"), msg("b")]);
  assertNotEquals(a, b);
});

Deno.test("payload hash: same length, different content → different hash", async () => {
  // 只綁字數偵測不到「同字數不同內容」— hash 綁定的存在理由。
  const a = await computeBillingPayloadHash([msg("abcd")]);
  const b = await computeBillingPayloadHash([msg("abce")]);
  assertNotEquals(a, b);
});

Deno.test("confirmation: missing → missing", () => {
  assertEquals(
    validateOverchargeConfirmation({
      confirmation: undefined,
      serverPayloadHash: "x".repeat(64),
      serverBillableChars: 2500,
    }),
    "missing",
  );
});

Deno.test("confirmation: hash + chars both match → valid", () => {
  const h = "a".repeat(64);
  assertEquals(
    validateOverchargeConfirmation({
      confirmation: {
        payloadHash: h,
        billableChars: 2500,
        confirmationId: "c-1",
      },
      serverPayloadHash: h,
      serverBillableChars: 2500,
    }),
    "valid",
  );
});

Deno.test("confirmation: payload hash mismatch → mismatch（確認後內容又改過）", () => {
  assertEquals(
    validateOverchargeConfirmation({
      confirmation: {
        payloadHash: "a".repeat(64),
        billableChars: 2500,
        confirmationId: "c-1",
      },
      serverPayloadHash: "b".repeat(64),
      serverBillableChars: 2500,
    }),
    "mismatch",
  );
});

Deno.test("confirmation: billableChars mismatch → mismatch（用戶確認的數字必須是實扣依據）", () => {
  const h = "a".repeat(64);
  assertEquals(
    validateOverchargeConfirmation({
      confirmation: {
        payloadHash: h,
        billableChars: 2400,
        confirmationId: "c-1",
      },
      serverPayloadHash: h,
      serverBillableChars: 2500,
    }),
    "mismatch",
  );
});

// ---------------------------------------------------------------------------
// Request 欄位驗證（index.ts 入口；新欄位嚴格、非法值 400）
// ---------------------------------------------------------------------------

Deno.test("parseBillingProtocolVersion: absent → ok undefined (legacy)", () => {
  assertEquals(parseBillingProtocolVersion(undefined), {
    ok: true,
    value: undefined,
  });
  assertEquals(parseBillingProtocolVersion(null), {
    ok: true,
    value: undefined,
  });
});

Deno.test("parseBillingProtocolVersion: 3 and future integers accepted", () => {
  assertEquals(parseBillingProtocolVersion(3), { ok: true, value: 3 });
  assertEquals(parseBillingProtocolVersion(4), { ok: true, value: 4 });
});

Deno.test("parseBillingProtocolVersion: garbage → invalid (400 at index)", () => {
  assertEquals(parseBillingProtocolVersion("3").ok, false);
  assertEquals(parseBillingProtocolVersion(2).ok, false);
  assertEquals(parseBillingProtocolVersion(3.5).ok, false);
  assertEquals(parseBillingProtocolVersion(-1).ok, false);
  assertEquals(parseBillingProtocolVersion({}).ok, false);
});

Deno.test("parseConfirmedOvercharge: absent → ok undefined", () => {
  assertEquals(parseConfirmedOvercharge(undefined), {
    ok: true,
    value: undefined,
  });
  assertEquals(parseConfirmedOvercharge(null), { ok: true, value: undefined });
});

Deno.test("parseConfirmedOvercharge: well-formed object accepted", () => {
  const h = "0123456789abcdef".repeat(4);
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: h,
      billableChars: 2500,
      confirmationId: "b2f6d4e8-1234-4abc-9def-001122334455",
    }),
    {
      ok: true,
      value: {
        payloadHash: h,
        billableChars: 2500,
        confirmationId: "b2f6d4e8-1234-4abc-9def-001122334455",
      },
    },
  );
});

Deno.test("parseConfirmedOvercharge: malformed → invalid (400 at index)", () => {
  const h = "0123456789abcdef".repeat(4);
  // 非 object
  assertEquals(parseConfirmedOvercharge("yes").ok, false);
  assertEquals(parseConfirmedOvercharge(true).ok, false);
  // hash 非 64-hex
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: "ZZ".repeat(32),
      billableChars: 2500,
      confirmationId: "c-1",
    }).ok,
    false,
  );
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: "abc",
      billableChars: 2500,
      confirmationId: "c-1",
    }).ok,
    false,
  );
  // billableChars 非正整數
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: h,
      billableChars: -1,
      confirmationId: "c-1",
    }).ok,
    false,
  );
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: h,
      billableChars: 2500.5,
      confirmationId: "c-1",
    }).ok,
    false,
  );
  // confirmationId 空 / 過長
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: h,
      billableChars: 2500,
      confirmationId: "",
    }).ok,
    false,
  );
  assertEquals(
    parseConfirmedOvercharge({
      payloadHash: h,
      billableChars: 2500,
      confirmationId: "x".repeat(129),
    }).ok,
    false,
  );
});

// ---------------------------------------------------------------------------
// JS/Dart 鏡像共用樣本（規格 #4：同字串集兩端結果一致）
// Dart 端：test/unit/services/message_calculator_test.dart 讀同一份 fixture。
// ---------------------------------------------------------------------------

Deno.test("mirror fixture: JS side matches shared vectors", async () => {
  const url = new URL(
    "../../../test/fixtures/adr19_billing_mirror_vectors.json",
    import.meta.url,
  );
  const fixture = JSON.parse(await Deno.readTextFile(url)) as {
    vectors: Array<{
      name: string;
      contents: Array<string | { repeat: string; times: number }>;
      charCount: number;
      band: string;
      units: number | null;
      sha256: string;
    }>;
  };
  assertEquals(fixture.vectors.length > 10, true);
  for (const v of fixture.vectors) {
    const contents = v.contents.map((c) =>
      typeof c === "string" ? c : c.repeat.repeat(c.times)
    );
    const messages = contents.map((content) => ({ content }));
    assertEquals(countPayloadChars(messages), v.charCount, `${v.name}: chars`);
    const band = bandForBillableChars(v.charCount);
    assertEquals(band.band, v.band, `${v.name}: band`);
    if (v.units != null) {
      assertEquals(
        (band as { band: string; units: number }).units,
        v.units,
        `${v.name}: units`,
      );
    }
    assertEquals(
      await computeBillingPayloadHash(messages),
      v.sha256,
      `${v.name}: hash`,
    );
  }
});
