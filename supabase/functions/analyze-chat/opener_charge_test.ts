// supabase/functions/analyze-chat/opener_charge_test.ts
//
// opener 扣費 idempotency 純 helper 契約（設計文件：
// docs/plans/2026-07-03-opener-idempotency-design.md）。
// DB 語義（ON CONFLICT 去重、RAISE rollback 連 ledger 一起回滾）在 migration，
// 由 prod SQL 實測＋Codex 雙審把關；這裡只測 Edge 側的路由與結果分類。

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  chargeOpenerQuota,
  isValidOpenerRequestId,
  type OpenerChargeRpc,
} from "./opener_charge.ts";

// ---------------------------------------------------------------------------
// isValidOpenerRequestId — 只收 canonical UUID（8-4-4-4-12 hex）
// 舊 client 不帶、或帶了怪形狀 → 一律走舊路（I3 fail-open 相容）
// ---------------------------------------------------------------------------

Deno.test("isValidOpenerRequestId accepts canonical UUID (lower/upper)", () => {
  assert(isValidOpenerRequestId("123e4567-e89b-42d3-a456-426614174000"));
  assert(isValidOpenerRequestId("123E4567-E89B-42D3-A456-426614174000"));
});

Deno.test("isValidOpenerRequestId rejects non-UUID shapes", () => {
  assertFalse(isValidOpenerRequestId(undefined));
  assertFalse(isValidOpenerRequestId(null));
  assertFalse(isValidOpenerRequestId(42));
  assertFalse(isValidOpenerRequestId(""));
  assertFalse(isValidOpenerRequestId("not-a-uuid"));
  // 少一段
  assertFalse(isValidOpenerRequestId("123e4567-e89b-42d3-a456"));
  // 無 dash 的 32 hex 不收（只收 canonical）
  assertFalse(isValidOpenerRequestId("123e4567e89b42d3a456426614174000"));
  // 前後空白不收（client 自己就該送乾淨的）
  assertFalse(
    isValidOpenerRequestId(" 123e4567-e89b-42d3-a456-426614174000"),
  );
  // 超長（塞尾巴）不收
  assertFalse(
    isValidOpenerRequestId("123e4567-e89b-42d3-a456-426614174000ff"),
  );
});

// ---------------------------------------------------------------------------
// chargeOpenerQuota — RPC 路由與 outcome 分類
// ---------------------------------------------------------------------------

type RpcCall = { fn: string; params: Record<string, unknown> };

function makeRpc(
  result: { data: unknown; error: { message?: string } | null },
  calls: RpcCall[],
): OpenerChargeRpc {
  return (fn, params) => {
    calls.push({ fn, params });
    return Promise.resolve(result);
  };
}

const BASE = {
  userId: "user-1",
  cost: 3,
  monthlyLimit: 100,
  dailyLimit: 10,
};

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";

Deno.test("valid requestId routes to increment_usage_idempotent with exact params", async () => {
  const calls: RpcCall[] = [];
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({ data: true, error: null }, calls),
    requestId: REQUEST_ID,
  });

  assertEquals(outcome, { kind: "charged", idempotent: true });
  assertEquals(calls, [{
    fn: "increment_usage_idempotent",
    params: {
      p_user_id: "user-1",
      p_messages: 3,
      p_monthly_limit: 100,
      p_daily_limit: 10,
      p_request_id: REQUEST_ID,
    },
  }]);
});

Deno.test("rpc returning false means already charged → dedup (not an error)", async () => {
  const calls: RpcCall[] = [];
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({ data: false, error: null }, calls),
    requestId: REQUEST_ID,
  });

  assertEquals(outcome, { kind: "dedup" });
});

Deno.test("missing requestId falls back to legacy increment_usage (byte-for-byte old params)", async () => {
  const calls: RpcCall[] = [];
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({ data: null, error: null }, calls),
    requestId: null,
  });

  assertEquals(outcome, { kind: "charged", idempotent: false });
  assertEquals(calls, [{
    fn: "increment_usage",
    params: {
      p_user_id: "user-1",
      p_messages: 3,
      p_monthly_limit: 100,
      p_daily_limit: 10,
    },
  }]);
});

Deno.test("quota RAISE maps to quota_exceeded on idempotent path", async () => {
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({
      data: null,
      error: { message: "P0001: QUOTA_EXCEEDED_MONTHLY" },
    }, []),
    requestId: REQUEST_ID,
  });

  assertEquals(outcome, {
    kind: "quota_exceeded",
    reason: "monthly_limit_exceeded",
  });
});

Deno.test("quota RAISE maps to quota_exceeded on legacy path", async () => {
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({
      data: null,
      error: { message: "P0001: QUOTA_EXCEEDED_DAILY" },
    }, []),
    requestId: null,
  });

  assertEquals(outcome, {
    kind: "quota_exceeded",
    reason: "daily_limit_exceeded",
  });
});

Deno.test("non-quota rpc error maps to failed with message", async () => {
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({
      data: null,
      error: { message: "connection reset" },
    }, []),
    requestId: REQUEST_ID,
  });

  assertEquals(outcome, { kind: "failed", message: "connection reset" });
});

Deno.test("rpc error without message still maps to failed (non-empty message)", async () => {
  const outcome = await chargeOpenerQuota({
    ...BASE,
    rpc: makeRpc({ data: null, error: {} }, []),
    requestId: REQUEST_ID,
  });

  assertEquals(outcome.kind, "failed");
  if (outcome.kind === "failed") {
    assert(outcome.message.length > 0);
  }
});
