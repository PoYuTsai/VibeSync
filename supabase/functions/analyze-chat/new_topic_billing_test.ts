import {
  assert,
  assertEquals,
  assertFalse,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  claimNewTopicRequest,
  classifyNewTopicReplayPreflight,
  computeNewTopicInputHash,
  isStrongNewTopicReplayHmacKey,
  NEW_TOPIC_REPLAY_HMAC_SECRET_NAME,
  newTopicReplayCutoffIso,
  normalizeNewTopicRequestId,
  releaseNewTopicClaim,
  settleNewTopicRequest,
} from "./new_topic_billing.ts";
import {
  buildNewTopicLedgerResult,
  type NewTopicLedgerResult,
} from "./new_topic_payload.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const OWNER_TOKEN = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const HASH = "a".repeat(64);
const STRONG_KEY = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));

function ledgerFixture(tier: "free" | "essential" = "free"): NewTopicLedgerResult {
  return buildNewTopicLedgerResult({
    topics: [1, 2, 3, 4, 5].map((n) => ({
      direction: `方向${n}`,
      openingLine: `開場句${n}`,
      whyItWorks: `因為${n}`,
      nextMove: `下一步${n}`,
    })),
    recommendationIndex: 1,
    recommendationReason: "理由",
    servedTier: tier,
  });
}

type RpcCall = { fn: string; params: Record<string, unknown> };

function fakeRpc(
  responder: (fn: string, params: Record<string, unknown>) => {
    data: unknown;
    error: { message?: string; code?: string } | null;
  },
): { rpc: Parameters<typeof claimNewTopicRequest>[0]["rpc"]; calls: RpcCall[] } {
  const calls: RpcCall[] = [];
  return {
    calls,
    rpc: (fn, params) => {
      calls.push({ fn, params });
      return Promise.resolve(responder(fn, params));
    },
  };
}

Deno.test("secret 名稱固定（部署 checklist 錨點）", () => {
  assertEquals(NEW_TOPIC_REPLAY_HMAC_SECRET_NAME, "NEW_TOPIC_REPLAY_HMAC_KEY");
});

Deno.test("normalizeNewTopicRequestId：canonical UUID 小寫化、非 UUID 拒絕", () => {
  assertEquals(
    normalizeNewTopicRequestId(REQUEST_ID.toUpperCase()),
    REQUEST_ID,
  );
  assertEquals(normalizeNewTopicRequestId("not-a-uuid"), null);
  assertEquals(normalizeNewTopicRequestId(123), null);
});

Deno.test("isStrongNewTopicReplayHmacKey：base64 至少 32 bytes 才過", () => {
  assert(isStrongNewTopicReplayHmacKey(STRONG_KEY));
  assertFalse(isStrongNewTopicReplayHmacKey(undefined));
  assertFalse(isStrongNewTopicReplayHmacKey("short"));
  assertFalse(isStrongNewTopicReplayHmacKey("!!!!" + "a".repeat(60)));
  assertFalse(
    isStrongNewTopicReplayHmacKey(
      btoa(String.fromCharCode(...new Uint8Array(16))),
    ),
    "16 bytes 太弱",
  );
});

Deno.test("computeNewTopicInputHash：確定性＋輸入/secret 敏感＋length-safe", async () => {
  const base = {
    userId: "user-1",
    partnerSummary: "摘要",
    effectiveStyleContext: null,
    situation: "stuck" as const,
    secret: STRONG_KEY,
  };
  const h1 = await computeNewTopicInputHash(base);
  const h2 = await computeNewTopicInputHash(base);
  assertEquals(h1, h2);
  assert(/^[0-9a-f]{64}$/.test(h1));

  assertNotEquals(
    h1,
    await computeNewTopicInputHash({ ...base, situation: "went_cold" }),
  );
  assertNotEquals(
    h1,
    await computeNewTopicInputHash({ ...base, partnerSummary: null }),
  );
  assertNotEquals(
    h1,
    await computeNewTopicInputHash({ ...base, secret: STRONG_KEY.slice(0, -4) + "AAA=" }),
  );

  // length-safe JSON array：欄位邊界不可碰撞（"a"+"bc" ≠ "ab"+"c"）。
  assertNotEquals(
    await computeNewTopicInputHash({
      ...base,
      userId: "a",
      partnerSummary: "bc",
    }),
    await computeNewTopicInputHash({
      ...base,
      userId: "ab",
      partnerSummary: "c",
    }),
  );
});

Deno.test("newTopicReplayCutoffIso：回推 24 小時", () => {
  const now = new Date("2026-07-24T12:00:00.000Z");
  assertEquals(newTopicReplayCutoffIso(now), "2026-07-23T12:00:00.000Z");
});

Deno.test("classifyNewTopicReplayPreflight 全態", () => {
  const now = new Date("2026-07-24T12:00:00.000Z");
  assertEquals(classifyNewTopicReplayPreflight(null, HASH, now), {
    kind: "fresh",
  });
  assertEquals(
    classifyNewTopicReplayPreflight({
      input_hash: "b".repeat(64),
      state: "pending",
      lease_expires_at: "2026-07-24T12:01:00.000Z",
      result_json: null,
    }, HASH, now),
    { kind: "mismatch" },
  );

  const stored = ledgerFixture();
  const replay = classifyNewTopicReplayPreflight({
    input_hash: HASH,
    state: "done",
    lease_expires_at: "2026-07-24T11:00:00.000Z",
    result_json: stored,
  }, HASH, now);
  assertEquals(replay, { kind: "replay", result: stored });

  // done 但 stored result 壞形狀→mismatch（絕不把壞資料回給 client）。
  assertEquals(
    classifyNewTopicReplayPreflight({
      input_hash: HASH,
      state: "done",
      lease_expires_at: "2026-07-24T11:00:00.000Z",
      // deno-lint-ignore no-explicit-any
      result_json: { topics: [] } as any,
    }, HASH, now),
    { kind: "mismatch" },
  );

  const pending = classifyNewTopicReplayPreflight({
    input_hash: HASH,
    state: "pending",
    lease_expires_at: "2026-07-24T12:00:30.000Z",
    result_json: null,
  }, HASH, now);
  assert(pending.kind === "pending" && pending.retryAfterMs === 30000);

  // lease 已過期→fresh（可 stale takeover）。
  assertEquals(
    classifyNewTopicReplayPreflight({
      input_hash: HASH,
      state: "pending",
      lease_expires_at: "2026-07-24T11:59:00.000Z",
      result_json: null,
    }, HASH, now),
    { kind: "fresh" },
  );
});

Deno.test("claim：claimed / pending / replay / mismatch / transport retryable", async () => {
  const claimed = fakeRpc(() => ({ data: { kind: "claimed" }, error: null }));
  assertEquals(
    await claimNewTopicRequest({
      rpc: claimed.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    }),
    { kind: "claimed" },
  );
  assertEquals(claimed.calls[0].fn, "claim_new_topic_request");

  const pending = fakeRpc(() => ({
    data: { kind: "pending", retryAfterMs: 1200.4 },
    error: null,
  }));
  assertEquals(
    await claimNewTopicRequest({
      rpc: pending.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    }),
    { kind: "pending", retryAfterMs: 1201 },
  );

  const stored = ledgerFixture("essential");
  const replay = fakeRpc(() => ({
    data: { kind: "replay", result: stored },
    error: null,
  }));
  assertEquals(
    await claimNewTopicRequest({
      rpc: replay.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    }),
    { kind: "replay", result: stored },
  );

  const mismatch = fakeRpc(() => ({
    data: null,
    error: { message: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH", code: "P0001" },
  }));
  assertEquals(
    (await claimNewTopicRequest({
      rpc: mismatch.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    })).kind,
    "mismatch",
  );

  const transport = fakeRpc(() => ({
    data: null,
    error: { message: "fetch failed", code: "" },
  }));
  assertEquals(
    (await claimNewTopicRequest({
      rpc: transport.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    })).kind,
    "retryable",
  );

  const badIdentity = await claimNewTopicRequest({
    rpc: claimed.rpc,
    userId: "u",
    requestId: "not-a-uuid",
    inputHash: HASH,
    ownerToken: OWNER_TOKEN,
  });
  assertEquals(badIdentity.kind, "failed");
});

Deno.test("release：全 identity 相符才 true；transport 例外回 false", async () => {
  const ok = fakeRpc(() => ({ data: true, error: null }));
  assert(
    await releaseNewTopicClaim({
      rpc: ok.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    }),
  );
  assertEquals(ok.calls[0].fn, "release_new_topic_claim");

  const missed = fakeRpc(() => ({ data: false, error: null }));
  assertFalse(
    await releaseNewTopicClaim({
      rpc: missed.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    }),
  );

  const thrown = {
    rpc: () => Promise.reject(new Error("socket reset")),
  };
  assertFalse(
    await releaseNewTopicClaim({
      // deno-lint-ignore no-explicit-any
      rpc: thrown.rpc as any,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
    }),
  );
});

Deno.test("settle：settled / quota RAISE / owner mismatch / transport / invalid result", async () => {
  const stored = ledgerFixture();

  const settled = fakeRpc(() => ({
    data: { charged: true, result: stored, monthlyUsed: 9, dailyUsed: 3 },
    error: null,
  }));
  const settledOutcome = await settleNewTopicRequest({
    rpc: settled.rpc,
    userId: "u",
    requestId: REQUEST_ID,
    inputHash: HASH,
    ownerToken: OWNER_TOKEN,
    result: stored,
    monthlyLimit: 30,
    dailyLimit: 10,
    chargeQuota: true,
  });
  assertEquals(settledOutcome, {
    kind: "settled",
    charged: true,
    result: stored,
  });
  assertEquals(settled.calls[0].fn, "settle_new_topic_request");
  assertEquals(settled.calls[0].params.p_charge_quota, true);

  const quota = fakeRpc(() => ({
    data: null,
    error: { message: "QUOTA_EXCEEDED_DAILY", code: "P0001" },
  }));
  assertEquals(
    await settleNewTopicRequest({
      rpc: quota.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
      result: stored,
      monthlyLimit: 30,
      dailyLimit: 10,
      chargeQuota: true,
    }),
    { kind: "quota_exceeded", reason: "daily_limit_exceeded" },
  );

  const ownerMismatch = fakeRpc(() => ({
    data: null,
    error: { message: "NEW_TOPIC_REQUEST_OWNER_MISMATCH", code: "P0001" },
  }));
  assertEquals(
    (await settleNewTopicRequest({
      rpc: ownerMismatch.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
      result: stored,
      monthlyLimit: 30,
      dailyLimit: 10,
      chargeQuota: true,
    })).kind,
    "retryable",
  );

  const transport = fakeRpc(() => ({
    data: null,
    error: { message: "connection timed out", code: "" },
  }));
  assertEquals(
    (await settleNewTopicRequest({
      rpc: transport.rpc,
      userId: "u",
      requestId: REQUEST_ID,
      inputHash: HASH,
      ownerToken: OWNER_TOKEN,
      result: stored,
      monthlyLimit: 30,
      dailyLimit: 10,
      chargeQuota: true,
    })).kind,
    "retryable",
  );

  // 本地 result 壞形狀連 RPC 都不打（invalid settlement）。
  const neverCalled = fakeRpc(() => ({ data: null, error: null }));
  const invalid = await settleNewTopicRequest({
    rpc: neverCalled.rpc,
    userId: "u",
    requestId: REQUEST_ID,
    inputHash: HASH,
    ownerToken: OWNER_TOKEN,
    // deno-lint-ignore no-explicit-any
    result: { topics: [] } as any,
    monthlyLimit: 30,
    dailyLimit: 10,
    chargeQuota: true,
  });
  assertEquals(invalid.kind, "failed");
  assertEquals(neverCalled.calls.length, 0);
});
