import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  claimKeyboardReplyRequest,
  classifyKeyboardReplyReplayPreflight,
  computeKeyboardReplyInputHash,
  isStrongKeyboardReplayHmacKey,
  isValidKeyboardReplyLedgerResult,
  KEYBOARD_REPLY_COST,
  keyboardReplyReplayCutoffIso,
  type KeyboardReplyRpc,
  releaseKeyboardReplyClaim,
  settleKeyboardReplyRequest,
} from "./billing.ts";
import {
  isValidKeyboardReplyRequestId,
  KEYBOARD_REPLY_STYLES,
} from "./contract.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const OWNER_TOKEN = "223e4567-e89b-42d3-a456-426614174000";
const HMAC_KEY = btoa("0123456789abcdef0123456789abcdef");
const result = {
  reply: "這樣聽起來真的很不容易。",
  style: "resonate" as const,
};

Deno.test("keyboard reply identity, cost, and replay window are fixed", () => {
  assertEquals(KEYBOARD_REPLY_COST, 1);
  assert(isValidKeyboardReplyRequestId(REQUEST_ID));
  assertFalse(isValidKeyboardReplyRequestId("not-a-uuid"));
  assertEquals(
    keyboardReplyReplayCutoffIso(new Date("2026-07-17T12:00:00.000Z")),
    "2026-07-16T12:00:00.000Z",
  );
});

Deno.test("keyboard reply HMAC binds user, normalized message, and style", async () => {
  const first = await computeKeyboardReplyInputHash({
    userId: "user-1",
    message: "你好嗎",
    style: "resonate",
    secret: HMAC_KEY,
  });
  const same = await computeKeyboardReplyInputHash({
    userId: "user-1",
    message: "你好嗎",
    style: "resonate",
    secret: HMAC_KEY,
  });
  const changed = await computeKeyboardReplyInputHash({
    userId: "user-1",
    message: "你好嗎",
    style: "humor",
    secret: HMAC_KEY,
  });
  const changedSecret = await computeKeyboardReplyInputHash({
    userId: "user-1",
    message: "你好嗎",
    style: "resonate",
    secret: btoa("abcdef0123456789abcdef0123456789"),
  });
  const changedUser = await computeKeyboardReplyInputHash({
    userId: "user-2",
    message: "你好嗎",
    style: "resonate",
    secret: HMAC_KEY,
  });
  assertEquals(first, same);
  assertEquals(first.length, 64);
  assert(first !== changed);
  assert(first !== changedSecret);
  assert(first !== changedUser);
  assert(isStrongKeyboardReplayHmacKey(HMAC_KEY));
  assertFalse(isStrongKeyboardReplayHmacKey("short-secret"));
});

Deno.test("keyboard replay preflight distinguishes done, pending, and stale lease", () => {
  const now = new Date("2026-07-17T12:00:00.000Z");
  assertEquals(
    classifyKeyboardReplyReplayPreflight(null, "a".repeat(64), now),
    {
      kind: "fresh",
    },
  );
  assertEquals(
    classifyKeyboardReplyReplayPreflight(
      {
        input_hash: "b".repeat(64),
        state: "done",
        lease_expires_at: "2026-07-17T12:01:00.000Z",
        result_json: result,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "mismatch" },
  );
  assertEquals(
    classifyKeyboardReplyReplayPreflight(
      {
        input_hash: "a".repeat(64),
        state: "done",
        lease_expires_at: "2026-07-17T12:01:00.000Z",
        result_json: result,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "replay", result },
  );
  assertEquals(
    classifyKeyboardReplyReplayPreflight(
      {
        input_hash: "a".repeat(64),
        state: "pending",
        lease_expires_at: "2026-07-17T12:00:45.000Z",
        result_json: null,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "pending", retryAfterMs: 45_000 },
  );
  assertEquals(
    classifyKeyboardReplyReplayPreflight(
      {
        input_hash: "a".repeat(64),
        state: "pending",
        lease_expires_at: "2026-07-17T11:59:59.000Z",
        result_json: null,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "fresh" },
  );
});

Deno.test("keyboard ledger accepts only minimal valid reply shape", () => {
  assert(isValidKeyboardReplyLedgerResult(result));
  assertFalse(
    isValidKeyboardReplyLedgerResult({ ...result, message: "private input" }),
  );
  assertFalse(
    isValidKeyboardReplyLedgerResult({ reply: "", style: "resonate" }),
  );
  assertFalse(
    isValidKeyboardReplyLedgerResult({ reply: "ok", style: "unknown" }),
  );
});

function rpcReturning(
  response: Awaited<ReturnType<KeyboardReplyRpc>>,
  calls: Array<Record<string, unknown>> = [],
): KeyboardReplyRpc {
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

Deno.test("keyboard claim serializes generation ownership", async () => {
  const calls: Array<Record<string, unknown>> = [];
  assertEquals(
    await claimKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({ data: { kind: "claimed" }, error: null }, calls),
    }),
    { kind: "claimed" },
  );
  assertEquals(calls[0], {
    fn: "claim_keyboard_reply_request",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_owner_token: OWNER_TOKEN,
    },
  });
  assertEquals(
    await claimKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({
        data: { kind: "pending", retryAfterMs: 1200.2 },
        error: null,
      }),
    }),
    { kind: "pending", retryAfterMs: 1201 },
  );
  assertEquals(
    await claimKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({ data: { kind: "replay", result }, error: null }),
    }),
    { kind: "replay", result },
  );
});

Deno.test("keyboard claim release is owner-bound and fail-closed", async () => {
  const calls: Array<Record<string, unknown>> = [];
  assertEquals(
    await releaseKeyboardReplyClaim({
      ...base,
      rpc: rpcReturning({ data: true, error: null }, calls),
    }),
    true,
  );
  assertEquals(calls[0], {
    fn: "release_keyboard_reply_claim",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_owner_token: OWNER_TOKEN,
    },
  });
  assertEquals(
    await releaseKeyboardReplyClaim({
      ...base,
      rpc: rpcReturning({ data: false, error: null }),
    }),
    false,
  );
  assertEquals(
    await releaseKeyboardReplyClaim({
      ...base,
      rpc: rpcReturning({ data: null, error: { message: "timeout" } }),
    }),
    false,
  );
  assertEquals(
    await releaseKeyboardReplyClaim({
      ...base,
      rpc: () => {
        throw new Error("network down");
      },
    }),
    false,
  );
});

Deno.test("keyboard settlement stores and charges atomically", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const settled = await settleKeyboardReplyRequest({
    ...base,
    rpc: rpcReturning({ data: { charged: true, result }, error: null }, calls),
  });
  assertEquals(settled, { kind: "settled", charged: true, result });
  assertEquals(calls[0], {
    fn: "settle_keyboard_reply_request",
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

Deno.test("keyboard settlement replays and maps quota races", async () => {
  assertEquals(
    await settleKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({ data: { charged: false, result }, error: null }),
    }),
    { kind: "settled", charged: false, result },
  );
  assertEquals(
    await settleKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "P0001: QUOTA_EXCEEDED_DAILY" },
      }),
    }),
    { kind: "quota_exceeded", reason: "daily_limit_exceeded" },
  );
});

Deno.test("keyboard settlement preserves ambiguous failures for same-id retry", async () => {
  assertEquals(
    await settleKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({ data: null, error: { message: "connection reset" } }),
    }),
    { kind: "retryable", message: "connection reset" },
  );
  assertEquals(
    await settleKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH" },
      }),
    }),
    { kind: "mismatch" },
  );
  assertEquals(
    await settleKeyboardReplyRequest({
      ...base,
      rpc: rpcReturning({
        data: null,
        error: { message: "KEYBOARD_REPLY_REQUEST_OWNER_MISMATCH" },
      }),
    }),
    { kind: "retryable", message: "keyboard reply lease ownership changed" },
  );
});

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260717120000_keyboard_reply_exactly_once.sql",
    import.meta.url,
  ),
);

Deno.test("keyboard migration owns claim, settlement, retention, and privacy", () => {
  const claim = migrationSource.indexOf("claim_keyboard_reply_request");
  const increment = migrationSource.indexOf("PERFORM public.increment_usage");
  const settle = migrationSource.indexOf("settle_keyboard_reply_request");
  assert(claim >= 0 && settle > claim && increment > settle);
  assert(migrationSource.includes("PRIMARY KEY (user_id, request_id)"));
  assert(
    migrationSource.includes(
      "state = 'done'\n      AND result_json IS NOT NULL",
    ),
  );
  assert(migrationSource.includes("result_json = jsonb_build_object("));
  assert(migrationSource.includes("KEYBOARD_REPLY_REQUEST_OWNER_MISMATCH"));
  assert(migrationSource.includes("release_keyboard_reply_claim"));
  assert(migrationSource.includes("AND owner_token = p_owner_token"));
  assert(migrationSource.includes("AND state = 'pending'"));
  assert(migrationSource.includes("SET lease_expires_at = v_lease_expires_at"));
  assert(migrationSource.includes("keyboard_reply_contract_version"));
  assert(migrationSource.includes("interval '24 hours'"));
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.keyboard_reply_requests FROM anon, authenticated",
    ),
  );
});

Deno.test("keyboard reply styles stay synchronized across TS, Swift, and SQL", async () => {
  const swiftSource = await Deno.readTextFile(
    new URL("../../../ios/VibeSyncKeyboard/KeyboardAPI.swift", import.meta.url),
  );
  const swiftCaseLine = swiftSource.match(
    /case\s+extend,\s*resonate,\s*tease,\s*humor,\s*coldRead/,
  );
  assert(swiftCaseLine !== null);
  const swiftStyles = swiftCaseLine[0]
    .replace(/^case\s+/, "")
    .split(",")
    .map((value) => value.trim());
  assertEquals(swiftStyles, [...KEYBOARD_REPLY_STYLES]);

  const tableCheck = migrationSource.match(
    /result_json ->> 'style' IN \(\s*([\s\S]*?)\s*\)/,
  );
  const settlementCheck = migrationSource.match(
    /p_result_json ->> 'style' NOT IN \(\s*([\s\S]*?)\s*\)/,
  );
  assert(tableCheck !== null);
  assert(settlementCheck !== null);
  const extractStyles = (source: string) =>
    [...source.matchAll(/'([^']+)'/g)].map((match) => match[1]);
  assertEquals(extractStyles(tableCheck[1]), [...KEYBOARD_REPLY_STYLES]);
  assertEquals(extractStyles(settlementCheck[1]), [...KEYBOARD_REPLY_STYLES]);
});
