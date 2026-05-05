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

Deno.test("prepareInvite prompt includes phase tag + boundary instruction + ≤45 cap", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "C" },
  );
  assertStringIncludes(p, "準備邀約");
  assertStringIncludes(p, "boundaryReminder");
  assertStringIncludes(p, "≤ 45");
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

Deno.test("openCoach prompt includes phase tag + open coach positioning", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "我太有邊界感，不知道怎麼推進" },
    { name: "X" },
  );
  assertStringIncludes(p, "我有其他問題");
  assertStringIncludes(p, "開放式教練診斷");
  assertStringIncludes(p, "不是自由聊天");
  assertStringIncludes(p, "健康主動性");
});

Deno.test("prompt frames healthy initiative with mature go/no-go judgment", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "她有男友還約我幹嘛？" },
    { name: "X" },
  );
  assertStringIncludes(p, "健康的進攻性");
  assertStringIncludes(p, "全局觀");
  assertStringIncludes(p, "何時該收");
  assertStringIncludes(p, "時間成本");
  assertStringIncludes(p, "不值得投入");
  assertStringIncludes(p, "RelationshipRiskAndTimeCostFrame");
  assertStringIncludes(p, "關係透明");
  assertStringIncludes(p, "目的清楚");
  assertStringIncludes(p, "可退出性");
  assertStringIncludes(p, "不要只因為「有邀約」就鼓勵赴約");
  assertStringIncludes(p, "做減法");
  assertStringIncludes(p, "不要補 PUA 技巧庫");
  assertStringIncludes(p, "不要做人格診斷");
});

Deno.test("openCoach prompt treats money and exploitation risk as triage, not pursuit", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "她一直叫我請客，還說想借錢投資" },
    { name: "X" },
  );
  assertStringIncludes(p, "金錢/利用風險");
  assertStringIncludes(p, "借錢、投資、訂房、機票、送禮、一直要求請客");
  assertStringIncludes(p, "不要給追求建議");
  assertStringIncludes(p, "observation 點出成本與不對等");
  assertStringIncludes(p, "task 給釐清或退出");
});

Deno.test("prompt allows internal tension craft but forbids exposing technique labels", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "我要怎麼幽默一點，又不要太刻意？" },
    { name: "X" },
  );
  assertStringIncludes(p, "互動張力");
  assertStringIncludes(p, "輕微調侃");
  assertStringIncludes(p, "誇張曲解");
  assertStringIncludes(p, "不要展示技巧名稱");
  assertStringIncludes(p, "推拉");
  assertStringIncludes(p, "自然的人味");
  assertStringIncludes(p, "吸引力不是技巧本身");
});

Deno.test("openCoach prompt handles ambiguous date invitations as time-cost triage", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "有男友了還約我幹嘛？這局該去嗎？" },
    { name: "X" },
  );
  assertStringIncludes(p, "這局該不該去");
  assertStringIncludes(p, "對方動機是否清楚");
  assertStringIncludes(p, "關係是否透明");
  assertStringIncludes(p, "低成本可退出");
  assertStringIncludes(p, "不要直接建議下次見面");
});

Deno.test("prompt does not ignore casual-sex intent when a partner has a relationship", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    {
      q1: "openQuestion",
      q3: "她有男友還約我？我對她沒感情，可以順勢把她變炮友？",
    },
    { name: "X" },
  );
  assertStringIncludes(p, "炮友");
  assertStringIncludes(p, "短期關係");
  assertStringIncludes(p, "不要忽略或道德審判");
  assertStringIncludes(p, "短期、低承諾的親密可能");
  assertStringIncludes(p, "清楚同意");
  assertStringIncludes(p, "關係透明");
  assertStringIncludes(p, "不得教用戶介入對方伴侶關係");
  assertStringIncludes(p, "性羞愧");
  assertStringIncludes(p, "成熟的男人不是沒有慾望");
  assertStringIncludes(p, "承認慾望、尊重對方、講清楚期待、承擔後果");
});

Deno.test("prompt supports emotional distress with empathy for both sides", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    {
      q1: "openQuestion",
      q3: "我最近失戀又跟她吵架，工作也很不順，整個人很亂",
    },
    { name: "X" },
  );
  assertStringIncludes(p, "失戀、吵架、被拒絕、人生低潮、工作或家庭壓力");
  assertStringIncludes(p, "先同理用戶，也同理對方可能的處境");
  assertStringIncludes(p, "不要急著教技巧");
  assertStringIncludes(p, "不要把所有問題導回邀約或吸引");
  assertStringIncludes(p, "5 分鐘內能做的小動作");
  assertStringIncludes(p, "情緒很滿時先穩住自己");
});

Deno.test("prompt covers core openCoach emotional support scenarios", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "她沒回我，我覺得自己很沒魅力又很上頭" },
    { name: "X" },
  );
  assertStringIncludes(p, "自我價值崩掉");
  assertStringIncludes(p, "把對方反應和自我價值拆開");
  assertStringIncludes(p, "暈船或過度投入");
  assertStringIncludes(p, "提醒降速");
  assertStringIncludes(p, "被拒絕後修復");
  assertStringIncludes(p, "保住用戶尊嚴");
  assertStringIncludes(p, "嫉妒、佔有慾或比較心");
  assertStringIncludes(p, "不要鼓勵控制、查勤、逼問或試探");
  assertStringIncludes(p, "道歉或犯錯後修復");
  assertStringIncludes(p, "短、誠實、不求立刻原諒");
});

Deno.test("prompt routes self-harm crisis away from dating coaching", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "我失戀到覺得活不下去" },
    { name: "X" },
  );
  assertStringIncludes(p, "自傷、想死、活不下去");
  assertStringIncludes(p, "不要做戀愛教練建議");
  assertStringIncludes(p, "安全支持");
  assertStringIncludes(p, "當地緊急服務或危機專線");
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
  const hasSoftHandling = p.includes("太早判斷") || p.includes("還看不出來");
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

Deno.test("styleContext appears as User voice & coaching preferences", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "我想更有幽默感" },
    { name: "X" },
    "- Preferred voice: 幽默；回覆要輕鬆、有留白",
  );
  assertStringIncludes(p, "User voice & coaching preferences");
  assertStringIncludes(p, "Preferred voice: 幽默");
});

Deno.test("styleContext section omitted when blank", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
    "   ",
  );
  assertEquals(p.includes("User voice & coaching preferences"), false);
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

Deno.test("q3 is marked as priority context, not buried beside q1/q2", () => {
  const p = buildCoachFollowUpPrompt(
    "postDateReflection",
    { q1: "unsure", q2: "cooling", q3: "我想跟她打炮" },
    { name: "X" },
  );
  assertStringIncludes(p, "[用戶補充 - 必須優先回應]");
  assertStringIncludes(p, "我想跟她打炮");
  assertStringIncludes(p, "不可只根據 q1/q2 泛泛回答");
});

Deno.test("openCoach q3 is required priority context", () => {
  const p = buildCoachFollowUpPrompt(
    "openCoach",
    { q1: "openQuestion", q3: "她回很慢，我該等還是約？" },
    { name: "X" },
  );
  assertStringIncludes(p, "q1=openQuestion（用戶直接問教練一個開放式問題）");
  assertStringIncludes(p, "[用戶補充 - 必須優先回應]");
  assertStringIncludes(p, "她回很慢，我該等還是約？");
});

Deno.test("prompt tells model how to handle explicit / rude / incoherent q3 safely", () => {
  const p = buildCoachFollowUpPrompt(
    "postDateReflection",
    { q1: "awkward", q2: "polite", q3: "她很白癡 ???" },
    { name: "X" },
  );
  assertStringIncludes(p, "露骨詞");
  assertStringIncludes(p, "辱罵或人格標籤");
  assertStringIncludes(p, "亂碼、打錯字或語意不足");
  assertStringIncludes(p, "不要照抄粗話");
});

Deno.test("prompt tells model to reason internally before concise coach output", () => {
  const p = buildCoachFollowUpPrompt(
    "postDateReflection",
    { q1: "unsure", q2: "cooling", q3: "我約完一直想確認她到底喜不喜歡我" },
    { name: "X" },
  );
  assertStringIncludes(p, "表層事件");
  assertStringIncludes(p, "背後情緒/不安");
  assertStringIncludes(p, "目前互動卡點");
  assertStringIncludes(p, "最小下一步");
  assertStringIncludes(p, "不要寫分析過程");
  assertStringIncludes(p, "observation / task / boundaryReminder");
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
  assertStringIncludes(p, "45");
  assertStringIncludes(p, "完整短句");
});

Deno.test("prompt instructs JSON-only output", () => {
  const p = buildCoachFollowUpPrompt(
    "prepareInvite",
    { q1: "fuzzy" },
    { name: "X" },
  );
  assertStringIncludes(p, "JSON");
});
