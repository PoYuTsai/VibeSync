// v3 串流流程：扣費時機、少卡、斷線、不送型、自傷關心、續看。模型與資料庫都是替身。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type {
  AnalysisStreamRun,
  ChargeStreamRunV3Input,
} from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import type { ReadTags } from "./read_tags.ts";
import { GUIDE_V3_STALE_AFTER_MS } from "./run_shape.ts";
import {
  type GuideV3StreamDeps,
  handleGuideV3Stream,
  STOP_CONDITION_CARE,
} from "./stream_flow.ts";
import { CARE_MESSAGE } from "./wire.ts";

const T0 = Date.parse("2026-10-16T00:00:00.000Z");

function tags(over: Partial<ReadTags> = {}): ReadTags {
  return {
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
    needsHisFacts: false,
    identityQuestion: false,
    hisStatedFacts: [],
    hasHisVoiceSample: false,
    replyWillingness: "high",
    worthyBallCount: 1,
    herTurnsPerfunctory: [],
    matchedEntries: [],
    readForUser: "她在分享日常，氣氛輕鬆。",
    waitFor: "",
    ...over,
  };
}

/// 綠燈、一般分享：排 4 張（接住、帶張力、接住、帶張力）。
const CHAT = [
  { isFromMe: true, content: "週末去哪玩" },
  { isFromMe: false, content: "去爬山，腿快斷了" },
];

const line = (card: number, messages: string[], invented = false) =>
  JSON.stringify({ card, messages, hasInventedDetail: invented }) + "\n";

const FOUR_CARDS = [
  line(1, ["腿斷了還能打字，看來還撐得住"]),
  line(2, ["爬完山還有力氣回我，體力不錯喔"]),
  line(3, ["哪座山？下次我也想去"]),
  line(4, ["妳這樣說我反而想看妳爬山的樣子"]),
];

interface Harness {
  deps: GuideV3StreamDeps;
  calls: string[];
  charges: ChargeStreamRunV3Input[];
  done: Record<string, unknown>[];
  failed: string[];
  logs: { event: string; metadata: Record<string, unknown> }[];
  tasks: Promise<unknown>[];
  run: AnalysisStreamRun;
}

function baseRun(over: Partial<AnalysisStreamRun> = {}): AnalysisStreamRun {
  return {
    id: "run-1",
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
    ...over,
  };
}

async function* chunks(parts: string[], failAfter?: Error) {
  for (const part of parts) {
    // 一張卡拆成兩段送，確認是等整行到了才處理。
    const mid = Math.floor(part.length / 2);
    yield part.slice(0, mid);
    yield part.slice(mid);
  }
  if (failAfter) throw failAfter;
}

function harness(opts: {
  readTags?: ReadTags | string;
  readError?: Error;
  messages?: { isFromMe: boolean; content: string }[];
  writeParts?: string[];
  writeError?: Error;
  writeFailAfter?: Error;
  chargeError?: Error;
  chargeErrorButCommitted?: boolean;
  /// 扣費卡在這裡，直到測試放行。
  chargeGate?: Promise<void>;
  markDoneError?: Error;
  accountIsTest?: boolean;
  analysisRunId?: string | null;
  existingRun?: AnalysisStreamRun;
  now?: number;
} = {}): Harness {
  const calls: string[] = [];
  const charges: ChargeStreamRunV3Input[] = [];
  const done: Record<string, unknown>[] = [];
  const failed: string[] = [];
  const logs: { event: string; metadata: Record<string, unknown> }[] = [];
  const tasks: Promise<unknown>[] = [];
  let run = opts.existingRun ?? baseRun();
  const h: Harness = {
    calls,
    charges,
    done,
    failed,
    logs,
    tasks,
    get run() {
      return run;
    },
    deps: {
      store: {
        getRun: () => {
          calls.push("getRun");
          return Promise.resolve(run);
        },
        createPendingRun: (args) => {
          calls.push("createPendingRun");
          run = baseRun({ request_context: args.requestContext });
          return Promise.resolve(run);
        },
        chargeRunV3: async (input) => {
          calls.push(`charge:${input.decisionKind}:${input.cardTask}`);
          charges.push(input);
          if (opts.chargeGate) await opts.chargeGate;
          if (opts.chargeError) {
            if (opts.chargeErrorButCommitted) {
              run = baseRun({
                ...run,
                status: "charged",
                charged_at: new Date(T0).toISOString(),
                card_task: input.cardTask,
                recommendation_json: input.recommendationJson,
              });
            }
            return Promise.reject(opts.chargeError);
          }
          run = baseRun({
            ...run,
            status: "charged",
            charged_at: new Date(T0).toISOString(),
            card_task: input.cardTask,
            decision_kind: input.decisionKind,
            recommendation_json: input.recommendationJson,
          });
          return Promise.resolve(run);
        },
        markDone: (args) => {
          calls.push("markDone");
          if (opts.markDoneError) return Promise.reject(opts.markDoneError);
          done.push(args.finalResult);
          run = { ...run, status: "done", final_result_json: args.finalResult };
          return Promise.resolve(run);
        },
        markFailed: (args) => {
          calls.push(`markFailed:${args.code}`);
          failed.push(args.code);
          run = { ...run, status: "failed", last_error_code: args.code };
          return Promise.resolve(run);
        },
      },
      userId: "user-1",
      analysisRunId: opts.analysisRunId ?? null,
      conversationHash: "hash-1",
      messages: opts.messages ?? CHAT,
      requestType: "analyze",
      effectiveTier: "starter",
      accountIsTest: opts.accountIsTest ?? false,
      quotaUsage: {
        shouldChargeQuota: true,
        quotaReason: "stream_analyze",
        quotaUnit: "message",
        chargedMessageCount: 2,
        estimatedMessageCount: 2,
      },
      monthlyLimit: 300,
      dailyLimit: 50,
      subMonthlyUsed: 10,
      subDailyUsed: 3,
      callRead: () => {
        calls.push("read");
        if (opts.readError) return Promise.reject(opts.readError);
        const t = opts.readTags ?? tags();
        return Promise.resolve({
          text: typeof t === "string" ? t : JSON.stringify(t),
          model: "claude-sonnet-5-5",
        });
      },
      callWrite: () => {
        calls.push("write");
        if (opts.writeError) return Promise.reject(opts.writeError);
        return Promise.resolve({
          model: "claude-sonnet-5-5",
          textStream: chunks(
            opts.writeParts ?? FOUR_CARDS,
            opts.writeFailAfter,
          ),
        });
      },
      log: (event, metadata) => logs.push({ event, metadata }),
      now: () => opts.now ?? T0,
      heartbeatIntervalMs: 0,
      resumePollIntervalMs: 0,
      resumeMaxWaitMs: 0,
      waitUntil: (task) => tasks.push(task),
    },
  };
  return h;
}

async function events(response: Response): Promise<Record<string, unknown>[]> {
  const text = await response.text();
  return text.split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

function types(evs: Record<string, unknown>[]): string[] {
  return evs.map((e) => String(e.type));
}

Deno.test("送出型：讀局面先送，第一張卡送出前扣一次，done 只由送出的卡組成", async () => {
  const h = harness();
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), [
    "analysis.started",
    "analysis.read",
    "analysis.card",
    "analysis.card",
    "analysis.card",
    "analysis.card",
    "analysis.done",
  ]);
  assertEquals(h.calls, [
    "createPendingRun",
    "read",
    "write",
    "charge:send:accept",
    "markDone",
  ]);
  assertEquals(h.charges.length, 1);
  const charge = h.charges[0];
  assertEquals(charge.chargeQuota, true);
  assertEquals(charge.messageCount, 2);
  assertEquals(charge.recommendationJson.cardTask, "accept");
  assertEquals(charge.recommendationJson.guideVersion, GUIDE_V3_VERSION);
  assertEquals(
    (charge.recommendationJson.firstCard as { messages: string[] }).messages,
    ["腿斷了還能打字，看來還撐得住"],
  );
  const read = evs[1];
  assertEquals(read.decision, "send");
  assertEquals(read.plannedCards, [
    { slot: 1, task: "accept" },
    { slot: 2, task: "tension" },
    { slot: 3, task: "accept" },
    { slot: 4, task: "tension" },
  ]);
  // 預設口吻：妳 → 你。
  assertEquals(evs[5].messages, ["你這樣說我反而想看你爬山的樣子"]);
  const client = evs[6].finalResult as Record<string, unknown>;
  assertEquals((client.cards as unknown[]).length, 4);
  assertEquals(client.partial, false);
  assert(!("guideV3Trace" in client), "伺服器專用欄位不送 App");
  assert("guideV3Trace" in h.done[0], "DB 存完整結果");
  assertEquals((client.usage as Record<string, unknown>).messagesUsed, 2);
  assertEquals((client.usage as Record<string, unknown>).dailyRemaining, 45);
  const trace = h.done[0].guideV3Trace as Record<string, unknown>;
  assertEquals(trace.rawMessages, [{
    slot: 4,
    messages: ["妳這樣說我反而想看妳爬山的樣子"],
  }]);
});

Deno.test("扣費還沒完成時，一張卡都不會先送出", async () => {
  let release!: () => void;
  const h = harness({ chargeGate: new Promise((r) => release = r) });
  const reader = (await handleGuideV3Stream(h.deps)).body!.getReader();
  const decoder = new TextDecoder();
  let seen = "";
  while (!seen.includes('"analysis.read"')) {
    seen += decoder.decode((await reader.read()).value);
  }
  while (h.charges.length === 0) await new Promise((r) => setTimeout(r, 0));
  // 扣費卡住時讀不到任何東西；這個讀取在放行後才會拿到第一張卡。
  const nextRead = reader.read().then((r) => decoder.decode(r.value));
  const pending = await Promise.race([
    nextRead,
    new Promise<string>((r) => setTimeout(() => r("(nothing)"), 30)),
  ]);
  assertEquals(pending, "(nothing)");
  assert(!seen.includes('"analysis.card"'));
  release();
  let rest = await nextRead;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    rest += decoder.decode(value);
  }
  assertEquals((rest.match(/"analysis\.card"/g) ?? []).length, 4);
});

Deno.test("收尾（她婉拒或說了界線）：一張收尾卡，扣費的任務是 close", async () => {
  const h = harness({
    readTags: tags({ declinedOrBoundary: true }),
    writeParts: [line(1, ["好，那妳先忙"])],
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(evs[1].decision, "close");
  assertEquals(evs[1].plannedCards, [{ slot: 1, task: "close" }]);
  assertEquals(h.charges[0].cardTask, "close");
  assertEquals(types(evs).at(-1), "analysis.done");
});

Deno.test("第一張卡被檢查拿掉：扣費改在第二張、只扣一次，結果標 partial", async () => {
  const h = harness({
    writeParts: [line(1, ["我會一直跟蹤你到你答應"]), ...FOUR_CARDS.slice(1)],
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs).filter((t) => t === "analysis.card").length, 3);
  assertEquals(h.charges.length, 1);
  assertEquals(h.charges[0].cardTask, "tension");
  const done = evs.at(-1)!;
  assertEquals(done.type, "analysis.done");
  assertEquals((done.finalResult as Record<string, unknown>).partial, true);
  const trace = h.done[0].guideV3Trace as Record<string, unknown>;
  assertEquals(trace.removed, [{ slot: 1, reason: "unsafe" }]);
});

Deno.test("每張都被拿掉：不扣、run 記失敗、送錯誤事件", async () => {
  const h = harness({
    writeParts: [
      line(1, ["我會一直跟蹤你"]),
      line(2, ["你不回我我就去死"]),
      line(9, ["沒有這張"]),
      "不是 JSON\n",
    ],
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), [
    "analysis.started",
    "analysis.read",
    "analysis.error",
  ]);
  assertEquals(evs[2].code, "GUIDE_V3_NO_CARDS");
  assertEquals(h.charges.length, 0);
  assertEquals(h.failed, ["GUIDE_V3_NO_CARDS"]);
});

Deno.test("寫卡呼叫失敗、一張都沒送：不扣，錯誤碼照上游", async () => {
  const err = Object.assign(new Error("overloaded"), { code: "SERVER_ERROR" });
  const h = harness({ writeError: err });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(evs.at(-1)!.code, "SERVER_ERROR");
  assertEquals(evs.at(-1)!.recoverable, true);
  assertEquals(h.charges.length, 0);
  assertEquals(h.failed, ["SERVER_ERROR"]);
});

Deno.test("寫卡中途斷掉、已送出 2 張：以送出的卡結案，算一次", async () => {
  const err = Object.assign(new Error("stream cut"), { code: "STREAM_ERROR" });
  const h = harness({
    writeParts: FOUR_CARDS.slice(0, 2),
    writeFailAfter: err,
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs).at(-1), "analysis.done");
  assertEquals(h.charges.length, 1);
  assertEquals(h.failed, []);
  const client = evs.at(-1)!.finalResult as Record<string, unknown>;
  assertEquals((client.cards as unknown[]).length, 2);
  assertEquals(client.partial, true);
  assertEquals(
    (client.telemetry as Record<string, unknown>).writeInterruptedCode,
    "STREAM_ERROR",
  );
});

Deno.test("扣費失敗（額度不足）：一張卡都不送、run 記失敗、額度訊息", async () => {
  const h = harness({ chargeError: new Error("QUOTA_EXCEEDED_DAILY") });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), [
    "analysis.started",
    "analysis.read",
    "analysis.error",
  ]);
  assertEquals(evs[2].code, "QUOTA_EXHAUSTED");
  assertEquals(h.failed, ["QUOTA_EXHAUSTED"]);
  assertEquals(h.done.length, 0);
});

Deno.test("扣費回應掉了但其實已扣：讀回 run 確認後照常送卡", async () => {
  const h = harness({
    chargeError: new Error("network reset"),
    chargeErrorButCommitted: true,
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs).filter((t) => t === "analysis.card").length, 4);
  assertEquals(types(evs).at(-1), "analysis.done");
  assertEquals(h.failed, []);
  assert(
    h.logs.some((l) => l.event === "guide_v3_charge_confirmed_after_error"),
  );
});

Deno.test("App 在第一張卡前斷線：不扣、停止生成、run 記失敗", async () => {
  const h = harness();
  const response = await handleGuideV3Stream(h.deps);
  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let seen = "";
  while (!seen.includes('"analysis.read"')) {
    const { value, done } = await reader.read();
    if (done) break;
    seen += decoder.decode(value);
  }
  await reader.cancel();
  await Promise.all(h.tasks);
  assertEquals(h.charges.length, 0);
  assertEquals(h.failed, ["GUIDE_V3_CLIENT_GONE"]);
});

Deno.test("markDone 失敗：已扣費的卡照樣送 done 給 App，只記 log", async () => {
  const h = harness({ markDoneError: new Error("db down") });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs).at(-1), "analysis.done");
  assert(h.logs.some((l) => l.event === "guide_v3_persist_failed"));
});

Deno.test("先別回（他是最後一則）：不寫卡，讀完扣一次不送型，等她的條件存進紀錄", async () => {
  const h = harness({
    messages: [...CHAT, { isFromMe: true, content: "哪座山" }],
    readTags: tags({ waitFor: "等她回你哪座山" }),
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), [
    "analysis.started",
    "analysis.read",
    "analysis.done",
  ]);
  assertEquals(evs[1].decision, "hold");
  assertEquals(evs[1].waitFor, "等她回你哪座山");
  assertEquals(h.calls.includes("write"), false);
  assertEquals(h.charges.length, 1);
  const c = h.charges[0];
  assertEquals(c.decisionKind, "do_not_send");
  assertEquals(c.cardTask, null);
  assertEquals(c.recommendationJson.action, "wait");
  assertEquals(c.recommendationJson.stopCondition, "等她回你哪座山");
  assertEquals("cardTask" in c.recommendationJson, false);
});

Deno.test("先別回但扣費失敗：判讀不送出、run 記失敗", async () => {
  const h = harness({
    messages: [...CHAT, { isFromMe: true, content: "哪座山" }],
    chargeError: new Error("QUOTA_EXCEEDED_MONTHLY"),
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), ["analysis.started", "analysis.error"]);
  assertEquals(evs[1].code, "QUOTA_EXHAUSTED");
  assertEquals(h.failed, ["QUOTA_EXHAUSTED"]);
});

Deno.test("停（明確拒絕）：acknowledge_and_stop、不寫卡", async () => {
  const h = harness({ readTags: tags({ explicitRejection: true }) });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(evs[1].decision, "stop");
  assertEquals(h.charges[0].decisionKind, "acknowledge_and_stop");
  assertEquals(h.charges[0].recommendationJson.action, "stop");
  assertEquals(h.calls.includes("write"), false);
});

Deno.test("自傷訊號：不寫卡、不扣額度、顯示固定關心訊息", async () => {
  const h = harness({ readTags: tags({ selfHarmSignal: true }) });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), [
    "analysis.started",
    "analysis.read",
    "analysis.done",
  ]);
  assertEquals(evs[1].decision, "care");
  assertEquals(evs[1].careMessage, CARE_MESSAGE);
  assertEquals(evs[1].plannedCards, []);
  assertEquals(h.calls.includes("write"), false);
  const c = h.charges[0];
  assertEquals(c.chargeQuota, false);
  assertEquals(c.messageCount, 0);
  assertEquals(c.decisionKind, "do_not_send");
  assertEquals(c.recommendationJson.action, "care");
  assertEquals(c.recommendationJson.stopCondition, STOP_CONDITION_CARE);
  const usage = (evs[2].finalResult as Record<string, unknown>).usage as Record<
    string,
    unknown
  >;
  assertEquals(usage.messagesUsed, 0);
  assertEquals(usage.shouldChargeQuota, false);
});

Deno.test("自傷訊號但紀錄寫不進資料庫：關心訊息照樣顯示，不呼叫 markDone", async () => {
  const h = harness({
    readTags: tags({ selfHarmSignal: true }),
    chargeError: new Error("db down"),
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs), [
    "analysis.started",
    "analysis.read",
    "analysis.done",
  ]);
  assertEquals(evs[1].careMessage, CARE_MESSAGE);
  assertEquals(h.calls.includes("markDone"), false);
});

Deno.test("讀局面拒答：不扣、不可重試的錯誤；格式壞掉：可重試的錯誤", async () => {
  const refusal = Object.assign(new Error("refused"), {
    code: "MODEL_REFUSAL",
  });
  const h1 = harness({ readError: refusal });
  const e1 = await events(await handleGuideV3Stream(h1.deps));
  assertEquals(types(e1), ["analysis.started", "analysis.error"]);
  assertEquals(e1[1].code, "MODEL_REFUSAL");
  assertEquals(e1[1].recoverable, false);
  assertEquals(h1.failed, ["MODEL_REFUSAL"]);

  const h2 = harness({ readTags: '{"light":"blue"}' });
  const e2 = await events(await handleGuideV3Stream(h2.deps));
  assertEquals(e2[1].code, "GUIDE_V3_READ_INVALID");
  assertEquals(h2.charges.length, 0);
});

Deno.test("測試帳號：照樣寫扣費紀錄，但不扣額度", async () => {
  const h = harness({ accountIsTest: true });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(h.charges[0].chargeQuota, false);
  assertEquals(h.charges[0].messageCount, 0);
  const usage = (evs.at(-1)!.finalResult as Record<string, unknown>)
    .usage as Record<string, unknown>;
  assertEquals(usage.messagesUsed, 0);
});

Deno.test("同一張卡重複或編號超出：略過、只送一次", async () => {
  const h = harness({
    writeParts: [
      FOUR_CARDS[0],
      FOUR_CARDS[0],
      line(7, ["多的"]),
      ...FOUR_CARDS.slice(1),
    ],
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs).filter((t) => t === "analysis.card").length, 4);
  const trace = h.done[0].guideV3Trace as Record<string, unknown>;
  assertEquals(trace.invalidLines, 2);
});

Deno.test("最後一行沒換行也會處理", async () => {
  const h = harness({
    writeParts: [...FOUR_CARDS.slice(0, 3), FOUR_CARDS[3].trimEnd()],
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  assertEquals(types(evs).filter((t) => t === "analysis.card").length, 4);
});

Deno.test("續看：v3 已完成的 run 重播剝掉伺服器欄位的結果", async () => {
  const final = {
    guideVersion: GUIDE_V3_VERSION,
    read: {},
    cards: [],
    guideV3Trace: { secret: true },
  };
  const h = harness({
    analysisRunId: "run-1",
    existingRun: baseRun({
      status: "done",
      card_task: "accept",
      charged_at: new Date(T0).toISOString(),
      final_result_json: final,
    }),
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  const done = evs.find((e) => e.type === "analysis.done")!;
  assertEquals(done.recovered, true);
  assert(!("guideV3Trace" in (done.finalResult as Record<string, unknown>)));
  assertEquals(h.calls.includes("read"), false);
});

Deno.test("續看：v2 的 run 不在 v3 重播（409）", async () => {
  const h = harness({
    analysisRunId: "run-1",
    existingRun: baseRun({
      status: "done",
      selected_style: "extend",
      request_context: {},
      final_result_json: { replies: {} },
      charged_at: new Date(T0).toISOString(),
    }),
  });
  const response = await handleGuideV3Stream(h.deps);
  assertEquals(response.status, 409);
});

Deno.test("續看：扣過費卻一直沒結案（原請求被終止）→ 重組判讀＋第一張卡", async () => {
  const firstCard = {
    slot: 1,
    task: "accept",
    method: "reaction",
    voice: "default",
    messages: ["腿斷了還能打字"],
    hasInventedDetail: false,
    hasBlank: false,
  };
  const h = harness({
    analysisRunId: "run-1",
    now: T0 + GUIDE_V3_STALE_AFTER_MS,
    existingRun: baseRun({
      status: "charged",
      card_task: "accept",
      decision_kind: "send",
      charged_at: new Date(T0).toISOString(),
      recommendation_json: {
        decisionKind: "send",
        cardTask: "accept",
        guideVersion: GUIDE_V3_VERSION,
        read: { decision: "send", judgment: "輕鬆" },
        firstCard,
      },
      request_context: {
        guideVersion: GUIDE_V3_VERSION,
        chargedMessageCount: 2,
      },
    }),
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  const done = evs.find((e) => e.type === "analysis.done")!;
  const result = done.finalResult as Record<string, unknown>;
  assertEquals(result.cards, [firstCard]);
  assertEquals(result.partial, true);
  assertEquals(result.recovered, true);
});

Deno.test("續看：一直停在 pending 的 v3 run 當失敗、不可重試", async () => {
  const h = harness({
    analysisRunId: "run-1",
    now: T0 + GUIDE_V3_STALE_AFTER_MS,
  });
  const evs = await events(await handleGuideV3Stream(h.deps));
  const err = evs.find((e) => e.type === "analysis.error")!;
  assertEquals(err.code, "STREAM_RUN_RETRY_UNAVAILABLE");
  assertEquals(err.recoverable, false);
});
