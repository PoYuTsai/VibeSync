// 對話分析的「重播」工具（健檢 F47）：把黑箱錄下的模型原始輸出，原樣餵回伺服器
// 的串流處理 handleAnalyzeStream，收集它送給 App 的 NDJSON 事件與落帳結果。
// 不呼叫模型、不連網、不花錢。給 analyze_replay_test.ts 與
// tools/ci/regen-analyze-replay-fixtures.ts 共用；入口 index.ts 不載入，不隨函式部署。
//
// 參數照黑箱工具 tools/analyze-v2-blackbox/run_blackbox.ts 的 runCase 組（付費五風格、
// 不回決策開、critic 影子關），錄音與重播才比得起來。
//
// 呼叫端要在 import 本模組之前把 globalThis.fetch 換成不連網的替身：分析處理
// 會寫 ai_logs（送到 deps.supabaseUrl），有些模組在載入時就抓住 fetch。
import { handleAnalyzeStream } from "./analyze_stream_handler.ts";
import { ANALYZE_CRITIC_SHADOW } from "./critic_shadow.ts";
import { STREAM_STYLES } from "./stream_events.ts";
import { markLatestAnalysisFragment } from "./stream_prompt.ts";
import type { StreamingClaudeResult } from "./streaming_fallback.ts";

export type ReplayMessage = { isFromMe: boolean; content: string };

export interface ReplayCase {
  /** 錄音裡的案例名，例如 thin_opening#1。 */
  name: string;
  messages: ReplayMessage[];
  /** 模型當時吐出的原始 JSONL，一行一個事件。 */
  rawText: string;
}

export interface ReplayOutcome {
  status: number;
  events: Record<string, unknown>[];
  charged: boolean;
  /// 每次扣額度呼叫的參數（扣不扣、扣幾則、扣費錨點），不只記有沒有呼叫。
  charges: Record<string, unknown>[];
  markDoneFinal: Record<string, unknown> | null;
}

export const REPLAY_MODEL = "claude-sonnet-5-5";

function latestIncomingRunStart(messages: ReplayMessage[]): number {
  let i = messages.length - 1;
  if (messages[i]?.isFromMe) return messages.length - 1;
  while (i > 0 && !messages[i - 1].isFromMe) i--;
  return i;
}

function buildUserPrompt(messages: ReplayMessage[]): string {
  const lines = messages.map((m) =>
    `${m.isFromMe ? "Me" : "Her"}: ${m.content}`
  );
  return [
    "Analyze the conversation below and return the structured JSON response.",
    "## Recent Conversation",
    markLatestAnalysisFragment(lines, latestIncomingRunStart(messages)),
  ].join("\n\n");
}

/**
 * 錄音切成一行一個 chunk，換行留在行尾；原文最後一行沒有換行就照樣沒有、空行也照送，
 * 接起來跟原文一字不差，串流結尾的處理才會照正式情況走到。
 */
export function replayChunks(rawText: string): string[] {
  return rawText.match(/[^\n]*\n|[^\n]+$/g) ?? [];
}

async function* replayLines(rawText: string): AsyncGenerator<string> {
  for (const chunk of replayChunks(rawText)) yield chunk;
}

export async function replayAnalyzeStream(
  replayCase: ReplayCase,
): Promise<ReplayOutcome> {
  const charges: Record<string, unknown>[] = [];
  let markDoneFinal: Record<string, unknown> | null = null;
  const run = {
    id: `run-${replayCase.name}`,
    status: "pending",
    retry_count: 0,
    conversation_hash: "h",
    final_result: null,
  };
  const styles = [...STREAM_STYLES];
  const messages = replayCase.messages;
  const deps = {
    store: {
      getRun: () => Promise.resolve(run),
      reserveRetry: () => Promise.resolve(run),
      createPendingRun: () => Promise.resolve(run),
      chargeRun: (args: Record<string, unknown>) => {
        // runId、userId 是固定值，不記。
        const { runId: _runId, userId: _userId, ...rest } = args;
        charges.push(JSON.parse(JSON.stringify(rest)));
        return Promise.resolve();
      },
      markDone: (args: { finalResult: Record<string, unknown> }) => {
        markDoneFinal = args.finalResult;
        return Promise.resolve();
      },
      markFailed: () => Promise.resolve({ ...run, status: "failed" }),
    },
    userId: "00000000-0000-4000-8000-0000000000bb",
    analysisRunId: null,
    requestType: "analyze",
    analyzeMode: "normal",
    expectedTier: "essential",
    effectiveTier: "essential",
    // 照一般付費用戶：測試帳號本來就免扣，扣額度的參數比對不到。
    accountIsTest: false,
    allowedFeatures: styles,
    noSendDecisions: true,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 1,
      estimatedMessageCount: 1,
    },
    monthlyLimit: 999,
    dailyLimit: 999,
    subMonthlyUsed: 0,
    subDailyUsed: 0,
    selectedModel: REPLAY_MODEL,
    userMessageContent: buildUserPrompt(messages),
    requestObservability: {},
    messages,
    hashInput: {
      messages,
      userDraft: undefined,
      partnerSummary: undefined,
      sessionContext: undefined,
      conversationSummary: undefined,
      effectiveStyleContext: undefined,
      knownContactName: undefined,
      analysisFragmentStartIndex: latestIncomingRunStart(messages),
    },
    claudeApiKey: "replay-no-key",
    supabaseUrl: "http://stub.invalid",
    supabaseServiceKey: "stub",
    callModel: () =>
      Promise.resolve(
        {
          model: REPLAY_MODEL,
          usage: {
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
          },
          textStream: replayLines(replayCase.rawText),
        } satisfies StreamingClaudeResult,
      ),
    criticShadow: { ...ANALYZE_CRITIC_SHADOW, enabled: false },
  };

  const quiet = [console.log, console.warn, console.error, console.info];
  console.log =
    console.warn =
    console.error =
    console.info =
      () => {};
  try {
    // deno-lint-ignore no-explicit-any
    const response = await handleAnalyzeStream(deps as any);
    const text = await response.text();
    const events = text.split("\n")
      .filter((line) => line.trim() !== "")
      .map((line) => JSON.parse(line) as Record<string, unknown>);
    return {
      status: response.status,
      events,
      charged: charges.length > 0,
      charges,
      markDoneFinal,
    };
  } finally {
    [console.log, console.warn, console.error, console.info] = quiet;
  }
}

/** 每次重播都會變、跟行為無關的計時欄位：一律記成 0。只列實測會變的，不放寬範圍。 */
const TIMING_KEYS = new Set(["serverAiLatencyMs"]);

function zeroTimings(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(zeroTimings);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map((
        [key, v],
      ) => [
        key,
        TIMING_KEYS.has(key) && typeof v === "number" ? 0 : zeroTimings(v),
      ]),
    );
  }
  return value;
}

/** 錄音與重播都會不同、跟行為無關的部分：心跳事件與計時欄位。 */
export function normalizeReplayEvents(
  events: readonly Record<string, unknown>[],
): Record<string, unknown>[] {
  return events
    .filter((event) =>
      !(event.type === "analysis.progress" && event.phase === "heartbeat")
    )
    .map((event) =>
      zeroTimings(JSON.parse(JSON.stringify(event))) as Record<
        string,
        unknown
      >
    );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

/** 不受鍵順序影響的 JSON，用來判斷兩份結果是否相同。 */
function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (isRecord(value)) {
    return `{${
      Object.keys(value).sort().map((k) =>
        `${JSON.stringify(k)}:${stableJson(value[k])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value) ?? "null";
}

export const SAME_AS_FINAL_RESULT = "<same as finalResult>";

/**
 * 測試比對與重產期望值共用的形狀。為了不存三份同樣的結果：完成事件的 result 跟
 * finalResult 相同時只留一份；落帳結果等於完成事件的 finalResult 加上只存在伺服器的
 * 發散計畫時，只存那份計畫。兩者不同時照原樣保留，所以比對時仍會抓到差異。
 */
export function normalizeReplayOutcome(outcome: ReplayOutcome): {
  status: number;
  charged: boolean;
  charges: unknown;
  events: Record<string, unknown>[];
  markDoneFinal: unknown;
} {
  const events = normalizeReplayEvents(outcome.events);
  const done = events.find((e) => e.type === "analysis.done");
  let markDoneFinal = zeroTimings(outcome.markDoneFinal);
  if (done && isRecord(done.finalResult)) {
    if (stableJson(done.result) === stableJson(done.finalResult)) {
      done.result = SAME_AS_FINAL_RESULT;
    }
    if (isRecord(markDoneFinal)) {
      const { analysisDivergencePlan, ...rest } = markDoneFinal;
      if (stableJson(rest) === stableJson(done.finalResult)) {
        markDoneFinal = {
          sameAsDoneFinalResult: true,
          analysisDivergencePlan: analysisDivergencePlan ?? null,
        };
      }
    }
  }
  return {
    status: outcome.status,
    charged: outcome.charged,
    charges: zeroTimings(outcome.charges),
    events,
    markDoneFinal,
  };
}
