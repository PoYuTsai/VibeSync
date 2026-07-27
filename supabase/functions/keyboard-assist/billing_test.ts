import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  claimKeyboardAssistRequest,
  classifyKeyboardAssistReplayPreflight,
  classifyKeyboardAssistStatus,
  computeKeyboardAssistInputHash,
  hasAllKeyboardAssistHmacVersions,
  isStrongKeyboardAssistHmacKey,
  KEYBOARD_ASSIST_COST,
  KEYBOARD_ASSIST_HMAC_KEY_RETENTION_MS,
  type KeyboardAssistRpc,
  releaseKeyboardAssistClaim,
  renewKeyboardAssistClaim,
  resolveKeyboardAssistHmacKey,
  settleKeyboardAssistRequest,
} from "./billing.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const OWNER_TOKEN = "223e4567-e89b-42d3-a456-426614174000";
const KEY_V1 = btoa("0123456789abcdef0123456789abcdef");
const KEY_V2 = btoa("abcdef0123456789abcdef0123456789");
const readyResult = {
  contractVersion: "keyboard-assist-v1" as const,
  status: "ready" as const,
  source: {
    scope: "screenshot_only" as const,
    messageCount: 2,
    confidence: "high" as const,
    sideConfidence: "high" as const,
  },
  turnState: "reply_due" as const,
  cue: "輪到你回覆。",
  uncertainty: null,
  options: [
    {
      strategy: "keep_pace" as const,
      text: "好啊，那你比較想去哪裡？",
      why: "接住畫面中的邀約",
      effect: "自然延續",
    },
    {
      strategy: "build_connection" as const,
      text: "你這樣講，我開始有點期待了 😄",
      why: "回應對方的正向語氣",
      effect: "增加互動溫度",
    },
    {
      strategy: "move_forward" as const,
      text: "那就週六？我下午比較方便",
      why: "把邀約落到時間",
      effect: "直接推進安排",
    },
  ],
};

Deno.test("keyboard assist HMAC binds payload but excludes pipeline version", async () => {
  const base = {
    userId: "user-1",
    imageBytes: new Uint8Array([1, 2, 3]),
    mediaType: "image/png" as const,
    speakerOverride: "none" as const,
    voice: { primary: "steady" as const, secondary: null },
    priorTurn: null,
    secret: KEY_V1,
  };
  const first = await computeKeyboardAssistInputHash(
    {
      ...base,
      pipelineVersion: "compiler-judge-v1",
    } as typeof base,
  );
  const upgraded = await computeKeyboardAssistInputHash(
    {
      ...base,
      pipelineVersion: "compiler-judge-v2",
    } as typeof base,
  );
  assertEquals(first, upgraded);
  assertEquals(first.length, 64);
  assert(
    first !==
      await computeKeyboardAssistInputHash({
        ...base,
        imageBytes: new Uint8Array([1, 2, 4]),
      }),
  );
  assert(
    first !==
      await computeKeyboardAssistInputHash({
        ...base,
        speakerOverride: "left_is_me",
      }),
  );
  assert(
    first !==
      await computeKeyboardAssistInputHash({
        ...base,
        voice: { primary: "gentle", secondary: null },
      }),
  );
});

Deno.test("keyboard assist key rotation follows the stored ledger version", () => {
  assertEquals(KEYBOARD_ASSIST_HMAC_KEY_RETENTION_MS, 25 * 60 * 60 * 1000);
  assert(isStrongKeyboardAssistHmacKey(KEY_V1));
  assertFalse(isStrongKeyboardAssistHmacKey("short"));
  const keyring = {
    currentVersion: 2,
    keys: new Map([[1, KEY_V1], [2, KEY_V2]]),
  };
  assertEquals(resolveKeyboardAssistHmacKey(null, keyring), {
    version: 2,
    secret: KEY_V2,
  });
  assertEquals(resolveKeyboardAssistHmacKey({ hmac_key_version: 1 }, keyring), {
    version: 1,
    secret: KEY_V1,
  });
  assertEquals(
    resolveKeyboardAssistHmacKey(
      { hmac_key_version: 1 },
      { currentVersion: 2, keys: new Map([[2, KEY_V2]]) },
    ),
    null,
  );
  assertEquals(hasAllKeyboardAssistHmacVersions([1, 2], keyring), true);
  assertEquals(
    hasAllKeyboardAssistHmacVersions(
      [1],
      { currentVersion: 2, keys: new Map([[2, KEY_V2]]) },
    ),
    false,
  );
});

Deno.test("replay preflight handles done, pending, mismatch, and corrupt rows", () => {
  const now = new Date("2026-07-27T12:00:00.000Z");
  const row = {
    input_hash: "a".repeat(64),
    hmac_key_version: 1,
    state: "done" as const,
    lease_expires_at: "2026-07-27T12:00:55.000Z",
    created_at: "2026-07-27T11:00:00.000Z",
    result_json: readyResult,
  };
  assertEquals(
    classifyKeyboardAssistReplayPreflight(null, "a".repeat(64), now),
    { kind: "fresh" },
  );
  assertEquals(
    classifyKeyboardAssistReplayPreflight(row, "b".repeat(64), now),
    { kind: "mismatch" },
  );
  assertEquals(
    classifyKeyboardAssistReplayPreflight(row, "a".repeat(64), now),
    { kind: "replay", result: readyResult },
  );
  assertEquals(
    classifyKeyboardAssistReplayPreflight(
      {
        ...row,
        state: "pending",
        result_json: null,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "pending", retryAfterMs: 55_000 },
  );
  assertEquals(
    classifyKeyboardAssistReplayPreflight(
      {
        ...row,
        result_json: {
          ...readyResult,
          transcript: "private",
        } as unknown as typeof readyResult,
      },
      "a".repeat(64),
      now,
    ),
    { kind: "mismatch" },
  );
});

Deno.test("image-free status classifies owner-scoped rows without HMAC", () => {
  const now = new Date("2026-07-27T12:00:00.000Z");
  assertEquals(classifyKeyboardAssistStatus(null, now), { kind: "missing" });
  assertEquals(
    classifyKeyboardAssistStatus({
      state: "done",
      lease_expires_at: "2026-07-27T11:59:00.000Z",
      created_at: "2026-07-27T11:00:00.000Z",
      result_json: readyResult,
    }, now),
    { kind: "done", result: readyResult },
  );
  assertEquals(
    classifyKeyboardAssistStatus({
      state: "pending",
      lease_expires_at: "2026-07-27T12:00:02.000Z",
      created_at: "2026-07-27T11:00:00.000Z",
      result_json: null,
    }, now),
    { kind: "pending", retryAfterMs: 2000 },
  );
  assertEquals(
    classifyKeyboardAssistStatus({
      state: "pending",
      lease_expires_at: "2026-07-27T11:59:59.000Z",
      created_at: "2026-07-27T11:00:00.000Z",
      result_json: null,
    }, now),
    { kind: "expired" },
  );
  assertEquals(
    classifyKeyboardAssistStatus({
      state: "done",
      lease_expires_at: "2026-07-27T11:59:00.000Z",
      created_at: "2026-07-26T11:59:59.000Z",
      result_json: readyResult,
    }, now),
    { kind: "missing" },
  );
});

function rpcReturning(
  response: Awaited<ReturnType<KeyboardAssistRpc>>,
  calls: Array<Record<string, unknown>>,
): KeyboardAssistRpc {
  return (fn, params) => {
    calls.push({ fn, params });
    return Promise.resolve(response);
  };
}

Deno.test("claim and renew bind owner, hash, and HMAC key version", async () => {
  const calls: Array<Record<string, unknown>> = [];
  assertEquals(KEYBOARD_ASSIST_COST, 1);
  assertEquals(
    await claimKeyboardAssistRequest({
      rpc: rpcReturning({ data: { kind: "claimed" }, error: null }, calls),
      userId: "user-1",
      requestId: REQUEST_ID,
      inputHash: "a".repeat(64),
      hmacKeyVersion: 7,
      ownerToken: OWNER_TOKEN,
    }),
    { kind: "claimed" },
  );
  assertEquals(calls[0], {
    fn: "claim_keyboard_assist_request",
    params: {
      p_user_id: "user-1",
      p_request_id: REQUEST_ID,
      p_input_hash: "a".repeat(64),
      p_hmac_key_version: 7,
      p_owner_token: OWNER_TOKEN,
    },
  });
  assertEquals(
    await renewKeyboardAssistClaim({
      rpc: rpcReturning({ data: true, error: null }, calls),
      userId: "user-1",
      requestId: REQUEST_ID,
      inputHash: "a".repeat(64),
      ownerToken: OWNER_TOKEN,
    }),
    true,
  );
  assertEquals(calls[1].fn, "renew_keyboard_assist_claim");
});

Deno.test("speaker confirmation settles done with explicitly zero charge", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const confirmation = {
    contractVersion: "keyboard-assist-v1" as const,
    status: "needs_speaker_confirmation" as const,
    suggestedMySide: "right" as const,
    sideConfidence: "low" as const,
  };
  assertEquals(
    await settleKeyboardAssistRequest({
      rpc: rpcReturning({
        data: { charged: false, result: confirmation },
        error: null,
      }, calls),
      userId: "user-1",
      requestId: REQUEST_ID,
      inputHash: "a".repeat(64),
      ownerToken: OWNER_TOKEN,
      result: confirmation,
      monthlyLimit: 800,
      dailyLimit: 80,
      chargeQuota: false,
    }),
    { kind: "settled", charged: false, result: confirmation },
  );
  assertEquals(
    (calls[0].params as Record<string, unknown>).p_charge_quota,
    false,
  );
  assertFalse(JSON.stringify(calls[0]).includes("transcript"));
});

Deno.test("release stays owner-bound and settlement ambiguity is preserved", async () => {
  const calls: Array<Record<string, unknown>> = [];
  assertEquals(
    await releaseKeyboardAssistClaim({
      rpc: rpcReturning({ data: true, error: null }, calls),
      userId: "user-1",
      requestId: REQUEST_ID,
      inputHash: "a".repeat(64),
      ownerToken: OWNER_TOKEN,
    }),
    true,
  );
  assertEquals(calls[0].fn, "release_keyboard_assist_claim");
  assertEquals(
    await settleKeyboardAssistRequest({
      rpc: rpcReturning({
        data: null,
        error: { message: "connection reset", code: "08006" },
      }, calls),
      userId: "user-1",
      requestId: REQUEST_ID,
      inputHash: "a".repeat(64),
      ownerToken: OWNER_TOKEN,
      result: readyResult,
      monthlyLimit: 800,
      dailyLimit: 80,
      chargeQuota: true,
    }),
    { kind: "uncertain", message: "connection reset" },
  );
});
