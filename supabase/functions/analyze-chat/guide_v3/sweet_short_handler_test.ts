// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）從正式入口走（guide_v3/v3_stream_harness.ts：
// 假 Supabase、假模型）：env 每次請求設定。開著時讀局面 worthyLines 多一種「撒嬌」（提示詞、schema、檢查）；她這一輪有標成
// 撒嬌的很短的一則時，只有一張卡的規格回那句、多短回的指示，其他卡回她別的話；她沒有別的話就少出幾張。短回指示只比卡片、
// 不比說明。沒設、off、test 但不是測試帳號、兩段式沒開時一字不變。假讀局面跟真的模型一樣：schema 有撒嬌才標撒嬌，沒有就標
// 情感。對話全部新寫，事件照種類找。
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
  SWEET_SHORT_CARD_PART,
  SWEET_WORTHY_LINES_NOTE,
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

/// 已經在交往：她最新這一輪先撒嬌一句很短的甜話，再說逛街逛到腳痠（Bruce 2026-10-22 試的形狀，句子全新）。
const MESSAGES = [
  { isFromMe: true, content: "到家了嗎" },
  { isFromMe: false, content: "剛到 好累" },
  { isFromMe: true, content: "快去洗澡 早點睡" },
  { isFromMe: false, content: "要你陪🥺" },
  { isFromMe: false, content: "今天逛了一整天街 腳快斷了" },
];
/// 同一段對話，她最新這一輪只有那句甜話。
const SWEET_ONLY = MESSAGES.slice(0, 4);

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
  worthyBallCount: 2,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "你們在交往，她跟你撒嬌要你陪，也說逛街逛到腳痠。",
  waitFor: "",
  establishedCouple: true,
  herAffection: true,
  herHappyShare: false,
  // 甜話那則的 kind 寫「撒嬌」；請求的 schema 沒有撒嬌（開關沒開）時，readFor 換成情感，跟真的模型一樣。
  worthyLines: [
    { line: 1, label: "要他陪", kind: "撒嬌" },
    { line: 2, label: "腳痠", kind: "其他" },
  ],
};
const READ_SWEET_ONLY = {
  ...READ,
  worthyBallCount: 1,
  worthyLines: [{ line: 1, label: "要他陪", kind: "撒嬌" }],
};

type Rec = Record<string, unknown>;

/// 這次讀局面請求的 schema 裡 worthyLines 的 kind 可以填哪些。
function kindsOf(body: Rec): string[] {
  const schema = (body.output_config as
    | { format?: { schema?: Rec } }
    | undefined)?.format?.schema as
      | {
        properties?: {
          worthyLines?: {
            items?: { properties?: { kind?: { enum?: string[] } } };
          };
        };
      }
      | undefined;
  return schema?.properties?.worthyLines?.items?.properties?.kind?.enum ?? [];
}

/// 假讀局面：schema 沒有撒嬌時，撒嬌那則改標情感（真的模型照 schema 只能填有的種類）。
function readFor(read: Rec, body: Rec): Rec {
  if (kindsOf(body).includes("撒嬌")) return read;
  return {
    ...read,
    worthyLines: (read.worthyLines as { kind: string }[]).map((w) =>
      w.kind === "撒嬌" ? { ...w, kind: "情感" } : w
    ),
  };
}

function userText(body: Rec): string {
  return (body.messages as { content: string }[])[0].content;
}

function analyze(args: {
  readonly env: Record<string, string | undefined>;
  readonly messages?: readonly { isFromMe: boolean; content: string }[];
  readonly read?: Rec;
  /// 讀局面照原樣回（不照 schema 換種類）：測開關沒開時讀局面標了撒嬌會怎樣。
  readonly rawRead?: boolean;
  readonly email?: string;
  readonly cardText?: (card: number) => string | undefined;
  readonly explainText?: (card: number) => string | undefined;
}): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages: args.messages ?? MESSAGES,
      billingProtocolVersion: BILLING_PROTOCOL_VERSION,
      analysisContractVersion: ANALYSIS_CONTRACT_VERSION_V3,
    },
    ...(args.email ? { email: args.email } : {}),
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
      ANALYZE_GUIDE_V3_RELATION: undefined,
      ANALYZE_GUIDE_V3_TWO_STAGE: "on",
      ANALYZE_GUIDE_V3_TYPING_STYLE: undefined,
      ANALYZE_GUIDE_V3_SHORT_PRAISE: undefined,
      ANALYZE_GUIDE_V3_TENSION_STYLE: undefined,
      ANALYZE_GUIDE_V3_PHRASE_TIDY: undefined,
      ANALYZE_GUIDE_V3_SWEET_SHORT: undefined,
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
                messages: [args.cardText?.(i + 1) ?? `陪你啊 第 ${i + 1} 張`],
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
          return Promise.resolve(
            fakeReadResponse(
              args.rawRead
                ? (args.read ?? READ)
                : readFor(args.read ?? READ, body),
            ),
          );
      }
    },
  });
}

const bodyOf = (out: V3HarnessOutcome, stage: string) =>
  out.modelBodies.find((b) => v3HarnessStage(b) === stage);
const specsOf = (out: V3HarnessOutcome) =>
  (out.finalResult?.guideV3Trace as {
    specs: { sweetShort?: boolean; answer?: { main: { line: number } } }[];
  }).specs;
const specLines = (write: string) =>
  write.split("\n").filter((l) => /^\d\. 任務：/.test(l));
const cardsOf = (out: V3HarnessOutcome) =>
  out.events.filter((e) => e.type === "analysis.card");

Deno.test("從正式入口：ANALYZE_GUIDE_V3_SWEET_SHORT=on、她這一輪有很短的甜話：只有第一張不是推進的卡回那句、多短回的指示，其他卡回她別的話；說明看到同一份；trace 標在那一張", async () => {
  const out = await analyze({ env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" } });
  assertEquals(out.status, 200);
  const write = userText(bodyOf(out, "write")!);
  assertEquals(write.split(SWEET_SHORT_CARD_PART).length - 1, 1);
  const lines = specLines(write);
  assertEquals(lines.length, 5);
  assert(
    lines[0].startsWith(
      "1. 任務：推進（種子）｜這張接：她的「今天逛了一整天街",
    ),
  );
  assert(
    lines[1].includes(`這張接：她的「要你陪」｜${SWEET_SHORT_CARD_PART}｜`),
    lines[1],
  );
  for (const [i, line] of lines.entries()) {
    if (i !== 1) assertEquals(line.includes("要你陪"), false, line);
  }
  const explain = userText(bodyOf(out, "explain")!);
  assertEquals(explain.split(SWEET_SHORT_CARD_PART).length - 1, 1);
  const specs = specsOf(out);
  assertEquals(specs.flatMap((s, i) => s.sweetShort ? [i] : []), [1]);
  assertEquals(cardsOf(out).length, 5);
  assertEquals(
    out.events.filter((e) => e.type === "analysis.card_explain").length,
    5,
  );
});

Deno.test("從正式入口：甜話短回沒設、off、test 但不是測試帳號：規格與說明都沒有短回那段，每張卡照舊都回那句甜話；test 加測試帳號就排", async () => {
  for (const flag of [undefined, "off", "test", "true"]) {
    const out = await analyze({ env: { ANALYZE_GUIDE_V3_SWEET_SHORT: flag } });
    assertEquals(out.status, 200, String(flag));
    const write = userText(bodyOf(out, "write")!);
    assertEquals(write.includes(SWEET_SHORT_CARD_PART), false, String(flag));
    for (const line of specLines(write)) {
      assert(line.includes("這張接：她的「要你陪」｜可以順帶："), line);
    }
    assertEquals(
      userText(bodyOf(out, "explain")!).includes(SWEET_SHORT_CARD_PART),
      false,
    );
    assertEquals(specsOf(out).some((s) => s.sweetShort), false);
    assertEquals(cardsOf(out).length, 5);
  }
  const testAccount = await analyze({
    env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "test" },
    email: TEST_EMAILS[0],
  });
  assertEquals(testAccount.status, 200);
  assertEquals(
    userText(bodyOf(testAccount, "write")!).split(SWEET_SHORT_CARD_PART)
      .length - 1,
    1,
  );
  assertEquals(
    specsOf(testAccount).filter((s) => s.sweetShort).length,
    1,
  );
});

Deno.test("從正式入口：甜話短回開、兩段式沒開：不排（只在兩段式開時有作用），寫卡的使用者訊息跟兩個都沒開一樣", async () => {
  const twoStageOff = { ANALYZE_GUIDE_V3_TWO_STAGE: undefined };
  const on = await analyze({
    env: { ...twoStageOff, ANALYZE_GUIDE_V3_SWEET_SHORT: "on" },
  });
  const off = await analyze({ env: twoStageOff });
  assertEquals(on.status, 200);
  assertEquals(
    userText(bodyOf(on, "write")!),
    userText(bodyOf(off, "write")!),
  );
  assertEquals(
    userText(bodyOf(on, "write")!).includes(SWEET_SHORT_CARD_PART),
    false,
  );
  assertEquals(bodyOf(on, "explain"), undefined);
  assertEquals(specsOf(on).some((s) => s.sweetShort), false);
});

Deno.test("從正式入口：甜話短回開、她只傳那句甜話：少出幾張（4→3），每張都回那句、都帶短回指示；沒開照舊 4 張", async () => {
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" },
    messages: SWEET_ONLY,
    read: READ_SWEET_ONLY,
  });
  assertEquals(on.status, 200);
  const write = userText(bodyOf(on, "write")!);
  assert(write.includes("## 卡片規格（照順序寫，一共 3 張）"));
  const lines = specLines(write);
  assertEquals(lines.length, 3);
  for (const line of lines) {
    assert(
      line.includes(`這張接：她的「要你陪」｜${SWEET_SHORT_CARD_PART}｜`),
      line,
    );
    assertEquals(line.includes("切入點要跟前面同規格的卡不同"), false);
  }
  assertEquals(cardsOf(on).length, 3);
  assertEquals(
    (on.events.find((e) => e.type === "analysis.read")!
      .plannedCards as unknown[]).length,
    3,
  );
  assertEquals(specsOf(on).every((s) => s.sweetShort === true), true);
  const off = await analyze({
    env: {},
    messages: SWEET_ONLY,
    read: READ_SWEET_ONLY,
  });
  assertEquals(cardsOf(off).length, 4);
  assertEquals(specsOf(off).some((s) => s.sweetShort), false);
});

Deno.test("從正式入口：甜話短回排到時，卡片照抄短回指示就拿掉那張；沒開不比", async () => {
  const leaky = (card: number) =>
    card === 2 ? `陪你 ${SWEET_SHORT_CARD_PART}` : undefined;
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" },
    cardText: leaky,
  });
  const removed = (on.finalResult?.guideV3Trace as {
    removed: { slot: number; reason: string }[];
  }).removed;
  assertEquals(removed.map((r) => [r.slot, r.reason]), [[2, "prompt_leak"]]);
  assertEquals(cardsOf(on).length, 4);
  const off = await analyze({ env: {}, cardText: leaky });
  assertEquals(
    (off.finalResult?.guideV3Trace as { removed: unknown[] }).removed,
    [],
  );
});

Deno.test("從正式入口：甜話短回排到時，說明寫到「短短回她一句就好」照送（只比卡片）；卡片寫到同一句照樣拿掉", async () => {
  const natural = (card: number) =>
    card === 2 ? `她撒嬌要你陪，這張${SWEET_SHORT_CARD_PART}。` : undefined;
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" },
    explainText: natural,
  });
  assertEquals(on.status, 200);
  const explainOf = (out: V3HarnessOutcome) => ({
    sent: out.events.filter((e) => e.type === "analysis.card_explain").map((
      e,
    ) => e.card),
    removed: (out.finalResult?.guideV3Trace as {
      twoStage: { explain: { removed: { card: number; reason: string }[] } };
    }).twoStage.explain.removed,
  });
  assertEquals(explainOf(on).removed, []);
  assertEquals(explainOf(on).sent, [1, 2, 3, 4, 5]);
  assert(
    on.events.some((e) =>
      e.type === "analysis.card_explain" && e.card === 2 &&
      String(e.text).includes(SWEET_SHORT_CARD_PART)
    ),
  );
  // 同一次分析，卡片寫到這一句照樣拿掉（卡片的哨兵不變）。
  const both = await analyze({
    env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" },
    explainText: natural,
    cardText: (card) =>
      card === 3 ? `陪你 ${SWEET_SHORT_CARD_PART}` : undefined,
  });
  assertEquals(
    (both.finalResult?.guideV3Trace as {
      removed: { slot: number; reason: string }[];
    }).removed.map((r) => [r.slot, r.reason]),
    [[3, "prompt_leak"]],
  );
  assertEquals(explainOf(both).removed, []);
});

Deno.test("從正式入口：甜話短回開時讀局面的請求換 worthyLines 那一條、schema 多撒嬌；沒開時讀局面的提示詞與 schema 都沒有撒嬌", async () => {
  const systemOf = (body: Rec) =>
    typeof body.system === "string"
      ? body.system
      : (body.system as { text?: string }[]).map((b) => b.text ?? "").join("");
  const on = await analyze({ env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" } });
  const readOn = bodyOf(on, "read")!;
  assert(systemOf(readOn).includes(SWEET_WORTHY_LINES_NOTE));
  assert(kindsOf(readOn).includes("撒嬌"));
  for (const flag of [undefined, "off", "test"]) {
    const off = await analyze({ env: { ANALYZE_GUIDE_V3_SWEET_SHORT: flag } });
    const readOff = bodyOf(off, "read")!;
    assertEquals(systemOf(readOff).includes(SWEET_WORTHY_LINES_NOTE), false);
    assertEquals(systemOf(readOff).includes("「撒嬌」"), false);
    assertEquals(kindsOf(readOff).includes("撒嬌"), false, String(flag));
  }
});

Deno.test("從正式入口：甜話短回沒開時讀局面標了撒嬌（schema 本來就不給）照今天一樣算讀局面失敗、不扣；開著才收", async () => {
  const off = await analyze({ env: {}, rawRead: true });
  assertEquals(off.status, 200);
  const error = off.events.find((e) => e.type === "analysis.error");
  assertEquals(error?.code, "GUIDE_V3_READ_INVALID");
  assertEquals(off.events.some((e) => e.type === "analysis.card"), false);
  assertEquals(
    off.rpcs.some((r) => r.fn === "charge_stream_analysis_run_v3"),
    false,
  );
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_SWEET_SHORT: "on" },
    rawRead: true,
  });
  assertEquals(on.events.some((e) => e.type === "analysis.error"), false);
  assertEquals(on.events.filter((e) => e.type === "analysis.card").length, 5);
});
