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
    // Prompt caching：system 必須是 content-block 陣列，text 與傳入 system
    // byte-for-byte 相同，且掛 ephemeral cache_control。
    assertEquals(captured.system, [
      {
        type: "text",
        text: "system contract",
        cache_control: { type: "ephemeral" },
      },
    ]);
    assertEquals(captured.messages, [
      { role: "user", content: "user evidence" },
    ]);
    assertEquals(captured.model, "claude-test");
    assertEquals(captured.temperature, 0.2);
    assertEquals(captured.thinking, undefined);
    assertEquals(captured.output_config, undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude joins multiple system messages byte-for-byte into one cached block", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | undefined;
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBody = JSON.parse(String(body));
    return Promise.resolve(
      new Response(
        JSON.stringify({ content: [{ type: "text", text: "ok" }] }),
        { status: 200 },
      ),
    );
  };
  try {
    await callClaude({
      apiKey: "test-key",
      model: "claude-test",
      messages: [
        { role: "system", content: "contract A" },
        { role: "system", content: "contract B" },
        { role: "user", content: "hello" },
      ],
      maxTokens: 100,
      temperature: 0.2,
      timeoutMs: 1_000,
    });
    assertEquals(capturedBody?.system, [
      {
        type: "text",
        text: "contract A\n\ncontract B",
        cache_control: { type: "ephemeral" },
      },
    ]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude keeps an empty system as-is instead of an empty cached block", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | undefined;
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBody = JSON.parse(String(body));
    return Promise.resolve(
      new Response(
        JSON.stringify({ content: [{ type: "text", text: "ok" }] }),
        { status: 200 },
      ),
    );
  };
  try {
    await callClaude({
      apiKey: "test-key",
      model: "claude-test",
      messages: [{ role: "user", content: "hello" }],
      maxTokens: 100,
      temperature: 0.2,
      timeoutMs: 1_000,
    });
    // Anthropic 拒絕空 text block；沒有 system 內容時維持原本的空字串行為。
    assertEquals(capturedBody?.system, "");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude forwards an optional structured output schema", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | undefined;
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBody = JSON.parse(String(body));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          content: [{ type: "text", text: '{"verdict":"accept"}' }],
        }),
        { status: 200 },
      ),
    );
  };
  const outputJsonSchema = {
    type: "object",
    properties: { verdict: { type: "string" } },
    required: ["verdict"],
    additionalProperties: false,
  } as const;
  try {
    const result = await callClaude({
      apiKey: "test-key",
      model: "claude-sonnet-5",
      messages: [{ role: "user", content: "return a verdict" }],
      maxTokens: 100,
      temperature: 0.2,
      timeoutMs: 1_000,
      outputJsonSchema,
    });

    assertEquals(result, '{"verdict":"accept"}');
    assertEquals(capturedBody?.output_config, {
      format: {
        type: "json_schema",
        schema: outputJsonSchema,
      },
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude with forcedTool sends tools and forced tool_choice", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | undefined;
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBody = JSON.parse(String(body));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          stop_reason: "tool_use",
          content: [{
            type: "tool_use",
            name: "emit_hint",
            input: { replies: ["a", "b"], coaching: "c" },
          }],
        }),
        { status: 200 },
      ),
    );
  };
  const inputSchema = {
    type: "object",
    properties: { replies: { type: "array" }, coaching: { type: "string" } },
    required: ["replies", "coaching"],
  } as const;
  try {
    const result = await callClaude({
      apiKey: "test-key",
      model: "claude-sonnet-5",
      messages: [{ role: "user", content: "hint please" }],
      maxTokens: 500,
      temperature: 0.2,
      timeoutMs: 1_000,
      forcedTool: {
        name: "emit_hint",
        description: "Emit the practice hint payload.",
        inputSchema,
      },
    });

    // 下游 parser 沿用「收字串」契約：tool_use input 序列化回傳。
    assertEquals(
      JSON.parse(result),
      { replies: ["a", "b"], coaching: "c" },
    );
    assertEquals(capturedBody?.tools, [
      {
        name: "emit_hint",
        description: "Emit the practice hint payload.",
        input_schema: inputSchema,
      },
    ]);
    assertEquals(capturedBody?.tool_choice, {
      type: "tool",
      name: "emit_hint",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude with forcedTool rejects a response without a tool_use block", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          content: [{ type: "text", text: "plain text instead of tool" }],
        }),
        { status: 200 },
      ),
    );
  try {
    await assertRejects(
      () =>
        callClaude({
          apiKey: "test-key",
          model: "claude-sonnet-5",
          messages: [{ role: "user", content: "hint please" }],
          maxTokens: 500,
          temperature: 0.2,
          timeoutMs: 1_000,
          forcedTool: {
            name: "emit_hint",
            inputSchema: { type: "object" },
          },
        }),
      Error,
      "claude_no_tool_use",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude without forcedTool sends no tools and keeps the text path", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | undefined;
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBody = JSON.parse(String(body));
    return Promise.resolve(
      new Response(
        JSON.stringify({ content: [{ type: "text", text: "plain" }] }),
        { status: 200 },
      ),
    );
  };
  try {
    const result = await callClaude({
      apiKey: "test-key",
      model: "claude-test",
      messages: [{ role: "user", content: "hello" }],
      maxTokens: 100,
      temperature: 0.2,
      timeoutMs: 1_000,
    });
    assertEquals(result, "plain");
    assertEquals(capturedBody?.tools, undefined);
    assertEquals(capturedBody?.tool_choice, undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("callClaude sends a Sonnet 5 compatible request", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | undefined;
  globalThis.fetch = (_input, init) => {
    const body = (init as { body?: BodyInit } | undefined)?.body;
    capturedBody = JSON.parse(String(body));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          content: [
            { type: "thinking", thinking: "private reasoning" },
            { type: "text", text: '{"ok":true}' },
          ],
        }),
        { status: 200 },
      ),
    );
  };
  try {
    const result = await callClaude({
      apiKey: "test-key",
      model: "claude-sonnet-5",
      messages: [{ role: "user", content: "hello" }],
      maxTokens: 100,
      temperature: 0.45,
      timeoutMs: 1_000,
    });

    assertEquals(result, '{"ok":true}');
    assertEquals(capturedBody?.thinking, { type: "disabled" });
    assertEquals(capturedBody?.temperature, undefined);
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

Deno.test("callClaude rejects refusal before exposing partial text", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          stop_reason: "refusal",
          content: [{ type: "text", text: '{"partial":"unsafe"}' }],
        }),
        { status: 200 },
      ),
    );
  try {
    const error = await assertRejects(
      () =>
        callClaude({
          apiKey: "test-key",
          model: "claude-sonnet-5",
          messages: [{ role: "user", content: "hello" }],
          maxTokens: 100,
          temperature: 0.2,
          timeoutMs: 1_000,
        }),
      Error,
    );
    assertEquals(error.message, "claude_refusal");
    assertEquals(error.message.includes("unsafe"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
