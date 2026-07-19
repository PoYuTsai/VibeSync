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

Deno.test("finish_reason=length → 拒絕 token 截斷的半成品", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          choices: [{
            finish_reason: "length",
            message: { content: '{"summary":"寫到一半' },
          }],
        }),
        { status: 200 },
      ),
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
    assertEquals(msg, "deepseek_max_tokens");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("only an explicit caller opt-out disables DeepSeek V4 thinking", async () => {
  const original = globalThis.fetch;
  const bodies: Array<Record<string, unknown>> = [];
  globalThis.fetch = (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    return Promise.resolve(
      new Response(
        JSON.stringify({
          choices: [{
            finish_reason: "stop",
            message: { content: '{"verdict":"accept"}' },
          }],
        }),
        { status: 200 },
      ),
    );
  };
  try {
    const baseArgs = {
      apiKey: "k",
      messages: [],
      maxTokens: 1200,
      temperature: 0.1,
      jsonMode: true,
      timeoutMs: 1000,
    };
    await callDeepSeek({
      ...baseArgs,
      thinking: { type: "disabled" },
    });
    await callDeepSeek(baseArgs);

    assertEquals(bodies[0].thinking, { type: "disabled" });
    assertEquals(Object.hasOwn(bodies[1], "thinking"), false);
  } finally {
    globalThis.fetch = original;
  }
});
