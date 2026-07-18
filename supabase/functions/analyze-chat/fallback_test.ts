import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { AiServiceError, callClaudeWithFallback } from "./fallback.ts";

type CapturedBody = {
  model?: string;
  thinking?: { type?: string };
};

function routingContracts(bodies: CapturedBody[]) {
  return bodies.map(({ model, thinking }) => ({
    model,
    ...(thinking ? { thinking } : {}),
  }));
}

function parseCapturedBody(init: unknown): CapturedBody {
  const body = (init as { body?: unknown } | undefined)?.body;
  return JSON.parse(String(body)) as CapturedBody;
}

function successResponse(text = '{"ok":true}', stopReason = "end_turn") {
  return new Response(
    JSON.stringify({
      content: [{ type: "text", text }],
      stop_reason: stopReason,
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}

function baseRequest(
  thinking?: { type: "adaptive" | "disabled" },
) {
  return {
    model: "claude-sonnet-5",
    max_tokens: 700,
    system: "Return JSON.",
    messages: [{ role: "user", content: "test" }],
    ...(thinking ? { thinking } : {}),
  };
}

Deno.test("Sonnet 5 defaults to thinking disabled when caller omits it", async () => {
  const originalFetch = globalThis.fetch;
  const capturedBodies: CapturedBody[] = [];
  globalThis.fetch = (_input, init) => {
    capturedBodies.push(parseCapturedBody(init));
    return Promise.resolve(successResponse());
  };

  try {
    await callClaudeWithFallback(baseRequest(), "test-key", {
      timeout: 1000,
      maxRetries: 1,
      allowModelFallback: false,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(routingContracts(capturedBodies), [{
    model: "claude-sonnet-5",
    thinking: { type: "disabled" },
  }]);
});

Deno.test("automatic Sonnet 5 thinking default is not sent to fallback models", async () => {
  const originalFetch = globalThis.fetch;
  const capturedBodies: CapturedBody[] = [];
  globalThis.fetch = (_input, init) => {
    const body = parseCapturedBody(init);
    capturedBodies.push(body);
    return Promise.resolve(
      capturedBodies.length < 3
        ? new Response("upstream unavailable", { status: 529 })
        : successResponse(),
    );
  };

  let result;
  try {
    result = await callClaudeWithFallback(baseRequest(), "test-key", {
      timeout: 1000,
      maxRetries: 1,
      allowModelFallback: true,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(result?.model, "claude-haiku-4-5-20251001");
  assertEquals(routingContracts(capturedBodies), [
    {
      model: "claude-sonnet-5",
      thinking: { type: "disabled" },
    },
    { model: "claude-sonnet-4-6" },
    { model: "claude-haiku-4-5-20251001" },
  ]);
});

Deno.test("caller-specified adaptive thinking is not sent to older fallback models", async () => {
  const originalFetch = globalThis.fetch;
  const capturedBodies: CapturedBody[] = [];
  globalThis.fetch = (_input, init) => {
    const body = parseCapturedBody(init);
    capturedBodies.push(body);
    return Promise.resolve(
      capturedBodies.length < 3
        ? new Response("upstream unavailable", { status: 529 })
        : successResponse(),
    );
  };

  try {
    await callClaudeWithFallback(
      baseRequest({ type: "adaptive" }),
      "test-key",
      {
        timeout: 1000,
        maxRetries: 1,
        allowModelFallback: true,
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(routingContracts(capturedBodies), [
    { model: "claude-sonnet-5", thinking: { type: "adaptive" } },
    { model: "claude-sonnet-4-6" },
    { model: "claude-haiku-4-5-20251001" },
  ]);
});

Deno.test("max_tokens without visible text retries through the fallback chain", async () => {
  const originalFetch = globalThis.fetch;
  const capturedBodies: CapturedBody[] = [];
  globalThis.fetch = (_input, init) => {
    capturedBodies.push(parseCapturedBody(init));
    if (capturedBodies.length === 1) {
      return Promise.resolve(
        new Response(
          JSON.stringify({ content: [], stop_reason: "max_tokens" }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(successResponse());
  };

  let result;
  try {
    result = await callClaudeWithFallback(baseRequest(), "test-key", {
      timeout: 1000,
      maxRetries: 1,
      allowModelFallback: true,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(result?.model, "claude-sonnet-4-6");
  assertEquals(capturedBodies.length, 2);
});

Deno.test("max_tokens with visible text also falls back before quota settlement", async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = () => {
    requestCount++;
    return Promise.resolve(
      requestCount === 1
        ? successResponse('{"ok":true}', "max_tokens")
        : successResponse(),
    );
  };

  let result;
  try {
    result = await callClaudeWithFallback(baseRequest(), "test-key", {
      timeout: 1000,
      maxRetries: 1,
      allowModelFallback: true,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(result?.model, "claude-sonnet-4-6");
  assertEquals(requestCount, 2);
});

Deno.test("refusal switches directly to the next model", async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = () => {
    requestCount++;
    return Promise.resolve(
      requestCount === 1
        ? successResponse("Cannot comply.", "refusal")
        : successResponse(),
    );
  };

  let result;
  try {
    result = await callClaudeWithFallback(baseRequest(), "test-key", {
      timeout: 1000,
      maxRetries: 2,
      allowModelFallback: true,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(result?.model, "claude-sonnet-4-6");
  assertEquals(requestCount, 2);
});

Deno.test("provider 4xx response body never reaches the error", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response("SECRET_BODY prompt=user-private-text", { status: 400 }),
    );

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 1000,
          maxRetries: 1,
          allowModelFallback: true,
        }),
      AiServiceError,
    );
    assertEquals(error.message, "API Error: 400");
    assertEquals(error.message.includes("SECRET_BODY"), false);
    assertEquals(error.message.includes("user-private-text"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("expired absolute deadline rejects before any provider call", async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = () => {
    requestCount++;
    return Promise.resolve(successResponse());
  };

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 1000,
          maxRetries: 2,
          allowModelFallback: true,
          absoluteDeadlineAtMs: Date.now() - 1,
        }),
      AiServiceError,
    );
    assertEquals(error.code, "DEADLINE_EXCEEDED");
    assertEquals(requestCount, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("absolute deadline caps total budget and stops before fallback", async () => {
  const originalFetch = globalThis.fetch;
  const capturedBodies: CapturedBody[] = [];
  globalThis.fetch = (_input, init) => {
    capturedBodies.push(parseCapturedBody(init));
    const signal = (init as RequestInit | undefined)?.signal;
    return new Promise<Response>((_resolve, reject) => {
      const rejectAbort = () =>
        reject(new DOMException("aborted", "AbortError"));
      if (signal?.aborted) {
        rejectAbort();
        return;
      }
      signal?.addEventListener("abort", rejectAbort, { once: true });
    });
  };

  const startedAt = Date.now();
  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 5000,
          maxRetries: 2,
          allowModelFallback: true,
          absoluteDeadlineAtMs: Date.now() + 30,
        }),
      AiServiceError,
    );
    const elapsedMs = Date.now() - startedAt;

    assertEquals(error.code, "DEADLINE_EXCEEDED");
    assertEquals(routingContracts(capturedBodies), [{
      model: "claude-sonnet-5",
      thinking: { type: "disabled" },
    }]);
    assertEquals(elapsedMs < 1000, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
