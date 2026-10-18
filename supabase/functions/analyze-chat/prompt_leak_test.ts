// 對話分析的外洩哨兵（v3 那幾句，Eric 2026-10-18 盤點）：都在 v3 的提示詞裡、夠長、簡轉繁
// 整理後不變；重播錄音裡模型寫出來的字（v3 的卡、判讀、要等她做什麼，v2 的原文）一句都
// 不會中。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import v2Fixtures from "./testdata/analyze_replay_fixtures.json" with {
  type: "json",
};
import v3Fixtures from "./testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import { compactForLeakScan } from "../_shared/prompt_leak_guard.ts";
import { parseWrittenCardLine } from "./guide_v3/cards.ts";
import { readSystemPrompt, writeSystemPrompt } from "./guide_v3/prompts.ts";
import { normalizeOutgoingScript } from "./outgoing_message_text.ts";
import {
  ANALYZE_CHAT_PROMPT_SENTINELS,
  GUIDE_V3_PROMPT_SENTINELS,
  hasAnalyzeChatPromptLeak,
} from "./prompt_leak.ts";

Deno.test("v3 哨兵：3 到 6 句，都在讀局面或寫卡的提示詞裡、至少 12 字、整理後不變", () => {
  assert(GUIDE_V3_PROMPT_SENTINELS.length >= 3);
  assert(GUIDE_V3_PROMPT_SENTINELS.length <= 6);
  const prompts = compactForLeakScan(
    `${readSystemPrompt()}\n${writeSystemPrompt()}`,
  );
  for (const sentinel of GUIDE_V3_PROMPT_SENTINELS) {
    assert(ANALYZE_CHAT_PROMPT_SENTINELS.includes(sentinel), sentinel);
    // 改提示詞時哨兵要跟著換，不然等於沒有。
    assert(prompts.includes(compactForLeakScan(sentinel)), sentinel);
    assert([...compactForLeakScan(sentinel)].length >= 12, sentinel);
    // 卡片會先簡轉繁再查（「用戶」會變成「使用者」）：哨兵整理後要一字不差。
    assertEquals(normalizeOutgoingScript(sentinel), sentinel);
    assert(hasAnalyzeChatPromptLeak(`好啊 ${sentinel} 週六見`), sentinel);
  }
});

Deno.test("v3 哨兵不誤擋：重播錄音寫出來的 73 張卡、28 句判讀與要等她做什麼都不會中", () => {
  const cards: string[] = [];
  const coachTexts: string[] = [];
  for (const c of v3Fixtures.cases) {
    // 掃模型原文（定稿前），被拿掉的卡也算在內。
    for (const line of c.writeText.split(/\r?\n/)) {
      const card = parseWrittenCardLine(line);
      if (card) cards.push(card.messages.join("\n"));
    }
    const tags = JSON.parse(c.readText) as Record<string, unknown>;
    for (const field of ["readForUser", "waitFor"]) {
      const text = tags[field];
      if (typeof text === "string" && text.trim()) coachTexts.push(text);
    }
  }
  assertEquals(cards.length, 73);
  assertEquals(coachTexts.length, 28);
  for (const text of [...cards, ...coachTexts]) {
    assert(!hasAnalyzeChatPromptLeak(text), text);
  }
});

Deno.test("v3 哨兵不誤擋：v2 重播錄音的 23 份模型原文也不會中", () => {
  assertEquals(v2Fixtures.cases.length, 23);
  for (const c of v2Fixtures.cases) {
    const raw = compactForLeakScan(c.rawText);
    for (const sentinel of GUIDE_V3_PROMPT_SENTINELS) {
      assert(!raw.includes(compactForLeakScan(sentinel)), c.name);
    }
  }
});
