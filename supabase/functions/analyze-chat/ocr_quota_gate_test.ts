// 截圖辨識（recognizeOnly）額度關卡（Eric＋Bruce 2026-10-30）：辨識不扣額度，但本月或
// 今天的額度用完就跟分析一樣回 429（帶 monthlyLimit／dailyLimit，App 顯示額度用完），
// 不打模型、也不佔 OCR 限流次數（increment_ocr_usage）。剩 1 則以上照舊免費辨識。
//
// 從正式入口 createAnalyzeChatHandler 送辨識請求。假 Supabase 回指定用量的訂閱列；
// 放行的請求走到 OCR 限流計數時回「已達每分鐘上限」，所以一定停在 429 OCR_RATE_LIMITED，
// 不會碰到模型。任何對外 fetch 都直接丟錯。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { TIER_DAILY_LIMITS, TIER_MONTHLY_LIMITS } from "../_shared/quota.ts";

const USER_ID = "11111111-2222-4333-8444-555555555556";

// 入口模組載入時讀 env 常數；不設 RevenueCat 金鑰，額度不夠時的對帳不會連網。
const originalFetch = globalThis.fetch;
let fetchCalls = 0;
globalThis.fetch = ((input: string | URL | Request) => {
  fetchCalls += 1;
  const url = String(input instanceof Request ? input.url : input);
  throw new Error(`unexpected fetch: ${url}`);
}) as typeof fetch;

const IMPORT_ENV: Record<string, string | undefined> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  REVENUECAT_IOS_API_KEY: undefined,
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) {
  if (v === undefined) Deno.env.delete(k);
  else Deno.env.set(k, v);
}
const { createAnalyzeChatHandler } = await import("./index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

interface Usage {
  tier: "free" | "starter" | "essential";
  monthlyUsed: number;
  dailyUsed: number;
}

function fakeSupabase(usage: Usage, rpcCalls: string[]) {
  const nowIso = new Date().toISOString();
  return {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: { user: { id: USER_ID, email: "user@example.com" } },
          error: null,
        }),
    },
    from(table: string) {
      const query = {
        select: () => query,
        eq: () => query,
        gte: () => query,
        maybeSingle: () =>
          Promise.resolve({
            data: table === "subscriptions"
              ? {
                tier: usage.tier,
                monthly_messages_used: usage.monthlyUsed,
                daily_messages_used: usage.dailyUsed,
                daily_reset_at: nowIso,
                monthly_reset_at: nowIso,
              }
              : null,
            error: null,
          }),
      };
      return query;
    },
    rpc(fn: string) {
      rpcCalls.push(fn);
      if (fn === "increment_ocr_usage") {
        return Promise.resolve({
          data: null,
          error: { message: "OCR_RATE_LIMITED_MINUTE" },
        });
      }
      return Promise.resolve({ data: true, error: null });
    },
  };
}

async function recognize(
  usage: Usage,
  extraBody: Record<string, unknown> = {},
) {
  const rpcCalls: string[] = [];
  const fetchBefore = fetchCalls;
  const quiet = [console.log, console.warn, console.error];
  console.log = console.warn = console.error = () => {};
  try {
    const handler = createAnalyzeChatHandler({
      createSupabaseClient: () => fakeSupabase(usage, rpcCalls) as never,
    });
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          recognizeOnly: true,
          messages: [],
          images: [{ data: "AAAA", mediaType: "image/jpeg", order: 1 }],
          ...extraBody,
        }),
      }),
    );
    const payload = await response.json();
    return {
      status: response.status,
      payload,
      rpcCalls,
      fetched: fetchCalls - fetchBefore,
    };
  } finally {
    [console.log, console.warn, console.error] = quiet;
  }
}

const FREE_DAILY = TIER_DAILY_LIMITS.free;
const FREE_MONTHLY = TIER_MONTHLY_LIMITS.free;

Deno.test("今天的額度用完：辨識回 429 今日額度（帶 dailyLimit），不打模型、不佔 OCR 次數", async () => {
  const result = await recognize({
    tier: "free",
    monthlyUsed: FREE_DAILY,
    dailyUsed: FREE_DAILY,
  });

  assertEquals(result.status, 429);
  assertEquals(result.payload.dailyLimit, FREE_DAILY);
  assertEquals(result.payload.monthlyLimit, undefined);
  assertEquals(result.payload.quotaNeeded, 1);
  assertEquals(result.payload.dailyRemaining, 0);
  assertEquals(result.rpcCalls.includes("increment_ocr_usage"), false);
  assertEquals(result.fetched, 0);
});

Deno.test("本月的額度用完：辨識回 429 本月額度（帶 monthlyLimit）", async () => {
  const result = await recognize({
    tier: "free",
    monthlyUsed: FREE_MONTHLY,
    dailyUsed: 0,
  });

  assertEquals(result.status, 429);
  assertEquals(result.payload.monthlyLimit, FREE_MONTHLY);
  assertEquals(result.payload.dailyLimit, undefined);
  assertEquals(result.payload.monthlyRemaining, 0);
  assertEquals(result.rpcCalls.includes("increment_ocr_usage"), false);
  assertEquals(result.fetched, 0);
});

Deno.test("付費方案今天用完也一樣擋", async () => {
  const result = await recognize({
    tier: "essential",
    monthlyUsed: TIER_DAILY_LIMITS.essential,
    dailyUsed: TIER_DAILY_LIMITS.essential,
  });

  assertEquals(result.status, 429);
  assertEquals(result.payload.dailyLimit, TIER_DAILY_LIMITS.essential);
  assertEquals(result.rpcCalls.includes("increment_ocr_usage"), false);
});

Deno.test("還剩 1 則：照舊免費辨識（過了額度關卡，走到 OCR 限流）", async () => {
  const result = await recognize({
    tier: "free",
    monthlyUsed: FREE_DAILY - 1,
    dailyUsed: FREE_DAILY - 1,
  });

  assertEquals(result.status, 429);
  assertEquals(result.payload.code, "OCR_RATE_LIMITED");
  assert(
    result.payload.monthlyLimit === undefined &&
      result.payload.dailyLimit === undefined,
    "OCR 限流的 429 不帶額度鍵",
  );
  assert(result.rpcCalls.includes("increment_ocr_usage"));
  assertEquals(result.fetched, 0);
});

// 主審 2026-10-31 P3：辨識請求帶 responseMode stream＋analysisRunId 假裝續看，也不能
// 跳過額度關卡、先佔 OCR 次數。
Deno.test("假裝串流續看的辨識請求：額度用完一樣先擋，不佔 OCR 次數", async () => {
  const result = await recognize(
    { tier: "free", monthlyUsed: FREE_DAILY, dailyUsed: FREE_DAILY },
    {
      responseMode: "stream",
      analysisRunId: "7a1c9e2b-4d3f-4b8a-9c6e-1f2a3b4c5d6e",
    },
  );

  assertEquals(result.status, 429);
  assertEquals(result.payload.dailyLimit, FREE_DAILY);
  assertEquals(result.rpcCalls.includes("increment_ocr_usage"), false);
  assertEquals(result.fetched, 0);
});

Deno.test("cleanup: restore fetch", () => {
  globalThis.fetch = originalFetch;
});
