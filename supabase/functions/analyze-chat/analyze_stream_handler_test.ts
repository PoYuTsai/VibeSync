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
import { DIVERGENCE_PLAN_EXTRA_TOKENS } from "./stream_budget.ts";
import { VALID_PLAN } from "./divergence_contract_test.ts";
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
  // Phase 3d critic shadow 注入（預設關閉）。
  criticShadow?: AnalyzeStreamDeps["criticShadow"];
  waitUntil?: AnalyzeStreamDeps["waitUntil"];
  callCritic?: AnalyzeStreamDeps["callCritic"];
}): AnalyzeStreamDeps {
  const { calls } = options;
  return {
    ...(options.criticShadow ? { criticShadow: options.criticShadow } : {}),
    ...(options.waitUntil ? { waitUntil: options.waitUntil } : {}),
    ...(options.callCritic ? { callCritic: options.callCritic } : {}),
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
        questionCount: 1,
      },
      tease: {
        sourceIndices: [1],
        sourceBallIds: ["b_1"],
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

Deno.test("stream v2 request injects selected situation knowledge; v1 stays untouched", async () => {
  const v2Systems: string[] = [];
  await runWithStubbedFetch({
    ...makeDeps({ calls: [], capturedSystems: v2Systems }),
    noSendDecisions: true,
  });
  assertEquals(v2Systems.length, 1);
  assert(v2Systems[0].includes("## Situation Knowledge"));
  assert(v2Systems[0].includes("1a. Message decision gate"));

  const v1Systems: string[] = [];
  await runWithStubbedFetch(
    makeDeps({ calls: [], capturedSystems: v1Systems }),
  );
  assertEquals(v1Systems, [
    buildAnalyzeStreamSystemPrompt(["extend", "tease"]),
  ]);
});

Deno.test("stream v2 request reserves divergence-plan tokens and asks for the plan; v1 budget unchanged", async () => {
  const capturedMaxTokens: number[] = [];
  const capturedSystems: string[] = [];
  await runWithStubbedFetch({
    ...makeDeps({ calls: [], capturedMaxTokens, capturedSystems }),
    noSendDecisions: true,
  });
  assertEquals(capturedMaxTokens, [4500 + DIVERGENCE_PLAN_EXTRA_TOKENS]);
  assert(capturedSystems[0].includes("`analysis.divergence_plan`"));
});

Deno.test("stream_knowledge_selected is logged only for v2 and carries ids/signals, never message text", async () => {
  const v2Logs = await withCapturedConsoleLog(async () => {
    await runWithStubbedFetch({
      ...makeDeps({ calls: [] }),
      noSendDecisions: true,
      messages: [{ isFromMe: false, content: "MESSAGE_SECRET 這週沒空耶" }],
    });
  });
  const selected = v2Logs.find((entry) =>
    entry[0] === "[analyze-chat] stream_knowledge_selected"
  );
  assert(selected, "expected stream_knowledge_selected log for v2");
  const metadata = selected[1] as Record<string, unknown>;
  assertEquals(
    Object.keys(metadata).sort(),
    ["analysisRunId", "knowledgeAtomIds", "knowledgeSignals", "user"],
  );
  assert((metadata.knowledgeAtomIds as string[]).length > 0);
  assert((metadata.knowledgeSignals as string[]).includes("rejection"));
  assertFalse(JSON.stringify(metadata).includes("MESSAGE_SECRET"));

  const v1Logs = await withCapturedConsoleLog(async () => {
    await runWithStubbedFetch(makeDeps({ calls: [] }));
  });
  assertFalse(
    v1Logs.some((entry) =>
      entry[0] === "[analyze-chat] stream_knowledge_selected"
    ),
  );
});

Deno.test("divergence plan is persisted and measured but never reaches the client, fresh or resumed", async () => {
  let persistedFinalResult: Record<string, unknown> | undefined;
  const deps = {
    ...makeDeps({
      calls: [],
      modelChunks: [
        line({
          type: "analysis.decision",
          messageDecision: "send",
          selectedStyle: "tease",
          nextStepBody: "接住",
          doThis: "先回",
        }),
        line(VALID_PLAN),
        line({
          type: "analysis.recommendation",
          selectedStyle: "tease",
          message: "先回她這句試試看。",
          reason: "接住話題再輕輕推進。",
          quotedContext: "嗨",
        }),
        line({
          type: "analysis.reply_option",
          style: "tease",
          reason: "r",
          // 走 production 的 segments 形狀：calibrate 只在送出的段落來源
          // 序列對得上 raw option 時才保留 metadata（含 Phase 2b 歸因）。
          segments: [
            {
              sourceIndex: 1,
              sourceMessage: "嗨",
              reply: "先回她這句試試看。",
              reason: "r",
            },
          ],
          // Phase 2b：option 自帶合法歸因。
          selectedBranchIds: ["br_2"],
          rhetoricalMove: "playful_contrast",
          styleIntensity: 2,
        }),
        line({
          type: "analysis.reply_option",
          style: "extend",
          reason: "r",
          segments: [
            {
              sourceIndex: 1,
              sourceMessage: "嗨",
              reply: "延伸一下。",
              reason: "r",
            },
          ],
        }),
        line({ type: "analysis.done", finalResult: {} }),
      ],
    }),
    noSendDecisions: true,
  };
  const originalMarkDone = deps.store.markDone;
  deps.store.markDone = (args) => {
    persistedFinalResult = args.finalResult;
    return originalMarkDone(args);
  };
  const logs = await withCapturedConsoleLog(async () => {
    const { text } = await runWithStubbedFetch(deps);
    assert(text.includes('"type":"analysis.done"'));
    assertFalse(text.includes("analysisDivergencePlan"));
    assertFalse(text.includes(VALID_PLAN.threadFrame));
    // 歸因 id／enum 跟其他 option 證據一樣可到 client；計畫本文不行。
    assertFalse(text.includes(VALID_PLAN.branchPool[0].idea));
  });
  assert(persistedFinalResult, "expected a persisted final result");
  const persistedPlan = persistedFinalResult
    .analysisDivergencePlan as Record<string, unknown>;
  assertEquals(persistedPlan.threadFrame, VALID_PLAN.threadFrame);
  const phase0 = logs.find((entry) =>
    entry[0] === "[analyze-chat] stream_phase0_observability"
  );
  assert(phase0, "expected Phase 0 telemetry log");
  const divergence = (phase0[1] as Record<string, unknown>)
    .divergencePlan as Record<string, unknown>;
  assertEquals(divergence.status, "observed");
  assertEquals(divergence.branchCount, 2);
  assertFalse(JSON.stringify(phase0[1]).includes(VALID_PLAN.threadFrame));
  // Phase 2b：歸因要活過 markDone 的 calibrate（用送出的回覆重建 variants）。
  // tease 自帶 br_2；extend 沒帶 → 計畫 styleBranchIds 指定的 br_1。
  assertEquals(divergence.attribution, {
    status: "observed",
    styleCount: 2,
    attributedCount: 2,
    unresolvedCount: 0,
    bySource: { option: 1, plan: 1, anchor: 0, unresolved: 0 },
    distinctBranchCount: 2,
    rhetoricalMoves: { playful_contrast: 1 },
    styleIntensity: { "2": 1 },
    invalidCount: 0,
  });

  // resume：DB 裡的 finalResult 帶計畫，回放給 client 前一樣剝掉。
  const doneRun = makeRun({
    status: "done",
    final_result_json: {
      finalRecommendation: { content: "回放結果" },
      analysisDivergencePlan: VALID_PLAN,
    },
  });
  const { text: resumed } = await runWithStubbedFetch({
    ...makeDeps({
      calls: [],
      analysisRunId: "00000000-0000-4000-8000-000000000123",
      getRunResult: doneRun,
    }),
    noSendDecisions: true,
  });
  assert(resumed.includes("回放結果"));
  assertFalse(resumed.includes("analysisDivergencePlan"));
  assertFalse(resumed.includes(VALID_PLAN.threadFrame));
});

Deno.test("an injected analysisDivergencePlan never survives when the server captured no plan", async () => {
  let persistedFinalResult: Record<string, unknown> | undefined;
  const deps = {
    ...makeDeps({
      calls: [],
      modelChunks: [
        line({
          type: "analysis.decision",
          messageDecision: "send",
          selectedStyle: "tease",
          nextStepBody: "接住",
          doThis: "先回",
        }),
        line({ ...VALID_PLAN, branchPool: [] }),
        line({
          type: "analysis.recommendation",
          selectedStyle: "tease",
          message: "先回她這句試試看。",
          reason: "接住話題再輕輕推進。",
          quotedContext: "嗨",
        }),
        line({
          type: "analysis.reply_option",
          style: "tease",
          message: "先回她這句試試看。",
          reason: "r",
        }),
        line({
          type: "analysis.reply_option",
          style: "extend",
          message: "延伸一下。",
          reason: "r",
        }),
        line({
          type: "analysis.done",
          finalResult: { analysisDivergencePlan: VALID_PLAN },
        }),
      ],
    }),
    noSendDecisions: true,
  };
  const originalMarkDone = deps.store.markDone;
  deps.store.markDone = (args) => {
    persistedFinalResult = args.finalResult;
    return originalMarkDone(args);
  };
  const { text } = await runWithStubbedFetch(deps);
  assert(text.includes('"type":"analysis.done"'));
  assertFalse(text.includes("analysisDivergencePlan"));
  assert(persistedFinalResult, "expected a persisted final result");
  assertEquals("analysisDivergencePlan" in persistedFinalResult, false);
});

/// Phase 3d：v2 send 的六行（盤點、決策、瘦卡、兩張 option、done）。
function v2SendChunks(): string[] {
  return [
    line({
      type: "analysis.inventory",
      balls: [{
        id: "b_1",
        sourceIndex: 1,
        sourceMessage: "SOURCE_SECRET",
        disposition: "接",
      }],
    }),
    line({
      type: "analysis.decision",
      schemaVersion: 2,
      selectedStyle: "extend",
      action: "connect",
      messageDecision: "send",
      replyMode: "variants",
      selectedBallIds: ["b_1"],
      betaRiskFlags: ["question_only"],
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
      segments: [{
        sourceIndex: 1,
        sourceMessage: "SOURCE_SECRET",
        reply: "不急著問，也先接住。",
        reason: "REASON_SECRET",
      }],
    }),
    line({ type: "analysis.done", finalResult: {} }),
  ];
}

Deno.test("Phase 3d critic shadow：done 之後排進背景，只審選中卡，telemetry 不帶文字", async () => {
  const scheduled: Promise<void>[] = [];
  const criticCalls: { model: string; prompt: string }[] = [];
  const logs = await withCapturedConsoleLog(async () => {
    const { text } = await runWithStubbedFetch(makeDeps({
      calls: [],
      modelChunks: v2SendChunks(),
      criticShadow: {
        enabled: true,
        model: "critic-model",
        timeoutMs: 500,
        trigger: "risk",
      },
      waitUntil: (task) => {
        scheduled.push(task);
      },
      callCritic: (args) => {
        criticCalls.push({ model: args.model, prompt: args.prompt });
        return Promise.resolve({
          content: [{
            type: "text",
            text: '{"verdict":"rewrite","violations":["question_density"]}',
          }],
          usage: { input_tokens: 700, output_tokens: 20 },
        });
      },
    }));
    // 背景 task 不擋回應：client 已拿到完整 done，task 交給 waitUntil。
    assert(text.includes('"analysis.done"'));
    assertEquals(scheduled.length, 1);
    await Promise.all(scheduled);
  });

  assertEquals(criticCalls.length, 1);
  assertEquals(criticCalls[0].model, "critic-model");
  assert(criticCalls[0].prompt.includes("gender_heuristic"));
  assert(criticCalls[0].prompt.includes("REPLY_SECRET?"));
  assert(!criticCalls[0].prompt.includes("不急著問"), "只審選中卡");

  const critic = logs.find((entry) =>
    entry[0] === "[analyze-chat] stream_semantic_critic"
  );
  assert(critic, "expected critic shadow telemetry log");
  const metadata = critic[1] as Record<string, unknown>;
  assertEquals(metadata.status, "ok");
  assertEquals(metadata.verdict, "rewrite");
  assertEquals(metadata.violations, ["question_density"]);
  assertEquals(metadata.model, "critic-model");
  assert((metadata.trigger as string[]).includes("beta:question_only"));
  assertEquals(metadata.inputTokens, 700);
  assertEquals(typeof metadata.analysisRunId, "string");
  assertEquals(typeof metadata.user, "string");
  const serialized = JSON.stringify(metadata);
  assert(!serialized.includes("SECRET"));
});

Deno.test("Phase 3d critic shadow：預設關閉時不排程也不呼叫", async () => {
  const scheduled: Promise<void>[] = [];
  let criticCalls = 0;
  await withCapturedConsoleLog(async () => {
    await runWithStubbedFetch(makeDeps({
      calls: [],
      modelChunks: v2SendChunks(),
      waitUntil: (task) => {
        scheduled.push(task);
      },
      callCritic: () => {
        criticCalls += 1;
        return Promise.resolve({});
      },
    }));
  });
  assertEquals(scheduled.length, 0);
  assertEquals(criticCalls, 0);
});
