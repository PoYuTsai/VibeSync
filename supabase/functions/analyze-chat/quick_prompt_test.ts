import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  QUICK_RESPONSE_SCHEMA_FIELDS,
  QUICK_SYSTEM_PROMPT,
} from "./quick_prompt.ts";

// Why each assertion exists is spelled out — when Haiku quality regresses and
// someone wants to "just add one more rule" to the prompt, these tests are
// what stops the file from drifting back toward the 162KB SYSTEM_PROMPT.

Deno.test("quick prompt enforces the 1.8x reply length rule", () => {
  // Core AI rule from CLAUDE.md: reply length ≤ 1.8x of partner's message.
  // Haiku is faster but less disciplined than Sonnet — the rule must be in
  // the prompt body, not implied.
  assertStringIncludes(QUICK_SYSTEM_PROMPT, "1.8");
});

Deno.test("quick prompt carries the 接住情緒 → 互動感 → 順勢延伸 priority", () => {
  // Plan D1 NOTE: full does not switch direction, so the priority the quick
  // model picks IS the priority the user sees long-term. Must be explicit.
  assertStringIncludes(QUICK_SYSTEM_PROMPT, "接住情緒");
});

Deno.test("quick prompt is a core decision prompt, not only a short rewrite prompt", () => {
  for (const term of ["核心判斷", "先判斷局勢", "最小可執行下一步"]) {
    assertStringIncludes(QUICK_SYSTEM_PROMPT, term);
  }
});

Deno.test("quick prompt classifies the message function before writing a reply", () => {
  for (
    const term of [
      "真問題",
      "情緒球",
      "測試框架",
      "玩笑/曖昧",
      "低投入",
      "邊界/風險",
    ]
  ) {
    assertStringIncludes(QUICK_SYSTEM_PROMPT, term);
  }
});

Deno.test("quick prompt chooses among the five reply styles internally", () => {
  for (const term of ["五種", "延展", "共感", "調侃", "幽默", "觀察"]) {
    assertStringIncludes(QUICK_SYSTEM_PROMPT, term);
  }
  assertStringIncludes(QUICK_SYSTEM_PROMPT, "不要永遠延展");
});

Deno.test("quick prompt preserves user draft intent instead of rewriting personality", () => {
  for (const term of ["用戶草稿", "保留用戶原本想表達的意思", "只修節奏"]) {
    assertStringIncludes(QUICK_SYSTEM_PROMPT, term);
  }
});

Deno.test("quick prompt forbids manipulation / pressure / dropped consent", () => {
  // VibeSync product positioning: practical, on the user's side, mature about
  // boundaries and consent. The short prompt must still encode this — it is
  // the foundation Codex / App Review will look for.
  for (const term of ["不操控", "不施壓"]) {
    assertStringIncludes(QUICK_SYSTEM_PROMPT, term);
  }
});

Deno.test("quick prompt requires JSON-only output", () => {
  // Haiku frequently wraps JSON in prose unless told not to. The slim prompt
  // can't afford a repair round-trip; insist on raw JSON.
  const lower = QUICK_SYSTEM_PROMPT.toLowerCase();
  assertStringIncludes(lower, "json");
});

Deno.test("quick prompt mentions every required schema field", () => {
  // QUICK_RESPONSE_SCHEMA_FIELDS is the canonical list shared with the
  // response parser. Whatever lands here must show up in the prompt body too,
  // otherwise the parser will reject Haiku output for missing keys.
  for (const field of QUICK_RESPONSE_SCHEMA_FIELDS) {
    assertStringIncludes(
      QUICK_SYSTEM_PROMPT,
      field,
      `prompt missing schema field "${field}"`,
    );
  }
});

Deno.test("quick prompt is dramatically shorter than the full SYSTEM_PROMPT", () => {
  // Plan target: quick prompt ≤ 20KB (full SYSTEM_PROMPT is ≈ 162KB). Going
  // over this means Haiku's input becomes large enough that we're paying for
  // the long context AND running on a small model — the worst of both worlds.
  assert(
    QUICK_SYSTEM_PROMPT.length < 20_000,
    `quick prompt grew to ${QUICK_SYSTEM_PROMPT.length} chars (cap 20000)`,
  );
});

Deno.test("quick prompt has no leading/trailing whitespace", () => {
  // Stray whitespace creeps in via copy/paste from larger prompt docs and can
  // mess with cache-hit fingerprinting.
  assertEquals(QUICK_SYSTEM_PROMPT, QUICK_SYSTEM_PROMPT.trim());
});

Deno.test("quick prompt does NOT pull in full-only report sections", () => {
  // Negative assertions catch the worst regression: someone "fixing Haiku
  // quality" by pasting full prompt sections back in. If quick has these,
  // it stops being a quick prompt.
  const fullOnlyMarkers = [
    "scenarioDetected", // psychology matrix lives in full
    "replyOptions",     // 5-style fan-out lives in full
    "healthCheck",      // diagnostic lives in full
    "dimensions",       // radar lives in full
    "targetProfile",    // partner profile extraction lives in full
    "gameStage",        // full report stage label
  ];
  for (const marker of fullOnlyMarkers) {
    assertFalse(
      QUICK_SYSTEM_PROMPT.includes(marker),
      `quick prompt contains full-only token "${marker}"`,
    );
  }
});

Deno.test("schema field list is the expected shape", () => {
  // Pin the exact 6 fields the plan calls out (D1 / Task 1.1). Adding a
  // field here is a deliberate change that needs a matching parser update.
  assertEquals(QUICK_RESPONSE_SCHEMA_FIELDS, [
    "nextStep",
    "pick",
    "recommendedReply",
    "shortReason",
    "insufficientContext",
    "confidence",
  ]);
});
