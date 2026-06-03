import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { ndjsonStreamResponse } from "./ndjson_response.ts";

async function text(response: Response): Promise<string> {
  return await response.text();
}

Deno.test("ndjsonStreamResponse emits newline-delimited JSON events", async () => {
  const response = ndjsonStreamResponse((emit, close) => {
    emit({ type: "analysis.progress", ordinal: 1 });
    emit({ type: "analysis.recommendation", message: "先穩住節奏" });
    close();
  });

  assertEquals(
    await text(response),
    '{"type":"analysis.progress","ordinal":1}\n' +
      '{"type":"analysis.recommendation","message":"先穩住節奏"}\n',
  );
});

Deno.test("ndjsonStreamResponse sets streaming-safe headers and preserves caller headers", () => {
  const response = ndjsonStreamResponse((_, close) => close(), {
    "Access-Control-Allow-Origin": "*",
    "X-Test-Header": "ok",
  });

  assertEquals(
    response.headers.get("content-type"),
    "application/x-ndjson; charset=utf-8",
  );
  assertEquals(response.headers.get("cache-control"), "no-cache, no-transform");
  assertEquals(response.headers.get("x-accel-buffering"), "no");
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
  assertEquals(response.headers.get("x-test-header"), "ok");
});

Deno.test("ndjsonStreamResponse supports async start callbacks", async () => {
  const response = ndjsonStreamResponse(async (emit, close) => {
    emit({ type: "first" });
    await Promise.resolve();
    emit({ type: "second" });
    close();
  });

  assertEquals(
    await text(response),
    '{"type":"first"}\n{"type":"second"}\n',
  );
});

Deno.test("ndjsonStreamResponse ignores events emitted after close", async () => {
  const response = ndjsonStreamResponse((emit, close) => {
    emit({ type: "before_close" });
    close();
    emit({ type: "after_close" });
    close();
  });

  assertEquals(await text(response), '{"type":"before_close"}\n');
});

Deno.test("ndjsonStreamResponse propagates sync start errors to the response body", async () => {
  const response = ndjsonStreamResponse(() => {
    throw new Error("boom");
  });

  await assertRejects(() => text(response), Error, "boom");
});

Deno.test("ndjsonStreamResponse propagates async start errors to the response body", async () => {
  const response = ndjsonStreamResponse(async (emit) => {
    emit({ type: "before_error" });
    await Promise.resolve();
    throw new Error("async boom");
  });

  await assertRejects(() => text(response), Error, "async boom");
});
