import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { ClaudeArgs } from "./claude.ts";
import {
  runSingleShot,
  SingleShotExhaustedError,
} from "./single_shot.ts";

const MODELS: [string, string] = [
  "claude-sonnet-5",
  "claude-haiku-4-5-20251001",
];

const FORCED_TOOL = {
  name: "emit_hint",
  inputSchema: { type: "object" } as Record<string, unknown>,
};

function baseArgs(overrides: Partial<Parameters<typeof runSingleShot>[0]> = {}) {
  return {
    callClaude: (_args: ClaudeArgs) => Promise.resolve('{"ok":true}'),
    apiKey: "test-key",
    messages: [{ role: "user" as const, content: "hi" }],
    forcedTool: FORCED_TOOL,
    maxTokens: 500,
    temperature: 0.45,
    perCallTimeoutMs: 15_000,
    deadlineAtMs: 1_000_000,
    now: () => 0,
    models: MODELS,
    validate: (raw: string, _model: string) => JSON.parse(raw),
    ...overrides,
  };
}

Deno.test("runSingleShot returns first-attempt result with no failures", async () => {
  const calls: ClaudeArgs[] = [];
  const outcome = await runSingleShot(baseArgs({
    callClaude: (args) => {
      calls.push(args);
      return Promise.resolve('{"ok":true}');
    },
  }));
  assertEquals(outcome.result, { ok: true });
  assertEquals(outcome.model, "claude-sonnet-5");
  assertEquals(outcome.attemptFailures, []);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].model, "claude-sonnet-5");
  assertEquals(calls[0].maxTokens, 500);
  assertEquals(calls[0].temperature, 0.45);
  assertEquals(calls[0].forcedTool?.name, "emit_hint");
});

Deno.test("runSingleShot fails over to the second model immediately", async () => {
  const calls: ClaudeArgs[] = [];
  const outcome = await runSingleShot(baseArgs({
    callClaude: (args) => {
      calls.push(args);
      if (args.model === "claude-sonnet-5") {
        return Promise.reject(new Error("claude_timeout"));
      }
      return Promise.resolve('{"ok":"haiku"}');
    },
  }));
  assertEquals(outcome.result, { ok: "haiku" });
  assertEquals(outcome.model, "claude-haiku-4-5-20251001");
  assertEquals(outcome.attemptFailures.length, 1);
  assertEquals(outcome.attemptFailures[0].model, "claude-sonnet-5");
  assertEquals(outcome.attemptFailures[0].code, "claude_timeout");
  assertEquals(calls.length, 2);
  assertEquals(calls[1].model, "claude-haiku-4-5-20251001");
});

Deno.test("runSingleShot treats a validate rejection as a failed attempt", async () => {
  let attempt = 0;
  const outcome = await runSingleShot(baseArgs({
    callClaude: () => Promise.resolve('{"ok":true}'),
    validate: (raw: string) => {
      attempt += 1;
      if (attempt === 1) throw new Error("gate:visible_label_leak");
      return JSON.parse(raw);
    },
  }));
  assertEquals(outcome.model, "claude-haiku-4-5-20251001");
  assertEquals(outcome.attemptFailures[0].code, "gate:visible_label_leak");
});

Deno.test("runSingleShot throws SingleShotExhaustedError when both attempts fail", async () => {
  const error = await assertRejects(
    () =>
      runSingleShot(baseArgs({
        callClaude: (args) =>
          Promise.reject(
            new Error(
              args.model === "claude-sonnet-5"
                ? "claude_timeout"
                : "claude_http_529",
            ),
          ),
      })),
    SingleShotExhaustedError,
  );
  assertEquals(error.attemptFailures.length, 2);
  assertEquals(error.attemptFailures[0].code, "claude_timeout");
  assertEquals(error.attemptFailures[1].code, "claude_http_529");
  assertEquals(error.attemptFailures[1].model, "claude-haiku-4-5-20251001");
});

Deno.test("runSingleShot clamps each call timeout to the request deadline", async () => {
  const timeouts: number[] = [];
  await runSingleShot(baseArgs({
    perCallTimeoutMs: 15_000,
    deadlineAtMs: 10_000,
    now: () => 0,
    callClaude: (args) => {
      timeouts.push(args.timeoutMs);
      return Promise.resolve('{"ok":true}');
    },
  }));
  // min(15000, 10000 - 0 - 1000) = 9000
  assertEquals(timeouts, [9_000]);
});

Deno.test("runSingleShot skips an attempt when under 3s remains before the deadline", async () => {
  const calls: string[] = [];
  // 第一發在 t=0 打（剩 20s）；第一發敗後時鐘推到 t=18_000（剩 2s < 3s）。
  let currentTime = 0;
  const error = await assertRejects(
    () =>
      runSingleShot(baseArgs({
        deadlineAtMs: 20_000,
        now: () => currentTime,
        callClaude: (args) => {
          calls.push(args.model);
          currentTime = 18_000;
          return Promise.reject(new Error("claude_http_500"));
        },
      })),
    SingleShotExhaustedError,
  );
  assertEquals(calls, ["claude-sonnet-5"]);
  assertEquals(error.attemptFailures[1].code, "deadline_exhausted");
  assertEquals(error.attemptFailures[1].model, "claude-haiku-4-5-20251001");
});

Deno.test("runSingleShot keeps candidate raw only in the failure record field", async () => {
  // 契約改版（2026-07-23 真機 gh6 觀測缺口，Eric 拍板）：gate 打回的候選
  // 原文保留在 attemptFailures[].raw 供 ai_logs.response_body 診斷 TP/FP；
  // error message／stack 仍然只准機器碼，絕不夾原文。
  const UNSAFE = "UNSAFE_CANDIDATE_RAW_TEXT_SHOULD_NEVER_LEAK";
  const error = await assertRejects(
    () =>
      runSingleShot(baseArgs({
        callClaude: () => Promise.resolve(`{"text":"${UNSAFE}"}`),
        validate: () => {
          throw new Error("gate:l4_unsafe");
        },
      })),
    SingleShotExhaustedError,
  );
  const serialized = JSON.stringify({
    message: error.message,
    stack: error.stack ?? "",
    codes: error.attemptFailures.map((failure) => failure.code),
  });
  assertEquals(serialized.includes(UNSAFE), false);
  // gate 打回帶 raw；transport 失敗（下一發 deadline/HTTP 類）不帶。
  assertEquals(
    error.attemptFailures[0].raw,
    `{"text":"${UNSAFE}"}`,
  );
});

Deno.test("runSingleShot omits raw for transport failures", async () => {
  const error = await assertRejects(
    () =>
      runSingleShot(baseArgs({
        callClaude: () => Promise.reject(new Error("claude_http_500")),
      })),
    SingleShotExhaustedError,
  );
  for (const failure of error.attemptFailures) {
    assertEquals(failure.raw, undefined);
  }
});
