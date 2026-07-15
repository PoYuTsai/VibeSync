import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildOptimizeMessageLedgerResult,
  classifyOptimizeMessageReplayPreflight,
  computeOptimizeMessageInputHash,
  hasUsableOptimizedMessage,
  hydrateOptimizeMessageReplayResult,
  isValidOptimizeMessageRequestId,
  OPTIMIZE_MESSAGE_COST,
  optimizeMessageReplayCutoffIso,
  type OptimizeMessageRpc,
  settleOptimizeMessageRequest,
} from "./optimize_message_billing.ts";
import { findClientShapeViolations } from "./client_shape_validator.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";

Deno.test("optimize-message fixed policy is exactly one message", () => {
  assertEquals(OPTIMIZE_MESSAGE_COST, 1);
});

Deno.test("optimize-message replay cutoff is exactly seven days", () => {
  assertEquals(
    optimizeMessageReplayCutoffIso(new Date("2026-07-16T12:00:00.000Z")),
    "2026-07-09T12:00:00.000Z",
  );
});

Deno.test("optimize-message request id accepts only canonical UUID", () => {
  assert(isValidOptimizeMessageRequestId(REQUEST_ID));
  assertFalse(isValidOptimizeMessageRequestId(undefined));
  assertFalse(isValidOptimizeMessageRequestId("not-a-uuid"));
  assertFalse(isValidOptimizeMessageRequestId(` ${REQUEST_ID}`));
});

Deno.test("optimize-message hash binds draft, context, and messages", async () => {
  const base = {
    messages: [{ isFromMe: false, content: "嗨" }],
    userDraft: "想約妳喝咖啡",
    conversationSummary: "剛認識",
  };
  const first = await computeOptimizeMessageInputHash(base);
  const same = await computeOptimizeMessageInputHash(base);
  const changedDraft = await computeOptimizeMessageInputHash({
    ...base,
    userDraft: "想約妳吃飯",
  });
  const changedContext = await computeOptimizeMessageInputHash({
    ...base,
    conversationSummary: "已聊一個月",
  });

  assertEquals(first, same);
  assertEquals(first.length, 64);
  assert(first !== changedDraft);
  assert(first !== changedContext);
});

Deno.test("optimize-message replay preflight returns cached result or mismatch", () => {
  const result = { optimizedMessage: { optimized: "要不要一起喝咖啡？" } };
  assertEquals(
    classifyOptimizeMessageReplayPreflight(null, "a".repeat(64)),
    { kind: "fresh" },
  );
  assertEquals(
    classifyOptimizeMessageReplayPreflight({
      input_hash: "b".repeat(64),
      result_json: result,
    }, "a".repeat(64)),
    { kind: "mismatch" },
  );
  assertEquals(
    classifyOptimizeMessageReplayPreflight({
      input_hash: "a".repeat(64),
      result_json: result,
    }, "a".repeat(64)),
    { kind: "replay", result },
  );
});

Deno.test("optimize-message success requires a non-empty optimized sentence", () => {
  assert(hasUsableOptimizedMessage({
    optimizedMessage: { optimized: "自然一點的句子" },
  }));
  assertFalse(hasUsableOptimizedMessage({}));
  assertFalse(hasUsableOptimizedMessage({ optimizedMessage: {} }));
  assertFalse(hasUsableOptimizedMessage({
    optimizedMessage: { optimized: "   " },
  }));
});

Deno.test("optimize-message ledger strips original/context and replay rehydrates current hash-bound draft", () => {
  const ledger = buildOptimizeMessageLedgerResult({
    optimizedMessage: {
      original: "原始私密草稿",
      optimized: "要不要找天一起喝咖啡？",
      reason: "讓邀約更自然",
    },
    usage: { monthlyRemaining: 10 },
    conversationSummary: "不得持久化",
  });
  assertEquals(ledger, {
    optimizedMessage: {
      optimized: "要不要找天一起喝咖啡？",
      reason: "讓邀約更自然",
    },
  });
  assertEquals(
    hydrateOptimizeMessageReplayResult(ledger!, "原始私密草稿"),
    {
      optimizedMessage: {
        original: "原始私密草稿",
        optimized: "要不要找天一起喝咖啡？",
        reason: "讓邀約更自然",
      },
    },
  );
});

Deno.test("optimize-message rejects a result the Flutter client cannot parse", () => {
  const violations = findClientShapeViolations({
    optimizedMessage: {
      original: "要不要喝咖啡",
      optimized: "要不要找天一起喝咖啡？",
      reason: 123,
    },
  });
  assertEquals(violations.map((violation) => violation.path), [
    "optimizedMessage.reason",
  ]);
});

type RpcCall = { fn: string; params: Record<string, unknown> };

function rpcReturning(
  response: {
    data: unknown;
    error: { message?: string; code?: string } | null;
  },
  calls: RpcCall[] = [],
): OptimizeMessageRpc {
  return (fn, params) => {
    calls.push({ fn, params });
    return Promise.resolve(response);
  };
}

const result = {
  optimizedMessage: { optimized: "要不要一起喝咖啡？", reason: "更自然" },
};
const settleBase = {
  userId: "user-1",
  requestId: REQUEST_ID,
  inputHash: "a".repeat(64),
  result,
  monthlyLimit: 800,
  dailyLimit: 80,
  chargeQuota: true,
};

Deno.test("optimize-message settlement wires fixed atomic RPC", async () => {
  const calls: RpcCall[] = [];
  const settled = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({
      data: { charged: true, result, monthlyUsed: 11, dailyUsed: 3 },
      error: null,
    }, calls),
  });

  assertEquals(settled, {
    kind: "settled",
    charged: true,
    result,
    monthlyUsed: 11,
    dailyUsed: 3,
  });
  assertEquals(calls, [{
    fn: "settle_optimize_message_request",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_result_json: result,
      p_monthly_limit: 800,
      p_daily_limit: 80,
      p_charge_quota: true,
    },
  }]);
});

Deno.test("optimize-message settlement reports dedup without a second charge", async () => {
  const settled = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({
      data: { charged: false, result, monthlyUsed: 11, dailyUsed: 3 },
      error: null,
    }),
  });
  assertEquals(settled, {
    kind: "settled",
    charged: false,
    result,
    monthlyUsed: 11,
    dailyUsed: 3,
  });
});

Deno.test("optimize-message settlement preserves test-account waiver", async () => {
  const calls: RpcCall[] = [];
  await settleOptimizeMessageRequest({
    ...settleBase,
    chargeQuota: false,
    rpc: rpcReturning({
      data: { charged: false, result, monthlyUsed: 0, dailyUsed: 0 },
      error: null,
    }, calls),
  });
  assertEquals(calls[0].params.p_charge_quota, false);
});

Deno.test("optimize-message settlement maps monthly and daily 429 races", async () => {
  for (
    const [message, reason] of [
      ["P0001: QUOTA_EXCEEDED_MONTHLY", "monthly_limit_exceeded"],
      ["P0001: QUOTA_EXCEEDED_DAILY", "daily_limit_exceeded"],
    ] as const
  ) {
    const settled = await settleOptimizeMessageRequest({
      ...settleBase,
      rpc: rpcReturning({ data: null, error: { message } }),
    });
    assertEquals(settled, { kind: "quota_exceeded", reason });
  }
});

Deno.test("optimize-message settlement retries ambiguous transport failure", async () => {
  const settled = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({ data: null, error: { message: "connection reset" } }),
  });
  assertEquals(settled, { kind: "retryable", message: "connection reset" });
});

Deno.test("optimize-message settlement fails closed on deterministic RPC error", async () => {
  const settled = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({
      data: null,
      error: { code: "P0001", message: "invalid quota limits" },
    }),
  });
  assertEquals(settled, { kind: "failed", message: "invalid quota limits" });
});

Deno.test("optimize-message settlement retries a thrown transport failure", async () => {
  const settled = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: () => Promise.reject(new Error("socket closed")),
  });
  assertEquals(settled, { kind: "retryable", message: "socket closed" });
});

Deno.test("optimize-message settlement rejects invalid identity before RPC", async () => {
  const calls: RpcCall[] = [];
  const settled = await settleOptimizeMessageRequest({
    ...settleBase,
    requestId: "not-a-uuid",
    rpc: rpcReturning({ data: { charged: true, result }, error: null }, calls),
  });

  assertEquals(settled, {
    kind: "failed",
    message: "invalid optimize request identity",
  });
  assertEquals(calls.length, 0);
});

Deno.test("optimize-message settlement maps replay mismatch and malformed RPC result", async () => {
  const mismatch = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({
      data: null,
      error: { message: "P0001: OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH" },
    }),
  });
  assertEquals(mismatch, { kind: "mismatch" });

  const malformed = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({ data: { charged: true }, error: null }),
  });
  assertEquals(malformed, {
    kind: "retryable",
    message: "missing optimize settlement result",
  });
});

Deno.test("optimize-message settlement requires authoritative usage counters", async () => {
  const missing = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({ data: { charged: true, result }, error: null }),
  });
  assertEquals(missing, {
    kind: "retryable",
    message: "missing optimize settlement usage counters",
  });

  const fractional = await settleOptimizeMessageRequest({
    ...settleBase,
    rpc: rpcReturning({
      data: { charged: true, result, monthlyUsed: 1.5, dailyUsed: 2 },
      error: null,
    }),
  });
  assertEquals(fractional, {
    kind: "retryable",
    message: "missing optimize settlement usage counters",
  });
});

const indexSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260716170000_optimize_message_fixed_charge.sql",
    import.meta.url,
  ),
);

function requiredIndex(source: string, snippet: string, from = 0): number {
  const position = source.indexOf(snippet, from);
  assert(position >= 0, `Expected source to contain: ${snippet}`);
  return position;
}

Deno.test("optimize-message cannot be quota-blocked before replay or routed through compatibility modes", () => {
  const responseModeRejection = requiredIndex(
    indexSource,
    "OPTIMIZE_MESSAGE_UNSUPPORTED_RESPONSE_MODE",
  );
  const quickBranch = requiredIndex(
    indexSource,
    'if (responseMode === "quick")',
  );
  assert(
    responseModeRejection < quickBranch,
    "optimize compatibility modes must be rejected before quick can charge",
  );

  for (
    const counterGate of [
      "sub.monthly_messages_used >= monthlyLimit",
      "sub.daily_messages_used >= dailyLimit",
    ]
  ) {
    const gate = requiredIndex(indexSource, counterGate);
    assert(
      indexSource.slice(Math.max(0, gate - 300), gate).includes(
        "!isOptimizeMessageRequestShape",
      ),
      "early global quota gates must let optimize requests reach replay lookup",
    );
  }
});

Deno.test("optimize-message replay preflight enforces the seven-day window", () => {
  const replayRead = requiredIndex(
    indexSource,
    '.from("optimize_message_requests")',
  );
  const replayReadEnd = requiredIndex(
    indexSource,
    ".maybeSingle()",
    replayRead,
  );
  const replayQuery = indexSource.slice(replayRead, replayReadEnd);
  assert(replayQuery.includes("input_hash, result_json, created_at"));
  assert(
    replayQuery.includes(
      '.gte("created_at", optimizeMessageReplayCutoffIso())',
    ),
  );
  const replayValidation = requiredIndex(
    indexSource,
    "const replayShapeViolations = findClientShapeViolations",
    replayReadEnd,
  );
  const replayReturn = requiredIndex(
    indexSource,
    "optimizeReplayResult = hydratedReplay",
    replayValidation,
  );
  assert(
    replayValidation < replayReturn,
    "cached results must still be client-parseable before replay",
  );
});

Deno.test("optimize-message replay preflight read failure returns retryable 503 before quota/model work", () => {
  const replayReadError = requiredIndex(
    indexSource,
    "if (replayReadError) {",
  );
  const retryableResponse = requiredIndex(
    indexSource,
    'error: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE"',
    replayReadError,
  );
  const projectedQuota = requiredIndex(
    indexSource,
    "let projectedMonthlyUsage",
    retryableResponse,
  );
  const branch = indexSource.slice(replayReadError, projectedQuota);
  assert(branch.includes("return jsonResponse({"));
  assert(branch.includes("retryable: true"));
  assert(branch.includes("}, 503)"));
});

Deno.test("already-paid optimize replay bypasses later downgrade while fresh request remains Essential-only", () => {
  const featureGate = requiredIndex(
    indexSource,
    "isMyMessageMode ||\n        (isOptimizeMessageMode && optimizeReplayResult === null)",
  );
  const replayReturn = requiredIndex(
    indexSource,
    "isOptimizeMessageMode && optimizeReplayResult !== null",
    featureGate,
  );
  assert(featureGate < replayReturn);
  assert(
    indexSource.slice(featureGate, replayReturn).includes(
      'effectiveTier !== "essential"',
    ),
    "fresh optimize must remain Essential-gated",
  );
});

Deno.test("optimize-message handler preserves caps and validates output before atomic settlement", () => {
  const hardCap = requiredIndex(
    indexSource,
    'billing.outcome === "reject_too_long"',
  );
  const replayReturn = requiredIndex(
    indexSource,
    "isOptimizeMessageMode && optimizeReplayResult !== null",
  );
  assert(hardCap < replayReturn, "hard cap must run even for cached replays");

  const confirmation = requiredIndex(
    indexSource,
    'billing.outcome === "requires_confirmation"',
  );
  assert(
    indexSource.slice(confirmation, confirmation + 240).includes(
      "!isOptimizeMessageMode",
    ),
    "optimize-message must bypass the variable-cost confirmation gate",
  );

  const clientShapeValidation = requiredIndex(
    indexSource,
    "findClientShapeViolations(result)",
  );
  const usableValidation = requiredIndex(
    indexSource,
    "!hasUsableOptimizedMessage(result)",
    clientShapeValidation,
  );
  const settlement = requiredIndex(
    indexSource,
    "settleOptimizeMessageRequest({",
    usableValidation,
  );
  const genericIncrement = requiredIndex(
    indexSource,
    'supabase.rpc("increment_usage"',
    settlement,
  );
  assert(
    clientShapeValidation < usableValidation && usableValidation < settlement &&
      settlement < genericIncrement,
    "client-parseable usable result must be validated before settlement, which must precede generic billing",
  );
  const minimalLedger = requiredIndex(
    indexSource,
    "buildOptimizeMessageLedgerResult(result)",
    usableValidation,
  );
  assert(
    minimalLedger < settlement &&
      indexSource.slice(minimalLedger, settlement + 500).includes(
        "result: optimizeLedgerResult",
      ),
    "atomic settlement must receive only the privacy-minimized replay snapshot",
  );
  assert(
    indexSource.slice(settlement, genericIncrement).includes(
      "quotaUsage.shouldChargeQuota = false",
    ),
    "atomic settlement must disable the generic increment path",
  );

  const quotaRace = requiredIndex(
    indexSource,
    'settlement.kind === "quota_exceeded"',
  );
  const authoritativeRead = requiredIndex(
    indexSource,
    "authoritativeSub",
    quotaRace,
  );
  const quotaPayload = requiredIndex(
    indexSource,
    "buildQuotaExceededPayload({",
    authoritativeRead,
  );
  assert(
    quotaRace < authoritativeRead && authoritativeRead < quotaPayload,
    "quota-race response must refresh counters before building the 429 payload",
  );
  assert(
    indexSource.includes(
      "optimizeSettledMonthlyUsed = settlement.monthlyUsed",
    ) &&
      indexSource.includes(
        "optimizeSettledDailyUsed = settlement.dailyUsed",
      ),
    "successful settlement must use transaction-authoritative counters",
  );
});

Deno.test("optimize-message migration makes result ledger and one-unit charge atomic", () => {
  const resultValidation = requiredIndex(
    migrationSource,
    "{optimizedMessage,optimized}",
  );
  const ledgerInsert = requiredIndex(
    migrationSource,
    "INSERT INTO public.optimize_message_requests",
  );
  const exactIncrement = requiredIndex(
    migrationSource,
    "PERFORM public.increment_usage(",
  );

  assert(resultValidation < ledgerInsert && ledgerInsert < exactIncrement);
  assert(
    migrationSource.includes("ON CONFLICT (user_id, request_id) DO NOTHING"),
  );
  assert(migrationSource.includes("FOR UPDATE"));
  assert(migrationSource.includes("'charged', FALSE"));
  assert(
    migrationSource.includes(
      "CREATE INDEX IF NOT EXISTS optimize_message_requests_created_at_idx",
    ),
  );
  const globalPurge = requiredIndex(
    migrationSource,
    "DELETE FROM public.optimize_message_requests",
  );
  const ledgerInsertAfterPurge = requiredIndex(
    migrationSource,
    "INSERT INTO public.optimize_message_requests",
    globalPurge,
  );
  const purgeClause = migrationSource.slice(
    globalPurge,
    ledgerInsertAfterPurge,
  );
  assert(purgeClause.includes("created_at < now() - interval '7 days'"));
  assertFalse(
    purgeClause.includes("user_id = p_user_id"),
    "expired private drafts must be purged globally, not only when that user returns",
  );
  assert(
    migrationSource.match(/'monthlyUsed', v_monthly_used/g)?.length === 2 &&
      migrationSource.match(/'dailyUsed', v_daily_used/g)?.length === 2,
    "fresh and replay settlements must both return authoritative counters",
  );
  assert(
    migrationSource.slice(exactIncrement, exactIncrement + 180).includes(
      "p_user_id,\n      1,",
    ),
    "settlement must call increment_usage with exactly one",
  );
  assert(
    migrationSource.includes(
      "REVOKE EXECUTE ON FUNCTION public.settle_optimize_message_request",
    ),
  );
});

Deno.test("optimize-message migration hardens nullable counters and bounds live-table retention", () => {
  assert(
    migrationSource.includes(
      "monthly_messages_used = COALESCE(monthly_messages_used, 0)",
    ),
  );
  assert(
    migrationSource.includes(
      "ALTER COLUMN monthly_messages_used SET NOT NULL",
    ) &&
      migrationSource.includes(
        "ALTER COLUMN daily_messages_used SET NOT NULL",
      ),
  );
  assert(
    migrationSource.includes(
      "CREATE OR REPLACE FUNCTION public.cleanup_expired_optimize_message_requests()",
    ),
  );
  assert(migrationSource.includes("CREATE EXTENSION IF NOT EXISTS pg_cron"));
  assert(
    migrationSource.includes(
      "'cleanup-expired-optimize-message-requests'",
    ) && migrationSource.includes("'17 * * * *'"),
  );
});

Deno.test("optimize-message database privacy constraint forbids separate raw-input and extra response fields", () => {
  assert(
    migrationSource.includes(
      "Exact equality forbids separate raw-input",
    ),
  );
  assert(
    migrationSource.match(/result_json = jsonb_build_object/g)?.length === 1,
  );
  assert(
    migrationSource.includes(
      "OR p_result_json <> jsonb_build_object",
    ),
  );
  assert(
    migrationSource.includes(
      "Stores only generated optimized text and reason, without separate raw-input fields; generated text may reflect input",
    ),
  );
});
