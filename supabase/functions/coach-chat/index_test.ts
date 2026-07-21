import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleRequest, selfHealSubscription } from "./index.ts";

Deno.test("GET health fails closed when ledger config is missing", async () => {
  // 測試環境無 SUPABASE_URL/SERVICE_KEY/COACH_REPLAY_HMAC_KEY：
  // F9 fail-closed——帳本裝備不齊即 503，不得自稱 ok。
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "GET",
    }),
  );
  assertEquals(res.status, 503);
  const body = await res.json();
  assertEquals(body, { status: "unavailable" });
});

Deno.test({
  name: "health is DB-contract-gated and weak HMAC key blocks ledger path",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    // GET health：env 齊全仍須 DB 回報 contract version 相符才 200。
    assert(source.includes('"coach_contract_version"'));
    assert(
      source.includes("databaseContractVersion !== COACH_CONTRACT_VERSION"),
    );
    assert(source.includes('{ status: "unavailable" }'));
    assert(
      source.includes("isStrongCoachReplayHmacKey(COACH_REPLAY_HMAC_KEY)"),
    );

    // POST：requestId 非 null＋金鑰缺/弱 → 500 config_missing，
    // 且守門位於 validate 之後、任何模型呼叫之前（不打模型不扣費）。
    const validate = source.indexOf("validateRequest(rawBody)");
    const requestIdGate = source.indexOf("normalizeCoachRequestId(");
    const weakKeyGate = source.indexOf(
      "requestId !== null && !isStrongCoachReplayHmacKey(",
    );
    const modelRun = source.indexOf("runCoachChat(");
    assert(validate >= 0 && requestIdGate > validate);
    assert(weakKeyGate > requestIdGate && weakKeyGate < modelRun);
  },
});

Deno.test("OPTIONS preflight returns CORS headers without auth", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "OPTIONS",
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("POST without auth returns 401", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(res.status, 401);
});

Deno.test({
  name: "quota preflight always gates, no clarification bypass",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // D1：checkQuota preflight 恆跑；額度歸零者不得再蹭免費釐清
    assertEquals(
      source.includes("allowNoChargeClarificationAttempt"),
      false,
    );
    assertEquals(source.includes("if (!gate.ok)"), true);
  },
});

Deno.test({
  name: "progress transport is opt-in and keeps buffered JSON rollback",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    assertEquals(source.includes("wantsCoachProgressStream(req)"), true);
    assertEquals(source.includes("coachProgressStreamResponse("), true);
    assertEquals(
      source.includes("return jsonResponse(result.body, result.status)"),
      true,
    );
  },
});

// 首次使用兩請求併發 selfHeal：後到者 insert 撞 unique constraint，
// 必須回讀既有列而非 null（null 會被上游映射成 403 鎖住新用戶）。
function buildRacedSupabaseFake(
  existing: Record<string, unknown> | null,
  insertErrorCode: string,
) {
  return {
    from: (_table: string) => ({
      insert: (_row: unknown) => ({
        select: (_cols: string) => ({
          single: () =>
            Promise.resolve({
              data: null,
              error: {
                code: insertErrorCode,
                message: "insert failed",
              },
            }),
        }),
      }),
      select: (_cols: string) => ({
        eq: (_col: string, _value: string) => ({
          maybeSingle: () => Promise.resolve({ data: existing, error: null }),
        }),
      }),
    }),
  };
}

Deno.test("selfHealSubscription duplicate insert falls back to existing row", async () => {
  const existing = {
    user_id: "user-1",
    tier: "free",
    monthly_messages_used: 2,
    daily_messages_used: 1,
    daily_reset_at: "2026-07-01T00:00:00.000Z",
    monthly_reset_at: "2026-07-01T00:00:00.000Z",
    started_at: "2026-06-01T00:00:00.000Z",
  };
  const sub = await selfHealSubscription(
    buildRacedSupabaseFake(existing, "23505"),
    "user-1",
  );
  assertEquals(sub, existing);
});

Deno.test("selfHealSubscription non-duplicate insert error still returns null", async () => {
  const sub = await selfHealSubscription(
    buildRacedSupabaseFake(null, "42501"),
    "user-1",
  );
  assertEquals(sub, null);
});

// ---- Phase C：帳本接線 handler 測（注入 fake client，不打網路不打模型） ----

import { computeCoachInputHash } from "./billing.ts";

const LEDGER_REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const STRONG_HMAC_KEY = btoa("0123456789abcdef0123456789abcdef");

const storedLedgerResult = {
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
  sessionId: null,
  provider: "claude",
  model: "claude-sonnet-5",
  generatedAt: "2026-07-21T11:00:00.000Z",
};

function freshSubRow(overrides: Record<string, unknown> = {}) {
  const nowIso = new Date().toISOString();
  return {
    tier: "free",
    monthly_messages_used: 0,
    daily_messages_used: 0,
    daily_reset_at: nowIso,
    monthly_reset_at: nowIso,
    ...overrides,
  };
}

function buildLedgerClientFake(opts: {
  replayRow?: Record<string, unknown> | null;
  sub?: Record<string, unknown>;
  rpcHandlers?: Record<
    string,
    (params: Record<string, unknown>) => {
      data: unknown;
      error: { message?: string; code?: string } | null;
    }
  >;
}) {
  const rpcCalls: Array<{ fn: string; params: Record<string, unknown> }> = [];
  const tablesTouched: string[] = [];
  const chain = (result: { data: unknown; error: unknown }) => {
    // deno-lint-ignore no-explicit-any
    const c: any = {};
    for (const method of ["select", "eq", "gte", "is", "update", "insert"]) {
      c[method] = () => c;
    }
    c.maybeSingle = () => Promise.resolve(result);
    c.single = () => Promise.resolve(result);
    c.then = undefined;
    return c;
  };
  const client = {
    auth: {
      getUser: (_token: string) =>
        Promise.resolve({
          data: { user: { id: "user-1", email: "u@example.com" } },
          error: null,
        }),
    },
    from: (table: string) => {
      tablesTouched.push(table);
      if (table === "coach_requests") {
        return chain({ data: opts.replayRow ?? null, error: null });
      }
      return chain({ data: opts.sub ?? freshSubRow(), error: null });
    },
    rpc: (fn: string, params: Record<string, unknown>) => {
      rpcCalls.push({ fn, params });
      const handler = opts.rpcHandlers?.[fn];
      if (handler) return Promise.resolve(handler(params));
      if (fn === "claim_coach_request") {
        return Promise.resolve({ data: { kind: "claimed" }, error: null });
      }
      if (fn === "release_coach_claim") {
        return Promise.resolve({ data: true, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { client, rpcCalls, tablesTouched };
}

function ledgerPostRequest(
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
) {
  return new Request("http://localhost/", {
    method: "POST",
    headers: {
      Authorization: "Bearer token",
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

const ledgerBody = {
  conversationId: "c1",
  userQuestion: "她已讀不回，我要不要再傳一句？",
  requestId: LEDGER_REQUEST_ID,
};

async function ledgerInputHash() {
  return await computeCoachInputHash({
    userId: "user-1",
    userQuestion: ledgerBody.userQuestion,
    sessionId: null,
    activeSessionTurns: [],
    forceAnswer: false,
    scopeKey: "conversation:c1",
    lifecyclePhase: null,
    secret: STRONG_HMAC_KEY,
  });
}

Deno.test("POST replay hit short-circuits with stored card and no claim", async () => {
  const fake = buildLedgerClientFake({
    replayRow: {
      input_hash: await ledgerInputHash(),
      state: "done",
      lease_expires_at: "2026-07-21T11:01:00.000Z",
      result_json: storedLedgerResult,
    },
  });
  const res = await handleRequest(ledgerPostRequest(ledgerBody), {
    supabase: fake.client,
    replayHmacKey: STRONG_HMAC_KEY,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), storedLedgerResult);
  assertEquals(fake.rpcCalls.length, 0);
});

Deno.test("POST pending lease returns 409 with retryAfterMs", async () => {
  const fake = buildLedgerClientFake({
    replayRow: {
      input_hash: await ledgerInputHash(),
      state: "pending",
      lease_expires_at: new Date(Date.now() + 60_000).toISOString(),
      result_json: null,
    },
  });
  const res = await handleRequest(ledgerPostRequest(ledgerBody), {
    supabase: fake.client,
    replayHmacKey: STRONG_HMAC_KEY,
  });
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.code, "COACH_REQUEST_PENDING");
  assert(typeof body.retryAfterMs === "number" && body.retryAfterMs > 0);
});

Deno.test("POST hash mismatch on same requestId returns 409", async () => {
  const fake = buildLedgerClientFake({
    replayRow: {
      input_hash: "b".repeat(64),
      state: "done",
      lease_expires_at: "2026-07-21T11:01:00.000Z",
      result_json: storedLedgerResult,
    },
  });
  const res = await handleRequest(ledgerPostRequest(ledgerBody), {
    supabase: fake.client,
    replayHmacKey: STRONG_HMAC_KEY,
  });
  assertEquals(res.status, 409);
  assertEquals((await res.json()).code, "COACH_REQUEST_REPLAY_MISMATCH");
});

async function withClaudeApiKey(fn: () => Promise<void>) {
  Deno.env.set("CLAUDE_API_KEY", "test-key");
  try {
    await fn();
  } finally {
    Deno.env.delete("CLAUDE_API_KEY");
  }
}

Deno.test("POST quota gate failure releases owner-bound claim", async () => {
  await withClaudeApiKey(async () => {
    const fake = buildLedgerClientFake({
      sub: freshSubRow({
        monthly_messages_used: 100000,
        daily_messages_used: 100000,
      }),
    });
    const res = await handleRequest(ledgerPostRequest(ledgerBody), {
      supabase: fake.client,
      replayHmacKey: STRONG_HMAC_KEY,
    });
    assertEquals(res.status, 429);
    const body = await res.json();
    assertEquals(body.code, "QUOTA_EXCEEDED");
    assertEquals(body.safeToClear, true);
    assertEquals(
      fake.rpcCalls.map((call) => call.fn),
      ["claim_coach_request", "release_coach_claim"],
    );
  });
});

Deno.test("POST model rate limited releases owner-bound claim", async () => {
  await withClaudeApiKey(async () => {
    const fake = buildLedgerClientFake({
      rpcHandlers: {
        increment_model_usage: () => ({
          data: null,
          error: { message: "P0001: MODEL_RATE_LIMITED_MINUTE" },
        }),
      },
    });
    const res = await handleRequest(ledgerPostRequest(ledgerBody), {
      supabase: fake.client,
      replayHmacKey: STRONG_HMAC_KEY,
    });
    assertEquals(res.status, 429);
    const body = await res.json();
    assertEquals(body.safeToClear, true);
    assertEquals(
      fake.rpcCalls.map((call) => call.fn),
      ["claim_coach_request", "increment_model_usage", "release_coach_claim"],
    );
  });
});

Deno.test("POST ledger path with missing CLAUDE_API_KEY fails before claim", async () => {
  // F3：config 缺失絕不能發生在 claim 之後（會留 pending 卡 90 秒）。
  const fake = buildLedgerClientFake({});
  const res = await handleRequest(ledgerPostRequest(ledgerBody), {
    supabase: fake.client,
    replayHmacKey: STRONG_HMAC_KEY,
  });
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "config_missing");
  assertEquals(
    fake.rpcCalls.some((call) => call.fn === "claim_coach_request"),
    false,
  );
});

Deno.test("POST streaming replay emits exactly one coach.done", async () => {
  const fake = buildLedgerClientFake({
    replayRow: {
      input_hash: await ledgerInputHash(),
      state: "done",
      lease_expires_at: "2026-07-21T11:01:00.000Z",
      result_json: storedLedgerResult,
    },
  });
  const res = await handleRequest(
    ledgerPostRequest(ledgerBody, { Accept: "application/x-ndjson" }),
    { supabase: fake.client, replayHmacKey: STRONG_HMAC_KEY },
  );
  assertEquals(res.status, 200);
  const lines = (await res.text()).trim().split("\n").map((line) =>
    JSON.parse(line)
  );
  assertEquals(lines.length, 1);
  assertEquals(lines[0].type, "coach.done");
  assertEquals(lines[0].result, storedLedgerResult);
});

Deno.test("POST without requestId never touches the ledger", async () => {
  const fake = buildLedgerClientFake({});
  const { requestId: _omitted, ...legacyBody } = ledgerBody;
  const res = await handleRequest(ledgerPostRequest(legacyBody), {
    supabase: fake.client,
    replayHmacKey: "",
  });
  // 測試環境無 CLAUDE_API_KEY：走到模型前的 config gate 即停，
  // 重點是全程零帳本符號（無 coach_requests 讀、無 claim）。
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "config_missing");
  assertEquals(fake.tablesTouched.includes("coach_requests"), false);
  assertEquals(
    fake.rpcCalls.some((call) => call.fn === "claim_coach_request"),
    false,
  );
});

Deno.test({
  name: "index preserves preflight, claim, gate, renew, settle ordering",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const auth = source.indexOf("supabase.auth.getUser");
    const validate = source.indexOf("validateRequest(rawBody)");
    const preflight = source.indexOf('.from("coach_requests")');
    const subscription = source.indexOf(
      "let sub = await fetchSubscription(supabase",
    );
    const entitlementGate = source.indexOf("let gate = checkQuota({");
    const claim = source.indexOf("const claim = await claimCoachRequest({");
    const terminalQuotaGate = source.indexOf("if (!gate.ok) {", claim);
    const rateGate = source.indexOf(
      "const rateVerdict = await enforceModelRateLimit({",
    );
    const renewal = source.indexOf("const renewal = await claimCoachRequest({");
    const streamBranch = source.indexOf(
      "coachProgressStreamResponse(runGenerationWithLedger",
    );
    assert(auth >= 0 && validate > auth && preflight > validate);
    assert(subscription > preflight && entitlementGate > subscription);
    assert(claim > entitlementGate && terminalQuotaGate > claim);
    assert(rateGate > terminalQuotaGate && renewal > rateGate);
    assert(streamBranch > renewal);
    // settlement 失敗絕不 release：settleResult 閉包內不得出現 release。
    const settleStart = source.indexOf("settleResult:");
    const settleEnd = source.indexOf("logger:", settleStart);
    assert(settleStart >= 0 && settleEnd > settleStart);
    assert(
      !source.slice(settleStart, settleEnd).includes("releaseCurrentClaim"),
    );
    assert(source.includes("settleCoachRequest({"));
    assert(source.includes('"COACH_CLAIM_RENEW_RETRYABLE"'));
    assert(source.includes('"COACH_CLAIM_RELEASE_RETRYABLE"'));
    assert(source.includes('"COACH_SETTLEMENT_RETRYABLE"'));
    // F3：帳本路徑的 CLAUDE_API_KEY 守門必須在 claim 之前。
    const apiKeyGuard = source.indexOf("requestId !== null && !apiKey");
    assert(apiKeyGuard >= 0 && apiKeyGuard < claim);
    // F2：settle-time quota 429（無 code）→ release＋QUOTA_EXCEEDED metadata。
    const settleQuotaRelease = source.indexOf(
      "result.status === 429 &&",
    );
    const settleQuotaMetadata = source.indexOf(
      'code: "QUOTA_EXCEEDED", safeToClear: true',
      settleQuotaRelease,
    );
    assert(settleQuotaRelease >= 0 && settleQuotaMetadata > settleQuotaRelease);
    assert(
      source.slice(settleQuotaRelease, settleQuotaMetadata).includes(
        "releaseCurrentClaim",
      ),
    );
    // F1：settle 回應必須用 ledger 權威 result。
    assert(source.includes("body: settlement"));
  },
});
