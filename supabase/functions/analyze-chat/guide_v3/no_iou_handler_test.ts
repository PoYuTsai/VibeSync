// 不記帳不承諾（開關 ANALYZE_GUIDE_V3_NO_IOU，Bruce 2026-10-22 PR #97 盲選回覆；Eric 同日「回了 來處理吧」）從正式入口走
//（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定。開著時讀局面的提示詞在 herAffection 下面多 herTired
// 那一行、schema 多 herTired；已經在交往、她撒嬌或喊累時不排推進（種子）；寫卡的系統提示詞不變。沒設、off、test 但不是測試帳號、
// 兩段式沒開時一字不變；跟甜話短回各自獨立。假讀局面跟真的模型一樣：schema 有 herTired 才給、有撒嬌才標撒嬌。對話全部新寫，事件
// 照種類找。
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
import { HER_TIRED_NOTE, SWEET_SHORT_CARD_PART } from "./two_stage_prompts.ts";
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

/// 已經在交往：她站了九個小時、說小腿脹到不行想躺平（喊累，沒撒嬌、情緒不差；句子全新）。他傳過兩則，沒開時第一張是推進（種子）。
const MESSAGES = [
  { isFromMe: true, content: "下班了嗎" },
  { isFromMe: false, content: "剛下班 今天站了九個小時" },
  { isFromMe: true, content: "辛苦了 快回家休息" },
  { isFromMe: false, content: "小腿脹到不行 想趕快躺平" },
];
/// 同樣在交往，她最新這一輪只撒嬌一句很短的甜話（跟甜話短回一起開的形狀；句子全新）。
const SWEET_MESSAGES = [...MESSAGES.slice(0, 3), {
  isFromMe: false,
  content: "抱抱🥺",
}];

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
  readForUser: "你們在交往，她站了九個小時、說小腿脹到不行想躺平。",
  waitFor: "",
  establishedCouple: true,
  herAffection: false,
  // schema 沒有 herTired（開關沒開）時，readFor 拿掉這一欄，跟真的模型一樣。
  herTired: true,
  herHappyShare: false,
  worthyLines: [{ line: 1, label: "小腿脹想躺平", kind: "情感" }],
};
const READ_SWEET = {
  ...READ,
  readForUser: "你們在交往，她跟你撒嬌要抱抱。",
  herAffection: true,
  herTired: false,
  // schema 沒有撒嬌（甜話短回沒開）時，readFor 換成情感。
  worthyLines: [{ line: 1, label: "要抱抱", kind: "撒嬌" }],
};

type Rec = Record<string, unknown>;

function schemaOf(body: Rec): {
  required?: string[];
  properties?: Record<string, { enum?: string[] } | undefined> & {
    worthyLines?: { items?: { properties?: { kind?: { enum?: string[] } } } };
  };
} {
  return ((body.output_config as { format?: { schema?: unknown } } | undefined)
    ?.format?.schema ?? {}) as ReturnType<typeof schemaOf>;
}

/// 假讀局面：schema 沒有 herTired 就不給這一欄、沒有撒嬌就把撒嬌那則標成情感（真的模型照 schema 只能填有的欄位與種類）。
function readFor(read: Rec, body: Rec): Rec {
  const schema = schemaOf(body);
  const { herTired, ...rest } = read;
  const out: Rec = schema.properties && "herTired" in schema.properties
    ? { ...rest, herTired }
    : rest;
  const kinds = schema.properties?.worthyLines?.items?.properties?.kind?.enum ??
    [];
  if (kinds.includes("撒嬌")) return out;
  return {
    ...out,
    worthyLines: (out.worthyLines as { kind: string }[]).map((w) =>
      w.kind === "撒嬌" ? { ...w, kind: "情感" } : w
    ),
  };
}

function userText(body: Rec): string {
  return (body.messages as { content: string }[])[0].content;
}

function systemOf(body: Rec): string {
  return typeof body.system === "string"
    ? body.system
    : (body.system as { text?: string }[]).map((b) => b.text ?? "").join("");
}

function analyze(args: {
  readonly env: Record<string, string | undefined>;
  readonly messages?: readonly { isFromMe: boolean; content: string }[];
  readonly read?: Rec;
  /// 讀局面照原樣回（不照 schema 調整）：測缺欄位、多欄位。
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
      ANALYZE_GUIDE_V3_NO_IOU: undefined,
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
                messages: [args.cardText?.(i + 1) ?? `先躺一下 第 ${i + 1} 張`],
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
const traceOf = (out: V3HarnessOutcome) =>
  out.finalResult?.guideV3Trace as {
    push: string | null;
    tags: Rec;
    specs: { task: string; sweetShort?: boolean }[];
    removed: { slot: number; reason: string }[];
    twoStage?: {
      explain: { removed: { card: number; reason: string }[] };
    };
  };
const specLines = (write: string) =>
  write.split("\n").filter((l) => /^\d\. 任務：/.test(l));
const cardsOf = (out: V3HarnessOutcome) =>
  out.events.filter((e) => e.type === "analysis.card");
const planned = (out: V3HarnessOutcome) =>
  (out.events.find((e) => e.type === "analysis.read")!.plannedCards as {
    task: string;
  }[]).map((p) => p.task);

Deno.test("從正式入口：ANALYZE_GUIDE_V3_NO_IOU=on、交往中她喊累：讀局面的提示詞多 herTired 那一行、schema 多 herTired；寫卡的系統提示詞跟沒開一字不差；沒有推進（種子）、張數照舊；trace 記 herTired、push 是 null", async () => {
  const out = await analyze({ env: { ANALYZE_GUIDE_V3_NO_IOU: "on" } });
  assertEquals(out.status, 200);
  const read = bodyOf(out, "read")!;
  assert(systemOf(read).includes(HER_TIRED_NOTE));
  assert(schemaOf(read).required!.includes("herTired"));
  assert(schemaOf(read).properties && "herTired" in schemaOf(read).properties!);
  const write = bodyOf(out, "write")!;
  const offWrite = bodyOf(await analyze({ env: {} }), "write")!;
  assertEquals(systemOf(write), systemOf(offWrite));
  const lines = specLines(userText(write));
  assertEquals(lines.length, 4);
  for (const line of lines) {
    assert(line.includes("任務：接住｜"), line);
    assertEquals(line.includes("推進"), false, line);
  }
  assertEquals(planned(out), ["accept", "accept", "accept", "accept"]);
  assertEquals(cardsOf(out).length, 4);
  assertEquals(
    out.events.filter((e) => e.type === "analysis.card_explain").length,
    4,
  );
  const trace = traceOf(out);
  assertEquals(trace.push, null);
  assertEquals([trace.tags.herTired, trace.tags.herAffection], [true, false]);
  assertEquals(trace.specs.some((s) => s.task === "推進"), false);
});

Deno.test("從正式入口：不記帳不承諾沒設、off、test 但不是測試帳號、打錯（true）：讀局面沒有 herTired、第一張是推進（種子）；test 加測試帳號就開", async () => {
  for (const flag of [undefined, "off", "test", "true"]) {
    const out = await analyze({ env: { ANALYZE_GUIDE_V3_NO_IOU: flag } });
    assertEquals(out.status, 200, String(flag));
    const read = bodyOf(out, "read")!;
    assertEquals(systemOf(read).includes("herTired"), false, String(flag));
    assertEquals(schemaOf(read).required!.includes("herTired"), false);
    const write = bodyOf(out, "write")!;
    assert(
      specLines(userText(write))[0].startsWith("1. 任務：推進（種子）｜"),
      String(flag),
    );
    assertEquals(planned(out), ["push", "accept", "accept", "accept"]);
    assertEquals(traceOf(out).push, "種子");
    assertEquals("herTired" in traceOf(out).tags, false);
  }
  const testAccount = await analyze({
    env: { ANALYZE_GUIDE_V3_NO_IOU: "test" },
    email: TEST_EMAILS[0],
  });
  assertEquals(testAccount.status, 200);
  assert(systemOf(bodyOf(testAccount, "read")!).includes(HER_TIRED_NOTE));
  assertEquals(planned(testAccount), ["accept", "accept", "accept", "accept"]);
  assertEquals(traceOf(testAccount).push, null);
});

Deno.test("從正式入口：不記帳不承諾開、兩段式沒開：不作用（只在兩段式開時有作用），讀局面與寫卡的請求跟兩個都沒開一字不差、沒有說明", async () => {
  const twoStageOff = { ANALYZE_GUIDE_V3_TWO_STAGE: undefined };
  const on = await analyze({
    env: { ...twoStageOff, ANALYZE_GUIDE_V3_NO_IOU: "on" },
  });
  const off = await analyze({ env: twoStageOff });
  assertEquals(on.status, 200);
  for (const stage of ["read", "write"]) {
    assertEquals(
      JSON.stringify(bodyOf(on, stage)),
      JSON.stringify(bodyOf(off, stage)),
      stage,
    );
  }
  assertEquals(systemOf(bodyOf(on, "read")!).includes("herTired"), false);
  assertEquals(bodyOf(on, "explain"), undefined);
  assertEquals(traceOf(on).push, traceOf(off).push);
});

Deno.test("從正式入口：跟甜話短回各自獨立——她只撒嬌一句很短的甜話：兩個都開 3 張都接住、都短回；只開甜話短回第一張是推進（種子）；只開這個 4 張都接住、沒有短回；都沒開 4 張、第一張推進", async () => {
  const run = (env: Record<string, string>) =>
    analyze({ env, messages: SWEET_MESSAGES, read: READ_SWEET });
  const both = await run({
    ANALYZE_GUIDE_V3_SWEET_SHORT: "on",
    ANALYZE_GUIDE_V3_NO_IOU: "on",
  });
  const sweetOnly = await run({ ANALYZE_GUIDE_V3_SWEET_SHORT: "on" });
  const noIouOnly = await run({ ANALYZE_GUIDE_V3_NO_IOU: "on" });
  const neither = await run({});
  assertEquals(planned(both), ["accept", "accept", "accept"]);
  for (const line of specLines(userText(bodyOf(both, "write")!))) {
    assert(
      line.includes(
        `任務：接住｜這張接：她的「抱抱」｜${SWEET_SHORT_CARD_PART}｜`,
      ),
      line,
    );
  }
  assertEquals(traceOf(both).specs.every((s) => s.sweetShort === true), true);
  assertEquals(traceOf(both).push, null);
  assertEquals(planned(sweetOnly), ["push", "accept", "accept"]);
  assertEquals(
    traceOf(sweetOnly).specs.every((s) => s.sweetShort === true),
    true,
  );
  assertEquals(planned(noIouOnly), ["accept", "accept", "accept", "accept"]);
  assertEquals(traceOf(noIouOnly).specs.some((s) => s.sweetShort), false);
  assertEquals(planned(neither), ["push", "accept", "accept", "accept"]);
  // 讀局面的請求：兩個開關各改各的（herTired 那一行與欄位、撒嬌那一條與種類）。
  const read = (out: V3HarnessOutcome) => systemOf(bodyOf(out, "read")!);
  assert(
    read(both).includes(HER_TIRED_NOTE) && read(both).includes("「撒嬌」"),
  );
  assert(!read(sweetOnly).includes(HER_TIRED_NOTE));
  assert(read(sweetOnly).includes("「撒嬌」"));
  assert(read(noIouOnly).includes(HER_TIRED_NOTE));
  assert(!read(noIouOnly).includes("「撒嬌」"));
});

Deno.test("從正式入口：開著時讀局面沒給 herTired（缺欄位）照常出卡、當沒喊累（她沒撒嬌就照舊排種子）；沒開時讀局面多給 herTired 也照常出卡、照舊排種子", async () => {
  const { herTired: _drop, ...missing } = READ;
  const on = await analyze({
    env: { ANALYZE_GUIDE_V3_NO_IOU: "on" },
    read: missing,
    rawRead: true,
  });
  assertEquals(on.status, 200);
  assertEquals(on.events.some((e) => e.type === "analysis.error"), false);
  assertEquals(planned(on), ["push", "accept", "accept", "accept"]);
  assertEquals(traceOf(on).push, "種子");
  const off = await analyze({ env: {}, rawRead: true });
  assertEquals(off.events.some((e) => e.type === "analysis.error"), false);
  assertEquals(planned(off), ["push", "accept", "accept", "accept"]);
});
