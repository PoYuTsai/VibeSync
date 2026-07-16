import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  classifyKeyboardReplyReplayPreflight,
  computeKeyboardReplyInputHash,
  isValidKeyboardReplyLedgerResult,
  isValidKeyboardReplyRequestId,
  KEYBOARD_REPLY_COST,
  keyboardReplyReplayCutoffIso,
  type KeyboardReplyRpc,
  settleKeyboardReplyRequest,
} from "./billing.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const result = {
  reply: "今天真的辛苦了，晚點想怎麼充電？",
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

Deno.test("keyboard reply hash binds normalized message and style", async () => {
  const first = await computeKeyboardReplyInputHash({
    message: "今天好累",
    style: "resonate",
  });
  const same = await computeKeyboardReplyInputHash({
    message: "今天好累",
    style: "resonate",
  });
  const changed = await computeKeyboardReplyInputHash({
    message: "今天好累",
    style: "humor",
  });
  assertEquals(first, same);
  assertEquals(first.length, 64);
  assert(first !== changed);
});

Deno.test("keyboard replay preflight returns cached result or mismatch", () => {
  assertEquals(classifyKeyboardReplyReplayPreflight(null, "a".repeat(64)), {
    kind: "fresh",
  });
  assertEquals(
    classifyKeyboardReplyReplayPreflight({
      input_hash: "b".repeat(64),
      result_json: result,
    }, "a".repeat(64)),
    { kind: "mismatch" },
  );
  assertEquals(
    classifyKeyboardReplyReplayPreflight({
      input_hash: "a".repeat(64),
      result_json: result,
    }, "a".repeat(64)),
    { kind: "replay", result },
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
  result,
  monthlyLimit: 800,
  dailyLimit: 80,
  chargeQuota: true,
};

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
      p_result_json: result,
      p_monthly_limit: 800,
      p_daily_limit: 80,
      p_charge_quota: true,
    },
  });
});

Deno.test("keyboard settlement replays without charging and maps quota races", async () => {
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
});

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260717120000_keyboard_reply_exactly_once.sql",
    import.meta.url,
  ),
);

Deno.test("keyboard migration atomically inserts ledger before quota increment", () => {
  const insert = migrationSource.indexOf(
    "INSERT INTO public.keyboard_reply_requests",
  );
  const increment = migrationSource.indexOf("PERFORM public.increment_usage");
  assert(insert >= 0 && increment > insert);
  assert(migrationSource.includes("PRIMARY KEY (user_id, request_id)"));
  assert(migrationSource.includes("result_json = jsonb_build_object("));
  assert(
    migrationSource.includes("jsonb_typeof(result_json -> 'style') = 'string'"),
  );
  assert(
    migrationSource.includes(
      "NULLIF(btrim(result_json ->> 'reply'), '') IS NOT NULL",
    ),
  );
  assert(migrationSource.includes("interval '24 hours'"));
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.keyboard_reply_requests FROM anon, authenticated",
    ),
  );
});
