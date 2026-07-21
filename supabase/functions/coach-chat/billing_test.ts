import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  claimCoachRequest,
  classifyCoachReplayPreflight,
  COACH_CONTRACT_VERSION,
  coachReplayCutoffIso,
  type CoachRpc,
  computeCoachInputHash,
  deriveCoachScopeKey,
  isStrongCoachReplayHmacKey,
  isValidCoachLedgerResult,
  normalizeCoachRequestId,
  releaseCoachClaim,
  settleCoachRequest,
} from "./billing.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const HMAC_KEY = btoa("0123456789abcdef0123456789abcdef");

Deno.test("coach contract version, replay window, and request id are fixed", () => {
  assertEquals(COACH_CONTRACT_VERSION, "coach-exactly-once-v1");
  assertEquals(
    coachReplayCutoffIso(new Date("2026-07-21T12:00:00.000Z")),
    "2026-07-20T12:00:00.000Z",
  );
  assertEquals(normalizeCoachRequestId(REQUEST_ID), REQUEST_ID);
  // 大寫 UUID 合法且 normalize 成小寫（zod .uuid() 收大小寫混寫）。
  assertEquals(
    normalizeCoachRequestId("123E4567-E89B-42D3-A456-426614174000"),
    REQUEST_ID,
  );
  assertEquals(normalizeCoachRequestId("not-a-uuid"), null);
  assertEquals(normalizeCoachRequestId(null), null);
  assertEquals(normalizeCoachRequestId(undefined), null);
});

Deno.test("coach scope key prefers explicit scope then conversation fallback", () => {
  assertEquals(
    deriveCoachScopeKey({
      scope: { type: "conversation", conversationId: "conv-1" },
      conversationId: "conv-1",
    }),
    "conversation:conv-1",
  );
  assertEquals(
    deriveCoachScopeKey({
      scope: { type: "partner", partnerId: "partner-9" },
      conversationId: "conv-1",
    }),
    "partner:partner-9",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: null, conversationId: "conv-2" }),
    "conversation:conv-2",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: undefined, conversationId: "conv-3" }),
    "conversation:conv-3",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: null, conversationId: "" }),
    "none",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: null, conversationId: null }),
    "none",
  );
});

Deno.test("coach HMAC binds every identity-relevant input field", async () => {
  const baseInput = {
    userId: "user-1",
    userQuestion: "我該怎麼回她",
    sessionId: "session-1",
    activeSessionTurns: [
      { role: "user", kind: "question", content: "她已讀不回" },
    ],
    forceAnswer: false,
    scopeKey: "conversation:conv-1",
    lifecyclePhase: "chatStalled",
    secret: HMAC_KEY,
  } as const;
  const first = await computeCoachInputHash(baseInput);
  const same = await computeCoachInputHash({ ...baseInput });
  assertEquals(first, same);
  assert(/^[0-9a-f]{64}$/.test(first));

  const variants = await Promise.all([
    computeCoachInputHash({ ...baseInput, userId: "user-2" }),
    computeCoachInputHash({ ...baseInput, userQuestion: "換個問題" }),
    computeCoachInputHash({ ...baseInput, sessionId: null }),
    computeCoachInputHash({
      ...baseInput,
      activeSessionTurns: [
        { role: "user", kind: "question", content: "她回了" },
      ],
    }),
    computeCoachInputHash({ ...baseInput, forceAnswer: true }),
    computeCoachInputHash({ ...baseInput, scopeKey: "partner:p-1" }),
    computeCoachInputHash({ ...baseInput, lifecyclePhase: null }),
    computeCoachInputHash({
      ...baseInput,
      secret: btoa("abcdef0123456789abcdef0123456789"),
    }),
  ]);
  for (const variant of variants) {
    assert(variant !== first);
  }

  assert(isStrongCoachReplayHmacKey(HMAC_KEY));
  assertFalse(isStrongCoachReplayHmacKey("short-secret"));
  assertFalse(isStrongCoachReplayHmacKey(undefined));
});

const OWNER_TOKEN = "223e4567-e89b-42d3-a456-426614174000";
const result = {
  card: {
    responseType: "coachAnswer",
    mode: "replyCraft",
    headline: "先穩住節奏",
    answer: "先回一句輕鬆的，不用急著解釋。",
    userState: "有點焦慮",
    frictionType: "fearOfMistake",
    nextStep: "傳出去後先放下手機",
    boundaryReminder: "不確定時先照顧自己的感受",
    needsReflection: false,
    rewriteDecision: "keep_original",
    costDeducted: 1,
  },
  sessionId: "session-1",
  provider: "claude" as const,
  model: "claude-sonnet-5",
  generatedAt: "2026-07-21T12:00:00.000Z",
};

Deno.test("coach ledger accepts only envelope + card whitelist shape", () => {
  assert(isValidCoachLedgerResult(result));
  assertFalse(
    isValidCoachLedgerResult({ ...result, prompt: "leaked prompt" }),
  );
  assertFalse(
    isValidCoachLedgerResult({
      ...result,
      card: { ...result.card, sourceMessage: "私密輸入" },
    }),
  );
  assertFalse(
    isValidCoachLedgerResult({
      ...result,
      card: { ...result.card, costDeducted: 2 },
    }),
  );
  assertFalse(
    isValidCoachLedgerResult({
      ...result,
      card: { ...result.card, responseType: "unknown" },
    }),
  );
  assertFalse(isValidCoachLedgerResult({ ...result, provider: "deepseek" }));
});

Deno.test("coach replay preflight distinguishes done, pending, and stale lease", () => {
  const now = new Date("2026-07-21T12:00:00.000Z");
  assertEquals(
    classifyCoachReplayPreflight(null, "a".repeat(64), now),
    { kind: "fresh" },
  );
  assertEquals(
    classifyCoachReplayPreflight(
      {
        input_hash: "b".repeat(64),
        state: "done",
        lease_expires_at: "2026-07-21T12:01:00.000Z",
        result_json: result,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "mismatch" },
  );
  assertEquals(
    classifyCoachReplayPreflight(
      {
        input_hash: "a".repeat(64),
        state: "done",
        lease_expires_at: "2026-07-21T12:01:00.000Z",
        result_json: result,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "replay", result },
  );
  assertEquals(
    classifyCoachReplayPreflight(
      {
        input_hash: "a".repeat(64),
        state: "pending",
        lease_expires_at: "2026-07-21T12:01:30.000Z",
        result_json: null,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "pending", retryAfterMs: 90_000 },
  );
  assertEquals(
    classifyCoachReplayPreflight(
      {
        input_hash: "a".repeat(64),
        state: "pending",
        lease_expires_at: "2026-07-21T11:59:59.000Z",
        result_json: null,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "fresh" },
  );
});

function rpcReturning(
  response: Awaited<ReturnType<CoachRpc>>,
  calls: Array<Record<string, unknown>> = [],
): CoachRpc {
  return (fn, params) => {
    calls.push({ fn, params });
    return Promise.resolve(response);
  };
}

const base = {
  userId: "user-1",
  requestId: REQUEST_ID,
  inputHash: "a".repeat(64),
  ownerToken: OWNER_TOKEN,
  result,
  monthlyLimit: 800,
  dailyLimit: 80,
  chargeQuota: true,
};

Deno.test("coach claim serializes generation ownership", async () => {
  const calls: Array<Record<string, unknown>> = [];
  assertEquals(
    await claimCoachRequest({
      ...base,
      rpc: rpcReturning({ data: { kind: "claimed" }, error: null }, calls),
    }),
    { kind: "claimed" },
  );
  assertEquals(calls[0], {
    fn: "claim_coach_request",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_owner_token: OWNER_TOKEN,
    },
  });
  assertEquals(
    await claimCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: { kind: "pending", retryAfterMs: 1200.2 },
        error: null,
      }),
    }),
    { kind: "pending", retryAfterMs: 1201 },
  );
  assertEquals(
    await claimCoachRequest({
      ...base,
      rpc: rpcReturning({ data: { kind: "replay", result }, error: null }),
    }),
    { kind: "replay", result },
  );
  assertEquals(
    await claimCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "COACH_REQUEST_REPLAY_MISMATCH" },
      }),
    }),
    { kind: "mismatch" },
  );
  assertEquals(
    await claimCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "connection reset" },
      }),
    }),
    { kind: "retryable", message: "connection reset" },
  );
  assertEquals(
    await claimCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "permission denied", code: "42501" },
      }),
    }),
    { kind: "failed", message: "permission denied" },
  );
});

Deno.test("coach claim release is owner-bound and fail-closed", async () => {
  const calls: Array<Record<string, unknown>> = [];
  assertEquals(
    await releaseCoachClaim({
      ...base,
      rpc: rpcReturning({ data: true, error: null }, calls),
    }),
    true,
  );
  assertEquals(calls[0], {
    fn: "release_coach_claim",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_owner_token: OWNER_TOKEN,
    },
  });
  assertEquals(
    await releaseCoachClaim({
      ...base,
      rpc: rpcReturning({ data: false, error: null }),
    }),
    false,
  );
  assertEquals(
    await releaseCoachClaim({
      ...base,
      rpc: rpcReturning({ data: null, error: { message: "timeout" } }),
    }),
    false,
  );
  assertEquals(
    await releaseCoachClaim({
      ...base,
      rpc: () => {
        throw new Error("network down");
      },
    }),
    false,
  );
});

Deno.test("coach settlement stores and charges atomically", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const settled = await settleCoachRequest({
    ...base,
    rpc: rpcReturning({ data: { charged: true, result }, error: null }, calls),
  });
  assertEquals(settled, { kind: "settled", charged: true, result });
  assertEquals(calls[0], {
    fn: "settle_coach_request",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_owner_token: OWNER_TOKEN,
      p_result_json: result,
      p_monthly_limit: 800,
      p_daily_limit: 80,
      p_charge_quota: true,
    },
  });
});

Deno.test("coach settlement replays and maps quota races", async () => {
  assertEquals(
    await settleCoachRequest({
      ...base,
      rpc: rpcReturning({ data: { charged: false, result }, error: null }),
    }),
    { kind: "settled", charged: false, result },
  );
  assertEquals(
    await settleCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "P0001: QUOTA_EXCEEDED_DAILY" },
      }),
    }),
    { kind: "quota_exceeded", reason: "daily_limit_exceeded" },
  );
  assertEquals(
    await settleCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "P0001: QUOTA_EXCEEDED_MONTHLY" },
      }),
    }),
    { kind: "quota_exceeded", reason: "monthly_limit_exceeded" },
  );
});

Deno.test("coach settlement preserves ambiguous failures for same-id retry", async () => {
  assertEquals(
    await settleCoachRequest({
      ...base,
      rpc: rpcReturning({ data: null, error: { message: "connection reset" } }),
    }),
    { kind: "retryable", message: "connection reset" },
  );
  assertEquals(
    await settleCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "COACH_REQUEST_REPLAY_MISMATCH" },
      }),
    }),
    { kind: "mismatch" },
  );
  assertEquals(
    await settleCoachRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "COACH_REQUEST_OWNER_MISMATCH" },
      }),
    }),
    { kind: "retryable", message: "coach lease ownership changed" },
  );
});
