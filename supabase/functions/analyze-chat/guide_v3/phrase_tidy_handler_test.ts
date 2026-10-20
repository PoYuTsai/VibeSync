// 「這題」「滿→蠻」交給程式（開關 ANALYZE_GUIDE_V3_PHRASE_TIDY，Bruce 2026-10-20 PR #97 再處理）從
// 正式入口走（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定；開了送出的卡、存的
// 結果與說明步驟都是改過的字，而且是口吻與斷句改完之後才改；沒開一字不變。事件照種類找。
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
import { TEST_EMAILS } from "../../_shared/quota.ts";
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

/// 她剪了頭髮、最新這一輪問會不會很怪（他沒有打過你／妳、用空白斷句）。
const MESSAGES = [
  { isFromMe: true, content: "今天休假在幹嘛" },
  { isFromMe: false, content: "下午去剪頭髮了" },
  { isFromMe: false, content: "[照片：她的自拍，短髮]" },
  { isFromMe: false, content: "比想像中短很多" },
  { isFromMe: false, content: "會很怪嗎" },
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
  readForUser: "她剪了短髮，問你會不會很怪。",
  waitFor: "",
};

const EXTRAS = {
  establishedCouple: false,
  herAffection: false,
  herHappyShare: false,
  worthyLines: [
    { line: 2, label: "照片", kind: "照片或貼圖" },
    { line: 4, label: "問他會不會很怪", kind: "問他" },
  ],
};

/// 模型寫的卡：有逗號與「妳」（口吻與斷句先改），再有「滿」「這題」（這一步才改）；「不怪啊」那條不用（Bruce
/// 2026-10-21），她就算問會不會很怪也照原文。
const CARD_MESSAGES = ["不怪啊，滿適合妳的", "這題不用想，短髮很好看。"];
/// 只開口吻與斷句：逗號換空白、句尾句號拿掉、他沒有稱呼習慣用「你」。
const TYPED = ["不怪啊 滿適合你的", "這題不用想 短髮很好看"];
/// 再開「這題」「滿→蠻」。
const TIDIED = ["不怪啊 蠻適合你的", "短髮很好看"];

function userText(body: Record<string, unknown>): string {
  return (body.messages as { content: string }[])[0].content;
}

function analyze(
  phraseTidy: string | undefined,
  explains: string[],
  email?: string,
): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages: MESSAGES,
      billingProtocolVersion: BILLING_PROTOCOL_VERSION,
      analysisContractVersion: ANALYSIS_CONTRACT_VERSION_V3,
    },
    ...(email ? { email } : {}),
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
      ANALYZE_GUIDE_V3_RELATION: undefined,
      ANALYZE_GUIDE_V3_TWO_STAGE: "on",
      ANALYZE_GUIDE_V3_TYPING_STYLE: "on",
      ANALYZE_GUIDE_V3_PHRASE_TIDY: phraseTidy,
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

type PhraseTidyTrace = {
  herQuizWords: boolean;
  changes: Record<string, number>;
};

Deno.test("從正式入口：ANALYZE_GUIDE_V3_PHRASE_TIDY=on 時送出的卡在口吻與斷句之後再改（她問會不會很怪，「不怪啊」照原文）；存的結果與說明步驟看同一份字", async () => {
  const explains: string[] = [];
  const out = await analyze("on", explains);
  assertEquals(out.status, 200);
  const cards = out.events.filter((e) => e.type === "analysis.card");
  assert(cards.length >= 3);
  for (const card of cards) assertEquals(card.messages, TIDIED);
  const done = out.events.find((e) => e.type === "analysis.done")!;
  for (
    const card of (done.finalResult as { cards: { messages: unknown }[] })
      .cards
  ) {
    assertEquals(card.messages, TIDIED);
  }
  // 存進資料庫的（續看重播的就是這份）也是改過的字。
  for (
    const card of (out.finalResult as { cards: { messages: unknown }[] }).cards
  ) {
    assertEquals(card.messages, TIDIED);
  }
  assertEquals(explains.length, 1);
  assert(explains[0].includes(`- ${TIDIED[0]}\n- ${TIDIED[1]}`));
  assertEquals(explains[0].includes("這題"), false);
  const trace = out.finalResult?.guideV3Trace as {
    phraseTidy: PhraseTidyTrace;
    typingStyle: { changes: { commas: number } };
  };
  assertEquals(trace.phraseTidy.herQuizWords, false);
  assertEquals(trace.phraseTidy.changes, {
    quiz: cards.length,
    quizRewrite: 0,
    degree: cards.length,
    messages: cards.length * 2,
  });
  // 口吻與斷句照樣先跑（兩個逗號換成空白）。
  assertEquals(trace.typingStyle.changes.commas, cards.length * 2);
});

Deno.test("從正式入口：沒設、off、或 test 但不是測試帳號，卡只有口吻與斷句改過、trace 沒有 phraseTidy；test 加測試帳號就改", async () => {
  for (const phraseTidy of [undefined, "off", "test"]) {
    const out = await analyze(phraseTidy, []);
    assertEquals(out.status, 200, String(phraseTidy));
    const cards = out.events.filter((e) => e.type === "analysis.card");
    assert(cards.length >= 3);
    for (const card of cards) assertEquals(card.messages, TYPED);
    assertEquals(
      "phraseTidy" in (out.finalResult?.guideV3Trace as object),
      false,
    );
  }
  const testAccount = await analyze("test", [], TEST_EMAILS[0]);
  assertEquals(testAccount.status, 200);
  const cards = testAccount.events.filter((e) => e.type === "analysis.card");
  assert(cards.length >= 3);
  for (const card of cards) assertEquals(card.messages, TIDIED);
});
