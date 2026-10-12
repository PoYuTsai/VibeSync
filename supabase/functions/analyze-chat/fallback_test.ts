import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { AiServiceError, callClaudeWithFallback } from "./fallback.ts";
import { ModelCallBudget } from "./model_call_budget.ts";

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

Deno.test("Sonnet 5.5 gets configuration C merged into structured output, then Sonnet 5 with its own params and base max_tokens", async () => {
  const originalFetch = globalThis.fetch;
  const bodies: Array<Record<string, unknown>> = [];
  globalThis.fetch = (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      bodies.length < 3
        ? new Response("upstream unavailable", { status: 529 })
        : successResponse(),
    );
  };

  try {
    await callClaudeWithFallback(
      {
        // 呼叫端 adaptive 只屬於 5.5；退到 Sonnet 5 必須回到 disabled。
        ...baseRequest({ type: "adaptive" }),
        model: "claude-sonnet-5-5",
        output_config: {
          format: { type: "json_schema", schema: { type: "object" } },
        },
      },
      "test-key",
      { timeout: 1000, maxRetries: 1, allowModelFallback: true },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  const format = { type: "json_schema", schema: { type: "object" } };
  assertEquals(
    bodies.map(({ model, max_tokens, thinking, output_config }) => ({
      model,
      max_tokens,
      thinking,
      output_config,
    })),
    [
      {
        model: "claude-sonnet-5-5",
        max_tokens: 4700,
        thinking: { type: "adaptive", display: "omitted" },
        output_config: { format, effort: "low" },
      },
      {
        model: "claude-sonnet-5",
        max_tokens: 700,
        thinking: { type: "disabled" },
        output_config: { format },
      },
      {
        model: "claude-sonnet-4-6",
        max_tokens: 700,
        thinking: undefined,
        output_config: { format },
      },
    ],
  );
});

Deno.test("max_tokens without visible text fails closed on Sonnet 5", async () => {
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
    assertEquals(error.code, "MAX_TOKENS");
    assertEquals(error.retryable, false);
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(capturedBodies.length, 1);
});

Deno.test("max_tokens with visible text fails closed before quota settlement", async () => {
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
    assertEquals(error.code, "MAX_TOKENS");
    assertEquals(error.retryable, false);
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(requestCount, 1);
});

Deno.test("refusal fails closed without switching to an older model", async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = () => {
    requestCount++;
    return Promise.resolve(successResponse("Cannot comply.", "refusal"));
  };

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 1000,
          maxRetries: 2,
          allowModelFallback: true,
        }),
      AiServiceError,
    );
    assertEquals(error.code, "MODEL_REFUSAL");
    assertEquals(error.retryable, false);
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(requestCount, 1);
});

Deno.test("context-window stop fails closed before quota settlement", async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = () => {
    requestCount++;
    return Promise.resolve(
      successResponse('{"ok":true}', "model_context_window_exceeded"),
    );
  };

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 1000,
          maxRetries: 2,
          allowModelFallback: true,
        }),
      AiServiceError,
    );
    assertEquals(error.code, "MODEL_CONTEXT_WINDOW_EXCEEDED");
    assertEquals(error.retryable, false);
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(requestCount, 1);
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

function refusalResponse(stopDetails?: unknown) {
  return new Response(
    JSON.stringify({
      content: [],
      stop_reason: "refusal",
      ...(stopDetails === undefined ? {} : { stop_details: stopDetails }),
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}

// 不理會中止訊號：模擬回應剛好在期限前到、處理完時已過期限。
function lateResponse(response: Response, delayMs: number): Promise<Response> {
  return new Promise((resolve) => setTimeout(() => resolve(response), delayMs));
}

Deno.test("Sonnet 5.5 primary stops after Sonnet 4.6 and never reaches Haiku", async () => {
  const originalFetch = globalThis.fetch;
  const models: Array<string | undefined> = [];
  globalThis.fetch = (_input, init) => {
    models.push(parseCapturedBody(init).model);
    return Promise.resolve(
      new Response("upstream unavailable", { status: 529 }),
    );
  };

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(
          { ...baseRequest(), model: "claude-sonnet-5-5" },
          "test-key",
          { timeout: 1000, maxRetries: 1, allowModelFallback: true },
        ),
      AiServiceError,
    );
    assertEquals(error.code, "ALL_MODELS_FAILED");
    assertEquals(error.metadata.lastModel, "claude-sonnet-4-6");
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(models, [
    "claude-sonnet-5-5",
    "claude-sonnet-5",
    "claude-sonnet-4-6",
  ]);
});

Deno.test("Sonnet 5 primary keeps its 5 → 4.6 → Haiku chain", async () => {
  const originalFetch = globalThis.fetch;
  const models: Array<string | undefined> = [];
  globalThis.fetch = (_input, init) => {
    models.push(parseCapturedBody(init).model);
    return Promise.resolve(
      new Response("upstream unavailable", { status: 529 }),
    );
  };

  try {
    await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 1000,
          maxRetries: 1,
          allowModelFallback: true,
        }),
      AiServiceError,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(models, [
    "claude-sonnet-5",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
  ]);
});

Deno.test("refusal carries only a well-formed stop_details.category", async () => {
  const originalFetch = globalThis.fetch;
  const cases: Array<[stopDetails: unknown, expected: string | undefined]> = [
    [
      { type: "refusal", category: "general_harms", explanation: "free text" },
      "general_harms",
    ],
    [{ type: "refusal", category: "cyber", explanation: null }, "cyber"],
    [{ type: "refusal", category: null, explanation: null }, undefined],
    [undefined, undefined],
    [{ type: "refusal", category: "not a token, free text" }, undefined],
    [{ type: "refusal", category: 42 }, undefined],
  ];
  try {
    for (const [stopDetails, expected] of cases) {
      globalThis.fetch = () => Promise.resolve(refusalResponse(stopDetails));
      const error = await assertRejects(
        () =>
          callClaudeWithFallback(baseRequest(), "test-key", {
            timeout: 1000,
            maxRetries: 2,
            allowModelFallback: true,
          }),
        AiServiceError,
      );
      assertEquals(error.code, "MODEL_REFUSAL");
      assertEquals(
        error.metadata.refusalCategory,
        expected,
        JSON.stringify(stopDetails),
      );
      assertEquals(JSON.stringify(error.metadata).includes("free text"), false);
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("a refusal processed after the absolute deadline is still MODEL_REFUSAL with its category", async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = () => {
    requestCount++;
    return lateResponse(
      refusalResponse({ type: "refusal", category: "general_harms" }),
      60,
    );
  };

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 5000,
          maxRetries: 2,
          allowModelFallback: true,
          absoluteDeadlineAtMs: Date.now() + 20,
        }),
      AiServiceError,
    );
    assertEquals(error.code, "MODEL_REFUSAL");
    assertEquals(error.metadata.refusalCategory, "general_harms");
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(requestCount, 1);
});

Deno.test("a successful response processed after the absolute deadline is still DEADLINE_EXCEEDED", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => lateResponse(successResponse(), 60);

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 5000,
          maxRetries: 2,
          allowModelFallback: true,
          absoluteDeadlineAtMs: Date.now() + 20,
        }),
      AiServiceError,
    );
    assertEquals(error.code, "DEADLINE_EXCEEDED");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("an attempt timeout shorter than the remaining deadline aborts as TIMEOUT, not DEADLINE_EXCEEDED", async () => {
  // 開場的規劃與改寫靠這條：自己的上限比整個請求的期限短時，中止算這一步逾時。
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (_input, init) => {
    const signal = (init as RequestInit | undefined)?.signal;
    return new Promise<Response>((_resolve, reject) => {
      signal?.addEventListener(
        "abort",
        () => reject(new DOMException("aborted", "AbortError")),
        { once: true },
      );
    });
  };

  try {
    const error = await assertRejects(
      () =>
        callClaudeWithFallback(baseRequest(), "test-key", {
          timeout: 20,
          maxRetries: 1,
          allowModelFallback: false,
          absoluteDeadlineAtMs: Date.now() + 5000,
        }),
      AiServiceError,
    );
    assertEquals(error.code, "MODEL_RETRY_EXHAUSTED");
    assertEquals(error.metadata.lastFailureCode, "TIMEOUT");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("each failed provider attempt reports its failure code; a refusal also reports its category", async () => {
  const originalFetch = globalThis.fetch;
  const records: Array<Record<string, unknown>> = [];
  const budget = new ModelCallBudget(
    Date.now() + 60_000,
    { stage: "test" },
    (record) => records.push(record),
  );
  let calls = 0;
  globalThis.fetch = () =>
    Promise.resolve(
      ++calls === 1
        ? new Response("upstream unavailable", { status: 529 })
        : refusalResponse({ type: "refusal", category: "general_harms" }),
    );

  try {
    await assertRejects(
      () =>
        callClaudeWithFallback(
          { ...baseRequest(), model: "claude-sonnet-5-5" },
          "test-key",
          { timeout: 1000, maxRetries: 1, allowModelFallback: true, budget },
        ),
      AiServiceError,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(
    records.map(({ model, status, failureCode, refusalCategory }) => ({
      model,
      status,
      failureCode,
      refusalCategory,
    })),
    [
      {
        model: "claude-sonnet-5-5",
        status: "failed",
        failureCode: "SERVER_ERROR",
        refusalCategory: undefined,
      },
      {
        model: "claude-sonnet-5",
        status: "failed",
        failureCode: "MODEL_REFUSAL",
        refusalCategory: "general_harms",
      },
    ],
  );
  assertEquals("refusalCategory" in records[0], false);
});
