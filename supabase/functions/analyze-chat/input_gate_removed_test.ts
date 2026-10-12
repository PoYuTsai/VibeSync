// F01（2026-10-03 健檢唯一 P1）回歸測試：舊的輸入關鍵字閘門把雙方訊息串起來
// 比對「如何…跟蹤」「怎麼…強迫」「她不願意…怎麼」「拒絕…還是想」，正常對話會
// 被擋成 400 UNSAFE_INPUT，App 又把它當成不能重試。閘門已刪除，界線與拒絕交給
// 模型的「先別回」決策。
//
// 這支從正式入口 createAnalyzeChatHandler 送出串流分析請求。假 Supabase 讓訂閱
// 讀取正常通過，並在模型限流計數（increment_model_usage，位置在原本閘門之後、
// 組 prompt 與呼叫模型之前）回「已達每分鐘上限」，所以請求會確定停在 429。
// 舊程式會在閘門回 400 UNSAFE_INPUT、根本走不到限流；這支在舊程式上會失敗。
import {
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const FAKE_SUPABASE_URL = "http://supabase.test";
const USER_ID = "11111111-2222-4333-8444-555555555555";

// 入口模組載入時會讀 env 常數，streaming_fallback 也可能在載入時抓走 fetch，
// 所以替身與 env 要在 import 之前裝好；import 完把 env 還原，不汙染其他測試。
// 這條路徑停在限流，不該打任何外部服務。
const originalFetch = globalThis.fetch;
globalThis.fetch = ((input: string | URL | Request) => {
  const url = String(input instanceof Request ? input.url : input);
  throw new Error(`unexpected fetch: ${url}`);
}) as typeof fetch;

// STREAM_ANALYZE_ENABLED 在模組載入時讀成常數；正式環境是 true，不設的話
// 串流分析會在限流之前就回 503 STREAM_MODE_UNAVAILABLE。
const IMPORT_ENV: Record<string, string> = {
  SUPABASE_URL: FAKE_SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  STREAM_ANALYZE_ENABLED: "true",
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) Deno.env.set(k, v);
const { createAnalyzeChatHandler } = await import("./index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

function fakeSupabase(rpcCalls: string[]) {
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
                tier: "free",
                monthly_messages_used: 0,
                daily_messages_used: 0,
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
      if (fn === "increment_model_usage") {
        return Promise.resolve({
          data: null,
          error: { message: "MODEL_RATE_LIMITED_MINUTE" },
        });
      }
      return Promise.resolve({ data: true, error: null });
    },
  };
}

async function analyze(
  messages: Array<{ content: string; isFromMe: boolean }>,
) {
  const rpcCalls: string[] = [];
  const quiet = [console.log, console.warn, console.error];
  console.log = console.warn = console.error = () => {};
  try {
    const handler = createAnalyzeChatHandler({
      createSupabaseClient: () => fakeSupabase(rpcCalls) as never,
    });
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ responseMode: "stream", messages }),
      }),
    );
    const payload = await response.json();
    return { status: response.status, payload, rpcCalls };
  } finally {
    [console.log, console.warn, console.error] = quiet;
  }
}

const NORMAL_CONVERSATIONS: Array<
  [label: string, messages: Array<{ content: string; isFromMe: boolean }>]
> = [
  ["她不願意吃辣", [
    { content: "她不願意吃辣，晚餐怎麼辦", isFromMe: false },
  ]],
  ["怎麼…強迫（跨訊息）", [
    { content: "你怎麼這麼晚還沒睡", isFromMe: false },
    { content: "我不想強迫你啦，想睡就先睡", isFromMe: true },
    { content: "沒事啦我只是失眠", isFromMe: false },
  ]],
  ["拒絕…還是想", [
    { content: "我拒絕了那個 offer", isFromMe: false },
    { content: "但我還是想出國念書", isFromMe: false },
  ]],
  ["如何…跟蹤（跨訊息）", [
    { content: "如何準備明天的面試", isFromMe: true },
    { content: "我昨天看完那部片覺得被跟蹤狂嚇到", isFromMe: false },
  ]],
  ["她不願意來…怎麼辦", [
    { content: "我朋友她不願意來", isFromMe: false },
    { content: "那我們怎麼辦", isFromMe: false },
  ]],
];

Deno.test("F01：正常對話不再被輸入關鍵字閘門擋下，會走到後面的模型限流", async () => {
  for (const [label, messages] of NORMAL_CONVERSATIONS) {
    const { status, payload, rpcCalls } = await analyze(messages);
    assertNotEquals(
      payload.code,
      "UNSAFE_INPUT",
      `${label}：不得被輸入閘門擋下`,
    );
    assertEquals(
      rpcCalls.includes("increment_model_usage"),
      true,
      `${label}：要走到原本閘門之後的模型限流，實際 RPC：${
        rpcCalls.join(",")
      }；回應 ${status} ${JSON.stringify(payload)}`,
    );
    assertEquals(status, 429, `${label}：替身限流回已達上限，應停在 429`);
  }
});

Deno.test("F01：輸入關鍵字閘門已從 guardrails 與入口移除", async () => {
  const guardrails = await Deno.readTextFile(
    new URL("./guardrails.ts", import.meta.url),
  );
  const handler = await Deno.readTextFile(
    new URL("./analyze_chat_handler.ts", import.meta.url),
  );
  assertEquals(/export function checkInput\b/.test(guardrails), false);
  assertEquals(handler.includes("UNSAFE_INPUT"), false);
});

globalThis.addEventListener("unload", () => {
  globalThis.fetch = originalFetch;
});
