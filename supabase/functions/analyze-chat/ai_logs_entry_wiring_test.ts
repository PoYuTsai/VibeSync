// 正式入口記帳串接（主審第 3 輪 P3）：從 createAnalyzeChatHandler 走進
// new_topic／opener_analyze／legacy opener，替身只有 Supabase client、
// EdgeRuntime.waitUntil 與 fetch 邊界。證明成功的供應商呼叫會經 waitUntil
// 排程一筆 ai_logs 寫入；拔掉入口的 recordAiCall 注入，這裡就會失敗。
import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { OPENER_FLOW_DB_CONTRACT_VERSION } from "./opener_session.ts";

const FAKE_SUPABASE_URL = "http://supabase.test";
const USER_ID = "11111111-2222-4333-8444-555555555555";

// 入口模組在載入時讀 env 常數，fetch 也可能在載入時被抓走（streaming_fallback），
// 所以替身與 env 都要在 import 之前裝好；import 完把 env 還原，不汙染其他測試。
let modelText = "{}";
const aiLogInserts: Array<Record<string, unknown>> = [];
globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
  const url = String(input instanceof Request ? input.url : input);
  if (url.startsWith(`${FAKE_SUPABASE_URL}/rest/v1/ai_logs`)) {
    const parsed = JSON.parse(String(init?.body));
    aiLogInserts.push(...(Array.isArray(parsed) ? parsed : [parsed]));
    return Promise.resolve(new Response(null, { status: 201 }));
  }
  if (url === "https://api.anthropic.com/v1/messages") {
    return Promise.resolve(Response.json({
      content: [{ type: "text", text: modelText }],
      usage: { input_tokens: 100, output_tokens: 50 },
      stop_reason: "end_turn",
    }));
  }
  throw new Error(`unexpected fetch: ${url}`);
}) as typeof fetch;

const IMPORT_ENV: Record<string, string> = {
  SUPABASE_URL: FAKE_SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) Deno.env.set(k, v);
const { createAnalyzeChatHandler } = await import("./index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

function fakeSupabase() {
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
    rpc(fn: string, params: Record<string, unknown>) {
      const data = fn === "opener_flow_contract_version"
        ? OPENER_FLOW_DB_CONTRACT_VERSION
        : fn === "claim_opener_analysis" || fn === "claim_new_topic_request"
        ? { kind: "claimed" }
        : fn === "settle_opener_analysis"
        ? {
          sessionId: "22222222-3333-4444-8555-666666666666",
          expiresAt: nowIso,
          analysisJson: params.p_analysis_json,
        }
        : fn === "settle_new_topic_request"
        ? { charged: true, result: params.p_result_json }
        : true;
      return Promise.resolve({ data, error: null });
    },
  };
}

async function runEntry(body: Record<string, unknown>, model: unknown) {
  modelText = JSON.stringify(model);
  aiLogInserts.length = 0;
  const scheduled: Promise<unknown>[] = [];
  const g = globalThis as unknown as { EdgeRuntime?: unknown };
  const savedRuntime = g.EdgeRuntime;
  g.EdgeRuntime = {
    waitUntil: (task: Promise<unknown>) => scheduled.push(task),
  };
  const hmacBefore = Deno.env.get("NEW_TOPIC_REPLAY_HMAC_KEY");
  Deno.env.set(
    "NEW_TOPIC_REPLAY_HMAC_KEY",
    btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
  );
  const quiet = [console.log, console.warn, console.error];
  console.log = console.warn = console.error = () => {};
  try {
    const handler = createAnalyzeChatHandler({
      createSupabaseClient: () => fakeSupabase() as never,
    });
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }),
    );
    const responseText = await response.text();
    const scheduledCount = scheduled.length;
    await Promise.all(scheduled);
    return {
      status: response.status,
      responseText,
      scheduledCount,
      rows: [...aiLogInserts],
    };
  } finally {
    [console.log, console.warn, console.error] = quiet;
    g.EdgeRuntime = savedRuntime;
    if (hmacBefore === undefined) Deno.env.delete("NEW_TOPIC_REPLAY_HMAC_KEY");
    else Deno.env.set("NEW_TOPIC_REPLAY_HMAC_KEY", hmacBefore);
  }
}

function assertOneLoggedCall(
  result: Awaited<ReturnType<typeof runEntry>>,
  requestType: string,
  userContent: string[],
) {
  assertEquals(result.status, 200, result.responseText);
  assertEquals(result.scheduledCount, 1, "成功的供應商呼叫要排程一筆背景寫入");
  assertEquals(result.rows.length, 1);
  const row = result.rows[0];
  assertEquals(
    [
      row.user_id,
      row.request_type,
      row.status,
      row.input_tokens,
      row.output_tokens,
    ],
    [USER_ID, requestType, "success", 100, 50],
  );
  const serialized = JSON.stringify(row);
  for (const text of userContent) {
    assertFalse(serialized.includes(text), `ai_logs 不得含用戶內容：${text}`);
  }
}

Deno.test("正式入口：new_topic 成功呼叫經 waitUntil 寫一筆 ai_logs", async () => {
  const model = {
    topics: [1, 2, 3, 4, 5].map((n) => ({
      direction: `方向${n}`,
      openingLine: `開場句${n}`,
      whyItWorks: `因為${n}`,
      nextMove: `下一步${n}`,
    })),
    recommendation: { index: 0, reason: "理由" },
  };
  const result = await runEntry({
    mode: "new_topic",
    requestId: "123e4567-e89b-42d3-a456-426614174000",
    partnerSummary: "對象：小雅。興趣：爬山。",
    situation: "went_cold",
  }, model);
  assertOneLoggedCall(result, "new_topic", ["小雅", "爬山", "開場句1"]);
});

Deno.test("正式入口：opener_analyze 成功呼叫經 waitUntil 寫一筆 ai_logs", async () => {
  const model = {
    wrongSurface: null,
    profileDigest: "自介：有養一隻狗，假日會去河堤",
    approach: { mode: "anchor_hooks", summary: "可以從她的狗開", avoid: [] },
    cues: [
      {
        id: "cue_1",
        label: "養狗",
        source: "profile_text",
        evidence: { field: "bio", quote: "有養一隻狗" },
      },
      {
        id: "cue_2",
        label: "河堤",
        source: "profile_text",
        evidence: { field: "bio", quote: "假日會去河堤" },
      },
    ],
    question: {
      affects: "sender_fact",
      text: "你跟養狗這件事比較接近哪種？",
      options: [
        {
          id: "option_1",
          label: "我自己有養",
          meaning: "assert_sender_fact",
          cueId: "cue_1",
          statement: "我有養狗",
        },
        {
          id: "option_2",
          label: "沒養，但有興趣",
          meaning: "curious_without_experience",
          cueId: "cue_1",
        },
        { id: "option_3", label: "其實想聊別的", meaning: "change_direction" },
      ],
    },
  };
  const result = await runEntry({
    mode: "opener_analyze",
    openerFlowVersion: 1,
    openerContractVersion: 2,
    analysisRequestId: "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f01",
    profileInfo: { bio: "有養一隻狗，假日會去河堤" },
  }, model);
  assertOneLoggedCall(result, "opener_analyze", ["養一隻狗", "河堤"]);
});

Deno.test("正式入口：legacy mode:opener 成功呼叫經 waitUntil 寫一筆 ai_logs", async () => {
  const openers = {
    extend: "妳最近在喝哪家咖啡？",
    resonate: "妳也喜歡手沖嗎？",
    tease: "咖啡喝這麼多睡得著嗎？",
    humor: "妳是靠咖啡續命派嗎？",
    coldRead: "感覺妳是會固定去同一家店的人？",
  };
  const result = await runEntry({
    mode: "opener",
    openerContractVersion: 2,
    profileInfo: { name: "Synthetic", bio: "週末都在河濱騎單車" },
  }, { openers });
  assertOneLoggedCall(result, "opener", ["河濱騎單車", "Synthetic", "手沖"]);
});
