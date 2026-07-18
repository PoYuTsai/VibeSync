import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AiStreamingServiceError,
  callClaudeStreaming,
  type ClaudeStreamingRequest,
  parseAnthropicSse,
} from "./streaming_fallback.ts";

function streamFromChunks(chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(encoder.encode(chunk));
      }
      controller.close();
    },
  });
}

async function collect(stream: AsyncGenerator<string>): Promise<string[]> {
  const chunks: string[] = [];
  for await (const text of stream) {
    chunks.push(text);
  }
  return chunks;
}

function streamingRequest(
  model = "claude-sonnet-5",
): ClaudeStreamingRequest {
  return {
    model,
    max_tokens: 1536,
    system: "system prompt",
    messages: [{ role: "user", content: "hello" }],
    thinking: model === "claude-sonnet-5" ? { type: "disabled" } : undefined,
  };
}

function successfulStream(text = "ok"): Response {
  return new Response(
    streamFromChunks([
      `data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"${text}"}}\n\n`,
      'data: {"type":"message_stop"}\n\n',
    ]),
    { status: 200 },
  );
}

Deno.test("parseAnthropicSse extracts text deltas in order", async () => {
  const sse = [
    "event: content_block_delta",
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"{\\"type\\":\\"analysis.progress\\""}}',
    "",
    "event: content_block_delta",
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":",\\"ordinal\\":1}\\n"}}',
    "",
    "event: message_stop",
    'data: {"type":"message_stop"}',
    "",
  ].join("\n");

  const chunks = await collect(parseAnthropicSse(streamFromChunks([sse])));

  assertEquals(chunks.join(""), '{"type":"analysis.progress","ordinal":1}\n');
});

Deno.test("parseAnthropicSse ignores non-text events and done sentinel", async () => {
  const sse = [
    "event: message_start",
    'data: {"type":"message_start","message":{"id":"msg_1"}}',
    "",
    "event: content_block_delta",
    'data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}',
    "",
    "event: content_block_delta",
    'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"private reasoning"}}',
    "",
    "event: content_block_delta",
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}',
    "",
    "data: [DONE]",
    "",
  ].join("\n");

  const chunks = await collect(parseAnthropicSse(streamFromChunks([sse])));

  assertEquals(chunks, ["ok"]);
});

Deno.test("parseAnthropicSse parses events split across stream chunks", async () => {
  const chunks = await collect(parseAnthropicSse(streamFromChunks([
    "event: content_block_delta\n",
    'data: {"type":"content_block_delta","delta":{"type":"text_',
    'delta","text":"hel',
    'lo"}}\n\n',
  ])));

  assertEquals(chunks, ["hello"]);
});

Deno.test("parseAnthropicSse fails on malformed Claude SSE data", async () => {
  const error = await assertRejects(
    () =>
      collect(parseAnthropicSse(streamFromChunks(["data: {not-json}\n\n"]))),
    AiStreamingServiceError,
  );

  assertEquals(error.code, "STREAM_PARSE_ERROR");
  assert(!error.message.includes("not-json"));
});

Deno.test("callClaudeStreaming forwards Sonnet 5 thinking-disabled contract", async () => {
  let capturedInput = "";
  let capturedInit: RequestInit | undefined;

  const result = await callClaudeStreaming(
    {
      model: "claude-sonnet-5",
      max_tokens: 1536,
      system: "system prompt",
      messages: [{ role: "user", content: "hello" }],
      thinking: { type: "disabled" },
    },
    "test-api-key",
    {
      timeout: 5000,
      fetchImpl: (input, init) => {
        capturedInput = input;
        capturedInit = init;
        return Promise.resolve(
          new Response(
            streamFromChunks([
              'data: {"type":"message_start","message":{"usage":{"input_tokens":120,"output_tokens":1,"cache_creation_input_tokens":80,"cache_read_input_tokens":40}}}\n\n',
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"first"}}\n\n',
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" second"}}\n\n',
              'data: {"type":"message_delta","usage":{"output_tokens":25}}\n\n',
            ]),
            { status: 200 },
          ),
        );
      },
    },
  );

  const body = JSON.parse(String(capturedInit?.body)) as {
    model: string;
    max_tokens: number;
    stream: boolean;
    thinking?: { type: string };
    system: Array<
      { type: string; text: string; cache_control: { type: string } }
    >;
    messages: Array<{ role: string; content: string }>;
  };
  const headers = capturedInit?.headers as Record<string, string>;

  assertEquals(capturedInput, "https://api.anthropic.com/v1/messages");
  assertEquals(capturedInit?.method, "POST");
  assertEquals(headers["x-api-key"], "test-api-key");
  assertEquals(headers["anthropic-version"], "2023-06-01");
  assertEquals(headers["anthropic-beta"], "prompt-caching-2024-07-31");
  assertEquals(body.stream, true);
  assertEquals(body.system[0].cache_control.type, "ephemeral");
  assertEquals(body.model, "claude-sonnet-5");
  assertEquals(body.thinking, { type: "disabled" });
  assertEquals(body.messages[0].content, "hello");
  assertEquals(result.model, "claude-sonnet-5");
  assertEquals(await collect(result.textStream), ["first", " second"]);
  assertEquals(result.usage, {
    inputTokens: 120,
    outputTokens: 25,
    cacheCreationTokens: 80,
    cacheReadTokens: 40,
  });
});

Deno.test("callClaudeStreaming omits thinking when caller leaves it unset", async () => {
  const capturedBodies: Array<Record<string, unknown>> = [];
  const result = await callClaudeStreaming(
    {
      model: "claude-sonnet-4-6",
      max_tokens: 1536,
      system: "system prompt",
      messages: [{ role: "user", content: "hello" }],
    },
    "test-api-key",
    {
      timeout: 5000,
      fetchImpl: (_input, init) => {
        capturedBodies.push(
          JSON.parse(String(init?.body)) as Record<string, unknown>,
        );
        return Promise.resolve(
          new Response(
            streamFromChunks(['data: {"type":"message_stop"}\n\n']),
            { status: 200 },
          ),
        );
      },
    },
  );

  assertEquals(await collect(result.textStream), []);
  assertEquals(capturedBodies.length, 1);
  assertEquals(capturedBodies[0].thinking, undefined);
});

Deno.test("callClaudeStreaming maps non-ok Anthropic responses", async () => {
  const error = await assertRejects(
    () =>
      callClaudeStreaming(
        {
          model: "claude-sonnet-4-6",
          max_tokens: 1536,
          system: "system",
          messages: [{ role: "user", content: "hello" }],
        },
        "test-api-key",
        {
          timeout: 5000,
          fetchImpl: () =>
            Promise.resolve(
              new Response(
                JSON.stringify({ error: { message: "bad request" } }),
                { status: 400 },
              ),
            ),
        },
      ),
    AiStreamingServiceError,
  );

  assertEquals(error.code, "API_ERROR");
  assertEquals(error.retryable, false);
  assert(!error.message.includes("bad request"));
});

Deno.test(
  "callClaudeStreaming falls back before exposing a stream on network and 429 failures",
  async () => {
    const requestBodies: Array<Record<string, unknown>> = [];
    let attempt = 0;

    const result = await callClaudeStreaming(
      { ...streamingRequest(), thinking: undefined },
      "test-api-key",
      {
        timeout: 5000,
        fetchImpl: (_input, init) => {
          requestBodies.push(
            JSON.parse(String(init?.body)) as Record<string, unknown>,
          );
          attempt += 1;
          if (attempt === 1) {
            return Promise.reject(new TypeError("socket unavailable"));
          }
          if (attempt === 2) {
            return Promise.resolve(
              new Response(
                JSON.stringify({
                  error: {
                    type: "rate_limit_error",
                    message: "provider-only detail",
                  },
                }),
                { status: 429 },
              ),
            );
          }
          return Promise.resolve(successfulStream("haiku"));
        },
      },
    );

    assertEquals(
      requestBodies.map((body) => body.model),
      [
        "claude-sonnet-5",
        "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001",
      ],
    );
    assertEquals(requestBodies[0].thinking, { type: "disabled" });
    assertEquals(requestBodies[1].thinking, undefined);
    assertEquals(requestBodies[2].thinking, undefined);
    assertEquals(result.model, "claude-haiku-4-5-20251001");
    assertEquals(await collect(result.textStream), ["haiku"]);
    assertEquals(result.usage, {
      inputTokens: 0,
      outputTokens: 0,
      cacheCreationTokens: 0,
      cacheReadTokens: 0,
    });
  },
);

Deno.test(
  "callClaudeStreaming falls back on 5xx and HTTP 200 without a body",
  async () => {
    const models: unknown[] = [];
    let attempt = 0;

    const result = await callClaudeStreaming(
      streamingRequest(),
      "test-api-key",
      {
        timeout: 5000,
        fetchImpl: (_input, init) => {
          const body = JSON.parse(String(init?.body)) as Record<
            string,
            unknown
          >;
          models.push(body.model);
          attempt += 1;
          if (attempt === 1) {
            return Promise.resolve(
              new Response("provider internal detail", { status: 503 }),
            );
          }
          if (attempt === 2) {
            return Promise.resolve(new Response(null, { status: 200 }));
          }
          return Promise.resolve(successfulStream("recovered"));
        },
      },
    );

    assertEquals(models, [
      "claude-sonnet-5",
      "claude-sonnet-4-6",
      "claude-haiku-4-5-20251001",
    ]);
    assertEquals(result.model, "claude-haiku-4-5-20251001");
    assertEquals(await collect(result.textStream), ["recovered"]);
  },
);

Deno.test("callClaudeStreaming keeps the fallback chain inside one total timeout", async () => {
  const models: unknown[] = [];

  const error = await assertRejects(
    () =>
      callClaudeStreaming(
        streamingRequest(),
        "test-api-key",
        {
          timeout: 5,
          fetchImpl: async (_input, init) => {
            const body = JSON.parse(String(init?.body)) as Record<
              string,
              unknown
            >;
            models.push(body.model);
            return await new Promise<Response>((_resolve, reject) => {
              init?.signal?.addEventListener("abort", () => {
                reject(new DOMException("aborted", "AbortError"));
              }, { once: true });
            });
          },
        },
      ),
    AiStreamingServiceError,
  );

  assertEquals(models, ["claude-sonnet-5"]);
  assertEquals(error.code, "TIMEOUT");
  assertEquals(error.metadata.timeoutMs, 5);
});

Deno.test(
  "callClaudeStreaming does not fallback on a non-retryable HTTP response",
  async () => {
    let calls = 0;
    const error = await assertRejects(
      () =>
        callClaudeStreaming(
          streamingRequest(),
          "test-api-key",
          {
            timeout: 5000,
            fetchImpl: () => {
              calls += 1;
              return Promise.resolve(
                new Response(
                  JSON.stringify({
                    error: { message: "sensitive provider explanation" },
                  }),
                  { status: 400 },
                ),
              );
            },
          },
        ),
      AiStreamingServiceError,
    );

    assertEquals(calls, 1);
    assertEquals(error.code, "API_ERROR");
    assertEquals(error.retryable, false);
    assert(!error.message.includes("sensitive provider explanation"));
  },
);

Deno.test(
  "callClaudeStreaming does not treat non-200 success statuses as fallbackable empty streams",
  async () => {
    let calls = 0;
    const error = await assertRejects(
      () =>
        callClaudeStreaming(
          streamingRequest(),
          "test-api-key",
          {
            timeout: 5000,
            fetchImpl: () => {
              calls += 1;
              return Promise.resolve(new Response(null, { status: 204 }));
            },
          },
        ),
      AiStreamingServiceError,
    );

    assertEquals(calls, 1);
    assertEquals(error.code, "API_ERROR");
    assertEquals(error.retryable, false);
  },
);

Deno.test(
  "callClaudeStreaming never switches models after returning a readable stream",
  async () => {
    let calls = 0;
    const result = await callClaudeStreaming(
      streamingRequest(),
      "test-api-key",
      {
        timeout: 5000,
        fetchImpl: () => {
          calls += 1;
          return Promise.resolve(
            new Response(
              streamFromChunks([
                'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"partial"}}\n\n',
                'data: {"type":"error","error":{"type":"overloaded_error","message":"sensitive overload detail"}}\n\n',
              ]),
              { status: 200 },
            ),
          );
        },
      },
    );

    const seen: string[] = [];
    const error = await assertRejects(
      async () => {
        for await (const text of result.textStream) seen.push(text);
      },
      AiStreamingServiceError,
    );

    assertEquals(seen, ["partial"]);
    assertEquals(calls, 1);
    assertEquals(result.model, "claude-sonnet-5");
    assertEquals(error.code, "STREAM_OVERLOADED");
    assertEquals(error.retryable, true);
    assert(!error.message.includes("sensitive overload detail"));
  },
);

Deno.test(
  "callClaudeStreaming sanitizes in-stream transport failures without fallback",
  async () => {
    const encoder = new TextEncoder();
    let emitted = false;
    let calls = 0;
    const result = await callClaudeStreaming(
      streamingRequest(),
      "test-api-key",
      {
        timeout: 5000,
        fetchImpl: () => {
          calls += 1;
          return Promise.resolve(
            new Response(
              new ReadableStream<Uint8Array>({
                pull(controller) {
                  if (!emitted) {
                    emitted = true;
                    controller.enqueue(encoder.encode(
                      'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"partial"}}\n\n',
                    ));
                    return;
                  }
                  controller.error(new Error("sensitive connection detail"));
                },
              }),
              { status: 200 },
            ),
          );
        },
      },
    );

    const seen: string[] = [];
    const error = await assertRejects(
      async () => {
        for await (const text of result.textStream) seen.push(text);
      },
      AiStreamingServiceError,
    );

    assertEquals(seen, ["partial"]);
    assertEquals(calls, 1);
    assertEquals(error.code, "STREAM_CONNECTION_ERROR");
    assertEquals(error.retryable, true);
    assert(!error.message.includes("sensitive connection detail"));
  },
);

Deno.test("parseAnthropicSse maps provider SSE errors without leaking detail", async () => {
  const error = await assertRejects(
    () =>
      collect(parseAnthropicSse(streamFromChunks([
        'data: {"type":"error","error":{"type":"api_error","message":"private provider detail"}}\n\n',
      ]))),
    AiStreamingServiceError,
  );

  assertEquals(error.code, "STREAM_PROVIDER_ERROR");
  assert(!error.message.includes("private provider detail"));
});

for (
  const [stopReason, expectedCode, retryable] of [
    ["max_tokens", "STREAM_MAX_TOKENS", true],
    [
      "model_context_window_exceeded",
      "STREAM_CONTEXT_WINDOW_EXCEEDED",
      false,
    ],
    ["refusal", "STREAM_MODEL_REFUSAL", false],
  ] as const
) {
  Deno.test(
    `parseAnthropicSse rejects terminal stop reason ${stopReason}`,
    async () => {
      const usage = {
        inputTokens: 0,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
      };
      const error = await assertRejects(
        () =>
          collect(parseAnthropicSse(
            streamFromChunks([
              `data: {"type":"message_delta","delta":{"stop_reason":"${stopReason}"},"usage":{"output_tokens":99}}\n\n`,
            ]),
            usage,
          )),
        AiStreamingServiceError,
      );

      assertEquals(error.code, expectedCode);
      assertEquals(error.retryable, retryable);
      assertEquals(usage.outputTokens, 99);
    },
  );
}
