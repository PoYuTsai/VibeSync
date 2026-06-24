// DeepSeek 呼叫測試（stub global fetch，不打真網路）。
// 跑法：deno test supabase/functions/practice-chat/deepseek_test.ts

import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { callDeepSeek } from "./deepseek.ts";

async function expectThrowMessage(fn: () => Promise<unknown>): Promise<string> {
  try {
    await fn();
  } catch (e) {
    return e instanceof Error ? e.message : String(e);
  }
  throw new Error("expected callDeepSeek to throw");
}

Deno.test("HTTP 失敗 → 錯誤訊息只含 status，不含 response body（log 不洩漏）", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response("SECRET_BODY_LEAK provider_key=sk-abc123", { status: 400 }),
    );
  try {
    const msg = await expectThrowMessage(() =>
      callDeepSeek({
        apiKey: "k",
        messages: [],
        maxTokens: 10,
        temperature: 0.5,
        timeoutMs: 1000,
      })
    );
    assertStringIncludes(msg, "400");
    assertEquals(msg.includes("SECRET_BODY_LEAK"), false);
    assertEquals(msg.includes("provider_key"), false);
  } finally {
    globalThis.fetch = original;
  }
});
