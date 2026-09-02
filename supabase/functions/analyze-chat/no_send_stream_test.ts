// Phase 1b: the no-send decision path through the reframer and the stream
// handler. Every test here also pins the capability gate: with the flag off a
// style-less decision is still the v1 STREAM_MALFORMED_RECOMMENDATION.
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createStreamReframer,
  type StreamChargePayload,
  type StreamOutputEvent,
} from "./reframer.ts";
import {
  type AnalyzeStreamDeps,
  handleAnalyzeStream,
} from "./analyze_stream_handler.ts";
import {
  isNoSendChargePayload,
  validateNoSendDecisionEvent,
} from "./no_send_decision.ts";
import type { AnalysisStreamRun } from "./stream_run_store.ts";

function line(value: Record<string, unknown>): string {
  return `${JSON.stringify(value)}\n`;
}

const INVENTORY = {
  type: "analysis.inventory",
  balls: [{
    sourceIndex: 1,
    sourceMessage: "哈哈",
    disposition: "略",
    reason: "語氣詞",
  }],
};
const NO_SEND = {
  type: "analysis.decision",
  messageDecision: "do_not_send",
  action: "pause",
  reason: "她只回哈哈，沒有新內容",
  stopCondition: "等她主動給新話題",
  leaked: "RAW_MODEL_FIELD",
};
const METRICS = {
  type: "analysis.metrics",
  gameStage: { current: "premise", status: "shouldRetreat" },
  enthusiasm: { score: 18, level: "cold" },
};
const REPLY_OPTION = {
  type: "analysis.reply_option",
  style: "extend",
  reason: "r",
  stretchLevel: "within",
  segments: [{
    sourceIndex: 1,
    sourceMessage: "哈哈",
    reply: "SHOULD_BE_DROPPED",
    reason: "x",
  }],
};
const RECOMMENDATION = {
  type: "analysis.recommendation",
  selectedStyle: "extend",
  reason: "SHOULD_BE_DROPPED",
  expectedReaction: "x",
};
const DONE_WITH_DEBRIS = {
  type: "analysis.done",
  finalResult: {
    replies: { extend: "DEBRIS", tease: "DEBRIS" },
    replyOptions: { extend: { messages: ["DEBRIS"] } },
    finalRecommendation: { pick: "extend", content: "DEBRIS" },
    strategy: "先停一下",
  },
};

function run(
  chunks: Record<string, unknown>[],
  options: {
    noSendDecisions?: boolean;
    charge?: () => { charged: boolean; code?: string; message?: string };
    precharged?: StreamChargePayload;
    requiredReplyStyles?:
      readonly ("extend" | "tease" | "resonate" | "humor" | "coldRead")[];
  } = {},
) {
  const events: StreamOutputEvent[] = [];
  const charges: StreamChargePayload[] = [];
  const reframer = createStreamReframer({
    emit: (event) => {
      events.push(event);
    },
    onRecommendation: (recommendation) => {
      charges.push(recommendation);
      return options.charge?.() ?? { charged: true };
    },
    prechargedRecommendation: options.precharged,
    requiredReplyStyles: options.requiredReplyStyles ??
      ["extend", "resonate", "tease", "humor", "coldRead"],
    noSendDecisions: options.noSendDecisions,
  });
  for (const chunk of chunks) reframer.pushText(line(chunk));
  return reframer.flush().then(() => ({ events, charges }));
}

function doneOf(events: StreamOutputEvent[]): Record<string, unknown> {
  const done = events.find((event) => event.type === "analysis.done");
  assert(done, `no done in ${events.map((e) => e.type).join(",")}`);
  return done.finalResult as Record<string, unknown>;
}

Deno.test("no-send: charges the decision, drops reply events, finishes with zero cards", async () => {
  const { events, charges } = await run(
    [
      INVENTORY,
      NO_SEND,
      RECOMMENDATION,
      REPLY_OPTION,
      METRICS,
      DONE_WITH_DEBRIS,
    ],
    { noSendDecisions: true },
  );

  assertEquals(charges.length, 1);
  const charge = charges[0];
  assert(isNoSendChargePayload(charge));
  assertEquals(charge.decisionKind, "do_not_send");
  assertEquals(charge.selectedStyle, null);
  assertEquals(charge.analysisDecisionV2?.replyMode, "none");
  // Charge-time inventory snapshot rides along for Phase 0 telemetry.
  assertEquals(charge.analysisInventory, INVENTORY);

  assertEquals(
    events.map((event) => event.type),
    [
      "analysis.inventory",
      "analysis.decision",
      "analysis.metrics",
      "analysis.done",
    ],
  );
  const decision = events[1];
  assertEquals(decision.messageDecision, "do_not_send");
  assertEquals(decision.replyMode, "none");
  assertFalse("leaked" in decision);
  assertFalse(events.some((event) => event.type === "analysis.error"));

  const finalResult = doneOf(events);
  assertEquals(finalResult.replies, {});
  assertEquals(finalResult.replyOptions, {});
  assertFalse("finalRecommendation" in finalResult);
  assertEquals(finalResult.strategy, "先停一下");
  assertEquals(
    (finalResult.analysisDecisionV2 as Record<string, unknown>).messageDecision,
    "do_not_send",
  );
  assertEquals(finalResult.enthusiasm, METRICS.enthusiasm);
  assertFalse(JSON.stringify(finalResult).includes("DEBRIS"));
  assertFalse(JSON.stringify(finalResult).includes("SHOULD_BE_DROPPED"));
});

Deno.test("no-send: the flag off keeps v1 behaviour (style-less decision is malformed, nothing charged)", async () => {
  const { events, charges } = await run([
    INVENTORY,
    NO_SEND,
    METRICS,
    DONE_WITH_DEBRIS,
  ]);
  assertEquals(charges.length, 0);
  const error = events.find((event) => event.type === "analysis.error");
  assert(error);
  assertEquals(error.code, "STREAM_MALFORMED_RECOMMENDATION");
  assertFalse(events.some((event) => event.type === "analysis.done"));
});

Deno.test("no-send: a send decision under the flag still takes the v1 charge path", async () => {
  const { events, charges } = await run([
    {
      ...NO_SEND,
      messageDecision: "send",
      selectedStyle: "extend",
      nextStepBody: "接住",
      doThis: "先回",
    },
    {
      type: "analysis.recommendation",
      selectedStyle: "extend",
      message: "m",
      reason: "r",
      quotedContext: "q",
    },
    {
      type: "analysis.reply_option",
      style: "extend",
      message: "m",
      reason: "r",
    },
    {
      type: "analysis.reply_option",
      style: "tease",
      message: "t",
      reason: "r",
    },
    { type: "analysis.done", finalResult: {} },
  ], { noSendDecisions: true, requiredReplyStyles: ["extend", "tease"] });
  assertEquals(charges.length, 1);
  assertFalse(isNoSendChargePayload(charges[0]));
  assertEquals(charges[0].selectedStyle, "extend");
  assertEquals(
    Object.keys(doneOf(events).replies as Record<string, unknown>).sort(),
    ["extend", "tease"],
  );
});

Deno.test("no-send: an empty-shell decision never charges and closes the stream", async () => {
  const { events, charges } = await run(
    [{ ...NO_SEND, stopCondition: "" }, METRICS, DONE_WITH_DEBRIS],
    { noSendDecisions: true },
  );
  assertEquals(charges.length, 0);
  const error = events.find((event) => event.type === "analysis.error");
  assert(error);
  assertEquals(error.code, "STREAM_MALFORMED_RECOMMENDATION");
  assertFalse(events.some((event) => event.type === "analysis.done"));
});

Deno.test("no-send: a failed charge surfaces the error and emits no decision or done", async () => {
  const { events } = await run([NO_SEND, METRICS, DONE_WITH_DEBRIS], {
    noSendDecisions: true,
    charge: () => ({
      charged: false,
      code: "STREAM_QUOTA_EXHAUSTED",
      message: "no quota",
    }),
  });
  assertEquals(events.map((event) => event.type), ["analysis.error"]);
  assertEquals(events[0].code, "STREAM_QUOTA_EXHAUSTED");
});

Deno.test("no-send: acknowledge_and_stop is replyMode single with its closing line", async () => {
  const { events, charges } = await run([
    {
      ...NO_SEND,
      messageDecision: "acknowledge_and_stop",
      action: "stop",
      closingMessage: "好，那先這樣。",
    },
    { type: "analysis.done", finalResult: {} },
  ], { noSendDecisions: true });
  assert(isNoSendChargePayload(charges[0]));
  assertEquals(charges[0].closingMessage, "好，那先這樣。");
  const decision = events.find((event) => event.type === "analysis.decision");
  assert(decision);
  assertEquals(decision.replyMode, "single");
  assertEquals(decision.closingMessage, "好，那先這樣。");
  const finalResult = doneOf(events);
  assertEquals(finalResult.replies, {});
  assertEquals(
    (finalResult.analysisDecisionV2 as Record<string, unknown>).closingMessage,
    "好，那先這樣。",
  );
});

Deno.test("no-send: resume from a charged no-send anchor never re-charges and freezes the decision", async () => {
  const validated = validateNoSendDecisionEvent(NO_SEND);
  assert(validated.ok);
  const { events, charges } = await run([
    INVENTORY,
    // Replayed model output tries to retarget the decision and add cards.
    {
      ...NO_SEND,
      messageDecision: "send",
      selectedStyle: "tease",
      nextStepBody: "x",
      doThis: "y",
    },
    { ...NO_SEND, messageDecision: "need_context", reason: "DIFFERENT" },
    RECOMMENDATION,
    REPLY_OPTION,
    METRICS,
    DONE_WITH_DEBRIS,
  ], { noSendDecisions: true, precharged: validated.payload });

  assertEquals(charges.length, 0);
  assertFalse(events.some((event) => event.type === "analysis.error"));
  assertFalse(events.some((event) => event.type === "analysis.reply_option"));
  assertFalse(events.some((event) => event.type === "analysis.recommendation"));
  const finalResult = doneOf(events);
  const decision = finalResult.analysisDecisionV2 as Record<string, unknown>;
  assertEquals(decision.messageDecision, "do_not_send");
  assertEquals(decision.reason, NO_SEND.reason);
  assertEquals(finalResult.replies, {});
  assertFalse(JSON.stringify(finalResult).includes("DEBRIS"));
});

Deno.test("no-send: a reply_option that arrives before the decision never leaks through the pre-charge buffer", async () => {
  const { events, charges } = await run(
    [
      INVENTORY,
      REPLY_OPTION,
      NO_SEND,
      RECOMMENDATION,
      METRICS,
      DONE_WITH_DEBRIS,
    ],
    { noSendDecisions: true },
  );
  assertEquals(charges.length, 1);
  assertEquals(
    events.map((event) => event.type),
    [
      "analysis.inventory",
      "analysis.decision",
      "analysis.metrics",
      "analysis.done",
    ],
  );
  assertFalse(JSON.stringify(events).includes("SHOULD_BE_DROPPED"));
  assertEquals(doneOf(events).replies, {});
});

Deno.test("no-send: a late no-send decision after a charged send anchor is dropped, cards stay intact", async () => {
  const { events, charges } = await run([
    {
      ...NO_SEND,
      messageDecision: "send",
      selectedStyle: "extend",
      nextStepBody: "接住",
      doThis: "先回",
    },
    {
      type: "analysis.recommendation",
      selectedStyle: "extend",
      message: "m",
      reason: "r",
      quotedContext: "q",
    },
    {
      type: "analysis.reply_option",
      style: "extend",
      message: "m",
      reason: "r",
    },
    // Model changes its mind after the charge: the first anchor wins.
    NO_SEND,
    {
      type: "analysis.reply_option",
      style: "tease",
      message: "t",
      reason: "r",
    },
    { type: "analysis.done", finalResult: {} },
  ], { noSendDecisions: true, requiredReplyStyles: ["extend", "tease"] });
  assertEquals(charges.length, 1);
  assertFalse(isNoSendChargePayload(charges[0]));
  assertEquals(
    events.filter((event) => event.type === "analysis.decision").length,
    1,
  );
  assertFalse(events.some((event) => event.messageDecision === "do_not_send"));
  assertFalse(events.some((event) => event.type === "analysis.error"));
  const finalResult = doneOf(events);
  assertEquals(
    Object.keys(finalResult.replies as Record<string, unknown>).sort(),
    ["extend", "tease"],
  );
  assertFalse(
    JSON.stringify(finalResult.analysisDecisionV2 ?? {}).includes(
      "do_not_send",
    ),
  );
});

Deno.test("no-send: a thin recommendation charged first makes a later no-send decision a no-op", async () => {
  const { events, charges } = await run([
    {
      type: "analysis.recommendation",
      selectedStyle: "extend",
      reason: "r",
      expectedReaction: "x",
    },
    NO_SEND,
    {
      type: "analysis.reply_option",
      style: "extend",
      message: "m",
      reason: "r",
    },
    {
      type: "analysis.reply_option",
      style: "tease",
      message: "t",
      reason: "r",
    },
    { type: "analysis.done", finalResult: {} },
  ], { noSendDecisions: true, requiredReplyStyles: ["extend", "tease"] });
  assertEquals(charges.length, 1);
  assertEquals(charges[0].selectedStyle, "extend");
  assertFalse(events.some((event) => event.type === "analysis.error"));
  assertFalse(events.some((event) => event.messageDecision === "do_not_send"));
  assertEquals(
    Object.keys(doneOf(events).replies as Record<string, unknown>).sort(),
    ["extend", "tease"],
  );
});

Deno.test("no-send: reply-bearing client records in done debris are stripped too", async () => {
  const { events } = await run([
    NO_SEND,
    {
      type: "analysis.done",
      finalResult: {
        optimizedMessage: { original: "o", optimized: "DEBRIS", reason: "r" },
        myMessageAnalysis: {
          sentMessage: "DEBRIS",
          backupTopics: ["DEBRIS"],
          warnings: [],
        },
        finalRecommendation: { pick: "extend", content: "DEBRIS" },
        coachActionHint: {
          actionType: "lowerPressureReply",
          microMove: "先不要回",
        },
      },
    },
  ], { noSendDecisions: true });
  const finalResult = doneOf(events);
  assertFalse("optimizedMessage" in finalResult);
  assertFalse("myMessageAnalysis" in finalResult);
  assertFalse("finalRecommendation" in finalResult);
  assertFalse(JSON.stringify(finalResult).includes("DEBRIS"));
  // Coaching metadata is not a reply card and stays.
  assertEquals(
    (finalResult.coachActionHint as Record<string, unknown>).actionType,
    "lowerPressureReply",
  );
});

// ---------------------------------------------------------------------------
// Handler level: capability flag, persistence, resume.

async function* chunks(values: string[]): AsyncIterable<string> {
  for (const value of values) yield value;
}

function makeRun(overrides: Record<string, unknown> = {}): AnalysisStreamRun {
  return {
    id: "run-1",
    user_id: "00000000-0000-4000-8000-000000000001",
    conversation_hash: "h",
    status: "pending",
    retry_count: 0,
    expires_at: new Date(Date.now() + 3600_000).toISOString(),
    final_result_json: null,
    recommendation_json: null,
    last_error_code: null,
    charged_at: null,
    selected_style: null,
    decision_kind: null,
    request_context: null,
    created_at: new Date().toISOString(),
    ...overrides,
  } as AnalysisStreamRun;
}

function makeDeps(options: {
  calls: string[];
  chargeInputs: StreamChargePayload[];
  doneResults: Record<string, unknown>[];
  systems: string[];
  modelChunks: Record<string, unknown>[];
  noSendDecisions?: boolean;
  analysisRunId?: string;
  retryRun?: AnalysisStreamRun;
  /// Successive getRun results (first attach, then each poll); falls back to retryRun.
  getRunSequence?: AnalysisStreamRun[];
}): AnalyzeStreamDeps {
  return {
    store: {
      getRun: () => {
        options.calls.push("getRun");
        const next = options.getRunSequence?.shift();
        if (next) return Promise.resolve(next);
        return Promise.resolve(
          options.getRunSequence?.length === 0 && options.retryRun
            ? options.retryRun
            : options.retryRun ?? makeRun(),
        );
      },
      reserveRetry: () => {
        options.calls.push("reserveRetry");
        return Promise.resolve(options.retryRun ?? makeRun());
      },
      createPendingRun: () => {
        options.calls.push("createPendingRun");
        return Promise.resolve(makeRun());
      },
      chargeRun: (args) => {
        options.calls.push("chargeRun");
        options.chargeInputs.push(args.recommendation);
        return Promise.resolve();
      },
      markDone: (args) => {
        options.calls.push("markDone");
        options.doneResults.push(args.finalResult);
        return Promise.resolve();
      },
      markFailed: () => {
        options.calls.push("markFailed");
        return Promise.resolve(makeRun({ status: "failed" }));
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
    noSendDecisions: options.noSendDecisions,
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
    messages: [{ isFromMe: false, content: "哈哈" }],
    hashInput: {
      messages: [{ isFromMe: false, content: "哈哈" }],
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
      options.calls.push("callModel");
      options.systems.push(request.system as string);
      return Promise.resolve({
        model: "claude-sonnet-5",
        usage: {
          inputTokens: 10,
          outputTokens: 5,
          cacheCreationTokens: 0,
          cacheReadTokens: 0,
        },
        textStream: chunks(options.modelChunks.map(line)),
        // deno-lint-ignore no-explicit-any
      } as any);
    },
  };
}

async function runHandler(deps: AnalyzeStreamDeps): Promise<string> {
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
    return await response.text();
  } finally {
    globalThis.fetch = originalFetch;
  }
}

Deno.test("handler: a v2 client gets a charged, persisted no-send result with zero reply cards", async () => {
  const calls: string[] = [];
  const chargeInputs: StreamChargePayload[] = [];
  const doneResults: Record<string, unknown>[] = [];
  const systems: string[] = [];
  const text = await runHandler(makeDeps({
    calls,
    chargeInputs,
    doneResults,
    systems,
    noSendDecisions: true,
    modelChunks: [INVENTORY, NO_SEND, REPLY_OPTION, METRICS, DONE_WITH_DEBRIS],
  }));

  assert(systems[0].includes("1a. Message decision gate"));
  assertEquals(calls.filter((call) => call === "chargeRun").length, 1);
  assert(isNoSendChargePayload(chargeInputs[0]));
  assertEquals(chargeInputs[0].decisionKind, "do_not_send");
  assert(calls.indexOf("markDone") > calls.indexOf("chargeRun"));
  assertFalse(calls.includes("markFailed"));

  const stored = doneResults[0];
  assertEquals(stored.replies, {});
  assertEquals(stored.replyOptions, {});
  assertFalse("finalRecommendation" in stored);
  assertEquals(
    (stored.analysisDecisionV2 as Record<string, unknown>).messageDecision,
    "do_not_send",
  );
  // Neither post-processing nor the safety guard re-populated canned replies.
  assertFalse(JSON.stringify(stored).includes("可以聊聊"));
  assertFalse(JSON.stringify(stored).includes("DEBRIS"));
  assert(text.includes('"messageDecision":"do_not_send"'));
  assertFalse(text.includes("STREAM_INCOMPLETE_REPLY_OPTIONS"));
});

Deno.test("handler: a v1 client never receives the gate and a style-less decision fails as before", async () => {
  const calls: string[] = [];
  const systems: string[] = [];
  const text = await runHandler(makeDeps({
    calls,
    chargeInputs: [],
    doneResults: [],
    systems,
    modelChunks: [INVENTORY, NO_SEND, METRICS, DONE_WITH_DEBRIS],
  }));
  assertFalse(systems[0].includes("Message decision gate"));
  assertFalse(calls.includes("chargeRun"));
  assert(text.includes("STREAM_MALFORMED_RECOMMENDATION"));
});

Deno.test("handler: retry of a charged no-send run resumes from the ledger without re-charging", async () => {
  const validated = validateNoSendDecisionEvent(NO_SEND);
  assert(validated.ok);
  const calls: string[] = [];
  const chargeInputs: StreamChargePayload[] = [];
  const doneResults: Record<string, unknown>[] = [];
  const text = await runHandler(makeDeps({
    calls,
    chargeInputs,
    doneResults,
    systems: [],
    noSendDecisions: true,
    analysisRunId: "run-1",
    retryRun: makeRun({
      status: "failed",
      charged_at: new Date().toISOString(),
      decision_kind: "do_not_send",
      recommendation_json: {
        decisionKind: "do_not_send",
        action: "pause",
        reason: NO_SEND.reason,
        stopCondition: NO_SEND.stopCondition,
        raw: NO_SEND,
        analysisDecisionV2: validated.payload.analysisDecisionV2,
      },
    }),
    modelChunks: [
      {
        ...NO_SEND,
        messageDecision: "send",
        selectedStyle: "extend",
        nextStepBody: "x",
        doThis: "y",
      },
      REPLY_OPTION,
      METRICS,
      DONE_WITH_DEBRIS,
    ],
  }));

  assertEquals(calls[0], "getRun");
  assertEquals(calls[1], "reserveRetry");
  assertFalse(calls.includes("chargeRun"));
  assert(calls.includes("markDone"));
  assertFalse(text.includes("STREAM_RUN_NOT_RETRYABLE"));
  assert(text.includes('"messageDecision":"do_not_send"'));
  assertEquals(doneResults[0].replies, {});
  assertEquals(
    (doneResults[0].analysisDecisionV2 as Record<string, unknown>)
      .messageDecision,
    "do_not_send",
  );
});

Deno.test("handler: a v1 request cannot retry or resume a v2 no-send run (capability gate covers the ledger)", async () => {
  const validated = validateNoSendDecisionEvent(NO_SEND);
  assert(validated.ok);
  const noSendRun = (status: string, extra: Record<string, unknown> = {}) =>
    makeRun({
      status,
      charged_at: new Date().toISOString(),
      decision_kind: "do_not_send",
      recommendation_json: {
        decisionKind: "do_not_send",
        action: "pause",
        reason: NO_SEND.reason,
        stopCondition: NO_SEND.stopCondition,
        raw: NO_SEND,
        analysisDecisionV2: validated.payload.analysisDecisionV2,
      },
      ...extra,
    });

  for (
    const run of [
      noSendRun("failed"),
      noSendRun("done", {
        final_result_json: {
          replies: {},
          analysisDecisionV2: validated.payload.analysisDecisionV2,
        },
      }),
      noSendRun("charged"),
    ]
  ) {
    const calls: string[] = [];
    const text = await runHandler(makeDeps({
      calls,
      chargeInputs: [],
      doneResults: [],
      systems: [],
      analysisRunId: "run-1",
      retryRun: run,
      modelChunks: [METRICS, DONE_WITH_DEBRIS],
    }));
    assertEquals(calls, ["getRun"], run.status);
    assert(text.includes("STREAM_RUN_RETRY_UNAVAILABLE"), run.status);
    assertFalse(text.includes("messageDecision"), run.status);
    assertFalse(text.includes("do_not_send"), run.status);
  }

  // A v1 send run is untouched by the gate: retry still works for v1.
  const calls: string[] = [];
  const text = await runHandler(makeDeps({
    calls,
    chargeInputs: [],
    doneResults: [],
    systems: [],
    analysisRunId: "run-1",
    retryRun: makeRun({
      status: "failed",
      charged_at: new Date().toISOString(),
      selected_style: "extend",
      recommendation_json: {
        selectedStyle: "extend",
        message: "m",
        reason: "r",
        quotedContext: "q",
        warnings: [],
        raw: {
          type: "analysis.decision",
          selectedStyle: "extend",
          nextStepBody: "m",
          doThis: "r",
        },
      },
    }),
    modelChunks: [
      {
        type: "analysis.decision",
        selectedStyle: "extend",
        nextStepBody: "m",
        doThis: "r",
      },
      {
        type: "analysis.reply_option",
        style: "extend",
        message: "m",
        reason: "r",
      },
      {
        type: "analysis.reply_option",
        style: "tease",
        message: "t",
        reason: "r",
      },
      { type: "analysis.done", finalResult: {} },
    ],
  }));
  assert(calls.includes("reserveRetry"));
  assert(calls.includes("markDone"));
  assertFalse(text.includes("STREAM_RUN_RETRY_UNAVAILABLE"));
});

Deno.test("handler: a v1 client that attached to a pending run is still gated when it settles as no-send", async () => {
  const validated = validateNoSendDecisionEvent(NO_SEND);
  assert(validated.ok);
  const doneNoSend = makeRun({
    status: "done",
    charged_at: new Date().toISOString(),
    decision_kind: "do_not_send",
    recommendation_json: {
      decisionKind: "do_not_send",
      action: "pause",
      reason: NO_SEND.reason,
      stopCondition: NO_SEND.stopCondition,
      raw: NO_SEND,
      analysisDecisionV2: validated.payload.analysisDecisionV2,
    },
    final_result_json: {
      replies: {},
      replyOptions: {},
      analysisDecisionV2: validated.payload.analysisDecisionV2,
    },
  });

  // v1: attach while pending, next poll sees the settled no-send run.
  const v1Calls: string[] = [];
  const v1Text = await runHandler(makeDeps({
    calls: v1Calls,
    chargeInputs: [],
    doneResults: [],
    systems: [],
    analysisRunId: "run-1",
    getRunSequence: [makeRun({ status: "pending" }), doneNoSend],
    retryRun: doneNoSend,
    modelChunks: [],
  }));
  assertFalse(v1Calls.includes("callModel"));
  assert(v1Text.includes("STREAM_RUN_RETRY_UNAVAILABLE"));
  assert(v1Text.includes('"upstreamCode":"STREAM_RUN_NOT_RETRYABLE"'));
  assertFalse(v1Text.includes("messageDecision"));
  assertFalse(v1Text.includes("do_not_send"));

  // v2: the same sequence replays the settled no-send result.
  const v2Calls: string[] = [];
  const v2Text = await runHandler(makeDeps({
    calls: v2Calls,
    chargeInputs: [],
    doneResults: [],
    systems: [],
    noSendDecisions: true,
    analysisRunId: "run-1",
    getRunSequence: [makeRun({ status: "pending" }), doneNoSend],
    retryRun: doneNoSend,
    modelChunks: [],
  }));
  assertFalse(v2Calls.includes("callModel"));
  assert(v2Text.includes('"recovered":true'));
  assert(v2Text.includes('"messageDecision":"do_not_send"'));
  assertFalse(v2Text.includes("STREAM_RUN_RETRY_UNAVAILABLE"));
});

// Phase 2a shadow：divergence_plan 只在 v2、且在已扣費的 send 決策之後，進 record-only 快照。
import { VALID_PLAN } from "./divergence_contract_test.ts";

const SEND_DECISION = {
  ...NO_SEND,
  messageDecision: "send",
  selectedStyle: "extend",
  nextStepBody: "接住",
  doThis: "先回",
};
const SEND_TAIL = [
  {
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "m",
    reason: "r",
    quotedContext: "q",
  },
  { type: "analysis.reply_option", style: "extend", message: "m", reason: "r" },
  { type: "analysis.reply_option", style: "tease", message: "t", reason: "r" },
];
const V2_TWO_STYLES = {
  noSendDecisions: true,
  requiredReplyStyles: ["extend", "tease"] as const,
};

Deno.test("divergence plan: after a charged send decision the first valid plan becomes the server snapshot", async () => {
  const { events, charges } = await run([
    SEND_DECISION,
    VALID_PLAN,
    { ...VALID_PLAN, threadFrame: "SECOND_PLAN_MUST_LOSE" },
    ...SEND_TAIL,
    {
      type: "analysis.done",
      finalResult: {
        analysisDivergencePlan: { schemaVersion: 1, threadFrame: "INJECTED" },
      },
    },
  ], V2_TWO_STYLES);
  assertEquals(charges.length, 1);
  // 扣費錨點在 decision，計畫在它之後才到，所以不進 recommendation_json。
  assertEquals("analysisDivergencePlan" in charges[0], false);
  assertFalse(
    events.some((event) => event.type === "analysis.divergence_plan"),
  );
  // reframer 的 finalResult 是 server 端的完整結果；client 剝除在 handler
  // markDone／resume 邊界（見 analyze_stream_handler_test）。
  const plan = doneOf(events).analysisDivergencePlan as Record<string, unknown>;
  assertEquals(plan.threadFrame, VALID_PLAN.threadFrame);
  assertEquals("type" in plan, false);
  assertEquals((plan.branchPool as unknown[]).length, 2);
});

Deno.test("divergence plan: flag off treats the event as the unknown line it used to be", async () => {
  const { events } = await run([
    VALID_PLAN,
    {
      type: "analysis.recommendation",
      selectedStyle: "extend",
      message: "m",
      reason: "r",
      quotedContext: "q",
    },
    VALID_PLAN,
    {
      type: "analysis.reply_option",
      style: "extend",
      message: "m",
      reason: "r",
    },
    {
      type: "analysis.reply_option",
      style: "tease",
      message: "t",
      reason: "r",
    },
    { type: "analysis.done", finalResult: {} },
  ], { requiredReplyStyles: ["extend", "tease"] });
  assertFalse(
    events.some((event) => event.type === "analysis.divergence_plan"),
  );
  assertEquals("analysisDivergencePlan" in doneOf(events), false);
});

Deno.test("divergence plan: a plan before the decision, a plan under no-send, and a malformed plan all leave no snapshot", async () => {
  // plan → send decision：decision 前到達的計畫不採用（也不進 pre-charge buffer）。
  const early = await run([
    VALID_PLAN,
    SEND_DECISION,
    ...SEND_TAIL,
    { type: "analysis.done", finalResult: {} },
  ], V2_TWO_STYLES);
  assertEquals("analysisDivergencePlan" in early.charges[0], false);
  assertEquals("analysisDivergencePlan" in doneOf(early.events), false);
  assertFalse(
    early.events.some((event) => event.type === "analysis.divergence_plan"),
  );

  // plan → no-send decision：no-send 的扣費快照與 finalResult 都不能帶計畫。
  const planThenNoSend = await run(
    [INVENTORY, VALID_PLAN, NO_SEND, VALID_PLAN, METRICS, DONE_WITH_DEBRIS],
    { noSendDecisions: true },
  );
  assertEquals(planThenNoSend.charges.length, 1);
  assertEquals("analysisDivergencePlan" in planThenNoSend.charges[0], false);
  assertEquals(
    "analysisDivergencePlan" in doneOf(planThenNoSend.events),
    false,
  );

  // 壞掉的計畫整份不採用。
  const malformed = await run([
    SEND_DECISION,
    { ...VALID_PLAN, branchPool: [] },
    ...SEND_TAIL,
    { type: "analysis.done", finalResult: {} },
  ], V2_TWO_STYLES);
  assertEquals("analysisDivergencePlan" in doneOf(malformed.events), false);
});

Deno.test("divergence plan: a rejected plan is not a valid event, so an otherwise empty v2 stream fails exactly like an empty one", async () => {
  const empty = await run([], V2_TWO_STYLES);
  const malformedOnly = await run(
    [{ ...VALID_PLAN, branchPool: [] }],
    V2_TWO_STYLES,
  );
  const earlyOnly = await run([VALID_PLAN], V2_TWO_STYLES);
  assertEquals(malformedOnly.events, empty.events);
  assertEquals(earlyOnly.events, empty.events);
  assertEquals(malformedOnly.charges.length, 0);
  assertEquals(earlyOnly.charges.length, 0);
});

// Phase 2b：五風格歸因——option 自帶 > 計畫指定 > anchor；client 事件永遠剝掉
// 歸因欄位；v1 連歸因都不做。
const ATTRIBUTED_TAIL = [
  {
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "m",
    reason: "r",
    quotedContext: "q",
  },
  {
    type: "analysis.reply_option",
    style: "extend",
    message: "m",
    reason: "r",
    branchId: "br_2",
    rhetoricalMove: "new_angle",
    styleIntensity: 1,
  },
  { type: "analysis.reply_option", style: "tease", message: "t", reason: "r" },
  {
    type: "analysis.reply_option",
    style: "humor",
    message: "h",
    reason: "r",
    branchId: "br_9",
    rhetoricalMove: "exaggeration",
    styleIntensity: 2,
  },
];
const V2_THREE_STYLES = {
  noSendDecisions: true,
  requiredReplyStyles: ["extend", "tease", "humor"] as const,
};

Deno.test("divergence attribution: every option resolves to a branch (option > plan > anchor), invalid fields are flagged, and attribution lives in the evidence linkage", async () => {
  const { events } = await run([
    SEND_DECISION,
    VALID_PLAN,
    ...ATTRIBUTED_TAIL,
    { type: "analysis.done", finalResult: {} },
  ], V2_THREE_STYLES);
  const options = events.filter((event) =>
    event.type === "analysis.reply_option"
  );
  assertEquals(options.length, 3);
  const done = doneOf(events);
  const linkage = done.analysisEvidenceLinkage as Record<string, unknown>;
  const variants = linkage.variants as Record<string, Record<string, unknown>>;
  assertEquals(variants.extend, {
    branchId: "br_2",
    branchSource: "option",
    rhetoricalMove: "new_angle",
    styleIntensity: 1,
  });
  // tease：沒帶、計畫也沒指定 → anchor（br_1）。
  assertEquals(variants.tease, { branchId: "br_1", branchSource: "anchor" });
  // humor：帶了未知枝 → 退回計畫指定（br_2）並標 invalid。
  assertEquals(variants.humor, {
    branchId: "br_2",
    branchSource: "plan",
    branchAttributionInvalid: true,
  });
  // 組裝進 replyOptions 的只有 approach／messages；歸因留在 linkage。
  assertEquals(
    JSON.stringify(done.replyOptions).includes("branchId"),
    false,
  );
});

Deno.test("divergence attribution: without a plan (or on v1) no variant is attributed", async () => {
  const noPlan = await run([
    SEND_DECISION,
    ...ATTRIBUTED_TAIL,
    { type: "analysis.done", finalResult: {} },
  ], V2_THREE_STYLES);
  const noPlanVariants = (doneOf(noPlan.events)
    .analysisEvidenceLinkage as Record<string, unknown> | undefined)
    ?.variants as Record<string, Record<string, unknown>> | undefined;
  assertEquals(noPlanVariants?.extend?.branchId, undefined);
  assertEquals(noPlanVariants?.tease?.branchSource, undefined);

  const v1 = await run([
    { ...SEND_DECISION, messageDecision: undefined },
    VALID_PLAN,
    ...ATTRIBUTED_TAIL,
    { type: "analysis.done", finalResult: {} },
  ], { requiredReplyStyles: ["extend", "tease", "humor"] as const });
  const v1Variants = (doneOf(v1.events)
    .analysisEvidenceLinkage as Record<string, unknown> | undefined)
    ?.variants as Record<string, Record<string, unknown>> | undefined;
  assertEquals(v1Variants?.extend?.branchId, undefined);
});

Deno.test("divergence attribution: plan repairs are recorded in the evidence linkage as enum-only entries", async () => {
  const { events } = await run([
    SEND_DECISION,
    {
      ...VALID_PLAN,
      branchPool: [
        { ...VALID_PLAN.branchPool[0], sourceIndex1: 1 },
        { ...VALID_PLAN.branchPool[1], method: "exaggeration" },
      ],
    },
    ...ATTRIBUTED_TAIL,
    { type: "analysis.done", finalResult: {} },
  ], V2_THREE_STYLES);
  const done = doneOf(events);
  const linkage = done.analysisEvidenceLinkage as Record<string, unknown>;
  assertEquals(linkage.divergencePlanRepairs, [
    "br_1:sourceIndex1",
    "br_2:method:exaggeration->association",
  ]);
  const plan = done.analysisDivergencePlan as Record<string, unknown>;
  assertEquals(
    (plan.branchPool as Record<string, unknown>[])[1].method,
    "association",
  );
});
