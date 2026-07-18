import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  callClaudeAPI,
  KEYBOARD_CLAUDE_ATTEMPT_TIMEOUT_MS,
  KEYBOARD_GENERATION_BUDGET_MS,
  KEYBOARD_REPLY_MODEL,
  KEYBOARD_REQUEST_BUDGET_MS,
  KEYBOARD_SETTLEMENT_RESERVE_MS,
  keyboardGenerationBudgetRemaining,
  KeyboardReplyFinalizeError,
  KeyboardReplyQuotaExceededError,
  runKeyboardReply,
} from "./generation.ts";

const input = {
  userId: "u1",
  apiKey: "test",
  accountIsTest: false,
  message: "今天工作好累",
  style: "resonate" as const,
  requestId: null,
};

Deno.test("generation deducts exactly once only after valid output", async () => {
  let calls = 0;
  let deductions = 0;
  const result = await runKeyboardReply(input, {
    callClaude: () => {
      calls++;
      return Promise.resolve({
        content: [{ text: '{"reply":"今天真的辛苦了，晚點想怎麼充電？"}' }],
      });
    },
    finalizeReply: (_userId, reply) => {
      deductions++;
      return Promise.resolve({ reply, costDeducted: 1 as const });
    },
  });
  assertEquals(result.status, 200);
  assertEquals(calls, 1);
  assertEquals(deductions, 1);
});

Deno.test("generation repairs once and never charges double", async () => {
  let calls = 0;
  let deductions = 0;
  const result = await runKeyboardReply(input, {
    callClaude: () =>
      Promise.resolve(
        calls++ === 0 ? { content: [{ text: "not-json" }] } : {
          content: [{
            text: '{"reply":"這種累真的會把人榨乾，先犒賞自己一下？"}',
          }],
        },
      ),
    finalizeReply: (_userId, reply) => {
      deductions++;
      return Promise.resolve({ reply, costDeducted: 1 as const });
    },
  });
  assertEquals(result.status, 200);
  assertEquals(calls, 2);
  assertEquals(deductions, 1);
});

Deno.test("Sonnet generation and repair share one bounded deadline", async () => {
  let nowMs = 0;
  const timeouts: number[] = [];
  const result = await runKeyboardReply(input, {
    now: () => nowMs,
    callClaude: (args) => {
      timeouts.push(args.timeoutMs);
      if (timeouts.length === 1) {
        nowMs = KEYBOARD_CLAUDE_ATTEMPT_TIMEOUT_MS;
      }
      return Promise.resolve({ content: [{ text: "not-json" }] });
    },
    finalizeReply: () => {
      throw new Error("must not settle invalid generation");
    },
  });

  assertEquals(KEYBOARD_GENERATION_BUDGET_MS, 20_000);
  assertEquals(KEYBOARD_CLAUDE_ATTEMPT_TIMEOUT_MS, 15_000);
  assertEquals(timeouts, [15_000, 5_000]);
  assertEquals(result.status, 500);
  assertEquals(result.body.error, "generation_failed");
  assertEquals(result.costDeducted, 0);
});

Deno.test("request deadline reserves settlement time before generation", () => {
  assertEquals(KEYBOARD_REQUEST_BUDGET_MS, 24_000);
  assertEquals(KEYBOARD_SETTLEMENT_RESERVE_MS, 4_000);
  assertEquals(keyboardGenerationBudgetRemaining(24_000, 0), 20_000);
  assertEquals(keyboardGenerationBudgetRemaining(24_000, 5_000), 15_000);
  assertEquals(keyboardGenerationBudgetRemaining(24_000, 20_000), 0);
});

Deno.test("double format failure returns 500 and does not charge", async () => {
  let deductions = 0;
  const result = await runKeyboardReply(input, {
    callClaude: () => Promise.resolve({ content: [{ text: "bad" }] }),
    finalizeReply: (_userId, reply) => {
      deductions++;
      return Promise.resolve({ reply, costDeducted: 1 as const });
    },
  });
  assertEquals(result.status, 500);
  assertEquals(deductions, 0);
});

Deno.test("refusal and context-window stops are terminal without repair", async () => {
  for (const stopReason of ["refusal", "model_context_window_exceeded"]) {
    let calls = 0;
    let deductions = 0;
    const result = await runKeyboardReply(input, {
      callClaude: () => {
        calls++;
        return Promise.resolve({
          stop_reason: stopReason,
          content: [{ type: "text", text: '{"reply":"不得使用"}' }],
        });
      },
      finalizeReply: (_userId, reply) => {
        deductions++;
        return Promise.resolve({ reply, costDeducted: 1 as const });
      },
    });

    assertEquals(result.status, 500);
    assertEquals(result.body.error, "generation_failed");
    assertEquals(calls, 1);
    assertEquals(deductions, 0);
  }
});

Deno.test("deduct-time quota race returns 429 without reply", async () => {
  const result = await runKeyboardReply(input, {
    callClaude: () =>
      Promise.resolve({
        content: [{ text: '{"reply":"辛苦了，先去吃點好吃的補血？"}' }],
      }),
    finalizeReply: () =>
      Promise.reject(
        new KeyboardReplyQuotaExceededError("daily_limit_exceeded", 5, 5),
      ),
  });
  assertEquals(result.status, 429);
  assertEquals(result.body.reply, undefined);
});

Deno.test("settlement replay returns authoritative stored reply without charging", async () => {
  const result = await runKeyboardReply(input, {
    callClaude: () =>
      Promise.resolve({ content: [{ text: '{"reply":"second generation"}' }] }),
    finalizeReply: () =>
      Promise.resolve({ reply: "first committed reply", costDeducted: 0 }),
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.reply, "first committed reply");
  assertEquals(result.costDeducted, 0);
});

Deno.test("ambiguous settlement failure stays retryable", async () => {
  const result = await runKeyboardReply(input, {
    callClaude: () =>
      Promise.resolve({ content: [{ text: '{"reply":"合法回覆"}' }] }),
    finalizeReply: () =>
      Promise.reject(
        new KeyboardReplyFinalizeError(
          503,
          "KEYBOARD_REPLY_SETTLEMENT_RETRYABLE",
          "connection reset",
        ),
      ),
  });
  assertEquals(result.status, 503);
  assertEquals(result.body.retryable, true);
  assertEquals(result.costDeducted, 0);
});

Deno.test("Keyboard Sonnet 5 request disables thinking and omits sampling", async () => {
  const originalFetch = globalThis.fetch;
  let body: Record<string, unknown> = {};
  globalThis.fetch = (_input, init) => {
    const requestBody = init && "body" in init ? init.body : undefined;
    body = JSON.parse(String(requestBody)) as Record<string, unknown>;
    return Promise.resolve(
      new Response(
        JSON.stringify({
          stop_reason: "end_turn",
          content: [{ type: "text", text: '{"reply":"收到"}' }],
        }),
        { status: 200 },
      ),
    );
  };
  try {
    await callClaudeAPI({
      apiKey: "test",
      system: "system",
      message: "message",
      timeoutMs: 1000,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assertEquals(body.model, KEYBOARD_REPLY_MODEL);
  assertEquals(body.thinking, { type: "disabled" });
  assertEquals("temperature" in body, false);
  assertEquals("top_p" in body, false);
  assertEquals("top_k" in body, false);
});
