import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  KeyboardReplyQuotaExceededError,
  runKeyboardReply,
} from "./generation.ts";

const input = {
  userId: "u1",
  apiKey: "test",
  accountIsTest: false,
  message: "今天工作好累",
  style: "resonate" as const,
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
    deductCredit: () => {
      deductions++;
      return Promise.resolve();
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
    deductCredit: () => {
      deductions++;
      return Promise.resolve();
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
    deductCredit: () => {
      deductions++;
      return Promise.resolve();
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
    deductCredit: () =>
      Promise.reject(
        new KeyboardReplyQuotaExceededError("daily_limit_exceeded", 5, 5),
      ),
  });
  assertEquals(result.status, 429);
  assertEquals(result.body.reply, undefined);
});
