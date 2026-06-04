import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleStreamAnalysisRequest } from "./stream_handler.ts";
import type {
  StreamChargeResult,
  StreamRecommendationForCharge,
} from "./reframer.ts";

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

async function* delayedChunks(
  values: string[],
  delayMs: number,
): AsyncIterable<string> {
  await new Promise((resolve) => setTimeout(resolve, delayMs));
  for (const value of values) {
    yield value;
  }
}

async function collectEvents(
  response: Response,
): Promise<Record<string, unknown>[]> {
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
  heartbeatIntervalMs?: number;
  prechargedRecommendation?: StreamRecommendationForCharge;
} = {}) {
  return {
    runId: "run-1",
    conversationHash: "hash-1",
    progressEvents: overrides.progressEvents as never,
    heartbeatIntervalMs: overrides.heartbeatIntervalMs,
    callClaude: overrides.callClaude ??
      (() =>
        Promise.resolve({
          textStream: chunks(
            overrides.textChunks ?? [
              line({
                type: "analysis.recommendation",
                selectedStyle: "resonate",
                message: "我懂，你先慢慢說，我在。",
                reason: "先接住對方情緒，不急著推進。",
                quotedContext: "我最近壓力很大",
              }),
            ],
          ),
        })),
    chargeRun: overrides.chargeRun ??
      (() => overrides.chargeResult ?? { charged: true }),
    prechargedRecommendation: overrides.prechargedRecommendation,
    markDone: overrides.markDone ?? (() => {}),
    markFailed: overrides.markFailed ?? (() => {}),
  };
}

Deno.test("stream handler emits default Traditional Chinese progress before Claude events", async () => {
  const response = handleStreamAnalysisRequest(createOptions());

  const events = await collectEvents(response);

  assertEquals(events.slice(0, 4).map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.recommendation",
  ]);
  assertEquals(events[0].runId, "run-1");
  assertEquals(events[0].etaSeconds, 18);
  assertEquals(events[1].label, "讀取對話脈絡");
  assertEquals(events[1].detail, "正在整理你們這一輪的訊息、情緒與回覆目標。");
  assertEquals(events[2].label, "判斷本回合方向");
  assertEquals(
    events[2].detail,
    "正在選擇最適合的回覆策略，完整分析會在下方繼續整理。",
  );
});

Deno.test("stream handler emits heartbeat progress while waiting for Claude", async () => {
  const response = handleStreamAnalysisRequest(createOptions({
    heartbeatIntervalMs: 1,
    callClaude: () =>
      Promise.resolve({
        textStream: delayedChunks([
          line({
            type: "analysis.recommendation",
            selectedStyle: "resonate",
            message: "I get why that felt off.",
            reason: "Respect the boundary.",
            quotedContext: "too fast",
          }),
          line({
            type: "analysis.done",
            finalResult: {
              finalRecommendation: {
                pick: "resonate",
                content: "I get why that felt off.",
              },
            },
          }),
        ], 8),
      }),
  }));

  const events = await collectEvents(response);
  const heartbeat = events.find((event) => event.phase === "heartbeat");

  assertEquals(heartbeat?.type, "analysis.progress");
  assertEquals(heartbeat?.runId, "run-1");
  assertEquals(events.at(-1)?.type, "analysis.done");
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
    if (event.type === "analysis.recommendation") {
      timeline.push("emitRecommendation");
    }
    if (event.type === "analysis.done") timeline.push("emitDone");
  }

  assertEquals(timeline, [
    "charge",
    "markDone",
    "emitRecommendation",
    "emitDone",
  ]);
});

Deno.test("stream handler emits buffered core events after charge succeeds", async () => {
  const response = handleStreamAnalysisRequest(createOptions({
    textChunks: [
      line({
        type: "analysis.decision",
        selectedStyle: "resonate",
        nextStepTitle: "Next move",
        nextStepBody: "Acknowledge first, then slow the pace.",
        doThis: "Send one grounded reply.",
        avoidThis: "Do not over-explain.",
      }),
      line({
        type: "analysis.recommendation",
        selectedStyle: "resonate",
        message: "I get why that felt off.",
        reason: "Respect the boundary.",
        quotedContext: "too fast",
      }),
      line({
        type: "analysis.report_section",
        section: "strategy",
        content: "Back off and rebuild trust.",
      }),
      line({
        type: "analysis.done",
        finalResult: {
          strategy: "Back off and rebuild trust.",
          finalRecommendation: {
            pick: "resonate",
            content: "I get why that felt off.",
          },
        },
      }),
    ],
  }));

  const events = await collectEvents(response);

  assertEquals(events.map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.decision",
    "analysis.recommendation",
    "analysis.report_section",
    "analysis.done",
  ]);
  assertEquals(events[3].nextStepTitle, "Next move");
  assertEquals(events[5].section, "strategy");
});

Deno.test("stream handler keeps a cleanly ended decision-only stream retryable", async () => {
  let markDoneCalls = 0;
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    textChunks: [
      line({
        type: "analysis.decision",
        selectedStyle: "resonate",
        nextStepBody: "This is useful, but not complete yet.",
        doThis: "Wait for a recommendation before completing.",
      }),
    ],
    markDone: () => {
      markDoneCalls += 1;
    },
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(markDoneCalls, 0);
  assertEquals(failedCodes, ["STREAM_MISSING_COMPLETION_ANCHOR"]);
  assertEquals(events.map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.decision",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_MISSING_COMPLETION_ANCHOR");
});

Deno.test("stream handler marks failed and emits no done when charge fails", async () => {
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    chargeResult: {
      charged: false,
      code: "STREAM_CHARGE_FAILED",
      message: "額度扣除失敗，請稍後重新分析。",
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
  assertEquals(events.at(-1)?.message, "額度扣除失敗，請稍後重新分析。");
});

Deno.test("stream handler reports pre-recommendation Claude failure without charging", async () => {
  let chargeCalls = 0;
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    callClaude: () =>
      Promise.resolve({
        textStream: failingChunks([
          line({ type: "analysis.progress", label: "model progress leaked" }),
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
  assertEquals(
    events.some((event) => event.label === "model progress leaked"),
    false,
  );
  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_UPSTREAM_FAILED");
  assertEquals(events.at(-1)?.message, "分析暫時無法完成，請稍後重新分析。");
});

Deno.test("stream handler does not leak decision content when decision charge fails", async () => {
  let chargeCalls = 0;
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    chargeResult: {
      charged: false,
      code: "STREAM_CHARGE_FAILED",
      message: "Quota failed.",
      recoverable: true,
    },
    callClaude: () =>
      Promise.resolve({
        textStream: chunks([
          line({
            type: "analysis.decision",
            selectedStyle: "resonate",
            nextStepBody: "This should stay buffered before charge.",
            doThis: "Send the calibrated reply.",
            avoidThis: "Do not over-explain.",
          }),
        ]),
      }),
    chargeRun: () => {
      chargeCalls += 1;
      return {
        charged: false,
        code: "STREAM_CHARGE_FAILED",
        message: "Quota failed.",
        recoverable: true,
      };
    },
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(chargeCalls, 1);
  assertEquals(failedCodes, ["STREAM_CHARGE_FAILED"]);
  assertEquals(
    events.some((event) => event.type === "analysis.decision"),
    false,
  );
  assertEquals(events.at(-1)?.code, "STREAM_CHARGE_FAILED");
});

Deno.test("stream handler preserves charged content before post-charge failure", async () => {
  const failedCodes: string[] = [];
  const response = handleStreamAnalysisRequest(createOptions({
    callClaude: () =>
      Promise.resolve({
        textStream: failingChunks([
          line({
            type: "analysis.recommendation",
            selectedStyle: "extend",
            message: "我懂，你剛剛那樣其實很累。",
            reason: "先共鳴",
            quotedContext: "你是不是太快了？",
          }),
        ], new Error("stream reset")),
      }),
    markFailed: (code) => {
      failedCodes.push(code);
    },
  }));

  const events = await collectEvents(response);

  assertEquals(failedCodes, ["STREAM_INTERRUPTED_AFTER_CONTENT"]);
  assertEquals(events.map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.recommendation",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_INTERRUPTED_AFTER_CONTENT");
  assertEquals(
    events.at(-1)?.message,
    "分析中途斷線，已保留先前產生的建議；請重新整理完整分析。",
  );
});

Deno.test("stream handler can resume from a precharged recommendation without charging again", async () => {
  let chargeCalls = 0;
  const response = handleStreamAnalysisRequest(createOptions({
    prechargedRecommendation: {
      selectedStyle: "resonate",
      message: "先接住你，這件事確實不容易。",
      reason: "保留已扣費的官方推薦。",
      quotedContext: "我最近真的很累",
      warnings: [],
      raw: {
        type: "analysis.recommendation",
        selectedStyle: "resonate",
        message: "先接住你，這件事確實不容易。",
      },
    },
    textChunks: [
      line({
        type: "analysis.recommendation",
        selectedStyle: "extend",
        message: "model retry should not replace stored recommendation",
        reason: "duplicate from retry model",
        quotedContext: "ignored",
      }),
      line({
        type: "analysis.done",
        finalResult: {
          finalRecommendation: {
            pick: "resonate",
            content: "先接住你，這件事確實不容易。",
          },
        },
      }),
    ],
    chargeRun: () => {
      chargeCalls += 1;
      return { charged: true };
    },
  }));

  const events = await collectEvents(response);

  assertEquals(chargeCalls, 0);
  assertEquals(events.map((event) => event.type), [
    "analysis.started",
    "analysis.progress",
    "analysis.progress",
    "analysis.recommendation",
    "analysis.done",
  ]);
  assertEquals(events[3].message, "先接住你，這件事確實不容易。");
  assertEquals(
    (events.at(-1)?.finalResult as Record<string, unknown>)
      .finalRecommendation,
    {
      pick: "resonate",
      content: "先接住你，這件事確實不容易。",
    },
  );
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
  assertEquals(events.at(-1)?.message, "完整分析儲存失敗，請重新分析。");
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
  assertEquals(events.at(-2)?.label, "紀錄失敗狀態時發生問題");
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
