import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { callClaude } from "./claude.ts";

Deno.test("callClaude maps practice messages to the Messages API", async () => {
  const originalFetch = globalThis.fetch;
  const capturedBodies: Record<string, unknown>[] = [];
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBodies.push(JSON.parse(String(body)));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          content: [{ type: "text", text: '  {"ok":true}  ' }],
        }),
        { status: 200 },
      ),
    );
  };
  try {
    const result = await callClaude({
      apiKey: "test-key",
      model: "claude-test",
      messages: [
        { role: "system", content: "system contract" },
        { role: "user", content: "user evidence" },
      ],
      maxTokens: 100,
      temperature: 0.2,
      timeoutMs: 1_000,
    });
    const captured = capturedBodies[0];
    assertEquals(result, '{"ok":true}');
    assertEquals(captured.system, "system contract");
    assertEquals(captured.messages, [
      { role: "user", content: "user evidence" },
    ]);
    assertEquals(captured.model, "claude-test");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude never leaks a provider response body", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response("SECRET_BODY_LEAK provider_key=sk-test", { status: 500 }),
    );
  try {
    const error = await assertRejects(
      () =>
        callClaude({
          apiKey: "test-key",
          model: "claude-test",
          messages: [{ role: "user", content: "hello" }],
          maxTokens: 100,
          temperature: 0.2,
          timeoutMs: 1_000,
        }),
      Error,
    );
    assertStringIncludes(error.message, "claude_http_500");
    assertEquals(error.message.includes("SECRET_BODY_LEAK"), false);
    assertEquals(error.message.includes("provider_key"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude rejects max-token truncation before exposing partial text", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          stop_reason: "max_tokens",
          content: [{ type: "text", text: '{"summary":"寫到一半' }],
        }),
        { status: 200 },
      ),
    );
  try {
    await assertRejects(
      () =>
        callClaude({
          apiKey: "test-key",
          model: "claude-test",
          messages: [{ role: "user", content: "hello" }],
          maxTokens: 10,
          temperature: 0.2,
          timeoutMs: 1_000,
        }),
      Error,
      "claude_max_tokens",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
