// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）走正式的 v3 流程：讀局面、
// 寫卡送出的請求，事件順序（照種類找），扣費與 trace。模型與資料庫都是替身，不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type {
  AnalysisStreamRun,
  ChargeStreamRunV3Input,
} from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import { planTurn } from "./plan.ts";
import {
  readSystemPrompt,
  readUserPrompt,
  writeSystemPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import {
  READ_TAGS_SCHEMA,
  READ_TAGS_SCHEMA_TWO_STAGE,
  type ReadTags,
  type TwoStageTags,
} from "./read_tags.ts";
import {
  type GuideV3ReadRequest,
  type GuideV3StreamDeps,
  type GuideV3WriteRequest,
  handleGuideV3Stream,
} from "./stream_flow.ts";
import { toTurns } from "./turns.ts";
import {
  HAPPY_SHARE_TASK,
  readSystemPromptTwoStage,
  readUserPromptTwoStage,
  writeSystemPromptTwoStage,
} from "./two_stage_prompts.ts";

const T0 = Date.parse("2026-10-19T00:00:00.000Z");

const MESSAGES = [
  { isFromMe: true, content: "晚餐吃什麼" },
  { isFromMe: false, content: "[照片：一盤咖哩飯]" },
  { isFromMe: false, content: "我自己煮的！" },
  { isFromMe: false, content: "好想你喔" },
];

function baseTags(over: Partial<ReadTags> = {}): ReadTags {
  return {
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
    readForUser: "她在分享自己煮的晚餐，心情很好。",
    waitFor: "",
    ...over,
  };
}

const EXTRAS: TwoStageTags = {
  establishedCouple: false,
  herAffection: false,
  herHappyShare: true,
  worthyLines: [
    { line: 2, label: "自己煮的", kind: "其他" },
    { line: 3, label: "說想他", kind: "情感" },
    { line: 1, label: "咖哩照片", kind: "照片或貼圖" },
  ],
};

function cardLine(card: number, messages: string[]): string {
  return JSON.stringify({ card, messages, hasInventedDetail: false }) + "\n";
}

/// 寫卡請求要幾張就回幾張（從卡片規格標題讀）。
function cardsFor(user: string): string[] {
  const n = Number(user.match(/一共 (\d+) 張/)?.[1] ?? 0);
  return Array.from(
    { length: n },
    (_, i) => cardLine(i + 1, [`看起來好好吃（第 ${i + 1} 張）`]),
  );
}

async function* stream(parts: readonly string[]) {
  for (const part of parts) yield part;
}

interface FlowHarness {
  deps: GuideV3StreamDeps;
  reads: GuideV3ReadRequest[];
  writes: GuideV3WriteRequest[];
  calls: string[];
  charges: ChargeStreamRunV3Input[];
  done: Record<string, unknown>[];
  failed: string[];
  logs: { event: string; metadata: Record<string, unknown> }[];
}

function flowHarness(opts: {
  twoStage?: boolean;
  readText?: string;
  tags?: ReadTags;
  extras?: TwoStageTags | null;
  messages?: { isFromMe: boolean; content: string }[];
  writeParts?: (user: string) => string[];
  extraDeps?: Partial<GuideV3StreamDeps>;
} = {}): FlowHarness {
  const reads: GuideV3ReadRequest[] = [];
  const writes: GuideV3WriteRequest[] = [];
  const calls: string[] = [];
  const charges: ChargeStreamRunV3Input[] = [];
  const done: Record<string, unknown>[] = [];
  const failed: string[] = [];
  const logs: { event: string; metadata: Record<string, unknown> }[] = [];
  let run: AnalysisStreamRun = {
    id: "run-2s",
    user_id: "user-1",
    conversation_hash: "hash-1",
    status: "pending",
    selected_style: null,
    decision_kind: null,
    card_task: null,
    recommendation_json: null,
    final_result_json: null,
    charged_at: null,
    last_error_code: null,
    retry_count: 0,
    request_context: { guideVersion: GUIDE_V3_VERSION },
    created_at: new Date(T0).toISOString(),
    expires_at: new Date(T0 + 30 * 60_000).toISOString(),
  };
  const extras = opts.extras === undefined ? EXTRAS : opts.extras;
  const readText = opts.readText ??
    JSON.stringify({ ...(opts.tags ?? baseTags()), ...(extras ?? {}) });
  const deps: GuideV3StreamDeps = {
    store: {
      getRun: () => Promise.resolve(run),
      createPendingRun: () => {
        calls.push("createPendingRun");
        return Promise.resolve(run);
      },
      chargeRunV3: (input) => {
        calls.push(`charge:${input.decisionKind}:${input.cardTask}`);
        charges.push(input);
        run = {
          ...run,
          status: "charged",
          charged_at: new Date(T0).toISOString(),
          card_task: input.cardTask,
          decision_kind: input.decisionKind,
          recommendation_json: input.recommendationJson,
        };
        return Promise.resolve(run);
      },
      markDone: (args) => {
        calls.push("markDone");
        done.push(args.finalResult);
        return Promise.resolve(run);
      },
      markFailedIfPending: (args) => {
        calls.push(`markFailedIfPending:${args.code}`);
        if (run.status !== "pending" || run.charged_at !== null) {
          return Promise.resolve(null);
        }
        failed.push(args.code);
        run = { ...run, status: "failed", last_error_code: args.code };
        return Promise.resolve(run);
      },
    },
    userId: "user-1",
    analysisRunId: null,
    conversationHash: "hash-1",
    messages: opts.messages ?? MESSAGES,
    requestType: "analyze",
    effectiveTier: "starter",
    accountIsTest: false,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "stream_analyze",
      quotaUnit: "message",
      chargedMessageCount: 3,
      estimatedMessageCount: 3,
    },
    monthlyLimit: 300,
    dailyLimit: 50,
    subMonthlyUsed: 10,
    subDailyUsed: 3,
    callRead: (req) => {
      calls.push("read");
      reads.push(req);
      return Promise.resolve({ text: readText, model: "claude-sonnet-5-5" });
    },
    callWrite: (req) => {
      calls.push("write");
      writes.push(req);
      return Promise.resolve({
        model: "claude-sonnet-5-5",
        textStream: stream((opts.writeParts ?? cardsFor)(req.user)),
      });
    },
    log: (event, metadata) => logs.push({ event, metadata }),
    now: () => T0,
    heartbeatIntervalMs: 0,
    ...(opts.twoStage === undefined ? {} : { twoStage: opts.twoStage }),
    ...opts.extraDeps,
  };
  return { deps, reads, writes, calls, charges, done, failed, logs };
}

async function eventsOf(
  response: Response,
): Promise<Record<string, unknown>[]> {
  const text = await response.text();
  return text.split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

Deno.test("兩段式開：讀局面送兩段式的系統提示詞、逐則編號的對話與多四欄的 schema", async () => {
  const h = flowHarness({ twoStage: true });
  const evs = await eventsOf(await handleGuideV3Stream(h.deps));
  assertEquals(h.reads.length, 1);
  assertEquals(h.reads[0].system, readSystemPromptTwoStage());
  assertEquals(h.reads[0].user, readUserPromptTwoStage(toTurns(MESSAGES)));
  assertEquals(h.reads[0].schema, READ_TAGS_SCHEMA_TWO_STAGE);
  assert(evs.some((e) => e.type === "analysis.card"));
  assertEquals(evs.at(-1)?.type, "analysis.done");
});

Deno.test("兩段式沒開（沒給或 false）：讀局面的請求跟今天一樣", async () => {
  for (const twoStage of [undefined, false]) {
    const h = flowHarness({ twoStage, extras: null });
    await eventsOf(await handleGuideV3Stream(h.deps));
    assertEquals(h.reads[0].system, readSystemPrompt(), String(twoStage));
    assertEquals(h.reads[0].user, readUserPrompt(toTurns(MESSAGES)));
    assertEquals(h.reads[0].schema, READ_TAGS_SCHEMA);
  }
});

Deno.test("兩段式開、讀局面少了新四欄：當成讀局面失敗，不寫卡、不扣", async () => {
  const h = flowHarness({ twoStage: true, extras: null });
  const evs = await eventsOf(await handleGuideV3Stream(h.deps));
  const error = evs.find((e) => e.type === "analysis.error");
  assertEquals(error?.code, "GUIDE_V3_READ_INVALID");
  assertEquals(h.calls.includes("write"), false);
  assertEquals(h.charges, []);
  assertEquals(h.failed, ["GUIDE_V3_READ_INVALID"]);
});

Deno.test("兩段式開：寫卡送兩段式的系統提示詞；規格第一張接最重要的那句，第二張是開心分享的共鳴", async () => {
  const h = flowHarness({ twoStage: true });
  const evs = await eventsOf(await handleGuideV3Stream(h.deps));
  assertEquals(h.writes.length, 1);
  assertEquals(h.writes[0].system, writeSystemPromptTwoStage());
  const user = h.writes[0].user;
  assert(!user.includes("「有他」做法"));
  assert(user.includes("1. 任務：接住｜這張接：她的「好想你喔」"), user);
  assert(
    user.includes(`2. 任務：${HAPPY_SHARE_TASK}｜這張接：她的「我自己煮的！」`),
  );
  assert(user.includes("第 2 輪・她：\n1. [照片：一盤咖哩飯]"));
  // 送出的卡跟規格一致：第二張是共鳴（resonate）。
  const cards = evs.filter((e) => e.type === "analysis.card");
  assertEquals(cards[1].task, "resonate");
  // trace 的規格帶每張要接的句子編號與 note。
  const trace = h.done[0].guideV3Trace as { specs: { lines?: number[] }[] };
  assertEquals(trace.specs[0].lines, [3]);
  assertEquals(
    (trace.specs[1] as { note?: string }).note,
    "happy_share",
  );
});

Deno.test("兩段式沒開：寫卡的請求跟今天一樣（系統提示詞與使用者提示詞逐字相同）", async () => {
  const h = flowHarness({ extras: null });
  await eventsOf(await handleGuideV3Stream(h.deps));
  assertEquals(h.writes[0].system, writeSystemPrompt());
  const turns = toTurns(MESSAGES);
  const plan = planTurn(turns, baseTags());
  assertEquals(
    h.writes[0].user,
    writeUserPrompt({
      turns,
      tags: baseTags(),
      entries: plan.entries,
      cards: plan.specs,
    }),
  );
  const trace = h.done[0].guideV3Trace as { specs: Record<string, unknown>[] };
  assert(trace.specs.every((spec) => !("lines" in spec) && !("note" in spec)));
});

Deno.test("兩段式開：卡片抄到寫卡新加的段落就拿掉（prompt_leak）；同一張卡在開關沒開時照送", async () => {
  const leaky = (user: string) => {
    const n = Number(user.match(/一共 (\d+) 張/)?.[1] ?? 0);
    return Array.from({ length: n }, (_, i) =>
      cardLine(i + 1, [
        i === 0
          ? "每則訊息都是他可以原封不動傳出去的自然句子"
          : `第 ${i + 1} 張`,
      ]));
  };
  const on = flowHarness({ twoStage: true, writeParts: leaky });
  await eventsOf(await handleGuideV3Stream(on.deps));
  const onTrace = on.done[0].guideV3Trace as {
    removed: { slot: number; reason: string }[];
  };
  assertEquals(onTrace.removed.map((r) => [r.slot, r.reason]), [[
    1,
    "prompt_leak",
  ]]);
  const off = flowHarness({ extras: null, writeParts: leaky });
  await eventsOf(await handleGuideV3Stream(off.deps));
  const offTrace = off.done[0].guideV3Trace as { removed: unknown[] };
  assertEquals(offTrace.removed, []);
});
