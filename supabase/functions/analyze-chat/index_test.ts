// supabase/functions/analyze-chat/index_test.ts
// Note: Edge Function tests run via Deno test

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// 訊息計算函數
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}

// 模型選擇函數
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
  if (context.tier === "essential") {
    return "claude-sonnet-4-20250514";
  }

  if (
    context.conversationLength > 20 ||
    context.enthusiasmLevel === "cold" ||
    context.hasComplexEmotions ||
    context.isFirstAnalysis
  ) {
    return "claude-sonnet-4-20250514";
  }

  return "claude-3-5-haiku-20241022";
}

// Test countMessages function
Deno.test("countMessages - single short message", () => {
  const messages = [{ content: "你好" }];
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - multiple messages", () => {
  const messages = [
    { content: "你好" },
    { content: "在嗎" },
    { content: "吃飯了嗎" },
  ];
  assertEquals(countMessages(messages), 3);
});

Deno.test("countMessages - long message splits by 200 chars", () => {
  const longContent = "a".repeat(450); // 450 chars = ceil(450/200) = 3
  const messages = [{ content: longContent }];
  assertEquals(countMessages(messages), 3);
});

Deno.test("countMessages - exactly 200 chars is 1 message", () => {
  const content = "a".repeat(200);
  const messages = [{ content }];
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - 201 chars is 2 messages", () => {
  const content = "a".repeat(201);
  const messages = [{ content }];
  assertEquals(countMessages(messages), 2);
});

Deno.test("countMessages - empty message counts as 1", () => {
  const messages = [{ content: "" }];
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - whitespace only message counts as 1", () => {
  const messages = [{ content: "   " }];
  assertEquals(countMessages(messages), 1);
});

// Test selectModel function
Deno.test("selectModel - essential tier always uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 5,
    enthusiasmLevel: "hot",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "essential",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - first analysis uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 3,
    enthusiasmLevel: null,
    hasComplexEmotions: false,
    isFirstAnalysis: true,
    tier: "free",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - cold enthusiasm uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 10,
    enthusiasmLevel: "cold",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "starter",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - long conversation uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 25,
    enthusiasmLevel: "warm",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "free",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - simple conversation uses Haiku", () => {
  const model = selectModel({
    conversationLength: 10,
    enthusiasmLevel: "warm",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "free",
  });
  assertEquals(model, "claude-3-5-haiku-20241022");
});

Deno.test("selectModel - complex emotions uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 5,
    enthusiasmLevel: "warm",
    hasComplexEmotions: true,
    isFirstAnalysis: false,
    tier: "starter",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});
