// v3 的「重播」工具：把黑箱錄下的兩段模型原始輸出（讀局面的 JSON、寫卡的一行一張），
// 原樣餵回正式流程 handleGuideV3Stream，收集送給 App 的事件、扣費呼叫與落帳結果。
// 不呼叫模型、不連網、不花錢。給 replay_test.ts 與
// tools/ci/regen-guide-v3-replay-fixtures.ts 共用；入口不載入，不隨函式部署。
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import { handleGuideV3Stream } from "./stream_flow.ts";

export interface GuideV3ReplayCase {
  /** 錄音裡的案例名，例如 thin_opening#1。 */
  readonly name: string;
  readonly messages: readonly { isFromMe: boolean; content: string }[];
  /** 讀局面的原始輸出（JSON 文字）。 */
  readonly readText: string;
  /** 寫卡的原始輸出（一行一張）；先別回、停的案例沒有。 */
  readonly writeText: string;
}

export interface GuideV3ReplayOutcome {
  readonly status: number;
  readonly events: Record<string, unknown>[];
  readonly calls: string[];
  readonly charges: Record<string, unknown>[];
  readonly markDoneFinal: Record<string, unknown> | null;
  readonly failedCodes: string[];
}

const T0 = Date.parse("2026-10-16T00:00:00.000Z");

/// 錄音切成一行一個 chunk（換行留在行尾），接起來跟原文一字不差。
export function replayLines(raw: string): string[] {
  return raw.match(/[^\n]*\n|[^\n]+$/g) ?? [];
}

async function* stream(parts: readonly string[]): AsyncGenerator<string> {
  for (const part of parts) yield part;
}

export async function replayGuideV3(
  replayCase: GuideV3ReplayCase,
): Promise<GuideV3ReplayOutcome> {
  const calls: string[] = [];
  const charges: Record<string, unknown>[] = [];
  const failedCodes: string[] = [];
  let markDoneFinal: Record<string, unknown> | null = null;
  let run: AnalysisStreamRun = {
    id: "replay-run",
    user_id: "replay-user",
    conversation_hash: "replay-hash",
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
  const response = await handleGuideV3Stream({
    store: {
      getRun: () => Promise.resolve(run),
      createPendingRun: () => {
        calls.push("createPendingRun");
        return Promise.resolve(run);
      },
      chargeRunV3: (input) => {
        calls.push(`charge:${input.decisionKind}:${input.cardTask}`);
        const { runId: _r, userId: _u, conversationHash: _h, ...rest } = input;
        charges.push(rest as unknown as Record<string, unknown>);
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
        markDoneFinal = args.finalResult;
        return Promise.resolve(run);
      },
      markFailedIfPending: (args) => {
        calls.push(`markFailedIfPending:${args.code}`);
        if (run.status !== "pending" || run.charged_at !== null) {
          return Promise.resolve(null);
        }
        failedCodes.push(args.code);
        run = { ...run, status: "failed", last_error_code: args.code };
        return Promise.resolve(run);
      },
    },
    userId: "replay-user",
    analysisRunId: null,
    conversationHash: "replay-hash",
    messages: replayCase.messages,
    requestType: "analyze",
    effectiveTier: "essential",
    accountIsTest: false,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 2,
      estimatedMessageCount: 2,
    },
    monthlyLimit: 800,
    dailyLimit: 120,
    subMonthlyUsed: 0,
    subDailyUsed: 0,
    callRead: () => {
      calls.push("read");
      return Promise.resolve({
        text: replayCase.readText,
        model: "claude-sonnet-5-5",
      });
    },
    callWrite: () => {
      calls.push("write");
      return Promise.resolve({
        model: "claude-sonnet-5-5",
        textStream: stream(replayLines(replayCase.writeText)),
      });
    },
    log: () => {},
    now: () => T0,
    heartbeatIntervalMs: 0,
  });
  const text = await response.text();
  // 扣費內容與落帳結果照資料庫實際存的樣子比（JSON 會丟掉 undefined 欄位）。
  return {
    status: response.status,
    events: text.split("\n").filter(Boolean).map((line) => JSON.parse(line)),
    calls,
    charges: JSON.parse(JSON.stringify(charges)),
    markDoneFinal: JSON.parse(JSON.stringify(markDoneFinal)),
    failedCodes,
  };
}
