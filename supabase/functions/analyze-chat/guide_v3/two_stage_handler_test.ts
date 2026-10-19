// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）從正式入口走（guide_v3/
// v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定，開了才多打說明那一跳、讀局面
// 用多四欄的 schema；沒設就跟今天一樣只有讀局面與寫卡。事件照種類找。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import，入口模組
// 也要在 env 裝好之後才動態載入（STREAM_ANALYZE_ENABLED 是載入時讀的常數）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { BILLING_PROTOCOL_VERSION } from "../billing.ts";
import { ANALYSIS_CONTRACT_VERSION_V3 } from "../no_send_decision.ts";
import { READ_TAGS_SCHEMA, READ_TAGS_SCHEMA_TWO_STAGE } from "./read_tags.ts";
import {
  fakeExplainResponse,
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
  type V3HarnessOutcome,
  v3HarnessStage,
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

const MESSAGES = [
  { isFromMe: true, content: "晚餐吃什麼？" },
  { isFromMe: false, content: "[照片：一盤咖哩飯]" },
  { isFromMe: false, content: "我自己煮的！" },
];

const TAGS = {
  light: "green",
  herMove: "高點",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: false,
  replyWillingness: "high",
  worthyBallCount: 1,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "她在分享自己煮的晚餐。",
  waitFor: "",
};

const EXTRAS = {
  establishedCouple: false,
  herAffection: false,
  herHappyShare: true,
  worthyLines: [
    { line: 2, label: "自己煮的", kind: "其他" },
    { line: 1, label: "咖哩照片", kind: "照片或貼圖" },
  ],
};

function userText(body: Record<string, unknown>): string {
  return (body.messages as { content: string }[])[0].content;
}

function writeCards(user: string): string[] {
  const n = Number(user.match(/一共 (\d+) 張/)?.[1] ?? 0);
  return Array.from({ length: n }, (_, i) =>
    JSON.stringify({
      card: i + 1,
      messages: [`看起來很好吃（第 ${i + 1} 張）`],
      hasInventedDetail: false,
    }));
}

function analyze(
  twoStage: string | undefined,
  email?: string,
): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    ...(email ? { email } : {}),
    body: {
      responseMode: "stream",
      messages: MESSAGES,
      billingProtocolVersion: BILLING_PROTOCOL_VERSION,
      analysisContractVersion: ANALYSIS_CONTRACT_VERSION_V3,
    },
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
      ANALYZE_GUIDE_V3_TWO_STAGE: twoStage,
    },
    model: (body) => {
      switch (v3HarnessStage(body)) {
        case "write":
          return Promise.resolve(fakeWriteResponse(writeCards(userText(body))));
        case "explain": {
          const slots = [...userText(body).matchAll(/### 第 (\d+) 張/g)].map((
            m,
          ) => Number(m[1]));
          return Promise.resolve(
            fakeExplainResponse(
              slots.map((card) => ({ card, text: `第 ${card} 張的道理。` })),
            ),
          );
        }
        default:
          return Promise.resolve(fakeReadResponse({ ...TAGS, ...EXTRAS }));
      }
    },
  });
}

Deno.test("從正式入口：ANALYZE_GUIDE_V3_TWO_STAGE=on 時讀局面多四欄、寫完卡多打一次說明，每張卡一則說明在 done 之前", async () => {
  const out = await analyze("on");
  assertEquals(out.status, 200);
  assertEquals(out.modelBodies.map(v3HarnessStage), [
    "read",
    "write",
    "explain",
  ]);
  const read = out.modelBodies[0].output_config as {
    format: { schema: unknown };
  };
  assertEquals(read.format.schema, READ_TAGS_SCHEMA_TWO_STAGE);
  const cards = out.events.filter((e) => e.type === "analysis.card");
  const explained = out.events.filter((e) =>
    e.type === "analysis.card_explain"
  );
  assert(cards.length >= 3);
  assertEquals(explained.map((e) => e.card), cards.map((c) => c.slot));
  const kinds = out.events.map((e) => String(e.type));
  assert(
    kinds.lastIndexOf("analysis.card") < kinds.indexOf("analysis.card_explain"),
  );
  assertEquals(kinds.at(-1), "analysis.done");
  // 扣費只有一次，跟沒開一樣。
  assertEquals(
    out.rpcs.filter((r) => r.fn === "charge_stream_analysis_run_v3").length,
    1,
  );
  const trace = out.finalResult?.guideV3Trace as {
    twoStage: { explain: { status: string } };
  };
  assertEquals(trace.twoStage.explain.status, "ok");
});

Deno.test("從正式入口：沒設、off、或 test 但不是測試帳號，都跟今天一樣（沒有說明那一跳、讀局面 schema 照舊）", async () => {
  for (const twoStage of [undefined, "off", "test"]) {
    const out = await analyze(twoStage);
    assertEquals(out.status, 200, String(twoStage));
    assertEquals(
      out.modelBodies.map(v3HarnessStage),
      ["read", "write"],
      String(twoStage),
    );
    const read = out.modelBodies[0].output_config as {
      format: { schema: unknown };
    };
    assertEquals(read.format.schema, READ_TAGS_SCHEMA);
    assertEquals(
      out.events.filter((e) => e.type === "analysis.card_explain"),
      [],
    );
    assertEquals(
      "twoStage" in (out.finalResult?.guideV3Trace as object),
      false,
    );
  }
});
