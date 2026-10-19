// 關係訊號開關（ANALYZE_GUIDE_V3_RELATION，Bruce 2026-10-19 路線二）沒開時，跟 afa50d6f 一字不差：
// 讀局面的系統提示詞、schema、使用者那一則，流程送出的事件、扣費內容、落帳結果（含 trace）與 log，
// 以及走整個 handler 時送給模型的請求。期望的雜湊都是在還沒改的 afa50d6f 上算出來的；
// 這支失敗就是開關沒開也改到了東西。不呼叫模型、不連網。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { readSystemPrompt, readUserPrompt } from "./prompts.ts";
import { READ_TAGS_SCHEMA } from "./read_tags.ts";
import {
  fixtureCase,
  type FlowCase,
  runFlow,
  withReadTags,
} from "./relation_flow_harness.ts";
import { guideMessagesFrom } from "./stream_flow.ts";
import { toTurns } from "./turns.ts";
import {
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
  type V3HarnessOutcome,
} from "./v3_stream_harness.ts";

const IMPORT_ENV: Record<string, string> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  STREAM_ANALYZE_ENABLED: "true",
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) Deno.env.set(k, v);
const { createAnalyzeChatHandler } = await import("../index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

const FLAG = "ANALYZE_GUIDE_V3_RELATION";

async function sha256(value: unknown): Promise<string> {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---- 1. 提示詞與 schema（afa50d6f 上算的） ----

const BASE_READ_SYSTEM_SHA256 =
  "91c6657e79d9dcb55f54beb7799c04186cbfada6f8bf4992bb61c8c2853e729c";
const BASE_READ_SCHEMA_SHA256 =
  "09de00926aa5e702514cec54ab1d6222ef456bee1b6e6b7808a0f51c30bb24f1";
const BASE_READ_USER_SHA256 =
  "c7dd7840339ae70660457248920c246211b566a61554abadcfb2e4d85e9a47c9";
const BASE_READ_USER_WITH_CONTEXT_SHA256 =
  "5a5ff74209382508f884d90dfbaa445fc1cf42a3a3bb011441590a8bdc363fa0";

const QUOTED_MESSAGES = [
  { isFromMe: true, content: "週末去哪玩" },
  {
    isFromMe: false,
    content: "去爬山，腿快斷了",
    quotedReplyPreview: "週末去哪玩",
  },
  { isFromMe: false, content: "你呢" },
];

Deno.test("關係訊號開關沒開：讀局面的系統提示詞、schema、使用者那一則跟 afa50d6f 一樣", async () => {
  assertEquals(await sha256(readSystemPrompt()), BASE_READ_SYSTEM_SHA256);
  assertEquals(await sha256(READ_TAGS_SCHEMA), BASE_READ_SCHEMA_SHA256);
  const teases = fixtureCase("she_teases_him#1");
  assertEquals(
    await sha256(readUserPrompt(toTurns(guideMessagesFrom(teases.messages)))),
    BASE_READ_USER_SHA256,
  );
  assertEquals(
    await sha256(
      readUserPrompt(
        toTurns(guideMessagesFrom(QUOTED_MESSAGES)),
        {
          meetingContext: "交友軟體",
          duration: "剛認識",
          goal: "約出來",
          analysisContextNote: "她上週說喜歡爬山",
          partnerSummary: "喜歡爬山、養貓",
          conversationSummary: "上次聊到週末計畫",
        },
        {
          decision: "send",
          light: "green",
          judgment: "她主動分享週末行程。",
          messages: [{ isFromMe: false, content: "週末想去走走" }],
        },
      ),
    ),
    BASE_READ_USER_WITH_CONTEXT_SHA256,
  );
});

// ---- 2. 整個 v3 流程（替身：時間固定、不連網） ----

/// 每種決定一案：出卡（5 張）、收尾、先別回、停、自傷關心、未成年。
const FLOW_CASES: readonly { case: FlowCase; sha256: string }[] = [
  {
    case: fixtureCase("she_teases_him#1"),
    sha256: "e14715e34590d5fd96d2c7f38ab31b9cadbf1e7d5f552ecf5537aa7cf434a7c3",
  },
  {
    case: fixtureCase("soft_reject_after_invite#1"),
    sha256: "cb960951d6db86d3b7663d0350fe99faa3cc9dc1e69c2c3de58f8cf07915d10c",
  },
  {
    case: fixtureCase("cold_one_word_replies#1"),
    sha256: "4d1c2ffb2493d2de4d17ddc2df899c96e844925c048eedd92cc6f513f8587479",
  },
  {
    case: withReadTags("she_teases_him#1", { explicitRejection: true }),
    sha256: "c7d43def83f0f802452a7a22a4841f926d30c98cfe660dfc0d25d75a05c2c6b5",
  },
  {
    case: withReadTags("she_teases_him#1", { selfHarmSignal: true }),
    sha256: "f7dc5224a3459a8321affff53f0f0f46f5ebaa286585f697588c3a0f2f964bcd",
  },
  {
    case: withReadTags("she_teases_him#1", { minorSignal: true }),
    sha256: "7f71ed65952cb7822d0eda082912987735eff23c90bcc422a13c145720f23472",
  },
];

for (const { case: flowCase, sha256: expected } of FLOW_CASES) {
  Deno.test(`關係訊號開關沒開（沒給、false）：${flowCase.name} 的事件、扣費、落帳、trace 與 log 跟 afa50d6f 一樣`, async () => {
    for (const extra of [{}, { relation: false }]) {
      const outcome = await runFlow(flowCase, extra);
      assertEquals(await sha256(outcome), expected, JSON.stringify(extra));
      assert(!JSON.stringify(outcome).includes('"relation"'));
    }
  });
}

// ---- 3. 走整個 handler（假 Supabase、假模型） ----

const BASE_HANDLER_MODEL_BODIES_SHA256 =
  "67452dd0c39bb4e1c42dfe318d9d62c768bb1bcde9a3f1d58d737cbe61dad329";
const BASE_HANDLER_RPCS_SHA256 =
  "f3931da9526425717bada714d4088524ec0b1b839b7304e1f8d54cfcaf38e88b";
const BASE_HANDLER_EVENTS_SHA256 =
  "2e4d8f233a6808a443db9b8c76c11e4c1965b5a637dccd56f9c5273d8c7d209c";

const HANDLER_MESSAGES = [
  { isFromMe: true, content: "週末去哪玩" },
  { isFromMe: false, content: "去爬山，腿快斷了，你呢？" },
];
const HANDLER_TAGS = JSON.parse(fixtureCase("she_teases_him#1").readText);
const HANDLER_CARDS = [1, 2, 3, 4, 5].map((card) =>
  JSON.stringify({
    card,
    messages: [`爬完還能打字，體力不錯（${card}）`],
    hasInventedDetail: false,
  })
);

function runHandler(flag: string | undefined): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages: HANDLER_MESSAGES,
      billingProtocolVersion: 3,
      analysisContractVersion: 3,
    },
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
      [FLAG]: flag,
    },
    model: (modelBody) =>
      Promise.resolve(
        modelBody.stream === true
          ? fakeWriteResponse(HANDLER_CARDS)
          : fakeReadResponse(HANDLER_TAGS),
      ),
  });
}

/// done 的 telemetry 有實際花的毫秒數，每次都不一樣；其他欄位都要一樣。
function eventsWithoutTiming(
  events: readonly Record<string, unknown>[],
): unknown[] {
  return events.map((e) => {
    if (e.type !== "analysis.done") return e;
    const strip = (r: unknown) => {
      const { telemetry: _t, ...rest } = r as Record<string, unknown>;
      return rest;
    };
    return { ...e, finalResult: strip(e.finalResult), result: strip(e.result) };
  });
}

Deno.test("關係訊號開關沒開（沒設、off、打錯、test 但不是測試帳號）：走 handler 送給模型的請求、扣費與事件跟 afa50d6f 一樣", async () => {
  for (const flag of [undefined, "off", "maybe", "test"]) {
    const out = await runHandler(flag);
    assertEquals(out.status, 200, String(flag));
    assertEquals(out.modelBodies.length, 2, "讀局面＋寫卡各一次");
    assertEquals(
      await sha256(out.modelBodies),
      BASE_HANDLER_MODEL_BODIES_SHA256,
      String(flag),
    );
    assertEquals(
      await sha256(out.rpcs),
      BASE_HANDLER_RPCS_SHA256,
      String(flag),
    );
    assertEquals(
      await sha256(eventsWithoutTiming(out.events)),
      BASE_HANDLER_EVENTS_SHA256,
      String(flag),
    );
    for (const stored of [out.events, out.rpcs, out.finalResult]) {
      assert(!JSON.stringify(stored).includes('"relation"'), String(flag));
    }
  }
});
