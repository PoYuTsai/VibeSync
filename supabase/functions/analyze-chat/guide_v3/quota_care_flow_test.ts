// 額度不夠時的自傷關心（Eric 2026-10-18）：v3 流程收到 careOnlyFromQuota 時，不讀局面、
// 不寫卡、不打記憶，直接給自傷關心訊息，只寫跟其他關心一樣的不扣額度紀錄。模型與資料庫
// 都是替身；事件一律照種類找，不看位置。
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type {
  AnalysisStreamRun,
  ChargeStreamRunV3Input,
} from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import { planCareFromQuota, STOP_REASON_CARE } from "./plan.ts";
import { NO_SAFETY_HITS, scanSafetyKeywords } from "./safety.ts";
import {
  type GuideV3Message,
  type GuideV3StreamDeps,
  handleGuideV3Stream,
  STOP_CONDITION_CARE,
} from "./stream_flow.ts";
import { CARE_MESSAGE } from "./wire.ts";

const T0 = Date.parse("2026-10-18T00:00:00.000Z");
const MONTHLY_LIMIT = 50;
const DAILY_LIMIT = 20;
const MONTHLY_USED = MONTHLY_LIMIT - 1;
const DAILY_USED = 3;
/// 這段對話照字數本來要扣的則數（比剩下的多，才會走到額度不夠）。
const ESTIMATED = 2;

const HER_SELF_HARM: GuideV3Message[] = [
  { isFromMe: true, content: "最近還好嗎" },
  { isFromMe: false, content: "我真的不想活了" },
];

interface Harness {
  deps: GuideV3StreamDeps;
  calls: string[];
  charges: ChargeStreamRunV3Input[];
  created: Record<string, unknown>[];
  done: Record<string, unknown>[];
  logs: { event: string; metadata: Record<string, unknown> }[];
}

function run(over: Partial<AnalysisStreamRun> = {}): AnalysisStreamRun {
  return {
    id: "run-q",
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

function harness(opts: {
  messages?: GuideV3Message[];
  careOnlyFromQuota?: boolean;
  chargeError?: Error;
} = {}): Harness {
  const calls: string[] = [];
  const charges: ChargeStreamRunV3Input[] = [];
  const created: Record<string, unknown>[] = [];
  const done: Record<string, unknown>[] = [];
  const logs: { event: string; metadata: Record<string, unknown> }[] = [];
  let current = run();
  const deps: GuideV3StreamDeps = {
    store: {
      getRun: () => {
        calls.push("getRun");
        return Promise.resolve(current);
      },
      createPendingRun: (args) => {
        calls.push("createPendingRun");
        created.push(args.requestContext);
        current = run({ request_context: args.requestContext });
        return Promise.resolve(current);
      },
      chargeRunV3: (input) => {
        calls.push(`charge:${input.decisionKind}`);
        charges.push(input);
        if (opts.chargeError) return Promise.reject(opts.chargeError);
        current = run({
          ...current,
          status: "charged",
          charged_at: new Date(T0).toISOString(),
          decision_kind: input.decisionKind,
          recommendation_json: input.recommendationJson,
        });
        return Promise.resolve(current);
      },
      markDone: (args) => {
        calls.push("markDone");
        done.push(args.finalResult);
        current = { ...current, status: "done" };
        return Promise.resolve(current);
      },
      markFailedIfPending: (args) => {
        calls.push(`markFailedIfPending:${args.code}`);
        return Promise.resolve(null);
      },
    },
    userId: "user-1",
    analysisRunId: null,
    conversationHash: "hash-1",
    messages: opts.messages ?? HER_SELF_HARM,
    requestType: "analyze",
    effectiveTier: "free",
    accountIsTest: false,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: ESTIMATED,
      estimatedMessageCount: ESTIMATED,
    },
    monthlyLimit: MONTHLY_LIMIT,
    dailyLimit: DAILY_LIMIT,
    subMonthlyUsed: MONTHLY_USED,
    subDailyUsed: DAILY_USED,
    callRead: () => {
      calls.push("read");
      return Promise.reject(new Error("額度不夠走關心時不得讀局面"));
    },
    callWrite: () => {
      calls.push("write");
      return Promise.reject(new Error("額度不夠走關心時不得寫卡"));
    },
    // 記憶開關開著也不能打。
    callExtract: () => {
      calls.push("extract");
      return Promise.reject(new Error("額度不夠走關心時不得打記憶"));
    },
    log: (event, metadata) => logs.push({ event, metadata }),
    now: () => T0,
    heartbeatIntervalMs: 0,
    maxCards: 2,
    ...(opts.careOnlyFromQuota === false ? {} : { careOnlyFromQuota: true }),
  };
  return { deps, calls, charges, created, done, logs };
}

async function events(response: Response): Promise<Record<string, unknown>[]> {
  const text = await response.text();
  return text.split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

function byType(evs: Record<string, unknown>[], type: string) {
  return evs.filter((e) => e.type === type);
}

Deno.test("planCareFromQuota：只有她的訊息有那五個自傷字眼才給關心；只有想死、只有未成年都不算", () => {
  const plan = planCareFromQuota(
    scanSafetyKeywords([{ isFromMe: false, content: "我想自殺" }]),
  );
  assert(plan);
  assertEquals(plan.decision, "care");
  assertEquals(plan.careKind, "self_harm");
  assertEquals(plan.careTrigger, "keyword");
  assertEquals(plan.reason, STOP_REASON_CARE);
  assertEquals(plan.specs, []);
  assertEquals(
    planCareFromQuota({ ...NO_SAFETY_HITS, wantsToDie: true }),
    null,
  );
  assertEquals(
    planCareFromQuota({ ...NO_SAFETY_HITS, minorWords: true }),
    null,
  );
  assertEquals(planCareFromQuota(NO_SAFETY_HITS), null);
});

Deno.test("額度不夠走關心：不讀局面、不寫卡、不打記憶，只寫不扣的關心紀錄，run 以 done 結案", async () => {
  const h = harness();
  const evs = await events(await handleGuideV3Stream(h.deps));

  assertEquals(h.calls.includes("read"), false);
  assertEquals(h.calls.includes("write"), false);
  assertEquals(h.calls.includes("extract"), false);
  // 建 run 時就記成不扣（不是這段對話照字數的則數）。
  assertEquals(h.created[0].chargedMessageCount, 0);
  // 跟其他關心一樣：一筆不扣額度的紀錄（done 一定要有 charged_at）。
  assertEquals(h.charges.length, 1);
  const c = h.charges[0];
  assertEquals([c.chargeQuota, c.messageCount], [false, 0]);
  assertEquals(c.decisionKind, "do_not_send");
  assertEquals(c.cardTask, null);
  assertEquals(c.recommendationJson.action, "care");
  assertEquals(c.recommendationJson.careKind, "self_harm");
  assertEquals(c.recommendationJson.careTrigger, "keyword");
  assertEquals(c.recommendationJson.reason, STOP_REASON_CARE);
  assertEquals(c.recommendationJson.stopCondition, STOP_CONDITION_CARE);
  assertEquals(c.recommendationJson.chargedMessageCount, 0);
  assertEquals(h.calls.filter((x) => x === "markDone").length, 1);

  assertEquals(byType(evs, "analysis.started").length, 1);
  assertEquals(byType(evs, "analysis.card"), []);
  assertEquals(byType(evs, "analysis.error"), []);
  assertEquals(byType(evs, "analysis.progress"), []);
  const [read] = byType(evs, "analysis.read");
  assertEquals(read.decision, "care");
  assertEquals(read.careKind, "self_harm");
  assertEquals(read.careMessage, CARE_MESSAGE);
  assertEquals(read.light, null);
  assertEquals(read.judgment, "");
  assertEquals(read.plannedCards, []);

  const [doneEvent] = byType(evs, "analysis.done");
  const result = doneEvent.finalResult as Record<string, unknown>;
  assertEquals(result.cards, []);
  // 送給 App 的結果不帶伺服器專用的 trace。
  assertEquals("guideV3Trace" in result, false);
  const usage = result.usage as Record<string, unknown>;
  assertEquals(usage.messagesUsed, 0);
  assertEquals(usage.shouldChargeQuota, false);
  assertEquals(usage.monthlyRemaining, MONTHLY_LIMIT - MONTHLY_USED);
  assertEquals(usage.dailyRemaining, DAILY_LIMIT - DAILY_USED);

  const trace = h.done[0].guideV3Trace as Record<string, unknown>;
  assertEquals(trace.tags, null);
  assertEquals(trace.care, {
    kind: "self_harm",
    trigger: "keyword",
    insufficientQuota: true,
  });
  assertEquals(
    (trace.keywordHits as { selfHarmWords: boolean }).selfHarmWords,
    true,
  );

  const outcome = h.logs.find((l) => l.event === "guide_v3_outcome")!;
  assertEquals(outcome.metadata.outcome, "done");
  assertEquals(outcome.metadata.decision, "care");
  assertEquals(outcome.metadata.careKind, "self_harm");
  assertEquals(outcome.metadata.careTrigger, "keyword");
  assertEquals(outcome.metadata.charged, false);
  assertEquals(outcome.metadata.insufficientQuota, true);
  // 只有代碼與數字，不放她的字。
  assertEquals(JSON.stringify(outcome.metadata).includes("不想活"), false);
});

Deno.test("額度不夠走關心：簡體寫法、否定說法也一樣直接給關心", async () => {
  for (const content of ["我想自杀", "我沒有割腕啦"]) {
    const h = harness({ messages: [{ isFromMe: false, content }] });
    const evs = await events(await handleGuideV3Stream(h.deps));
    const [read] = byType(evs, "analysis.read");
    assertEquals(read.careKind, "self_harm", content);
    assertEquals(h.calls.includes("read"), false, content);
    assertEquals(h.charges.map((c) => c.chargeQuota), [false], content);
  }
});

Deno.test("額度不夠走關心：她的訊息沒有那五個字（只有想死、只在他的訊息、只有未成年）就是呼叫端的錯，不建 run、不打模型", async () => {
  const cases: GuideV3Message[][] = [
    [{ isFromMe: false, content: "我好想死" }],
    [
      { isFromMe: true, content: "我真的不想活了" },
      { isFromMe: false, content: "怎麼了？" },
    ],
    [{ isFromMe: false, content: "我今年高二" }],
  ];
  for (const messages of cases) {
    const h = harness({ messages });
    await assertRejects(() => handleGuideV3Stream(h.deps));
    assertEquals(h.calls, [], JSON.stringify(messages));
  }
});

Deno.test("額度不夠走關心：關心紀錄寫不進資料庫也照樣顯示，不呼叫 markDone", async () => {
  const h = harness({ chargeError: new Error("db down") });
  const evs = await events(await handleGuideV3Stream(h.deps));
  const [read] = byType(evs, "analysis.read");
  assertEquals(read.careMessage, CARE_MESSAGE);
  assertEquals(byType(evs, "analysis.done").length, 1);
  assertEquals(h.calls.includes("markDone"), false);
  assertEquals(h.calls.includes("read"), false);
});

Deno.test("沒有 careOnlyFromQuota：同一段自傷對話照常先讀局面，trace 不標額度不夠", async () => {
  const h = harness({ careOnlyFromQuota: false });
  await events(await handleGuideV3Stream(h.deps));
  assertEquals(h.calls.includes("read"), true);
  const trace = h.done[0].guideV3Trace as { care: Record<string, unknown> };
  assertEquals(trace.care.kind, "self_harm");
  assertEquals("insufficientQuota" in trace.care, false);
});
