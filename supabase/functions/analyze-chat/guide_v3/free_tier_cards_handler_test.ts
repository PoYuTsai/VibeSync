// 免費也看全部卡（Bruce PR #97 10/18，Eric 2026-10-19）：從正式入口走（guide_v3/
// v3_stream_harness.ts：假 Supabase、假模型），免費帳號跟付費帳號拿到同一組卡——寫卡請求
// 帶全部的卡片規格、每張都寫也都送，判讀的 plannedCards 沒有鎖住的（舊版 App 看 locked
// 決定要不要顯示升級區塊，欄位照樣送、一律 false）。事件照種類找，張數從排卡規則算。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import，入口模組
// 也要在 env 裝好之後才動態載入（STREAM_ANALYZE_ENABLED 是載入時讀的常數）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { BILLING_PROTOCOL_VERSION } from "../billing.ts";
import { ANALYSIS_CONTRACT_VERSION_V3 } from "../no_send_decision.ts";
import { planTurn } from "./plan.ts";
import { parseReadTags } from "./read_tags.ts";
import { toTurns } from "./turns.ts";
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

const MESSAGES = [
  { isFromMe: true, content: "週末去哪玩？" },
  { isFromMe: false, content: "去爬山，腿快斷了" },
];

/// 綠燈、一般分享：排 4 張（接住、帶張力交錯）。
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

/// 寫卡請求要幾張就回幾張（從使用者訊息的卡片規格標題讀），每張的字不一樣。
function writeCards(user: string): string[] {
  const n = Number(user.match(/一共 (\d+) 張/)?.[1] ?? 0);
  return Array.from({ length: n }, (_, i) =>
    JSON.stringify({
      card: i + 1,
      messages: [`腿斷了還能打字，看來還撐得住（第 ${i + 1} 張）`],
      hasInventedDetail: false,
    }));
}

function userText(body: Record<string, unknown>): string {
  return (body.messages as { content: string }[])[0].content;
}

function analyze(tier: string): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    tier,
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
    },
    model: (modelBody) =>
      Promise.resolve(
        modelBody.stream === true
          ? fakeWriteResponse(writeCards(userText(modelBody)))
          : fakeReadResponse(TAGS),
      ),
  });
}

Deno.test("免費帳號跟付費帳號拿到同一組卡：全部都寫、都送，plannedCards 沒有鎖住的", async () => {
  const tags = parseReadTags(TAGS);
  assert(tags);
  const planned = planTurn(toTurns(MESSAGES), tags).specs.length;
  assert(planned >= 3, "排的卡要比舊的免費上限多，才看得出差別");
  const seen: Record<string, unknown> = {};
  for (const tier of ["free", "starter", "essential"]) {
    const out = await analyze(tier);
    assertEquals(out.status, 200, tier);
    // 寫卡請求帶全部的卡片規格。
    const write = out.modelBodies.find((b) => b.stream === true);
    assert(write, `${tier}：要有寫卡請求`);
    assert(userText(write).includes(`一共 ${planned} 張`), tier);
    const read = out.events.find((e) => e.type === "analysis.read")!;
    const plannedCards = read.plannedCards as {
      slot: number;
      locked: boolean;
    }[];
    assertEquals(plannedCards.length, planned, tier);
    assertEquals(plannedCards.filter((c) => c.locked !== false), [], tier);
    const cards = out.events.filter((e) => e.type === "analysis.card");
    assertEquals(
      cards.map((c) => c.slot),
      plannedCards.map((c) => c.slot),
      tier,
    );
    const done = out.events.find((e) => e.type === "analysis.done")!;
    const result = done.finalResult as Record<string, unknown>;
    assertEquals((result.cards as unknown[]).length, planned, tier);
    assertEquals(result.partial, false, tier);
    const telemetry = result.telemetry as Record<string, unknown>;
    assertEquals(
      [telemetry.cardsPlanned, telemetry.cardsDelivered],
      [planned, planned],
      tier,
    );
    // 存進資料庫的 trace 跟送出的一致：規格是全部的卡。
    const trace = out.finalResult?.guideV3Trace as { specs: unknown[] };
    assertEquals(trace.specs.length, planned, tier);
    seen[tier] = { plannedCards, cards: result.cards };
  }
  assertEquals(seen.free, seen.essential);
  assertEquals(seen.free, seen.starter);
});
