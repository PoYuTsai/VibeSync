// 唯一 AnalyzeStreamHandler 的 fake-port 行為測試：
// create／retry／resume／charge／markDone／markFailed 的呼叫順序。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AnalyzeStreamDeps,
  handleAnalyzeStream,
} from "./analyze_stream_handler.ts";
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
    effectiveTier: "free",
    accountIsTest: false,
    allowedFeatures: ["extend", "tease"],
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
    callModel: () => {
      calls.push("callModel");
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
    },
  });
  await runWithStubbedFetch(makeDeps({
    calls,
    analysisRunId: "run-1",
    getRunResult: retryableRun,
  }));

  assertEquals(calls[0], "getRun");
  assertEquals(calls[1], "reserveRetry");
  assertEquals(calls[2], "callModel");
  assert(!calls.includes("createPendingRun"), "retry 不建新 run");
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
