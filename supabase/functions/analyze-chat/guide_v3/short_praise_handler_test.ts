// 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE，Bruce 2026-10-20「可以」）從正式入口走
//（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定。開著、這次的 runId 抽到短版時，
// 一張卡的規格與說明在「這張接」後面寫短版的誇法；沒開或沒抽到一字不變。事件照種類找。
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
import { lightShortRun } from "./rules.ts";
import {
  LIGHT_SHORT_CARD_PART,
  SHORT_PRAISE_WRITER_SENTINELS,
} from "./two_stage_prompts.ts";
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

/// 抽得到、抽不到短版的兩個 runId（照 rules.ts lightShortRun 找，固定）。
const IDS = Array.from(
  { length: 40 },
  (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
);
const PICKED = IDS.find(lightShortRun)!;
const NOT_PICKED = IDS.find((id) => !lightShortRun(id))!;

/// 她剪了頭髮、問他會不會很奇怪（還沒交往）。
const MESSAGES = [
  { isFromMe: true, content: "今天去哪" },
  { isFromMe: false, content: "[照片：剛剪好的短髮自拍]" },
  { isFromMe: false, content: "會不會很奇怪" },
];

const READ = {
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
  readForUser: "她剪了頭髮，想知道你覺得好不好看。",
  waitFor: "",
  establishedCouple: false,
  herAffection: false,
  herHappyShare: false,
  worthyLines: [
    { line: 1, label: "自拍", kind: "照片或貼圖" },
    { line: 2, label: "問會不會怪", kind: "問他" },
  ],
};

type Rec = Record<string, unknown>;

function userText(body: Rec): string {
  return (body.messages as { content: string }[])[0].content;
}

function analyze(args: {
  readonly env: Record<string, string | undefined>;
  readonly runId: string;
  readonly cardText?: (card: number) => string | undefined;
}): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    runId: args.runId,
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
      ANALYZE_GUIDE_V3_TYPING_STYLE: undefined,
      ANALYZE_GUIDE_V3_SHORT_PRAISE: undefined,
      ANALYZE_GUIDE_V3_TENSION_STYLE: undefined,
      ...args.env,
    },
    model: (body) => {
      switch (v3HarnessStage(body)) {
        case "write": {
          const n = Number(userText(body).match(/一共 (\d+) 張/)?.[1] ?? 0);
          return Promise.resolve(fakeWriteResponse(
            Array.from({ length: n }, (_, i) =>
              JSON.stringify({
                card: i + 1,
                messages: [args.cardText?.(i + 1) ?? `好看啊 第 ${i + 1} 張`],
                hasInventedDetail: false,
              })),
          ));
        }
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
          return Promise.resolve(fakeReadResponse(READ));
      }
    },
  });
}

const bodyOf = (out: V3HarnessOutcome, stage: string) =>
  out.modelBodies.find((b) => v3HarnessStage(b) === stage)!;
const specsOf = (out: V3HarnessOutcome) =>
  (out.finalResult?.guideV3Trace as { specs: { shortPraise?: boolean }[] })
    .specs;

Deno.test("從正式入口：ANALYZE_GUIDE_V3_SHORT_PRAISE=on、這次的 runId 抽到短版：一張卡的規格與說明在「這張接」後面寫短版的誇法；trace 標在那一張", async () => {
  const out = await analyze({
    env: { ANALYZE_GUIDE_V3_SHORT_PRAISE: "on" },
    runId: PICKED,
  });
  assertEquals(out.status, 200);
  assertEquals(
    out.events.find((e) => e.type === "analysis.started")!.runId,
    PICKED,
  );
  const write = userText(bodyOf(out, "write"));
  assertEquals(write.split(LIGHT_SHORT_CARD_PART).length - 1, 1);
  assert(
    write.includes(
      `這張接：她的「會不會很奇怪」（連同第 1 則）｜${LIGHT_SHORT_CARD_PART}｜`,
    ),
  );
  const explain = userText(bodyOf(out, "explain"));
  assertEquals(explain.split(LIGHT_SHORT_CARD_PART).length - 1, 1);
  const specs = specsOf(out);
  assertEquals(specs.filter((s) => s.shortPraise).length, 1);
  const cards = out.events.filter((e) => e.type === "analysis.card");
  assert(cards.length >= 3);
  assert(out.events.some((e) => e.type === "analysis.card_explain"));
});

Deno.test("從正式入口：短版稱讚沒設、off、test 但不是測試帳號，或這次沒抽到：規格與說明都沒有短版那段", async () => {
  for (const flag of [undefined, "off", "test"]) {
    const out = await analyze({
      env: { ANALYZE_GUIDE_V3_SHORT_PRAISE: flag },
      runId: PICKED,
    });
    assertEquals(out.status, 200, String(flag));
    assertEquals(
      userText(bodyOf(out, "write")).includes(LIGHT_SHORT_CARD_PART),
      false,
    );
    assertEquals(specsOf(out).some((s) => s.shortPraise), false);
  }
  const notPicked = await analyze({
    env: { ANALYZE_GUIDE_V3_SHORT_PRAISE: "on" },
    runId: NOT_PICKED,
  });
  assertEquals(
    userText(bodyOf(notPicked, "write")).includes(LIGHT_SHORT_CARD_PART),
    false,
  );
  assertEquals(
    userText(bodyOf(notPicked, "explain")).includes(LIGHT_SHORT_CARD_PART),
    false,
  );
});

Deno.test("從正式入口：短版稱讚開，卡片照抄規格裡短版那段就拿掉那張；沒開不比", async () => {
  const leaky = (card: number) =>
    card === 1 ? `好看 ${SHORT_PRAISE_WRITER_SENTINELS[1]}` : undefined;
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_SHORT_PRAISE: "on" },
    runId: NOT_PICKED,
    cardText: leaky,
  });
  const removed = (on.finalResult?.guideV3Trace as {
    removed: { slot: number; reason: string }[];
  }).removed;
  assertEquals(removed.map((r) => [r.slot, r.reason]), [[1, "prompt_leak"]]);
  const off = await analyze({ env: {}, runId: NOT_PICKED, cardText: leaky });
  assertEquals(
    (off.finalResult?.guideV3Trace as { removed: unknown[] }).removed,
    [],
  );
});
