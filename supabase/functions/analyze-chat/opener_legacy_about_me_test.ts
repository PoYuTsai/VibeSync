// 舊單段開場救星（mode: opener）的「關於我」隔離：「關於我」只給 Coach 1:1（2026-08-04），
// 8/4 以前的舊版 App 還會帶 effectiveStyleContext。伺服器只拿它算重送指紋，不交給模型、
// 不拿來組共鳴開場的「我也＋引文」；不合法的值當作沒帶。正式 handler，只替換 supabase
// 與模型 fetch 邊界（同 opener_cost_guard_test.ts）。
// 串流層在載入時就抓住 fetch：轉接器必須是第一個 import（見 test_fetch_dispatcher.ts）。
import "./test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleOpenerRequest, type OpenerHandlerDeps } from "./opener_handler.ts";
import { computeOpenerInputHash, OPENER_REPLAY_LIMIT } from "./opener_charge.ts";
import { OPENER_TYPES } from "./opener_payload.ts";

const ABOUT_ME_CANARY = "CANARY-關於我-7F3A";
const REQUEST_ID = "2aa16d52-4fd5-419f-b879-59bf4b0e3638";
const PROFILE = { name: "Synthetic", bio: "週末都在爬山" };
const OPENERS = {
  extend: "妳最近爬哪座山？",
  resonate: "妳也喜歡爬山嗎？",
  tease: "爬這麼多山腿還好嗎？",
  humor: "妳是靠爬山續命派嗎？",
  coldRead: "感覺妳是會早起去爬山的人？",
};

type ModelRequest = {
  stream?: boolean;
  messages: Array<{ role: string; content: unknown }>;
};

/** Anthropic SSE：一段文字＋結束原因（照 streaming_fallback 解析的事件格式）。 */
function sseResponse(text: string): Response {
  const events = [
    {
      type: "message_start",
      message: { usage: { input_tokens: 10, output_tokens: 1 } },
    },
    { type: "content_block_delta", delta: { type: "text_delta", text } },
    {
      type: "message_delta",
      delta: { stop_reason: "end_turn" },
      usage: { output_tokens: 10 },
    },
    { type: "message_stop" },
  ];
  const encoder = new TextEncoder();
  return new Response(
    new ReadableStream({
      start(controller) {
        for (const event of events) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify(event)}\n\n`),
          );
        }
        controller.close();
      },
    }),
    { status: 200, headers: { "content-type": "text/event-stream" } },
  );
}

/**
 * 跑一次正式 handler。replayRow 有值時帶 requestId，查帳回這一列（用來看 handler 算出的
 * 指紋）；沒值時不帶 requestId、不查帳。
 */
async function runOpener(input: {
  rawEffectiveStyleContext: unknown;
  responseMode?: "legacy" | "stream";
  replayRow?: Record<string, unknown>;
  modelPayload?: Record<string, unknown>;
}) {
  const modelRequests: ModelRequest[] = [];
  const text = JSON.stringify(input.modelPayload ?? { openers: OPENERS });
  const originalFetch = globalThis.fetch;
  const streamFlag = Deno.env.get("OPENER_STREAM_ENABLED");
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as ModelRequest;
    modelRequests.push(request);
    if (request.stream === true) return Promise.resolve(sseResponse(text));
    return Promise.resolve(Response.json({
      content: [{ type: "text", text }],
      usage: { input_tokens: 100, output_tokens: 50 },
      stop_reason: "end_turn",
    }));
  }) as typeof fetch;
  if (input.responseMode === "stream") {
    Deno.env.set("OPENER_STREAM_ENABLED", "true");
  } else {
    Deno.env.delete("OPENER_STREAM_ENABLED");
  }
  const query = {
    select: () => query,
    eq: () => query,
    maybeSingle: () =>
      Promise.resolve({ data: input.replayRow ?? null, error: null }),
  };
  const deps: OpenerHandlerDeps = {
    supabase: {
      from: () => query,
      rpc: () => Promise.resolve({ data: true, error: null }),
    },
    userId: "synthetic-owner",
    images: null,
    rawProfileInfo: PROFILE,
    rawRequestId: input.replayRow ? REQUEST_ID : null,
    rawKnownContactName: null,
    rawEffectiveStyleContext: input.rawEffectiveStyleContext,
    rawOpenerContractVersion: 2,
    responseMode: input.responseMode ?? "legacy",
    requestStartedAtMs: Date.now(),
    accountIsTest: false,
    claudeApiKey: "fake",
    refreshTierFromRevenueCat: () => Promise.reject(new Error("must not refresh")),
    quota: () => ({
      sub: { monthly_messages_used: 0, daily_messages_used: 0 },
      monthlyLimit: 300,
      dailyLimit: 50,
      effectiveTier: "essential",
      allowedFeatures: [...OPENER_TYPES],
    }),
  };
  try {
    const response = await handleOpenerRequest(deps);
    const streamed = (response.headers.get("content-type") ?? "").includes(
      "ndjson",
    );
    const raw = await response.text();
    const json = streamed
      ? JSON.parse(raw.split("\n").filter((line) => line.trim()).at(-1)!)
      : JSON.parse(raw);
    return { status: response.status, json, modelRequests };
  } finally {
    globalThis.fetch = originalFetch;
    if (streamFlag === undefined) Deno.env.delete("OPENER_STREAM_ENABLED");
    else Deno.env.set("OPENER_STREAM_ENABLED", streamFlag);
  }
}

Deno.test("舊單段開場：舊版 App 帶「關於我」→ 一般與串流都不進模型請求，送出的內容跟沒帶時逐字相同", async () => {
  for (const responseMode of ["legacy", "stream"] as const) {
    const withAboutMe = await runOpener({
      rawEffectiveStyleContext: ABOUT_ME_CANARY,
      responseMode,
    });
    assertEquals(withAboutMe.status, 200, responseMode);
    assertEquals(withAboutMe.modelRequests.length, 1, responseMode);
    assertEquals(
      withAboutMe.modelRequests[0].stream === true,
      responseMode === "stream",
      `${responseMode}：要走到對應的模型呼叫`,
    );
    assertFalse(
      JSON.stringify(withAboutMe.modelRequests).includes(ABOUT_ME_CANARY),
      `${responseMode}：關於我漏進模型請求`,
    );
    const without = await runOpener({
      rawEffectiveStyleContext: null,
      responseMode,
    });
    assertEquals(without.status, 200, responseMode);
    assertEquals(
      JSON.stringify(withAboutMe.modelRequests),
      JSON.stringify(without.modelRequests),
      responseMode,
    );
  }
});

Deno.test("舊單段開場：模型說共鳴有交集也不組「我也＋關於我原文」，共鳴卡一律照模型寫的那句", async () => {
  const aboutMe = "我的興趣：爬山、養了一隻柴犬";
  const result = await runOpener({
    rawEffectiveStyleContext: aboutMe,
    modelPayload: {
      openers: OPENERS,
      profileAnalysis: {
        resonateBasis: "style_overlap",
        senderFactQuoted: "爬山",
      },
    },
  });
  assertEquals(result.status, 200);
  const resonate = String(result.json.openers?.resonate ?? "");
  assertEquals(resonate, OPENERS.resonate);
  assertFalse(resonate.startsWith("我也"));
});

Deno.test("舊單段開場：舊版 App 帶的「關於我」照舊進重送指紋；指紋少了它就對不上", async () => {
  const hashWith = (effectiveStyleContext: string | null) =>
    computeOpenerInputHash({
      images: null,
      profileInfo: PROFILE,
      effectiveStyleContext,
    });
  // 帳本上這筆已重試到上限：handler 算出的指紋跟它一樣才會回 EXHAUSTED，不一樣是 MISMATCH。
  const exhausted = await runOpener({
    rawEffectiveStyleContext: ABOUT_ME_CANARY,
    replayRow: {
      input_hash: await hashWith(ABOUT_ME_CANARY),
      replay_count: OPENER_REPLAY_LIMIT,
    },
  });
  assertEquals(exhausted.status, 400);
  assertEquals(exhausted.json.error, "OPENER_REQUEST_REPLAY_EXHAUSTED");
  assertEquals(exhausted.modelRequests, []);

  const mismatched = await runOpener({
    rawEffectiveStyleContext: ABOUT_ME_CANARY,
    replayRow: {
      input_hash: await hashWith(null),
      replay_count: OPENER_REPLAY_LIMIT,
    },
  });
  assertEquals(mismatched.status, 400);
  assertEquals(mismatched.json.error, "OPENER_REQUEST_REPLAY_MISMATCH");
  assertEquals(mismatched.modelRequests, []);
});

Deno.test("舊單段開場：不合法的「關於我」當作沒帶，不再回 400；指紋跟沒帶時一樣", async () => {
  for (
    const invalid of [42, ["列表"], { note: "物件" }, "長".repeat(1201)]
  ) {
    const label = typeof invalid === "string"
      ? `${invalid.length} 字`
      : JSON.stringify(invalid);
    const result = await runOpener({ rawEffectiveStyleContext: invalid });
    assertEquals(result.status, 200, label);
    assertEquals(result.modelRequests.length, 1, label);
    // 指紋：沒帶時的 2 元素形狀，帳本那一列已到上限 → EXHAUSTED（不是 MISMATCH）。
    const replay = await runOpener({
      rawEffectiveStyleContext: invalid,
      replayRow: {
        input_hash: await computeOpenerInputHash({
          images: null,
          profileInfo: PROFILE,
        }),
        replay_count: OPENER_REPLAY_LIMIT,
      },
    });
    assertEquals(replay.status, 400, label);
    assertEquals(replay.json.error, "OPENER_REQUEST_REPLAY_EXHAUSTED", label);
  }
  // 空白字串照舊視同沒帶。
  const blank = await runOpener({ rawEffectiveStyleContext: "   " });
  assertEquals(blank.status, 200);
  assert(blank.modelRequests.length === 1);
});
