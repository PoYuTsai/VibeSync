// 新話題 handler 行為測試（2026-10-01 規格 §2／§4.7）：正式 handler，只替換
// supabase 與模型 fetch 邊界。鎖住進階開關、擋字發生在任何 DB／限流／模型
// 之前，以及開關開時兩段提示詞真的換成進階版。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleNewTopicRequest } from "./new_topic_handler.ts";
import {
  buildNewTopicUserPrompt,
  NEW_TOPIC_PROMPT,
} from "./new_topic_prompt.ts";
import { NEW_TOPIC_TWO_STAGE_PROMPT } from "./new_topic_two_stage.ts";

const USER_ID = "11111111-2222-4333-8444-555555555555";
const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const STRONG_KEY = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));

const MODEL_PAYLOAD = {
  topics: [1, 2, 3, 4, 5].map((n) => ({
    direction: `方向${n}`,
    openingLine: `開場句${n}`,
    whyItWorks: `因為${n}`,
    nextMove: `下一步${n}`,
  })),
  recommendation: { index: 0, reason: "理由" },
};

type ModelRequest = {
  system: Array<{ text: string }>;
  messages: Array<{ role: string; content: string }>;
};

function body(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    mode: "new_topic",
    requestId: REQUEST_ID,
    partnerSummary: "對象：小雅。興趣：爬山。",
    situation: "went_cold",
    ...extra,
  };
}

async function run(
  requestBody: Record<string, unknown>,
  twoStageFlag: string | undefined,
  settleCharged = true,
  modelPayload: unknown = MODEL_PAYLOAD,
  startedMsAgo = 0,
) {
  const dbCalls: string[] = [];
  const logEvents: string[] = [];
  const modelRequests: ModelRequest[] = [];
  const supabase = {
    from(table: string) {
      dbCalls.push(`from:${table}`);
      const query = {
        select: () => query,
        eq: () => query,
        gte: () => query,
        maybeSingle: () => Promise.resolve({ data: null, error: null }),
      };
      return query;
    },
    rpc(fn: string, params: Record<string, unknown>) {
      dbCalls.push(`rpc:${fn}`);
      if (fn === "claim_new_topic_request") {
        return Promise.resolve({ data: { kind: "claimed" }, error: null });
      }
      if (fn === "settle_new_topic_request") {
        return Promise.resolve({
          data: { charged: settleCharged, result: params.p_result_json },
          error: null,
        });
      }
      if (fn === "increment_model_usage") {
        return Promise.resolve({ data: null, error: null });
      }
      return Promise.resolve({ data: true, error: null });
    },
  };

  const originalFetch = globalThis.fetch;
  const originalLog = console.log;
  console.log = (message: unknown) => logEvents.push(String(message));
  const env = ["NEW_TOPIC_TWO_STAGE_ENABLED", "NEW_TOPIC_REPLAY_HMAC_KEY"]
    .map((key) => [key, Deno.env.get(key)] as const);
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    modelRequests.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          content: [{ type: "text", text: JSON.stringify(modelPayload) }],
          usage: { input_tokens: 10, output_tokens: 10 },
          stop_reason: "end_turn",
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;
  Deno.env.set("NEW_TOPIC_REPLAY_HMAC_KEY", STRONG_KEY);
  if (twoStageFlag === undefined) {
    Deno.env.delete("NEW_TOPIC_TWO_STAGE_ENABLED");
  } else {
    Deno.env.set("NEW_TOPIC_TWO_STAGE_ENABLED", twoStageFlag);
  }
  try {
    const response = await handleNewTopicRequest({
      supabase,
      userId: USER_ID,
      requestBody,
      responseMode: "legacy",
      requestStartedAtMs: Date.now() - startedMsAgo,
      accountIsTest: false,
      claudeApiKey: "test-key",
      refreshTierFromRevenueCat: () => Promise.resolve("not_paid"),
      quota: () => ({
        sub: { monthly_messages_used: 0, daily_messages_used: 0, tier: "free" },
        monthlyLimit: 100,
        dailyLimit: 30,
        effectiveTier: "essential",
      }),
    });
    return {
      status: response.status,
      json: await response.json(),
      dbCalls,
      modelRequests,
      logEvents,
    };
  } finally {
    globalThis.fetch = originalFetch;
    console.log = originalLog;
    for (const [key, value] of env) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

const STORY = {
  coldDuration: "weeks",
  materialKind: "my_story",
  materialText: "信心滿滿走進店裡，才發現走錯分店",
};

Deno.test("handler：開關沒開＋有 topicContext → 422（不進 5xx 告警），不碰 DB／限流／模型", async () => {
  for (const flag of [undefined, "false", "1", "TRUE"]) {
    const result = await run(body({ topicContext: STORY }), flag);
    assertEquals(result.status, 422, String(flag));
    assertEquals(result.json, {
      error: "NEW_TOPIC_ADVANCED_UNAVAILABLE",
      code: "NEW_TOPIC_ADVANCED_UNAVAILABLE",
      message: "進階模式暫時無法使用，可以改用基本模式生成。本次不會扣額度。",
      retryable: false,
      shouldChargeQuota: false,
    });
    assertEquals(result.dbCalls, []);
    assertEquals(result.modelRequests, []);
  }
});

Deno.test("handler：開關沒開＋沒有 topicContext → 照舊走 legacy 提示詞", async () => {
  const result = await run(body(), undefined);
  assertEquals(result.status, 200);
  assertEquals(result.json.usage, { cost: 3 });
  assertEquals(result.modelRequests.length, 1);
  const [request] = result.modelRequests;
  assertEquals(request.system[0].text, NEW_TOPIC_PROMPT);
  assertEquals(
    request.messages[0].content,
    buildNewTopicUserPrompt({
      partnerSummary: "對象：小雅。興趣：爬山。",
      effectiveStyleContext: null,
      situation: "went_cold",
      requestId: REQUEST_ID,
    }),
  );
  assert(result.dbCalls.includes("rpc:settle_new_topic_request"));
});

Deno.test("handler：素材原文命中粗俗詞 → 422，不碰 DB／限流／模型", async () => {
  // 零寬字元／雙向控制拆開的粗俗詞，sanitize 拿掉格式字元後一樣擋。
  for (
    const materialText of [
      "她說想打炮",
      "幹你娘超好笑",
      "她說想打\u200B炮",
      "幹\u2060你\u200D娘超好笑",
    ]
  ) {
    const result = await run(
      body({ topicContext: { materialKind: "inside_joke", materialText } }),
      "true",
    );
    assertEquals(result.status, 422, materialText);
    assertEquals(result.json, {
      error: "NEW_TOPIC_MATERIAL_BLOCKED",
      code: "NEW_TOPIC_MATERIAL_BLOCKED",
      message: "你寫的那句含有不適合的字眼，請改寫後再生成。本次不會扣額度。",
      shouldChargeQuota: false,
    });
    assertEquals(result.dbCalls, []);
    assertEquals(result.modelRequests, []);
  }
});

Deno.test("handler：開關先於擋字（開關沒開時髒字也回進階不可用）", async () => {
  const result = await run(
    body({
      topicContext: { materialKind: "inside_joke", materialText: "她說想打炮" },
    }),
    undefined,
  );
  assertEquals(result.status, 422);
  assertEquals(result.json.code, "NEW_TOPIC_ADVANCED_UNAVAILABLE");
});

Deno.test("handler：topicContext 格式錯 → 400，不碰 DB／模型", async () => {
  const result = await run(body({ topicContext: { mood: "x" } }), "true");
  assertEquals(result.status, 400);
  assertEquals(result.json.code, "NEW_TOPIC_REQUEST_INVALID");
  assertEquals(result.dbCalls, []);
  assertEquals(result.modelRequests, []);
});

Deno.test("handler：只選「沒有，幫我想」且沒有其他素材 → 422 CONTEXT_REQUIRED", async () => {
  const result = await run(
    {
      mode: "new_topic",
      requestId: REQUEST_ID,
      topicContext: { materialKind: "none" },
    },
    "true",
  );
  assertEquals(result.status, 422);
  assertEquals(result.json.code, "NEW_TOPIC_CONTEXT_REQUIRED");
  assertEquals(result.dbCalls, []);
});

Deno.test("handler：開關開＋有 topicContext → 進階 system＋含局面段的 user prompt", async () => {
  const result = await run(body({ topicContext: STORY }), "true");
  assertEquals(result.status, 200);
  assertEquals(result.json.usage, { cost: 3 });
  assertEquals(result.modelRequests.length, 1);
  const [request] = result.modelRequests;
  assertEquals(request.system[0].text, NEW_TOPIC_TWO_STAGE_PROMPT);
  const userPrompt = request.messages[0].content;
  assert(
    userPrompt.includes("## 這次的局面（用戶自己說的現況，照這裡的做法寫）"),
  );
  assert(userPrompt.includes("- 多久沒聊：一到四週"));
  assert(userPrompt.includes("- 原文：「信心滿滿走進店裡，才發現走錯分店」"));
  assert(!userPrompt.includes("本輪內容素材"));
  assert(result.dbCalls.includes("rpc:settle_new_topic_request"));
});

Deno.test("handler：只有素材原文（沒選狀況、沒作戰板）也能生成", async () => {
  const result = await run(
    {
      mode: "new_topic",
      requestId: REQUEST_ID,
      topicContext: { materialKind: "trigger", materialText: "路過浮誇甜點店" },
    },
    "true",
  );
  assertEquals(result.status, 200);
  assertEquals(
    result.modelRequests[0].system[0].text,
    NEW_TOPIC_TWO_STAGE_PROMPT,
  );
});

Deno.test("handler：稽核只記本筆落帳的結果，replayed（先完成者贏）略過", async () => {
  const hasAudit = (events: string[]) =>
    events.some((event) => event.endsWith(" new_topic_two_stage_audit"));
  const charged = await run(body({ topicContext: STORY }), "true");
  assertEquals(charged.status, 200);
  assert(hasAudit(charged.logEvents));

  const replayed = await run(body({ topicContext: STORY }), "true", false);
  assertEquals(replayed.status, 200);
  assert(
    replayed.logEvents.some((event) =>
      event.endsWith(" new_topic_settlement_replayed")
    ),
  );
  assert(!hasAudit(replayed.logEvents));
});

// ---------------------------------------------------------------------------
// 「我們」：提示詞那一行與輸出守門同一個判準（2026-10-01 審查 E3／E7）
// ---------------------------------------------------------------------------

const SHARED_FRAME_ALLOWED_LINE =
  "- 「我們」：可以寫你們一起的事或一起做某件事的小想像，但不越級。";
const SHARED_FRAME_DENIED_LINE =
  "- 「我們」：不寫「我們＋動作」的句子；提到過去的事用「上次」「那次」「妳那句」。";

function payloadWithOpening(openingLine: string) {
  const topics = MODEL_PAYLOAD.topics.map((topic) => ({ ...topic }));
  topics[0].openingLine = openingLine;
  return { ...MODEL_PAYLOAD, topics };
}

Deno.test("handler：「我們」守門與提示詞一致（想靠近＋很投入、你們的梗放行；其他擋）", async () => {
  const cases: Array<{
    name: string;
    request: Record<string, unknown>;
    openingLine: string;
    allowed: boolean;
  }> = [
    {
      name: "warm_up＋green",
      request: body({
        situation: "warm_up",
        topicContext: { engagement: "green" },
      }),
      openingLine: "我們一起去看那場展吧",
      allowed: true,
    },
    {
      name: "inside_joke＋原文",
      request: body({
        situation: "stuck",
        topicContext: {
          materialKind: "inside_joke",
          materialText: "她說我的五分鐘都是半小時",
        },
      }),
      openingLine: "我們吃飯那天的五分鐘又變半小時了",
      allowed: true,
    },
    {
      name: "stuck＋yellow＋my_story",
      request: body({
        situation: "stuck",
        topicContext: {
          engagement: "yellow",
          materialKind: "my_story",
          materialText: "信心滿滿走進店裡，才發現走錯分店",
        },
      }),
      openingLine: "我們去那家分店吃吃看",
      allowed: false,
    },
  ];
  for (const { name, request, openingLine, allowed } of cases) {
    const result = await run(
      request,
      "true",
      true,
      payloadWithOpening(openingLine),
      // 擋下的那筆會進 format repair；把生成期限壓到剩約 1 秒，測試不用等滿 45 秒。
      allowed ? 0 : 44_000,
    );
    const userPrompt = result.modelRequests[0].messages[0].content;
    assert(
      userPrompt.includes(
        allowed ? SHARED_FRAME_ALLOWED_LINE : SHARED_FRAME_DENIED_LINE,
      ),
      name,
    );
    assertFalse(
      userPrompt.includes(
        allowed ? SHARED_FRAME_DENIED_LINE : SHARED_FRAME_ALLOWED_LINE,
      ),
      name,
    );
    if (allowed) {
      assertEquals(result.status, 200, name);
      assertEquals(result.json.topics[0].openingLine, openingLine, name);
    } else {
      // 守門擋下：整份不交付、不落帳、不扣。
      assert(result.status !== 200, name);
      assertEquals(result.json.shouldChargeQuota, false, name);
      assertFalse(result.dbCalls.includes("rpc:settle_new_topic_request"));
    }
  }
});

Deno.test("handler：用戶素材裡的英文 stuck 被模型照抄不再判外洩", async () => {
  const topics = MODEL_PAYLOAD.topics.map((topic) => ({ ...topic }));
  topics[0] = {
    ...topics[0],
    openingLine: "報告卡在第一段，整個 stuck 住",
    whyItWorks: "用你自己 stuck 的小事開場，她不用回答問題也能接",
  };
  const result = await run(
    body({
      situation: "stuck",
      topicContext: {
        materialKind: "my_story",
        materialText: "這週寫報告一直 stuck 在第一段",
      },
    }),
    "true",
    true,
    { ...MODEL_PAYLOAD, topics },
  );
  assertEquals(result.status, 200);
  assertEquals(result.modelRequests.length, 1);
  assertEquals(
    result.json.topics[0].openingLine,
    "報告卡在第一段，整個 stuck 住",
  );
});
