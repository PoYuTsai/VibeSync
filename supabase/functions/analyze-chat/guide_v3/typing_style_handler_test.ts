// 口吻與斷句交給程式（開關 ANALYZE_GUIDE_V3_TYPING_STYLE，Bruce 2026-10-20 改法 3）從正式入口走
//（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定；開了送出的卡、存的結果與
// 說明步驟都是照他習慣改過的字，沒開一字不變。事件照種類找。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import，入口模組也要在 env 裝好
// 之後才動態載入（STREAM_ANALYZE_ENABLED 是載入時讀的常數）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { BILLING_PROTOCOL_VERSION } from "../billing.ts";
import { ANALYSIS_CONTRACT_VERSION_V3 } from "../no_send_decision.ts";
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

/// 他打「妳」、用空白斷句。
const MESSAGES = [
  { isFromMe: true, content: "妳到家了嗎" },
  { isFromMe: false, content: "到了" },
  { isFromMe: true, content: "好 那妳先休息" },
  { isFromMe: false, content: "可是我還要加班" },
  { isFromMe: false, content: "你會不會覺得我很忙" },
];

const TAGS = {
  light: "green",
  herMove: "問他意見",
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
  hasHisVoiceSample: true,
  replyWillingness: "high",
  worthyBallCount: 1,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "她還要加班，問你會不會覺得她很忙。",
  waitFor: "",
};

const EXTRAS = {
  establishedCouple: false,
  herAffection: false,
  herHappyShare: false,
  worthyLines: [
    { line: 1, label: "還要加班", kind: "情感" },
    { line: 2, label: "問他會不會覺得很忙", kind: "問他" },
  ],
};

/// Bruce 的例子當卡：一張卡兩則，有逗號、有「你」也有「妳」。
const CARD_MESSAGES = ["好，那你先忙", "忙完有空再說，不急。"];

function userText(body: Record<string, unknown>): string {
  return (body.messages as { content: string }[])[0].content;
}

function analyze(
  typingStyle: string | undefined,
  explains: string[],
): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
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
      ANALYZE_GUIDE_V3_RELATION: undefined,
      ANALYZE_GUIDE_V3_TWO_STAGE: "on",
      ANALYZE_GUIDE_V3_TYPING_STYLE: typingStyle,
    },
    model: (body) => {
      switch (v3HarnessStage(body)) {
        case "write": {
          const n = Number(userText(body).match(/一共 (\d+) 張/)?.[1] ?? 0);
          return Promise.resolve(fakeWriteResponse(
            Array.from({ length: n }, (_, i) =>
              JSON.stringify({
                card: i + 1,
                messages: CARD_MESSAGES,
                hasInventedDetail: false,
              })),
          ));
        }
        case "explain": {
          explains.push(userText(body));
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

Deno.test("從正式入口：ANALYZE_GUIDE_V3_TYPING_STYLE=on 時送出的卡照他的習慣改（他打「妳」、用空白斷句）；存的結果與說明步驟看同一份字", async () => {
  const explains: string[] = [];
  const out = await analyze("on", explains);
  assertEquals(out.status, 200);
  const cards = out.events.filter((e) => e.type === "analysis.card");
  assert(cards.length >= 3);
  for (const card of cards) {
    assertEquals(card.messages, ["好 那妳先忙", "忙完有空再說 不急"]);
  }
  const done = out.events.find((e) => e.type === "analysis.done")!;
  for (
    const card of (done.finalResult as { cards: { messages: unknown }[] })
      .cards
  ) {
    assertEquals(card.messages, ["好 那妳先忙", "忙完有空再說 不急"]);
  }
  assertEquals(explains.length, 1);
  assert(explains[0].includes("- 好 那妳先忙\n- 忙完有空再說 不急"));
  assertEquals(explains[0].includes("好，那你先忙"), false);
  const trace = out.finalResult?.guideV3Trace as {
    typingStyle: {
      habits: { address: string; usesCommas: boolean; messages: number };
      changes: { address: number; commas: number; finalPeriods: number };
    };
  };
  assertEquals(trace.typingStyle.habits.address, "妳");
  assertEquals(trace.typingStyle.habits.usesCommas, false);
  assertEquals(trace.typingStyle.habits.messages, 2);
  assertEquals(trace.typingStyle.changes.address, cards.length);
  assertEquals(trace.typingStyle.changes.commas, cards.length * 2);
  assertEquals(trace.typingStyle.changes.finalPeriods, cards.length);
});

Deno.test("從正式入口：沒設、off、或 test 但不是測試帳號，卡一字不變、trace 沒有 typingStyle", async () => {
  for (const typingStyle of [undefined, "off", "test"]) {
    const out = await analyze(typingStyle, []);
    assertEquals(out.status, 200, String(typingStyle));
    const cards = out.events.filter((e) => e.type === "analysis.card");
    assert(cards.length >= 3);
    for (const card of cards) assertEquals(card.messages, CARD_MESSAGES);
    assertEquals(
      "typingStyle" in (out.finalResult?.guideV3Trace as object),
      false,
    );
  }
});
