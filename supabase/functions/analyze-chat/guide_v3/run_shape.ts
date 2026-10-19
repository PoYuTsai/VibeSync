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
  // 實際扣了幾則記在扣費內容裡（自傷關心是 0）；建立 run 時的預估不能用。
  const messagesUsed = typeof stored.chargedMessageCount === "number"
    ? stored.chargedMessageCount
    : 0;
  return {
    guideVersion: stored.guideVersion,
    read,
    cards: run.card_task ? [firstCard] : [],
    partial: Boolean(run.card_task),
    recovered: true,
    usage: { messagesUsed, shouldChargeQuota: messagesUsed > 0 },
    // 原請求沒有結案：判讀與第一張卡在扣費那一刻就定了，用扣費時間（不是重組的時間）。
    ...(isoUtc(run.charged_at) ? { completedAt: isoUtc(run.charged_at) } : {}),
  };
}

/// 資料庫的時間（PostgREST 回「…+00:00」、微秒六位）換成跟結案時間同一種寫法（toISOString 的
/// UTC「…Z」）；讀不懂就當沒有。
function isoUtc(value: string | null | undefined): string | undefined {
  const ms = typeof value === "string" ? Date.parse(value) : NaN;
  return Number.isNaN(ms) ? undefined : new Date(ms).toISOString();
}

/// 續看重播的結案時間：結果裡存的那個；沒存的（這個欄位之前結案的、或從扣費內容重組的）用扣費
/// 時間。都是 run 原本的時間，不是重播當下（Eric 2026-10-20）。
function replayedCompletedAt(
  run: AnalysisStreamRun,
  finalResult: Record<string, unknown> | null,
): string | undefined {
  if (!finalResult) return undefined;
  const stored = finalResult.completedAt;
  if (typeof stored === "string" && stored !== "") return stored;
  return isoUtc(run.charged_at);
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
  // 扣過費卻沒有結果：還在 charged 的要等逾時（原請求可能還在寫）；被記成 failed 的
  // 已經沒有人在寫，馬上重組（v3 扣過費的 run 不該被記 failed，萬一有就照扣費內容給）。
  const recoverNow = !finalResult && run.charged_at !== null &&
    (run.status === "failed" || (run.status === "charged" && stale));
  if (recoverNow) {
    finalResult = recoveredGuideV3Result(run);
    if (!finalResult) {
      status = "failed";
      lastErrorCode = "GUIDE_V3_RECOVERY_UNAVAILABLE";
    }
  } else if (!finalResult && stale && run.status === "pending") {
    status = "failed";
    lastErrorCode = "GUIDE_V3_ABANDONED";
  }
  const completedAt = replayedCompletedAt(run, finalResult);
  return {
    status,
    finalResult: finalResult ? stripClientHiddenFinalResult(finalResult) : null,
    lastErrorCode,
    retriesRemaining: 0,
    wasCharged: run.charged_at !== null,
    ...(completedAt ? { completedAt } : {}),
  };
}
