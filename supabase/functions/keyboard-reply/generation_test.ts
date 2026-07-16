import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
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
