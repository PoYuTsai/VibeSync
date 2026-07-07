// 教練拆解卡解析測試。
// 跑法：deno test supabase/functions/practice-chat/debrief_card_test.ts

import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseDebriefCard } from "./debrief_card.ts";

const valid = JSON.stringify({
  summary: "整體有來有往，後段她有點冷掉",
  strengths: ["開場自然不油", "有接住她的話題"],
  watchouts: ["問句太密像查戶口", "可以多分享自己"],
  suggestedLine: "那家店我也想去，週末有空一起？",
  vibe: "中性",
});

Deno.test("合法 JSON → 完整解析", () => {
  const c = parseDebriefCard(valid);
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
  assertEquals(c.strengths.length, 2);
  assertEquals(c.watchouts.length, 2);
  assertEquals(c.vibe, "中性");
});

Deno.test("帶 markdown 圍欄也能解析", () => {
  const c = parseDebriefCard("```json\n" + valid + "\n```");
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
});

Deno.test("前後有說明文字或空白時，仍抽出第一個 JSON 物件解析", () => {
  const c = parseDebriefCard(
    "\n好的，以下是 JSON：\n```json\n" + valid + "\n```\n請參考",
  );
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
});

Deno.test("fenced JSON 後方仍有說明文字時，也只解析 JSON 物件", () => {
  const c = parseDebriefCard("```json\n" + valid + "\n```\n請參考");
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
});

Deno.test("strengths/watchouts 超過 2 點 → clamp 到 2", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      strengths: ["a", "b", "c", "d"],
      watchouts: ["e", "f", "g"],
      vibe: "暖",
    }),
  );
  assertEquals(c.strengths.length, 2);
  assertEquals(c.watchouts.length, 2);
});

Deno.test("vibe 非法 → 回退『中性』", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y", vibe: "超熱" }),
  );
  assertEquals(c.vibe, "中性");
});

Deno.test("strengths 缺省 → 空陣列（不爆）", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y" }),
  );
  assertEquals(c.strengths, []);
  assertEquals(c.watchouts, []);
});

Deno.test("非 JSON → 丟出", () => {
  assertThrows(() => parseDebriefCard("這不是 json"));
});

Deno.test("缺 summary / suggestedLine → debrief_missing_fields", () => {
  assertThrows(
    () => parseDebriefCard(JSON.stringify({ strengths: ["a"] })),
    Error,
    "debrief_missing_fields",
  );
});

Deno.test("JSON 是陣列而非物件 → debrief_not_object", () => {
  assertThrows(
    () => parseDebriefCard(JSON.stringify(["a", "b"])),
    Error,
    "debrief_not_object",
  );
});

// ── Batch 2：約出來機會欄位 ───────────────────────────────────────────

Deno.test("解析 dateChance / dateChanceReason / nextInviteMove", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      dateChance: "high",
      dateChanceReason: "她主動釋出週末時間",
      nextInviteMove: "提一個她有興趣的具體低壓行程",
    }),
  );
  assertEquals(c.dateChance, "high");
  assertEquals(c.dateChanceReason, "她主動釋出週末時間");
  assertEquals(c.nextInviteMove, "提一個她有興趣的具體低壓行程");
});

Deno.test("dateChance 大小寫不敏感（HIGH → high）", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y", dateChance: "HIGH" }),
  );
  assertEquals(c.dateChance, "high");
});

Deno.test("非法 dateChance + 有理由文字 → fallback medium", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      dateChance: "很高",
      dateChanceReason: "聊得不錯但邀約鋪墊不足",
    }),
  );
  assertEquals(c.dateChance, "medium");
});

Deno.test("非法 dateChance + 無理由 → fallback low（保守）", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y", dateChance: "爆表" }),
  );
  assertEquals(c.dateChance, "low");
});

Deno.test("舊卡缺 dateChance 欄位 → 向後相容 low + 空字串", () => {
  const c = parseDebriefCard(valid);
  assertEquals(c.dateChance, "low");
  assertEquals(c.dateChanceReason, "");
  assertEquals(c.nextInviteMove, "");
});

Deno.test("visible fields with internal labels are rejected", () => {
  for (
    const leaked of [
      { summary: "relationshipScore 88" },
      { suggestedLine: "scene_prompt says go" },
      { dateChanceReason: "replyTempo short" },
      { nextInviteMove: "partnerMood guarded" },
      { strengths: ["memory_summary leaked"] },
      { watchouts: ["innerThought leaked"] },
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            summary: "整體不錯",
            suggestedLine: "約她喝咖啡",
            ...leaked,
          }),
        ),
      Error,
      "debrief_internal_label_leak",
    );
  }
});
