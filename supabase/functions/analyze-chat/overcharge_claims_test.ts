// ADR #19 定案 #5 idempotency claim 測試。
//
// 不變量：
//   I1 同一 (user, confirmationId) 只有第一次 claim 回 "claimed"（會扣費），
//      之後同 payload 重送回 "replay"（絕不重扣 20）。
//   I2 同 confirmationId 但 payload hash 不同 → "mismatch"（絕不拿舊確認
//      扣新內容；caller 回新的 confirmation_required）。
//   I3 真正的原子性 / TTL 在 Postgres RPC `claim_overcharge_confirmation`
//      內（migration 20260611*_adr19_overcharge_confirmations.sql）；
//      本檔測 TS 層 wrapper 的輸入防護與結果映射。
import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createSupabaseOverchargeClaimDriver,
  OverchargeClaimStore,
} from "./overcharge_claims.ts";

const VALID_INPUT = {
  userId: "00000000-0000-4000-8000-000000000001",
  confirmationId: "c-1",
  payloadHash: "a".repeat(64),
  billableChars: 2500,
  chargedUnits: 20,
};

function fakeDriver(result: string) {
  return {
    claim: () => Promise.resolve(result as never),
  };
}

Deno.test("claim store: passes through driver verdicts", async () => {
  for (const verdict of ["claimed", "replay", "mismatch", "expired"]) {
    const store = new OverchargeClaimStore(fakeDriver(verdict));
    assertEquals(await store.claim(VALID_INPUT), verdict);
  }
});

Deno.test("claim store: rejects malformed input before hitting DB", async () => {
  const store = new OverchargeClaimStore(fakeDriver("claimed"));
  await assertRejects(() =>
    store.claim({ ...VALID_INPUT, confirmationId: "" })
  );
  await assertRejects(() => store.claim({ ...VALID_INPUT, chargedUnits: 0 }));
  await assertRejects(() =>
    store.claim({ ...VALID_INPUT, billableChars: -5 })
  );
  await assertRejects(() =>
    store.claim({ ...VALID_INPUT, payloadHash: "abc" })
  );
});

Deno.test("supabase driver: maps rpc data to verdict", async () => {
  const calls: unknown[] = [];
  const driver = createSupabaseOverchargeClaimDriver({
    rpc(fn: string, args: unknown) {
      calls.push([fn, args]);
      return Promise.resolve({ data: "replay", error: null });
    },
  });
  assertEquals(await driver.claim(VALID_INPUT), "replay");
  assertEquals(calls.length, 1);
  const [fn, args] = calls[0] as [string, Record<string, unknown>];
  assertEquals(fn, "claim_overcharge_confirmation");
  assertEquals(args.p_user_id, VALID_INPUT.userId);
  assertEquals(args.p_confirmation_id, VALID_INPUT.confirmationId);
  assertEquals(args.p_payload_hash, VALID_INPUT.payloadHash);
  assertEquals(args.p_billable_chars, VALID_INPUT.billableChars);
  assertEquals(args.p_charged_units, VALID_INPUT.chargedUnits);
});

Deno.test("supabase driver: rpc error → throws (caller fails closed, 不扣費)", async () => {
  const driver = createSupabaseOverchargeClaimDriver({
    rpc() {
      return Promise.resolve({ data: null, error: { message: "boom" } });
    },
  });
  await assertRejects(() => driver.claim(VALID_INPUT));
});

Deno.test("supabase driver: unexpected verdict → throws (fail closed)", async () => {
  const driver = createSupabaseOverchargeClaimDriver({
    rpc() {
      return Promise.resolve({ data: "what", error: null });
    },
  });
  await assertRejects(() => driver.claim(VALID_INPUT));
});
