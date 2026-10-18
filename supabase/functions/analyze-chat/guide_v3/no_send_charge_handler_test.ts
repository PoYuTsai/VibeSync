// 先別回、停照字數扣（Bruce PR #97 10/18 維持 10/16 的規則，Eric 2026-10-19 照他改回）：
// 從正式入口走（guide_v3/v3_stream_harness.ts：假 Supabase、假模型），同一段對話出卡、停、
// 先別回扣一樣的則數，數字照 billing.ts 的計費規則算；先別回最後面他傳的那則照 F04 不算。
// 事件照種類找，期望的數字都從計費與額度常數算。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import，入口模組
// 也要在 env 裝好之後才動態載入（STREAM_ANALYZE_ENABLED 是載入時讀的常數）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { TIER_DAILY_LIMITS, TIER_MONTHLY_LIMITS } from "../../_shared/quota.ts";
import {
  bandForBillableChars,
  BILLING_PROTOCOL_VERSION,
  countPayloadChars,
} from "../billing.ts";
import { ANALYSIS_CONTRACT_VERSION_V3 } from "../no_send_decision.ts";
import { billingMessagesFor } from "./routing.ts";
import {
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
  type V3HarnessOutcome,
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

type Msg = { isFromMe: boolean; content: string };

/// 她最後一則；字數要超過計費的第一級（1 則），才分得出不是固定扣 1 則。
const CHAT: Msg[] = [
  { isFromMe: true, content: "週末去哪玩？" },
  {
    isFromMe: false,
    content:
      "去爬山，腿快斷了，下山的時候一直在想晚餐要吃什麼，結果一到家就直接睡著，醒來已經半夜",
  },
];
/// 先別回：最後面多一則他傳的。
const HIS_LAST: Msg[] = [...CHAT, { isFromMe: true, content: "哪座山？" }];

const TAGS = {
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
  hasHisVoiceSample: false,
  replyWillingness: "high",
  worthyBallCount: 1,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "她在分享日常，氣氛輕鬆。",
  waitFor: "",
};

const CARD_LINES = [1, 2, 3, 4, 5].map((card) =>
  JSON.stringify({
    card,
    messages: [`腿斷了還能打字，看來還撐得住（${card}）`],
    hasInventedDetail: false,
  })
);

/// 這段對話照 billing.ts 該扣幾則（協定版本 3 的一般文字串流分析：最後面他傳的照 F04 不算）。
function billedUnits(messages: Msg[]): number {
  const band = bandForBillableChars(
    countPayloadChars(
      billingMessagesFor(messages, {
        contractVersion: ANALYSIS_CONTRACT_VERSION_V3,
        plainStreamAnalysis: true,
      }),
    ),
  );
  assert(band.band === "standard");
  return band.units;
}

function analyze(
  messages: Msg[],
  tags: Record<string, unknown>,
): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages,
      billingProtocolVersion: BILLING_PROTOCOL_VERSION,
      analysisContractVersion: ANALYSIS_CONTRACT_VERSION_V3,
    },
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
    },
    model: (modelBody) =>
      Promise.resolve(
        modelBody.stream === true
          ? fakeWriteResponse(CARD_LINES)
          : fakeReadResponse(tags),
      ),
  });
}

Deno.test("先別回、停跟出卡一樣照字數扣：扣費則數、done 的用量與剩餘都照計費規則算", async () => {
  const expected = billedUnits(CHAT);
  assert(expected > 1, "要超過 1 則才分得出不是固定扣 1 則");
  // 先別回最後面他傳的照 F04 不算：扣費字數跟她最後一則的對話一樣。
  assertEquals(billedUnits(HIS_LAST), expected);
  const cases: [string, Msg[], Record<string, unknown>, string][] = [
    ["出卡", CHAT, TAGS, "send"],
    ["停", CHAT, { ...TAGS, explicitRejection: true }, "stop"],
    ["先別回", HIS_LAST, TAGS, "hold"],
  ];
  for (const [label, messages, tags, decision] of cases) {
    const out = await analyze(messages, tags);
    assertEquals(out.status, 200, label);
    const read = out.events.find((e) => e.type === "analysis.read");
    assertEquals(read?.decision, decision, label);
    const charge = out.rpcs.find((r) =>
      r.fn === "charge_stream_analysis_run_v3"
    );
    assert(charge, `${label}：要有扣費`);
    assertEquals(charge.args.p_charge_quota, true, label);
    assertEquals(charge.args.p_message_count, expected, label);
    const done = out.events.find((e) => e.type === "analysis.done");
    const usage = (done?.finalResult as Record<string, unknown>)
      .usage as Record<string, unknown>;
    assertEquals(usage.messagesUsed, expected, label);
    assertEquals(usage.estimatedMessages, expected, label);
    // 假資料庫的訂閱是 Essential、這個月和今天都還沒用。
    assertEquals(
      usage.monthlyRemaining,
      TIER_MONTHLY_LIMITS.essential - expected,
      label,
    );
    assertEquals(
      usage.dailyRemaining,
      TIER_DAILY_LIMITS.essential - expected,
      label,
    );
  }
});
