// practice-chat draw_profile handler 測試（mock supabase client 覆蓋 RPC 行為）。
// 跑法：deno test --allow-env supabase/functions/practice-chat/draw_handler_test.ts
//
// 不起 HTTP、不連真 Supabase；以 mock client 注入訂閱列、已抽清單與 RPC 回應，驗證
// handler 對 cost0 / 402 升級 / cost5 / 429 quota / idempotent replay / 撞號重抽 /
// 無訂閱 / 測試帳號免扣 的處理，以及「不需要 DEEPSEEK_API_KEY」。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type DrawSupabaseClient,
  handleDrawProfile,
} from "./draw_handler.ts";
import type { PracticeDrawRequest } from "./validate.ts";

// 固定 now = Taipei 14:00（過中午 → 今日視窗）；sub reset_at 設同一 UTC 日/月 → 不觸發 reset。
const NOW = new Date("2026-06-26T06:00:00.000Z");
const RESET_AT = "2026-06-26T06:00:00.000Z";

function sub(
  tier: string,
  daily = 0,
  monthly = 0,
): Record<string, unknown> {
  return {
    tier,
    monthly_messages_used: monthly,
    daily_messages_used: daily,
    daily_reset_at: RESET_AT,
    monthly_reset_at: RESET_AT,
  };
}

interface MockOpts {
  sub: Record<string, unknown> | null;
  subError?: string;
  drawn?: string[];
  drawnError?: string;
  rpc: Array<{ data?: unknown; error?: string }>;
}

function mockClient(
  opts: MockOpts,
): { client: DrawSupabaseClient; rpcCalls: Array<Record<string, unknown>> } {
  const rpcCalls: Array<Record<string, unknown>> = [];
  let rpcIdx = 0;

  // deno-lint-ignore no-explicit-any
  const client: any = {
    from(_table: string) {
      return {
        select(_cols: string) {
          // builder 同時是 thenable（events 直接 await）與有 maybeSingle（subscriptions）。
          // deno-lint-ignore no-explicit-any
          const builder: any = {
            eq(_c: string, _v: unknown) {
              return builder;
            },
            maybeSingle() {
              return Promise.resolve(
                opts.subError
                  ? { data: null, error: { message: opts.subError } }
                  : { data: opts.sub, error: null },
              );
            },
            // deno-lint-ignore no-explicit-any
            then(onF: any, onR: any) {
              const res = opts.drawnError
                ? { data: null, error: { message: opts.drawnError } }
                : {
                  data: (opts.drawn ?? []).map((id) => ({ profile_id: id })),
                  error: null,
                };
              return Promise.resolve(res).then(onF, onR);
            },
          };
          return builder;
        },
        update(_values: Record<string, unknown>) {
          return {
            eq(_c: string, _v: unknown) {
              return Promise.resolve({ data: null, error: null });
            },
          };
        },
      };
    },
    rpc(_fn: string, params: Record<string, unknown>) {
      rpcCalls.push(params);
      const r = opts.rpc[Math.min(rpcIdx, opts.rpc.length - 1)];
      rpcIdx++;
      return Promise.resolve(
        r.error
          ? { data: null, error: { message: r.error } }
          : { data: r.data ?? null, error: null },
      );
    },
  };

  return { client: client as DrawSupabaseClient, rpcCalls };
}

function req(
  partial: Partial<PracticeDrawRequest> = {},
): PracticeDrawRequest {
  return {
    mode: "draw_profile",
    requestId: "req-1",
    ...partial,
  };
}

function receipt(over: Record<string, unknown> = {}) {
  return {
    profile_id: "practice_girl_007",
    cost_messages: 0,
    free_allowance: 1,
    free_used: 1,
    free_remaining: 0,
    daily_messages_used: 0,
    monthly_messages_used: 0,
    idempotent_replay: false,
    ...over,
  };
}

async function run(
  opts: MockOpts,
  request = req(),
  email: string | null = "user@example.com",
) {
  const { client, rpcCalls } = mockClient(opts);
  const result = await handleDrawProfile({
    supabase: client,
    userId: "u-1",
    userEmail: email,
    request,
    now: NOW,
  });
  // deno-lint-ignore no-explicit-any
  return { result, body: result.body as any, rpcCalls };
}

// ── Free 第一抽 → cost 0 ───────────────────────────────────────────────
Deno.test("Free 第一抽：cost 0，回 profile + draw receipt + usage", async () => {
  const { result, body, rpcCalls } = await run({
    sub: sub("free", 3, 5),
    drawn: [],
    rpc: [{
      data: receipt({
        profile_id: "practice_girl_007",
        daily_messages_used: 3,
        monthly_messages_used: 5,
      }),
    }],
  });
  assertEquals(result.status, 200);
  assertEquals(body.profile.profileId, "practice_girl_007");
  assertEquals(body.profile.photoId, "practice_girl_007");
  assertEquals(body.draw.costMessages, 0);
  assertEquals(body.draw.freeAllowance, 1);
  assertEquals(body.draw.extraCostMessages, 5);
  assertEquals(body.usage.dailyUsed, 3);
  assertEquals(body.usage.dailyLimit, 15);
  // Free：傳給 RPC 的額度/付費旗標正確
  assertEquals(rpcCalls[0].p_free_allowance, 1);
  assertEquals(rpcCalls[0].p_allow_paid_extra, false);
  assertEquals(rpcCalls[0].p_extra_cost, 5);
  assertEquals(rpcCalls[0].p_charge_quota, true);
});

// ── Free 第二抽 → 402 升級 ─────────────────────────────────────────────
Deno.test("Free 免費用完：RPC RAISE upgrade → 402 practice_draw_upgrade_required", async () => {
  const { result, body } = await run({
    sub: sub("free", 3, 5),
    drawn: ["practice_girl_007"],
    rpc: [{ error: "PRACTICE_DRAW_UPGRADE_REQUIRED" }],
  });
  assertEquals(result.status, 402);
  assertEquals(body.error, "practice_draw_upgrade_required");
  assertEquals(body.draw.freeAllowance, 1);
  assertEquals(body.draw.freeRemaining, 0);
  assertEquals(body.draw.extraCostMessages, 5);
  assert(typeof body.draw.nextResetAt === "string");
});

// ── Starter 付費額外抽 → cost 5 ────────────────────────────────────────
Deno.test("Starter 額外抽：cost 5，限額/付費旗標傳給 RPC 正確", async () => {
  const { result, body, rpcCalls } = await run({
    sub: sub("starter", 8, 20),
    drawn: ["a", "b", "c"],
    rpc: [{
      data: receipt({
        profile_id: "practice_girl_010",
        cost_messages: 5,
        free_allowance: 3,
        free_used: 3,
        free_remaining: 0,
        daily_messages_used: 13,
        monthly_messages_used: 25,
      }),
    }],
  });
  assertEquals(result.status, 200);
  assertEquals(body.profile.profileId, "practice_girl_010");
  assertEquals(body.draw.costMessages, 5);
  assertEquals(body.usage.dailyLimit, 50);
  assertEquals(body.usage.monthlyLimit, 300);
  assertEquals(rpcCalls[0].p_free_allowance, 3);
  assertEquals(rpcCalls[0].p_allow_paid_extra, true);
  assertEquals(rpcCalls[0].p_daily_limit, 50);
  assertEquals(rpcCalls[0].p_monthly_limit, 300);
});

// ── 付費額外抽但 quota 不足 → 429 ──────────────────────────────────────
Deno.test("Starter 額外抽 quota 不足：RPC RAISE daily → 429 quota payload", async () => {
  const { result, body } = await run({
    sub: sub("starter", 49, 100),
    drawn: ["a", "b", "c"],
    rpc: [{ error: "PRACTICE_DRAW_QUOTA_EXCEEDED_DAILY" }],
  });
  assertEquals(result.status, 429);
  assertEquals(body.error, "Daily limit exceeded");
  assertEquals(body.dailyLimit, 50);
  assertEquals(body.quotaNeeded, 5);
});

Deno.test("Essential 額外抽 quota 不足：RPC RAISE monthly → 429 monthly payload", async () => {
  const { result, body } = await run({
    sub: sub("essential", 10, 800),
    drawn: ["a", "b", "c", "d", "e"],
    rpc: [{ error: "PRACTICE_DRAW_QUOTA_EXCEEDED_MONTHLY" }],
  });
  assertEquals(result.status, 429);
  assertEquals(body.error, "Monthly limit exceeded");
  assertEquals(body.monthlyLimit, 800);
});

// ── idempotent replay：回原本抽到的那一位 ──────────────────────────────
Deno.test("idempotent replay：RPC 回原 profile_id → 回應用 receipt 的人，不是本地重選", async () => {
  const { result, body } = await run({
    sub: sub("starter", 0, 0),
    drawn: [],
    rpc: [{
      data: receipt({
        profile_id: "practice_girl_002",
        cost_messages: 0,
        free_allowance: 3,
        free_used: 1,
        free_remaining: 2,
        idempotent_replay: true,
      }),
    }],
  }, req({ currentProfileId: "practice_girl_001" }));
  assertEquals(result.status, 200);
  assertEquals(body.profile.profileId, "practice_girl_002");
  assertEquals(body.draw.freeRemaining, 2);
});

// ── 撞號重抽：第一次 conflict，第二次成功 ──────────────────────────────
Deno.test("撞號：RPC 第一次 PROFILE_CONFLICT → 換一張重抽，第二次成功（呼叫 2 次）", async () => {
  const { result, body, rpcCalls } = await run({
    sub: sub("starter", 0, 0),
    drawn: [],
    rpc: [
      { error: "PRACTICE_DRAW_PROFILE_CONFLICT" },
      { data: receipt({ profile_id: "practice_girl_015", free_allowance: 3 }) },
    ],
  });
  assertEquals(result.status, 200);
  assertEquals(body.profile.profileId, "practice_girl_015");
  assertEquals(rpcCalls.length, 2);
  // 兩次帶不同候選 profile（換一張）
  assert(rpcCalls[0].p_profile_id !== rpcCalls[1].p_profile_id);
});

// ── 無訂閱 → 403，且不呼叫 RPC ─────────────────────────────────────────
Deno.test("無訂閱列：403 No subscription，不呼叫 RPC", async () => {
  const { result, body, rpcCalls } = await run({ sub: null, rpc: [] });
  assertEquals(result.status, 403);
  assertEquals(body.error, "No subscription found");
  assertEquals(rpcCalls.length, 0);
});

// ── 測試帳號：p_charge_quota=false（仍寫 event）──────────────────────────
Deno.test("測試帳號：傳給 RPC p_charge_quota=false（免扣但仍記錄）", async () => {
  const { rpcCalls } = await run(
    {
      sub: sub("starter", 8, 20),
      drawn: ["a", "b", "c"],
      rpc: [{ data: receipt({ cost_messages: 5, free_allowance: 3 }) }],
    },
    req(),
    "vibesync.test@gmail.com",
  );
  assertEquals(rpcCalls[0].p_charge_quota, false);
});

// ── 不需要 DEEPSEEK_API_KEY ─────────────────────────────────────────────
Deno.test("draw handler 不需要 DEEPSEEK_API_KEY（移除 env 仍正常）", async () => {
  const prev = Deno.env.get("DEEPSEEK_API_KEY");
  Deno.env.delete("DEEPSEEK_API_KEY");
  try {
    const { result } = await run({
      sub: sub("free", 0, 0),
      drawn: [],
      rpc: [{ data: receipt() }],
    });
    assertEquals(result.status, 200);
  } finally {
    if (prev !== undefined) Deno.env.set("DEEPSEEK_API_KEY", prev);
  }
});
