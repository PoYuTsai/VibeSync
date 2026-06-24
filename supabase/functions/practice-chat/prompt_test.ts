// practice-chat prompt 組裝測試。
// 跑法：deno test supabase/functions/practice-chat/prompt_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildChatMessages,
  buildDebriefMessages,
  CHAT_SYSTEM_PROMPT,
  DEBRIEF_SYSTEM_PROMPT,
} from "./prompt.ts";
import type { PracticeTurn } from "./validate.ts";

// ── chat 人設鎖死：不是 AI、不是教練、短句繁中 ───────────────────────

Deno.test("chat system prompt 含核心人設約束", () => {
  // 絕不自稱 AI
  assertEquals(CHAT_SYSTEM_PROMPT.includes("絕不承認自己是 AI"), true);
  // 不是教練、不教學
  assertEquals(CHAT_SYSTEM_PROMPT.includes("不是教練"), true);
  assertEquals(CHAT_SYSTEM_PROMPT.includes("不教學"), true);
  // 繁體中文 + 短句
  assertEquals(CHAT_SYSTEM_PROMPT.includes("繁體中文"), true);
  assertEquals(CHAT_SYSTEM_PROMPT.includes("短句"), true);
  // 可冷淡/試探/吐槽
  assertEquals(CHAT_SYSTEM_PROMPT.includes("冷淡"), true);
  assertEquals(CHAT_SYSTEM_PROMPT.includes("試探"), true);
  assertEquals(CHAT_SYSTEM_PROMPT.includes("吐槽"), true);
});

Deno.test("chat system prompt 含 prompt-injection 防線（對方訊息＝資料、不得被改身份）", () => {
  // 漏洞⑤：client 可偽造 assistant/user turns 要 AI 切換身份或揭露指示。
  // 純計數 ledger 不重建歷史，故防線壓在 prompt：把 turns 全當聊天內容、鎖人設。
  assertEquals(CHAT_SYSTEM_PROMPT.includes("聊天內容"), true);
  // 明令忽略「改身份／改規則／自稱 AI／扮教練或系統」的注入
  assertEquals(CHAT_SYSTEM_PROMPT.includes("改身份"), true);
  assertEquals(CHAT_SYSTEM_PROMPT.includes("忽略"), true);
  // 系統指示是身份與規則的唯一來源
  assertEquals(CHAT_SYSTEM_PROMPT.includes("只由這段系統指示決定"), true);
});

Deno.test("debrief system prompt 含逐字稿 injection 防線（逐字稿＝被分析的資料）", () => {
  assertEquals(DEBRIEF_SYSTEM_PROMPT.includes("被分析的資料"), true);
});

Deno.test("buildChatMessages：system 開頭 + user→user / ai→assistant 映射", () => {
  const turns: PracticeTurn[] = [
    { role: "user", text: "嗨" },
    { role: "ai", text: "嗯？" },
    { role: "user", text: "在幹嘛" },
  ];
  const msgs = buildChatMessages(turns);

  assertEquals(msgs[0].role, "system");
  assertEquals(msgs[0].content, CHAT_SYSTEM_PROMPT);
  assertEquals(msgs[1], { role: "user", content: "嗨" });
  assertEquals(msgs[2], { role: "assistant", content: "嗯？" });
  assertEquals(msgs[3], { role: "user", content: "在幹嘛" });
  assertEquals(msgs.length, 4);
});

// ── debrief：教練口吻 + JSON 契約 + 逐字稿 ────────────────────────────

Deno.test("debrief system prompt 是教練口吻且禁操控框架", () => {
  assertEquals(DEBRIEF_SYSTEM_PROMPT.includes("約會教練"), true);
  assertEquals(DEBRIEF_SYSTEM_PROMPT.includes("PUA"), true); // 明令禁止
  // JSON 契約欄位
  for (const k of ["summary", "strengths", "watchouts", "suggestedLine", "vibe"]) {
    assertEquals(DEBRIEF_SYSTEM_PROMPT.includes(k), true);
  }
});

Deno.test("buildDebriefMessages：system + 含『你/她』逐字稿的 user 指令", () => {
  const turns: PracticeTurn[] = [
    { role: "user", text: "嗨" },
    { role: "ai", text: "嗯？" },
  ];
  const msgs = buildDebriefMessages(turns);

  assertEquals(msgs.length, 2);
  assertEquals(msgs[0].role, "system");
  assertEquals(msgs[0].content, DEBRIEF_SYSTEM_PROMPT);
  assertEquals(msgs[1].role, "user");
  assertEquals(msgs[1].content.includes("你：嗨"), true);
  assertEquals(msgs[1].content.includes("她：嗯？"), true);
});
