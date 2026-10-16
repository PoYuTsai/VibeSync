// 認 v3 的 run，以及 v3 run 的續看快照。v2 handler 也用（擋舊版 App、不讓 v3 run
// 進 retry），所以這裡不 import stream_flow，避免互相 import。
import { stripClientHiddenFinalResult } from "../divergence_contract.ts";
import type { StreamAnalysisResumeSnapshot } from "../stream_handler.ts";
import type { AnalysisStreamRun } from "../stream_run_store.ts";

/// 扣過費（或已建立）超過這麼久還沒有 final_result，就當原請求已經被終止
///（v3 整個請求的模型期限是 90 秒）。
export const GUIDE_V3_STALE_AFTER_MS = 120_000;

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

/// v3 的 run：第一張卡的任務有記、扣費內容或建立時的 requestContext 帶 guideVersion。
export function isGuideV3Run(run: AnalysisStreamRun): boolean {
  return (typeof run.card_task === "string" && run.card_task !== "") ||
    typeof record(run.recommendation_json)?.guideVersion === "string" ||
    typeof record(run.request_context)?.guideVersion === "string";
}

function isCardView(value: unknown): boolean {
  const card = record(value);
  return card !== null && Number.isInteger(card.slot) &&
    typeof card.task === "string" && Array.isArray(card.messages) &&
    card.messages.length > 0 &&
    card.messages.every((m) => typeof m === "string");
}

/// 原請求被終止時，從扣費內容重組結果：判讀＋第一張卡（不送型只有判讀）。
/// 內容不完整就回 null（照失敗處理）。
export function recoveredGuideV3Result(
  run: AnalysisStreamRun,
): Record<string, unknown> | null {
  const stored = record(run.recommendation_json);
  const read = record(stored?.read);
  if (!stored || !read || typeof read.decision !== "string") return null;
  const firstCard = stored.firstCard;
  if (run.card_task) {
    if (!isCardView(firstCard)) return null;
  }
  const chargedMessageCount = record(run.request_context)
    ?.chargedMessageCount;
  const messagesUsed = typeof chargedMessageCount === "number"
    ? chargedMessageCount
    : 0;
  return {
    guideVersion: stored.guideVersion,
    read,
    cards: run.card_task ? [firstCard] : [],
    partial: Boolean(run.card_task),
    recovered: true,
    usage: { messagesUsed, shouldChargeQuota: messagesUsed > 0 },
  };
}

/// v3 run 的續看快照：不 retry（retriesRemaining 一律 0）；太久沒結案的 pending
/// 當失敗、太久沒結案的 charged 從扣費內容重組結果。
export function guideV3ResumeSnapshot(
  run: AnalysisStreamRun,
  nowMs: number,
): StreamAnalysisResumeSnapshot {
  const stale = nowMs - Date.parse(run.created_at) >= GUIDE_V3_STALE_AFTER_MS;
  let finalResult = run.final_result_json;
  let status = run.status;
  let lastErrorCode = run.last_error_code;
  if (!finalResult && stale && run.status === "charged") {
    finalResult = recoveredGuideV3Result(run);
    if (!finalResult) {
      status = "failed";
      lastErrorCode = "GUIDE_V3_RECOVERY_UNAVAILABLE";
    }
  } else if (!finalResult && stale && run.status === "pending") {
    status = "failed";
    lastErrorCode = "GUIDE_V3_ABANDONED";
  }
  return {
    status,
    finalResult: finalResult ? stripClientHiddenFinalResult(finalResult) : null,
    lastErrorCode,
    retriesRemaining: 0,
    wasCharged: run.charged_at !== null,
  };
}
