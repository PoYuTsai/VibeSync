import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleStreamAnalysisRequest } from "./stream_handler.ts";
import type { StreamChargeResult } from "./reframer.ts";

function line(value: Record<string, unknown>): string {
  return `${JSON.stringify(value)}\n`;
}

async function* chunks(values: string[]): AsyncIterable<string> {
  for (const value of values) {
    yield value;
  }
}

async function* failingChunks(
  values: string[],
  error: Error,
): AsyncIterable<string> {
  for (const value of values) {
    yield value;
  }
  throw error;
}

async function collectEvents(response: Response): Promise<Record<string, unknown>[]> {
  const text = await response.text();
  return text
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((item) => JSON.parse(item) as Record<string, unknown>);
}

function createOptions(overrides: {
  textChunks?: string[];
  chargeResult?: StreamChargeResult;
  chargeRun?: () => StreamChargeResult | Promise<StreamChargeResult>;
  markDone?: (
    result: Record<string, unknown>,
  ) => Record<string, unknown> | void | Promise<Record<string, unknown> | void>;
  markFailed?: (
    code: string,
    details?: Record<string, unknown>,
  ) => void | Promise<void>;
  callClaude?: () => Promise<{ textStream: AsyncIterable<string> }>;
  progressEvents?: Record<string, unknown>[];
} = {}) {
  return {
    runId: "run-1",
    conversationHash: "hash-1",
    progressEvents: overrides.progressEvents as never,
    callClaude: overrides.callClaude ??
      (() =>
        Promise.resolve({
          textStream: chunks(overrides.textChunks ?? [
            line({
              type: "analysis.recommendation",
              selectedStyle: "resonate",
              message: "我懂，你可以慢慢說。",
              reason: "先承接壓力。",
              quotedContext: "太快了",
            }),
          ]),
        })),
    chargeRun: overrides.chargeRun ??
      (() => overrides.chargeResult ?? { charged: true }),
    markDone: overrides.markDone ?? (() => {}),
    markFailed: overrides.markFailed ?? (() => {}),
  };
}

Deno.test("stream handler emits started and progress before Claude events", async () => {
  const response = handleStreamAnalysisRequest(createOptions({
    progressEvents: [
      {
        type: "analysis.progress",
        label: "正在整理這段對話",
      },
    ],
  }));

  const events = await collectEvents(response);

  assertEquals(events.slice(0, 3).map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.recommendation",
  ]);
  assertEquals(events[0].runId, "run-1");
  assertEquals(events[1].label, "正在整理這段對話");
});

Deno.test("stream handler charges before emitting recommendation", async () => {
  const timeline: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    chargeRun: () => {
      timeline.push("charge");
      return { charged: true };
    },
    markDone: () => {
      timeline.push("markDone");
    },
  }));

  const text = await response.text();
  for (const item of text.trim().split("\n").filter(Boolean)) {
    const event = JSON.parse(item) as Record<string, unknown>;
    if (event.type === "analysis.recommendation") timeline.push("emitRecommendation");
    if (event.type === "analysis.done") timeline.push("emitDone");
  }

  assertEquals(timeline, [
    "charge",
    "markDone",
    "emitRecommendation",
    "emitDone",
  ]);
});

Deno.test("stream handler marks failed and emits no done when charge fails", async () => {
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    chargeResult: {
      charged: false,
      code: "STREAM_CHARGE_FAILED",
      message: "額度更新失敗，請稍後重試。",
      recoverable: true,
    },
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(failedCodes, ["STREAM_CHARGE_FAILED"]);
  assertEquals(events.map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_CHARGE_FAILED");
});

Deno.test("stream handler reports pre-recommendation Claude failure without charging", async () => {
  let chargeCalls = 0;
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    callClaude: () =>
      Promise.resolve({
        textStream: failingChunks([
          line({ type: "analysis.progress", label: "先看語氣" }),
        ], new Error("network down")),
      }),
    chargeRun: () => {
      chargeCalls += 1;
      return { charged: true };
    },
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(chargeCalls, 0);
  assertEquals(failedCodes, ["STREAM_UPSTREAM_FAILED"]);
  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_UPSTREAM_FAILED");
});

Deno.test("stream handler preserves recommendation before post-recommendation failure", async () => {
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    callClaude: () =>
      Promise.resolve({
        textStream: failingChunks([
          line({
            type: "analysis.recommendation",
            selectedStyle: "extend",
            message: "我先聽你說。",
            reason: "保留空間。",
            quotedContext: "有壓力",
          }),
        ], new Error("stream reset")),
      }),
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(failedCodes, ["STREAM_INTERRUPTED_AFTER_RECOMMENDATION"]);
  assertEquals(events.map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.recommendation",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_INTERRUPTED_AFTER_RECOMMENDATION");
});

Deno.test("stream handler persists final result before emitting done", async () => {
  const timeline: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    markDone: () => {
      timeline.push("markDone");
    },
  }));

  const text = await response.text();
  for (const item of text.trim().split("\n").filter(Boolean)) {
    const event = JSON.parse(item) as Record<string, unknown>;
    if (event.type === "analysis.done") timeline.push("emitDone");
  }

  assertEquals(timeline, ["markDone", "emitDone"]);
});

Deno.test("stream handler emits processed final result returned by markDone", async () => {
  const response = handleStreamAnalysisRequest(createOptions({
    markDone: (result) => ({
      ...result,
      processedByPostProcess: true,
    }),
  }));

  const events = await collectEvents(response);
  const done = events.find((event) => event.type === "analysis.done");
  const finalResult = done?.finalResult as Record<string, unknown> | undefined;

  assertEquals(finalResult?.processedByPostProcess, true);
});

Deno.test("stream handler emits terminal error when final persist fails", async () => {
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    markDone: () => {
      throw new Error("db unavailable");
    },
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(failedCodes, ["STREAM_FINAL_PERSIST_FAILED"]);
  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_FINAL_PERSIST_FAILED");
});

Deno.test("stream handler keeps response readable when markFailed itself fails", async () => {
  const response = handleStreamAnalysisRequest(createOptions({
    callClaude: () => Promise.reject(new Error("upstream unavailable")),
    markFailed: () => {
      throw new Error("failed log unavailable");
    },
  }));

  const events = await collectEvents(response);

  assertEquals(events.at(-2)?.type, "analysis.progress");
  assertEquals(events.at(-2)?.phase, "failure-log");
  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_UPSTREAM_FAILED");
});

Deno.test("stream handler body rejects only when the NDJSON controller fails", async () => {
  const response = handleStreamAnalysisRequest(createOptions({
    markDone: () => {},
  }));

  await assertRejects(async () => {
    // The body is locked after the first read; this assertion protects the test
    // harness from accidentally hiding stream-controller failures.
    await response.text();
    await response.text();
  });
});
