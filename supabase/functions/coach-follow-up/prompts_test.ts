// supabase/functions/coach-follow-up/prompts_test.ts
//
// T4 — phase-specific prompt assembly tests. Sync (no assertRejects needed).
// Verifies:
//   - All three phase keys produce a phase-tagged prompt with boundaryReminder ≤ 60
//   - preDateReminder does NOT instruct AI to infer from partnerHint.name
//   - postDateReflection handles 還看不出來 / 太早判斷不出 explicitly
//   - partnerHint.lastConversationSummary appears verbatim in prompt context
//   - banned vocabulary list is part of the system prompt (defense-in-depth with
//     validate.ts::assertCardSafe — both layers must agree on the list)

import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildCoachFollowUpPrompt } from "./prompts.ts";

Deno.test("prepareInvite prompt includes phase tag + boundary instruction + ≤60 cap", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "C" },
  );
  assertStringIncludes(p, "準備邀約");
  assertStringIncludes(p, "boundaryReminder");
  assertStringIncludes(p, "≤ 60");
});

Deno.test("preDateReminder prompt includes phase tag + boundary instruction", () => {
  const p = buildCoachFollowUpPrompt(
    "preDateReminder",
    { q1: "明天" },
    { name: "Candy" },
  );
  assertStringIncludes(p, "約會前提醒");
  assertStringIncludes(p, "boundaryReminder");
});

Deno.test("postDateReflection prompt includes phase tag + boundary instruction", () => {
  const p = buildCoachFollowUpPrompt(
    "postDateReflection",
    { q1: "卡卡的", q2: "stillUnclear" },
    { name: "X" },
  );
  assertStringIncludes(p, "約會後復盤");
  assertStringIncludes(p, "boundaryReminder");
});

Deno.test("preDateReminder does NOT instruct inference from partner name", () => {
  const p = buildCoachFollowUpPrompt(
    "preDateReminder",
    { q1: "今天" },
    { name: "Candy" },
  );
  // The instruction "根據對方名字" or "從名字推測" must NOT appear — name is display only
  assertEquals(p.includes("根據對方名字"), false);
  assertEquals(p.includes("從名字推測"), false);
});

Deno.test("postDateReflection includes 還看不出來 handling", () => {
  const p = buildCoachFollowUpPrompt(
    "postDateReflection",
    { q1: "卡卡的", q2: "stillUnclear" },
    { name: "X" },
  );
  // Either 太早判斷 or 還看不出來 must appear in the phase instructions so the
  // model knows to defuse instead of catastrophising
  const hasSoftHandling =
    p.includes("太早判斷") || p.includes("還看不出來");
  assertEquals(hasSoftHandling, true);
});

Deno.test("partnerHint.lastConversationSummary appears verbatim when provided", () => {
  const summary = "對話氣氛輕鬆，最近聊到週末有空";
  const p = buildCoachFollowUpPrompt(
    "preDateReminder",
    { q1: "明天" },
    { name: "X", lastConversationSummary: summary },
  );
  assertStringIncludes(p, summary);
});

Deno.test("partnerHint.lastConversationSummary section omitted when null/missing", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  // No "[Context] 最近對話摘要" line should be emitted
  assertEquals(p.includes("最近對話摘要"), false);
});

Deno.test("heatScore appears in context when provided", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X", heatScore: 70 },
  );
  assertStringIncludes(p, "heatScore=70");
});

Deno.test("gameStage appears in context when provided", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X", gameStage: "close" },
  );
  assertStringIncludes(p, "gameStage=close");
});

Deno.test("answers q1 always appears", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  assertStringIncludes(p, "q1=fuzzy");
});

Deno.test("answers q2/q3 marked (skip) when null/undefined", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  assertStringIncludes(p, "q2=(skip)");
  assertStringIncludes(p, "q3=(skip)");
});

Deno.test("answers q3 free-text passes through verbatim", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy", q3: "我怕她已讀不回" },
    { name: "X" },
  );
  assertStringIncludes(p, "我怕她已讀不回");
});

Deno.test("prompt lists every banned token (mirrors validate.ts BANNED_TOKENS)", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  // The full BANNED_TOKENS list must appear in the system prompt so the model
  // is explicitly warned. validate.ts::assertCardSafe enforces; this is the
  // belt-and-suspenders pair.
  for (const t of ["收割", "PUA", "控住", "攻略", "壞女人", "高分妹", "玩咖"]) {
    assertStringIncludes(p, t);
  }
});

Deno.test("prompt declares boundaryReminder REQUIRED, never null", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  // System prompt must spell out that boundaryReminder is non-null required
  assertStringIncludes(p, "REQUIRED");
});

Deno.test("prompt instructs JSON-only output", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  assertStringIncludes(p, "JSON");
});
