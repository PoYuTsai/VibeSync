import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AiStreamingServiceError,
  callClaudeStreaming,
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
      fetchImpl: async (input, init) => {
        capturedInput = input;
        capturedInit = init;
        return new Response(
          streamFromChunks([
            'data: {"type":"message_start","message":{"usage":{"input_tokens":120,"output_tokens":1,"cache_creation_input_tokens":80,"cache_read_input_tokens":40}}}\n\n',
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"first"}}\n\n',
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" second"}}\n\n',
            'data: {"type":"message_delta","usage":{"output_tokens":25}}\n\n',
          ]),
          { status: 200 },
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
      fetchImpl: async (_input, init) => {
        capturedBodies.push(
          JSON.parse(String(init?.body)) as Record<string, unknown>,
        );
        return new Response(
          streamFromChunks(['data: {"type":"message_stop"}\n\n']),
          { status: 200 },
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
          fetchImpl: async () =>
            new Response(
              JSON.stringify({ error: { message: "bad request" } }),
              { status: 400 },
            ),
        },
      ),
    AiStreamingServiceError,
  );

  assertEquals(error.code, "API_ERROR");
  assertEquals(error.retryable, false);
  assert(error.message.includes("bad request"));
});
