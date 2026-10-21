// 帶張力改寫法 v2（開關 ANALYZE_GUIDE_V3_TENSION_STYLE，Bruce 2026-10-21「改」：推拉換成三條不要）從正式入口走
//（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定。開時排卡不變（帶張力照排），寫卡
// 與說明看到的帶張力推拉那一條換成三條不要；沒開一字不變；自傷關心照舊不打寫卡。事件照種類找。
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
  TENSION_STYLE_EXPLAIN_RULE,
  TENSION_STYLE_EXPLAIN_SENTINELS,
} from "./explain.ts";
import {
  TENSION_STYLE_LINE,
  TENSION_STYLE_WRITER_SENTINELS,
  TWO_STAGE_TENSION_LINE,
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

/// 她吃了他推薦的拉麵（曖昧期，綠燈）：兩段式照今天會排一張帶張力。
const MESSAGES = [
  { isFromMe: true, content: "我先去洗澡" },
  { isFromMe: false, content: "好～" },
  { isFromMe: false, content: "你上次說的那家拉麵我今天去吃了" },
  { isFromMe: false, content: "真的很好吃欸" },
];

const READ = {
  light: "green",
  herMove: "生活",
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
  readForUser: "她去吃了你推薦的店，回來跟你分享。",
  waitFor: "",
  establishedCouple: false,
  herAffection: false,
  herHappyShare: false,
  worthyLines: [
    { line: 2, label: "去吃了那家拉麵", kind: "其他" },
    { line: 3, label: "說很好吃", kind: "情感" },
  ],
};

type Rec = Record<string, unknown>;

function userText(body: Rec): string {
  return (body.messages as { content: string }[])[0].content;
}

function systemText(body: Rec): string {
  const system = body.system;
  return typeof system === "string"
    ? system
    : (system as { text: string }[]).map((s) => s.text).join("\n");
}

function analyze(args: {
  readonly env: Record<string, string | undefined>;
  readonly read?: Rec;
  readonly cardText?: (card: number) => string | undefined;
  readonly explainText?: (card: number) => string | undefined;
}): Promise<V3HarnessOutcome> {
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
                messages: [args.cardText?.(i + 1) ?? `好吃就好 第 ${i + 1} 張`],
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
              slots.map((card) => ({
                card,
                text: args.explainText?.(card) ?? `第 ${card} 張的道理。`,
              })),
            ),
          );
        }
        default:
          return Promise.resolve(fakeReadResponse(args.read ?? READ));
      }
    },
  });
}

const bodyOf = (out: V3HarnessOutcome, stage: string) =>
  out.modelBodies.find((b) => v3HarnessStage(b) === stage);
const tasksOf = (out: V3HarnessOutcome) =>
  out.events.filter((e) => e.type === "analysis.card").map((e) => e.task);

Deno.test("從正式入口：ANALYZE_GUIDE_V3_TENSION_STYLE=on，帶張力照排（卡的任務跟沒開一樣），寫卡與說明看到的推拉那一條換成三條不要", async () => {
  const off = await analyze({ env: {} });
  const on = await analyze({ env: { ANALYZE_GUIDE_V3_TENSION_STYLE: "on" } });
  assertEquals(on.status, 200);
  assertEquals(tasksOf(on), tasksOf(off));
  assertEquals(tasksOf(on).filter((t) => t === "tension").length, 1);
  const writeOn = systemText(bodyOf(on, "write")!);
  assert(writeOn.includes(TENSION_STYLE_LINE));
  assertEquals(writeOn.includes("  - 推拉："), false);
  // 帶張力的定義與手法照兩段式原本的寫法。
  assert(writeOn.includes(TWO_STAGE_TENSION_LINE));
  assert(writeOn.includes("刻意誤解"));
  // 寫卡的使用者訊息（規格）不變。
  assertEquals(
    userText(bodyOf(on, "write")!),
    userText(bodyOf(off, "write")!),
  );
  const explainOn = bodyOf(on, "explain")!;
  assert(systemText(explainOn).includes(TENSION_STYLE_EXPLAIN_RULE));
  assert(userText(explainOn).includes(TENSION_STYLE_LINE));
  assert(on.events.some((e) => e.type === "analysis.card_explain"));
});

Deno.test("從正式入口：帶張力改寫法沒設、off、或 test 但不是測試帳號，寫卡與說明的提示詞照舊", async () => {
  for (const flag of [undefined, "off", "test"]) {
    const out = await analyze({
      env: { ANALYZE_GUIDE_V3_TENSION_STYLE: flag },
    });
    assertEquals(out.status, 200, String(flag));
    const write = systemText(bodyOf(out, "write")!);
    assert(write.includes(TWO_STAGE_TENSION_LINE));
    assert(write.includes("  - 推拉："));
    assertEquals(write.includes(TENSION_STYLE_LINE), false);
    assertEquals(
      systemText(bodyOf(out, "explain")!).includes(TENSION_STYLE_EXPLAIN_RULE),
      false,
    );
  }
});

Deno.test("從正式入口：帶張力改寫法開，卡片照抄新寫法的字就拿掉那張；說明照抄新規則就不給那張的說明", async () => {
  const out = await analyze({
    env: { ANALYZE_GUIDE_V3_TENSION_STYLE: "on" },
    cardText: (card) =>
      card === 1 ? `好吃 ${TENSION_STYLE_WRITER_SENTINELS[1]}` : undefined,
    explainText: (card) =>
      card === 2 ? `${TENSION_STYLE_EXPLAIN_SENTINELS[0]}。` : undefined,
  });
  assertEquals(out.status, 200);
  const trace = out.finalResult?.guideV3Trace as {
    removed: { slot: number; reason: string }[];
    twoStage: { explain: { removed: { card: number; reason: string }[] } };
  };
  assertEquals(trace.removed.map((r) => [r.slot, r.reason]), [[
    1,
    "prompt_leak",
  ]]);
  assertEquals(trace.twoStage.explain.removed, [{
    card: 2,
    reason: "blocked",
  }]);
  const off = await analyze({
    env: {},
    cardText: (card) =>
      card === 1 ? `好吃 ${TENSION_STYLE_WRITER_SENTINELS[1]}` : undefined,
  });
  assertEquals(
    (off.finalResult?.guideV3Trace as { removed: unknown[] }).removed,
    [],
  );
});

Deno.test("從正式入口：帶張力改寫法開，自傷關心照舊（不打寫卡、不打說明，事件跟沒開一樣）", async () => {
  const care = { ...READ, selfHarmSignal: true };
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_TENSION_STYLE: "on" },
    read: care,
  });
  const off = await analyze({ env: {}, read: care });
  assertEquals(on.status, 200);
  assertEquals(bodyOf(on, "write"), undefined);
  assertEquals(bodyOf(on, "explain"), undefined);
  assertEquals(
    on.events.map((e) => e.type),
    off.events.map((e) => e.type),
  );
  assertEquals(
    on.events.find((e) => e.type === "analysis.done")?.decision ??
      on.events.find((e) => e.type === "analysis.read")?.decision,
    off.events.find((e) => e.type === "analysis.done")?.decision ??
      off.events.find((e) => e.type === "analysis.read")?.decision,
  );
});

Deno.test("從正式入口：帶張力改寫法開，說明照抄帶張力的新寫法（寫卡看到的那一條）就不送那張的說明（主審第 1 輪 P2）", async () => {
  const plain = await analyze({
    env: { ANALYZE_GUIDE_V3_TENSION_STYLE: "on" },
  });
  const tensionSlot = plain.events.find((e) =>
    e.type === "analysis.card" && e.task === "tension"
  )!.slot as number;
  const copying = (card: number) =>
    card === tensionSlot ? TENSION_STYLE_LINE : undefined;
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_TENSION_STYLE: "on" },
    explainText: copying,
  });
  assertEquals(on.status, 200);
  const trace = on.finalResult?.guideV3Trace as {
    twoStage: { explain: { removed: { card: number; reason: string }[] } };
  };
  assertEquals(trace.twoStage.explain.removed, [{
    card: tensionSlot,
    reason: "blocked",
  }]);
  const sent = on.events.filter((e) => e.type === "analysis.card_explain")
    .map((e) => e.card);
  assertEquals(sent.includes(tensionSlot), false);
  // 沒開時同一段不比（跟今天一樣送出）。
  const off = await analyze({ env: {}, explainText: copying });
  assertEquals(
    (off.finalResult?.guideV3Trace as typeof trace).twoStage.explain.removed,
    [],
  );
});
