// 「資料不夠」（need_context）不扣額度：每人每天前 3 次免扣，長分析帶照扣，
// do_not_send／acknowledge_and_stop 照扣，retry／resume 不重扣。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AnalyzeStreamDeps,
  handleAnalyzeStream,
} from "./analyze_stream_handler.ts";
import { MODEL_RATE_LIMITS } from "../_shared/model_rate_limit.ts";
import { validateNoSendDecisionEvent } from "./no_send_decision.ts";
import {
  type AnalysisStreamRun,
  type AnalysisStreamRunDriver,
  AnalysisStreamRunStore,
} from "./stream_run_store.ts";

const USER = "00000000-0000-4000-8000-000000000001";
// 用戶傳過兩句以上、她只回「哈哈」：三種不回決策都在選單裡。
const MESSAGES = [
  { isFromMe: true, content: "我昨天去看展，裡面有一區超像你之前說的那種風格" },
  { isFromMe: true, content: "妳最近有去哪裡走走嗎" },
  { isFromMe: false, content: "哈哈" },
];
const DECISIONS = {
  need_context: {
    type: "analysis.decision",
    messageDecision: "need_context",
    action: "pause",
    reason: "只看得到她一句哈哈，不知道你們前面聊到哪",
    stopCondition: "補上前面幾句再分析",
  },
  do_not_send: {
    type: "analysis.decision",
    messageDecision: "do_not_send",
    action: "pause",
    reason: "她只回哈哈，沒有新內容",
    stopCondition: "等她主動給新話題",
  },
  acknowledge_and_stop: {
    type: "analysis.decision",
    messageDecision: "acknowledge_and_stop",
    action: "stop",
    reason: "她在收尾",
    stopCondition: "等她下次開話題",
    closingMessage: "好喔，那先這樣～",
  },
} as const;
type DecisionKind = keyof typeof DECISIONS;

const LIMITS = { monthlyLimit: 30, dailyLimit: 15, subMonthly: 5, subDaily: 2 };

/// increment_model_usage 的記憶體版：同一 (user, scope) 當天超過 p_daily_limit 就 RAISE。
function fakeCounter(options: { broken?: boolean } = {}) {
  const counts = new Map<string, number>();
  const calls: Record<string, unknown>[] = [];
  return {
    calls,
    client: {
      rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, ...args });
        if (options.broken) {
          return Promise.resolve({ error: { message: "connection refused" } });
        }
        const key = `${args.p_user_id}:${args.p_scope}`;
        const next = (counts.get(key) ?? 0) + 1;
        if (next > (args.p_daily_limit as number)) {
          return Promise.resolve({
            error: { message: "MODEL_RATE_LIMITED_DAILY" },
          });
        }
        counts.set(key, next);
        return Promise.resolve({ error: null });
      },
    },
  };
}

function makeRun(
  overrides: Partial<AnalysisStreamRun> = {},
): AnalysisStreamRun {
  return {
    id: "run-1",
    user_id: USER,
    conversation_hash: "h",
    status: "pending",
    selected_style: null,
    decision_kind: null,
    recommendation_json: null,
    final_result_json: null,
    charged_at: null,
    last_error_code: null,
    retry_count: 0,
    request_context: null,
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 3600_000).toISOString(),
    ...overrides,
  };
}

function chargedNeedContextRun(
  overrides: Partial<AnalysisStreamRun>,
): AnalysisStreamRun {
  const validated = validateNoSendDecisionEvent(DECISIONS.need_context);
  assert(validated.ok);
  return makeRun({
    charged_at: new Date().toISOString(),
    decision_kind: "need_context",
    recommendation_json: {
      ...validated.payload,
      raw: DECISIONS.need_context,
    } as unknown as Record<string, unknown>,
    ...overrides,
  });
}

async function* chunks(
  values: string[],
  breakAfter = Infinity,
): AsyncIterable<string> {
  for (const [i, value] of values.entries()) {
    if (i >= breakAfter) throw new Error("upstream connection reset");
    yield value;
  }
}

async function analyze(options: {
  decision: DecisionKind;
  counter: ReturnType<typeof fakeCounter>;
  eligible?: boolean;
  shouldChargeQuota?: boolean;
  analysisRunId?: string;
  existingRun?: AnalysisStreamRun;
  /// 真的 AnalysisStreamRunStore（記憶體 driver）；省略＝只記扣費參數的假 store。
  runStore?: AnalysisStreamRunStore;
  /// 模型吐出決策後連線就斷（扣費已發生，沒有 analysis.done）。
  streamBreaksAfterDecision?: boolean;
}) {
  const charges: { chargeQuota: boolean; messageCount: number }[] = [];
  const done: Record<string, unknown>[] = [];
  const aiLogs: Record<string, unknown>[] = [];
  const runStore = options.runStore;
  const deps: AnalyzeStreamDeps = {
    store: runStore
      ? {
        getRun: (args) => runStore.getRun(args),
        reserveRetry: (args) => runStore.reserveRetry(args),
        createPendingRun: (args) => runStore.createPendingRun(args),
        chargeRun: (args) => runStore.chargeRun(args),
        markDone: async (args) => {
          done.push(args.finalResult);
          return await runStore.markDone(args);
        },
        markFailed: (args) => runStore.markFailed(args),
      }
      : {
        getRun: () => Promise.resolve(options.existingRun ?? makeRun()),
        reserveRetry: () => Promise.resolve(options.existingRun ?? makeRun()),
        createPendingRun: () => Promise.resolve(makeRun()),
        chargeRun: (args) => {
          charges.push({
            chargeQuota: args.chargeQuota,
            messageCount: args.messageCount,
          });
          return Promise.resolve();
        },
        markDone: (args) => {
          done.push(args.finalResult);
          return Promise.resolve();
        },
        markFailed: () => Promise.resolve(makeRun({ status: "failed" })),
      },
    userId: USER,
    analysisRunId: options.analysisRunId ?? null,
    requestType: "analyze",
    analyzeMode: "normal",
    expectedTier: "free",
    effectiveTier: "free",
    accountIsTest: false,
    allowedFeatures: ["extend", "tease"],
    noSendDecisions: true,
    needContextWaiverEligible: options.eligible ?? true,
    rateLimitClient: options.counter.client,
    quotaUsage: {
      shouldChargeQuota: options.shouldChargeQuota ?? true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 1,
      estimatedMessageCount: 1,
    },
    monthlyLimit: LIMITS.monthlyLimit,
    dailyLimit: LIMITS.dailyLimit,
    subMonthlyUsed: LIMITS.subMonthly,
    subDailyUsed: LIMITS.subDaily,
    selectedModel: "claude-sonnet-5",
    userMessageContent: "分析這段對話",
    requestObservability: {},
    messages: MESSAGES,
    hashInput: {
      messages: MESSAGES,
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
    callModel: () =>
      Promise.resolve({
        model: "claude-sonnet-5",
        usage: {
          inputTokens: 10,
          outputTokens: 5,
          cacheCreationTokens: 0,
          cacheReadTokens: 0,
        },
        textStream: chunks(
          [
            DECISIONS[options.decision],
            {
              type: "analysis.metrics",
              enthusiasm: { score: 30, level: "cool" },
            },
            { type: "analysis.done", finalResult: { strategy: "先停一下" } },
          ].map((event) => `${JSON.stringify(event)}\n`),
          options.streamBreaksAfterDecision ? 1 : undefined,
        ),
        // deno-lint-ignore no-explicit-any
      } as any),
  };

  const originalFetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    if (String(input).includes("/rest/v1/ai_logs") && init?.body) {
      aiLogs.push(JSON.parse(String(init.body)));
    }
    return Promise.resolve(
      new Response("{}", {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  };
  try {
    const response = await handleAnalyzeStream(deps);
    const text = await response.text();
    return { charges, done, aiLogs, text };
  } finally {
    globalThis.fetch = originalFetch;
  }
}

function sections(result: Awaited<ReturnType<typeof analyze>>) {
  assertEquals(result.done.length, 1, result.text);
  const finalResult = result.done[0];
  return {
    usage: finalResult.usage as Record<string, unknown>,
    telemetry: finalResult.telemetry as Record<string, unknown>,
    responseBody: result.aiLogs.at(-1)?.response_body as Record<
      string,
      unknown
    >,
  };
}

function assertWaived(result: Awaited<ReturnType<typeof analyze>>) {
  assertEquals(result.charges, [{ chargeQuota: false, messageCount: 0 }]);
  const { usage, telemetry, responseBody } = sections(result);
  assertEquals(usage.messagesUsed, 0);
  assertEquals(
    usage.monthlyRemaining,
    LIMITS.monthlyLimit - LIMITS.subMonthly,
  );
  assertEquals(usage.dailyRemaining, LIMITS.dailyLimit - LIMITS.subDaily);
  assertEquals(usage.shouldChargeQuota, false);
  assertEquals(usage.quotaWaivedReason, "need_context_waived");
  assertEquals(telemetry.shouldChargeQuota, false);
  assertEquals(telemetry.chargedMessageCount, 0);
  assertEquals(telemetry.quotaWaivedReason, "need_context_waived");
  assertEquals(responseBody.chargedQuota, false);
  assertEquals(responseBody.quotaWaivedReason, "need_context_waived");
}

function assertCharged(result: Awaited<ReturnType<typeof analyze>>) {
  assertEquals(result.charges, [{ chargeQuota: true, messageCount: 1 }]);
  const { usage, telemetry, responseBody } = sections(result);
  assertEquals(usage.messagesUsed, 1);
  assertEquals(
    usage.monthlyRemaining,
    LIMITS.monthlyLimit - LIMITS.subMonthly - 1,
  );
  assertEquals(usage.dailyRemaining, LIMITS.dailyLimit - LIMITS.subDaily - 1);
  assertEquals(usage.shouldChargeQuota, true);
  assertEquals(telemetry.shouldChargeQuota, true);
  assertEquals(telemetry.chargedMessageCount, 1);
  assertEquals(responseBody.chargedQuota, true);
  for (const record of [usage, telemetry, responseBody]) {
    assertFalse("quotaWaivedReason" in record);
  }
}

Deno.test("need_context waiver: a short need_context run is not charged and usage stays put", async () => {
  const counter = fakeCounter();
  const result = await analyze({ decision: "need_context", counter });
  assert(result.text.includes('"messageDecision":"need_context"'));
  assertWaived(result);
  assertEquals(counter.calls, [{
    fn: "increment_model_usage",
    p_user_id: USER,
    p_scope: "need_context_waiver",
    p_minute_limit: 6,
    p_daily_limit: 3,
  }]);
});

Deno.test("need_context waiver: the minute window can never refuse the first waivers of a new UTC day", () => {
  // increment_model_usage 先判分鐘窗，且分鐘窗跨 UTC 午夜不重置：昨天
  // 23:59 用掉 3 次、今天 00:00 再來，分鐘計數仍是 3。上限至少 2×perDay，
  // 今天的前 3 次才一定免扣。
  const { perMinute, perDay } = MODEL_RATE_LIMITS.need_context_waiver;
  assert(perMinute >= 2 * perDay);
});

Deno.test("need_context waiver: the 4th need_context of the day is charged as today", async () => {
  const counter = fakeCounter();
  for (let i = 0; i < 3; i++) {
    assertWaived(await analyze({ decision: "need_context", counter }));
  }
  assertCharged(await analyze({ decision: "need_context", counter }));
});

Deno.test("need_context waiver: the long-analysis band is charged and never touches the counter", async () => {
  const counter = fakeCounter();
  assertCharged(
    await analyze({ decision: "need_context", counter, eligible: false }),
  );
  assertEquals(counter.calls, []);

  // 接線：資格只看計費結果，>2000 字的確認帶與舊 client 封頂都排除。
  const source = (await Deno.readTextFile(
    new URL("./analyze_chat_handler.ts", import.meta.url),
  )).replace(/\s+/g, " ");
  assert(
    source.includes(
      'needContextWaiverEligible: billing.outcome === "charge" && !billing.legacyOver2000Capped, rateLimitClient: supabase,',
    ),
  );
});

Deno.test("need_context waiver: do_not_send and acknowledge_and_stop are charged as today", async () => {
  for (const decision of ["do_not_send", "acknowledge_and_stop"] as const) {
    const counter = fakeCounter();
    const result = await analyze({ decision, counter });
    assert(result.text.includes(`"messageDecision":"${decision}"`), decision);
    assertCharged(result);
    assertEquals(counter.calls, [], decision);
  }
});

Deno.test("need_context waiver: an unavailable counter falls back to charging", async () => {
  const counter = fakeCounter({ broken: true });
  assertCharged(await analyze({ decision: "need_context", counter }));
  assertEquals(counter.calls.length, 1);
});

Deno.test("need_context waiver: a run that is not charged anyway leaves the counter alone", async () => {
  // 例：長分析確認重送（overcharge_confirmation_replayed）已經是 0 扣。
  const counter = fakeCounter();
  const result = await analyze({
    decision: "need_context",
    counter,
    shouldChargeQuota: false,
  });
  assertEquals(result.charges, [{ chargeQuota: false, messageCount: 0 }]);
  assertEquals(counter.calls, []);
  assertFalse("quotaWaivedReason" in sections(result).usage);
});

Deno.test("need_context waiver: retry and resume never charge or touch the counter", async () => {
  const counter = fakeCounter();
  const retry = await analyze({
    decision: "need_context",
    counter,
    analysisRunId: "run-1",
    existingRun: chargedNeedContextRun({ status: "failed" }),
  });
  assertEquals(retry.charges, []);
  assert(retry.text.includes('"messageDecision":"need_context"'));
  const { usage, telemetry } = sections(retry);
  assertEquals(usage.messagesUsed, 0);
  assertEquals(usage.shouldChargeQuota, false);
  assertEquals(telemetry.chargedMessageCount, 0);

  const resume = await analyze({
    decision: "need_context",
    counter,
    analysisRunId: "run-1",
    existingRun: chargedNeedContextRun({
      status: "done",
      final_result_json: { replies: {}, usage: { messagesUsed: 0 } },
    }),
  });
  assertEquals(resume.charges, []);
  assertEquals(resume.done, []);
  assert(resume.text.includes('"recovered":true'), resume.text);
  assertEquals(counter.calls, []);
});

/// analysis_stream_runs 一列的記憶體版，照 charge_stream_analysis_run_v2 與
/// reserve_stream_analysis_retry 的語義：recommendation_json 以 jsonb 原樣存、原樣讀回。
function memoryRunDriver() {
  let row = makeRun();
  const driver: AnalysisStreamRunDriver = {
    createPendingRun: () => Promise.resolve(row),
    getRun: () => Promise.resolve(row),
    reserveRetry: () => {
      row = {
        ...row,
        status: "charged",
        retry_count: row.retry_count + 1,
        last_error_code: null,
      };
      return Promise.resolve(row);
    },
    chargeRun: (input) => {
      if (row.charged_at === null) {
        row = {
          ...row,
          status: "charged",
          charged_at: new Date().toISOString(),
          recommendation_json: JSON.parse(
            JSON.stringify(input.recommendationJson),
          ),
          selected_style: input.selectedStyle,
          decision_kind: input.decisionKind ?? null,
        };
      }
      return Promise.resolve(row);
    },
    markDone: (input) => {
      row = { ...row, status: "done", final_result_json: input.finalResult };
      return Promise.resolve(row);
    },
    markFailed: (input) => {
      row = { ...row, status: "failed", last_error_code: input.code };
      return Promise.resolve(row);
    },
  };
  return { store: new AnalysisStreamRunStore(driver), row: () => row };
}

Deno.test("need_context waiver: the waived anchor survives a failed stream, so the retry still reports the waiver", async () => {
  const counter = fakeCounter();
  const db = memoryRunDriver();
  const failed = await analyze({
    decision: "need_context",
    counter,
    runStore: db.store,
    streamBreaksAfterDecision: true,
  });
  assertEquals(failed.done, []);
  assertEquals(db.row().status, "failed");
  assertEquals(
    db.row().recommendation_json?.quotaWaivedReason,
    "need_context_waived",
  );

  const retry = await analyze({
    decision: "need_context",
    counter,
    runStore: db.store,
    analysisRunId: "run-1",
  });
  assert(retry.text.includes('"messageDecision":"need_context"'), retry.text);
  const { usage, telemetry, responseBody } = sections(retry);
  assertEquals(usage.messagesUsed, 0);
  assertEquals(usage.shouldChargeQuota, false);
  assertEquals(usage.quotaWaivedReason, "need_context_waived");
  assertEquals(telemetry.chargedMessageCount, 0);
  assertEquals(telemetry.quotaWaivedReason, "need_context_waived");
  assertEquals(responseBody.quotaWaivedReason, "need_context_waived");
  // 免扣名額只在第一次扣費時佔一格，retry 不再碰計數。
  assertEquals(counter.calls.length, 1);
  // 存回的 final result 也帶標記：之後 resume 回放的就是這份。
  assertEquals(
    (db.row().final_result_json?.usage as Record<string, unknown>)
      .quotaWaivedReason,
    "need_context_waived",
  );
});

Deno.test("need_context waiver: a charged need_context anchor never gains the marker on retry", async () => {
  const counter = fakeCounter();
  for (let i = 0; i < 3; i++) {
    assertWaived(await analyze({ decision: "need_context", counter }));
  }
  const db = memoryRunDriver();
  await analyze({
    decision: "need_context",
    counter,
    runStore: db.store,
    streamBreaksAfterDecision: true,
  });
  assertFalse("quotaWaivedReason" in db.row().recommendation_json!);
  const retry = await analyze({
    decision: "need_context",
    counter,
    runStore: db.store,
    analysisRunId: "run-1",
  });
  assertFalse("quotaWaivedReason" in sections(retry).usage);
});
