// 唯一 AnalyzeStreamHandler 的 fake-port 行為測試：
// create／retry／resume／charge／markDone／markFailed 的呼叫順序。

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AnalyzeStreamDeps,
  handleAnalyzeStream,
} from "./analyze_stream_handler.ts";
import { buildAnalyzeStreamSystemPrompt } from "./analyze_prompt.ts";
import { buildPhase0ObservabilityTelemetry } from "./phase0_observability.ts";
import { AiStreamingServiceError } from "./streaming_fallback.ts";

function line(value: Record<string, unknown>): string {
  return `${JSON.stringify(value)}\n`;
}

async function* chunks(values: string[]): AsyncIterable<string> {
  for (const value of values) {
    yield value;
  }
}

// deno-lint-ignore no-explicit-any
function makeRun(overrides: Record<string, unknown> = {}): any {
  return {
    id: "run-1",
    status: "pending",
    retry_count: 0,
    expires_at: new Date(Date.now() + 3600_000).toISOString(),
    final_result_json: null,
    recommendation_json: null,
    last_error_code: null,
    charged_at: null,
    ...overrides,
  };
}

function makeDeps(options: {
  calls: string[];
  analysisRunId?: string | null;
  effectiveTier?: string;
  allowedFeatures?: string[];
  capturedMaxTokens?: number[];
  capturedSystems?: string[];
  // deno-lint-ignore no-explicit-any
  getRunResult?: any;
  modelChunks?: string[];
  modelError?: Error;
}): AnalyzeStreamDeps {
  const { calls } = options;
  return {
    store: {
      getRun: (_args) => {
        calls.push("getRun");
        return Promise.resolve(options.getRunResult ?? makeRun());
      },
      reserveRetry: (_args) => {
        calls.push("reserveRetry");
        return Promise.resolve(options.getRunResult ?? makeRun());
      },
      createPendingRun: (_args) => {
        calls.push("createPendingRun");
        return Promise.resolve(makeRun());
      },
      chargeRun: (_args) => {
        calls.push("chargeRun");
        return Promise.resolve();
      },
      markDone: (_args) => {
        calls.push("markDone");
        return Promise.resolve();
      },
      markFailed: (_args) => {
        calls.push("markFailed");
        return Promise.resolve(makeRun({ status: "failed", retry_count: 1 }));
      },
    },
    userId: "00000000-0000-4000-8000-000000000001",
    analysisRunId: options.analysisRunId ?? null,
    requestType: "analyze",
    analyzeMode: "normal",
    expectedTier: "free",
    effectiveTier: options.effectiveTier ?? "free",
    accountIsTest: false,
    allowedFeatures: options.allowedFeatures ?? ["extend", "tease"],
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 1,
      estimatedMessageCount: 1,
    },
    monthlyLimit: 30,
    dailyLimit: 15,
    subMonthlyUsed: 0,
    subDailyUsed: 0,
    selectedModel: "claude-sonnet-5",
    userMessageContent: "分析這段對話",
    requestObservability: {},
    messages: [{ isFromMe: false, content: "嗨" }],
    hashInput: {
      messages: [{ isFromMe: false, content: "嗨" }],
      userDraft: undefined,
      partnerSummary: undefined,
      sessionContext: undefined,
      conversationSummary: undefined,
      effectiveStyleContext: undefined,
      knownContactName: undefined,
    },
    claudeApiKey: "fake-key",
    supabaseUrl: "http://localhost:54321",
    supabaseServiceKey: "fake-service-key",
    callModel: (request) => {
      calls.push("callModel");
      options.capturedMaxTokens?.push(request.max_tokens);
      options.capturedSystems?.push(request.system);
      if (options.modelError) return Promise.reject(options.modelError);
      return Promise.resolve({
        model: "claude-sonnet-5",
        usage: {
          inputTokens: 10,
          outputTokens: 5,
          cacheCreationTokens: 0,
          cacheReadTokens: 0,
        },
        textStream: chunks(
          options.modelChunks ?? [
            line({
              type: "analysis.recommendation",
              selectedStyle: "tease",
              message: "先回她這句試試看。",
              reason: "接住話題再輕輕推進。",
              quotedContext: "嗨",
            }),
            line({
              type: "analysis.reply_option",
              style: "extend",
              message: "多聊聊今天的事吧。",
              reason: "延展話題。",
            }),
            line({
              type: "analysis.reply_option",
              style: "tease",
              message: "先回她這句試試看。",
              reason: "接住話題再輕輕推進。",
            }),
            line({
              type: "analysis.done",
              finalResult: {
                replies: {
                  extend: "多聊聊今天的事吧。",
                  tease: "先回她這句試試看。",
                },
                finalRecommendation: {
                  pick: "tease",
                  content: "先回她這句試試看。",
                },
              },
            }),
          ],
        ),
        // deno-lint-ignore no-explicit-any
      } as any);
    },
  };
}

async function runWithStubbedFetch(
  deps: AnalyzeStreamDeps,
): Promise<{ response: Response; text: string }> {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response("{}", {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  try {
    const response = await handleAnalyzeStream(deps);
    const text = await response.text();
    return { response, text };
  } finally {
    globalThis.fetch = originalFetch;
  }
}

async function withCapturedConsoleLog(
  run: () => Promise<void>,
): Promise<unknown[][]> {
  const entries: unknown[][] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => entries.push(args);
  try {
    await run();
  } finally {
    console.log = original;
  }
  return entries;
}

Deno.test("stream fresh run：createPendingRun → callModel → chargeRun → markDone 順序", async () => {
  const calls: string[] = [];
  const { text } = await runWithStubbedFetch(makeDeps({ calls }));

  assert(text.includes('"analysis.started"') || text.includes("analysis"));
  assertEquals(calls[0], "createPendingRun");
  assertEquals(calls[1], "callModel");
  const chargeAt = calls.indexOf("chargeRun");
  const doneAt = calls.indexOf("markDone");
  assert(chargeAt > 1, "recommendation 出現後才扣費");
  assert(doneAt > chargeAt, "markDone 必須在 chargeRun 之後");
  assert(!calls.includes("getRun"), "fresh run 不讀舊 run");
  assert(!calls.includes("reserveRetry"), "fresh run 不佔 retry 名額");
  assert(!calls.includes("markFailed"));
});

Deno.test("Phase 0 handler emits content-free decision-to-reply telemetry", async () => {
  const calls: string[] = [];
  const logs = await withCapturedConsoleLog(async () => {
    await runWithStubbedFetch(makeDeps({
      calls,
      modelChunks: [
        line({
          type: "analysis.inventory",
          balls: [{
            id: "b_1",
            sourceIndex: 1,
            sourceMessage: "SOURCE_SECRET",
            disposition: "接",
            reason: "REASON_SECRET",
          }],
        }),
        line({
          type: "analysis.decision",
          schemaVersion: 2,
          decisionId: "SOURCE_SECRET",
          selectedStyle: "extend",
          action: "connect",
          messageDecision: "send",
          replyMode: "variants",
          selectedBallIds: ["b_1"],
          betaRiskFlags: ["question_only"],
          solutionModeAllowed: false,
          newTopicBudget: 0,
          nextStepBody: "維持自然互動。",
          doThis: "先接住內容。",
        }),
        line({
          type: "analysis.recommendation",
          selectedStyle: "extend",
          message: "REPLY_SECRET?",
          reason: "REASON_SECRET",
          quotedContext: "QUOTE_SECRET",
        }),
        line({
          type: "analysis.reply_option",
          style: "extend",
          action: "connect",
          selectedBallIds: ["b_1"],
          sourceBallIds: ["b_1"],
          questionCount: 1,
          newTopicCount: 0,
          solutionMode: false,
          segments: [{
            sourceIndex: 1,
            sourceMessage: "SOURCE_SECRET",
            reply: "REPLY_SECRET?",
            reason: "REASON_SECRET",
          }],
        }),
        line({
          type: "analysis.reply_option",
          style: "tease",
          action: "connect",
          selectedBallIds: ["b_1"],
          sourceBallIds: ["b_1"],
          questionCount: 0,
          newTopicCount: 0,
          solutionMode: false,
          segments: [{
            sourceIndex: 1,
            sourceMessage: "SOURCE_SECRET",
            reply: "不急著問，也先接住。",
            reason: "REASON_SECRET",
          }],
        }),
        line({ type: "analysis.done", finalResult: {} }),
      ],
    }));
  });

  const phase0 = logs.find((entry) =>
    entry[0] === "[analyze-chat] stream_phase0_observability"
  );
  assert(phase0, "expected Phase 0 telemetry log");
  const metadata = phase0[1] as Record<string, unknown>;
  assertEquals(metadata.decisionId, "unknown");
  assertEquals(metadata.actionMismatch, false);
  assertEquals(metadata.ballMismatch, false);
  assertEquals(metadata.noSendConflict, "unknown");
  assertEquals(metadata.betaRiskFlags, ["question_only"]);
  assertEquals(metadata.meaningfulBallCoverage, {
    status: "observed",
    meaningfulSourceIndices: [1],
    coveredSourceIndicesByStyle: { extend: [1], tease: [1] },
    allVariantsCoverMeaningful: true,
  });
  assertEquals(metadata.questionCounts, {
    status: "observed",
    byStyle: { extend: 1, tease: 0 },
    maxQuestionCount: 1,
  });
  assertEquals(metadata.topicJump, {
    status: "observed",
    newTopicBudget: 0,
    maxNewTopicCount: 0,
    exceedsBudget: false,
  });
  assertEquals(metadata.solutionMode, {
    status: "observed",
    allowed: false,
    usedByStyle: { extend: false, tease: false },
    conflict: false,
  });
  assertEquals(metadata.fiveCardSourceDivergence, {
    status: "observed",
    baselineStyle: "extend",
    sourceBallIdEvidence: "complete",
    sourceMessageEvidence: "complete",
    // The recommended card's source is repaired against the delivered
    // conversation, while the non-selected style card retains its own source.
    divergentStyles: ["tease"],
    allMatch: false,
  });

  const logged = JSON.stringify(metadata);
  assertFalse(logged.includes("SOURCE_SECRET"));
  assertFalse(logged.includes("REPLY_SECRET"));
  assertFalse(logged.includes("REASON_SECRET"));
  assertFalse(logged.includes("QUOTE_SECRET"));
  assertFalse(logged.includes("b_1"));
  assert(calls.includes("markDone"), "telemetry must run after persistence");
});

Deno.test("Phase 0 handler ignores record-shaped done snapshot injection for persistence and telemetry", async () => {
  const calls: string[] = [];
  let persistedFinalResult: Record<string, unknown> | undefined;
  const deps = makeDeps({
    calls,
    allowedFeatures: ["tease"],
    modelChunks: [
      line({
        type: "analysis.recommendation",
        selectedStyle: "tease",
        message: "先回她這句試試看。",
        reason: "接住話題再輕輕推進。",
        quotedContext: "嗨",
      }),
      line({
        type: "analysis.done",
        finalResult: {
          analysisDecisionV2: {
            schemaVersion: 2,
            decisionId: "ad_done_injected",
            action: "invite",
          },
          analysisInventory: {
            balls: [{
              sourceIndex: 1,
              sourceMessage: "DONE_INJECTED_SOURCE_SECRET",
              disposition: "接",
            }],
          },
          analysisEvidenceLinkage: {
            schemaVersion: 1,
            decisionId: "ad_done_injected",
            selectedStyle: "extend",
            variants: { extend: { sourceIndices: [1] } },
          },
        },
      }),
    ],
  });
  const originalMarkDone = deps.store.markDone;
  deps.store.markDone = (args) => {
    persistedFinalResult = args.finalResult;
    return originalMarkDone(args);
  };

  const logs = await withCapturedConsoleLog(async () => {
    await runWithStubbedFetch(deps);
  });

  assert(persistedFinalResult, "expected a persisted final result");
  assertEquals("analysisDecisionV2" in persistedFinalResult, false);
  assertEquals("analysisInventory" in persistedFinalResult, false);
  assertEquals(persistedFinalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    selectedStyle: "tease",
    variants: {
      tease: {
        sourceIndices: [1],
        questionCount: 0,
      },
    },
  });

  const phase0 = logs.find((entry) =>
    entry[0] === "[analyze-chat] stream_phase0_observability"
  );
  assert(phase0, "expected Phase 0 telemetry log");
  const metadata = phase0[1] as Record<string, unknown>;
  assertEquals(metadata.decisionSchema, "unknown");
  assertEquals(metadata.decisionId, "unknown");
  const logged = JSON.stringify(metadata);
  assertFalse(logged.includes("ad_done_injected"));
  assertFalse(logged.includes("DONE_INJECTED_SOURCE_SECRET"));
});

Deno.test("Phase 0 handler calibrates linkage after a safety fallback replaces delivered replies", async () => {
  const calls: string[] = [];
  let persistedFinalResult: Record<string, unknown> | undefined;
  const deps = makeDeps({
    calls,
    modelChunks: [
      line({
        type: "analysis.inventory",
        balls: [{
          id: "b_1",
          sourceIndex: 1,
          sourceMessage: "原始球",
          disposition: "接",
        }],
      }),
      line({
        type: "analysis.decision",
        schemaVersion: 2,
        decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
        selectedStyle: "extend",
        action: "connect",
        messageDecision: "send",
        replyMode: "variants",
        selectedBallIds: ["b_1"],
        nextStepBody: "先順著聊。",
        doThis: "接住原本的話題。",
      }),
      line({
        type: "analysis.recommendation",
        selectedStyle: "extend",
        message: "你今天過得怎麼樣？",
        reason: "先接住近況。",
        quotedContext: "原始球",
      }),
      line({
        type: "analysis.reply_option",
        style: "extend",
        action: "connect",
        selectedBallIds: ["b_1"],
        sourceBallIds: ["b_1"],
        questionCount: 99,
        segments: [{
          sourceIndex: 1,
          sourceMessage: "原始球",
          reply: "不要放棄一直跟著她。",
        }],
      }),
      line({
        type: "analysis.reply_option",
        style: "tease",
        action: "connect",
        selectedBallIds: ["b_1"],
        sourceBallIds: ["b_1"],
        questionCount: 99,
        segments: [{
          sourceIndex: 1,
          sourceMessage: "原始球",
          reply: "先輕鬆回一句。",
        }],
      }),
      line({ type: "analysis.done", finalResult: {} }),
    ],
  });
  const originalMarkDone = deps.store.markDone;
  deps.store.markDone = (args) => {
    persistedFinalResult = args.finalResult;
    return originalMarkDone(args);
  };

  await runWithStubbedFetch(deps);

  assert(persistedFinalResult, "expected a persisted final result");
  assertEquals(persistedFinalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
    selectedStyle: "extend",
    selectedBallIds: ["b_1"],
    inventorySourceIndices: [1],
    variants: {
      extend: { questionCount: 1 },
      tease: { questionCount: 0 },
    },
  });
  const telemetry = buildPhase0ObservabilityTelemetry({
    finalResult: persistedFinalResult,
    user: "user-summary",
    analysisRunId: "run-1",
  });
  assertEquals(telemetry.questionCounts, {
    status: "observed",
    byStyle: { extend: 1, tease: 0 },
    maxQuestionCount: 1,
  });
  assertEquals(telemetry.meaningfulBallCoverage, { status: "unknown" });
  assertEquals(telemetry.actionMismatch, "unknown");
  assertEquals(telemetry.ballMismatch, "unknown");
});

Deno.test("Phase 0 handler calibrates linkage to source-repaired delivered segments", async () => {
  const calls: string[] = [];
  let persistedFinalResult: Record<string, unknown> | undefined;
  const deps = makeDeps({
    calls,
    modelChunks: [
      line({
        type: "analysis.inventory",
        balls: [{
          id: "b_1",
          sourceIndex: 1,
          sourceMessage: "可以修正的來源球",
          disposition: "接",
        }],
      }),
      line({
        type: "analysis.decision",
        schemaVersion: 2,
        decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
        selectedStyle: "extend",
        action: "connect",
        messageDecision: "send",
        replyMode: "variants",
        selectedBallIds: ["b_1"],
        nextStepBody: "先順著聊。",
        doThis: "接住原本的話題。",
      }),
      line({
        type: "analysis.recommendation",
        selectedStyle: "extend",
        message: "你今天過得怎麼樣？",
        reason: "先接住近況。",
        quotedContext: "可以修正的來源球",
      }),
      line({
        type: "analysis.reply_option",
        style: "extend",
        action: "connect",
        selectedBallIds: ["b_1"],
        sourceBallIds: ["raw_wrong_id"],
        questionCount: 99,
        segments: [{
          sourceIndex: 99,
          sourceMessage: "可以修正的來源球",
          reply: "這句聽起來很有畫面？",
        }],
      }),
      line({
        type: "analysis.reply_option",
        style: "tease",
        action: "connect",
        selectedBallIds: ["b_1"],
        sourceBallIds: ["raw_wrong_id"],
        questionCount: 99,
        segments: [{
          sourceIndex: 1,
          sourceMessage: "可以修正的來源球",
          reply: "先輕輕回一句。",
        }],
      }),
      line({ type: "analysis.done", finalResult: {} }),
    ],
  });
  deps.messages = [{ isFromMe: false, content: "可以修正的來源球" }];
  deps.hashInput.messages = [{ isFromMe: false, content: "可以修正的來源球" }];
  const originalMarkDone = deps.store.markDone;
  deps.store.markDone = (args) => {
    persistedFinalResult = args.finalResult;
    return originalMarkDone(args);
  };

  await runWithStubbedFetch(deps);

  assert(persistedFinalResult, "expected a persisted final result");
  const finalRecommendation = persistedFinalResult
    .finalRecommendation as Record<
      string,
      unknown
    >;
  assertEquals(finalRecommendation.replySegments, [{
    label: "",
    sourceIndex: 1,
    sourceMessage: "可以修正的來源球",
    reply: "這句聽起來很有畫面？",
    reason: "",
  }]);
  assertEquals(persistedFinalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
    selectedStyle: "extend",
    selectedBallIds: ["b_1"],
    inventorySourceIndices: [1],
    variants: {
      extend: {
        sourceIndices: [1],
        sourceBallIds: ["b_1"],
        action: "connect",
        selectedBallIds: ["b_1"],
        questionCount: 1,
      },
      tease: {
        sourceIndices: [1],
        sourceBallIds: ["b_1"],
        action: "connect",
        selectedBallIds: ["b_1"],
        questionCount: 0,
      },
    },
  });
  const telemetry = buildPhase0ObservabilityTelemetry({
    finalResult: persistedFinalResult,
    user: "user-summary",
    analysisRunId: "run-1",
  });
  assertEquals(telemetry.fiveCardSourceDivergence, {
    status: "observed",
    baselineStyle: "extend",
    sourceBallIdEvidence: "complete",
    sourceMessageEvidence: "complete",
    divergentStyles: [],
    allMatch: true,
  });
  const serialized = JSON.stringify(telemetry);
  assertFalse(serialized.includes("可以修正的來源球"));
  assertFalse(serialized.includes("這句聽起來很有畫面？"));
  assertFalse(serialized.includes("raw_wrong_id"));
  assertFalse(serialized.includes("b_1"));
});

Deno.test("stream Free provider request uses 4500 output-token cap", async () => {
  const calls: string[] = [];
  const capturedMaxTokens: number[] = [];
  const capturedSystems: string[] = [];

  await runWithStubbedFetch(makeDeps({
    calls,
    capturedMaxTokens,
    capturedSystems,
  }));

  assertEquals(capturedMaxTokens, [4500]);
  assertEquals(
    capturedSystems,
    [buildAnalyzeStreamSystemPrompt(["extend", "tease"])],
  );
});

Deno.test("stream paid provider request keeps 6000 output-token cap", async () => {
  const calls: string[] = [];
  const capturedMaxTokens: number[] = [];
  const capturedSystems: string[] = [];

  await runWithStubbedFetch(makeDeps({
    calls,
    capturedMaxTokens,
    capturedSystems,
    effectiveTier: "essential",
    allowedFeatures: ["extend", "resonate", "tease", "humor", "coldRead"],
  }));

  assertEquals(capturedMaxTokens, [6000]);
  assertEquals(
    capturedSystems,
    [
      buildAnalyzeStreamSystemPrompt([
        "extend",
        "resonate",
        "tease",
        "humor",
        "coldRead",
      ]),
    ],
  );
});

Deno.test("stream provider 失敗：markFailed，絕不 chargeRun", async () => {
  const calls: string[] = [];
  await runWithStubbedFetch(makeDeps({
    calls,
    modelError: new AiStreamingServiceError("boom", "UPSTREAM_ERROR", true),
  }));

  assertEquals(calls[0], "createPendingRun");
  assertEquals(calls[1], "callModel");
  assert(calls.includes("markFailed"));
  assert(!calls.includes("chargeRun"), "provider 失敗不得扣費");
  assert(!calls.includes("markDone"));
});

Deno.test("stream retry：getRun → reserveRetry，沿用 precharged recommendation", async () => {
  const calls: string[] = [];
  let persistedFinalResult: Record<string, unknown> | undefined;
  const retryableRun = makeRun({
    status: "failed",
    retry_count: 1,
    charged_at: new Date().toISOString(),
    recommendation_json: {
      selectedStyle: "tease",
      message: "先回她這句試試看。",
      reason: "接住話題再輕輕推進。",
      quotedContext: "嗨",
      warnings: [],
      raw: {},
      analysisDecisionV2: {
        schemaVersion: 2,
        decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
        action: "connect",
        messageDecision: "send",
        replyMode: "variants",
        selectedBallIds: ["b_1"],
      },
      analysisInventory: {
        type: "analysis.inventory",
        balls: [{ sourceIndex: 1, disposition: "接" }],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
        selectedStyle: "tease",
        selectedBallIds: ["b_1"],
        inventorySourceIndices: [1],
      },
    },
  });
  const deps = makeDeps({
    calls,
    analysisRunId: "run-1",
    getRunResult: retryableRun,
  });
  const originalMarkDone = deps.store.markDone;
  deps.store.markDone = (args) => {
    persistedFinalResult = args.finalResult;
    return originalMarkDone(args);
  };
  await runWithStubbedFetch(deps);

  assertEquals(calls[0], "getRun");
  assertEquals(calls[1], "reserveRetry");
  assertEquals(calls[2], "callModel");
  assert(!calls.includes("createPendingRun"), "retry 不建新 run");
  assert(persistedFinalResult, "retry must persist a final result");
  assertEquals(persistedFinalResult.analysisDecisionV2, {
    schemaVersion: 2,
    decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
    action: "connect",
    messageDecision: "send",
    replyMode: "variants",
    selectedBallIds: ["b_1"],
  });
  assertEquals(persistedFinalResult.analysisInventory, {
    type: "analysis.inventory",
    balls: [{ sourceIndex: 1, disposition: "接" }],
  });
  assertEquals(persistedFinalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    decisionId: "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV",
    selectedStyle: "tease",
    selectedBallIds: ["b_1"],
    inventorySourceIndices: [1],
    variants: {
      extend: { questionCount: 0 },
      tease: { questionCount: 0 },
    },
  });
});

Deno.test("stream resume：done run 直接回放 stored result，不重打模型", async () => {
  const calls: string[] = [];
  const doneRun = makeRun({
    status: "done",
    final_result_json: { finalRecommendation: { content: "回放結果" } },
  });
  const { text } = await runWithStubbedFetch(makeDeps({
    calls,
    analysisRunId: "run-1",
    getRunResult: doneRun,
  }));

  assertEquals(calls[0], "getRun");
  assert(!calls.includes("reserveRetry"), "done run 不佔 retry 名額");
  assert(!calls.includes("callModel"), "resume 不重打模型");
  assert(!calls.includes("chargeRun"), "resume 不重複扣費");
  assert(text.includes("回放結果"));
});
