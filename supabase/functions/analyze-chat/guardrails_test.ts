import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { getSafeReplies } from "./guardrails.ts";

Deno.test("getSafeReplies - hot fallback keeps the conversation moving", () => {
  const replies = getSafeReplies("hot");

  assertEquals(replies.extend, "這個有畫面欸，你是怎麼想到的？");
  assertEquals(replies.resonate, "有點準，但我想聽聽你為什麼這樣覺得");
  assertFalse(replies.extend.includes("繼續聊這個，我覺得很有意思"));
  assertFalse(replies.resonate.includes("對啊，我也這麼覺得"));
});
