// 案1批3：outcome loop 去識別化上傳的驗證 + 建 row 純函式。
// index.ts 只負責 dispatch 與 upsert；本檔可單測。
//
// 白名單原則：只讀以下欄位。outcomeTextPreview（對方回覆原文）、userNote
// （使用者筆記）、partnerId、conversationId 即使 client 誤送也絕不落庫。
import { truncateOptionalStringToMax } from "./feedback_utils.ts";

export const OUTCOME_SUMMARY_MAX = 160;
export const OUTCOME_ID_MAX = 128;
export const OUTCOME_ENUM_MAX = 40;
export const OUTCOME_ADVICE_TYPE_MAX = 48;
export const OUTCOME_ADVICE_ID_MAX = 128;
export const OUTCOME_USER_TIER_MAX = 50;

export interface OutcomeRow {
  id: string;
  user_id: string;
  source: string;
  advice_type?: string;
  advice_id?: string;
  user_action: string;
  outcome: string;
  suggested_move_summary: string;
  user_tier?: string;
  client_created_at: string;
}

export type BuildOutcomeResult =
  | { ok: true; row: OutcomeRow }
  | { ok: false; error: string };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// 必填字串：非字串或 trim 後為空 → null；否則 trim + 硬截斷（不加省略號）。
function requiredTrimmed(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  return trimmed.slice(0, max);
}

/**
 * 從信任的 userId + 不信任的 client rawEvent 建出可 upsert 的 outcome row。
 * 只挑白名單欄位；任何未列欄位（含敏感的 outcomeTextPreview／userNote）一律丟棄。
 */
export function buildOutcomeRow(
  userId: string,
  rawEvent: unknown,
): BuildOutcomeResult {
  if (!isPlainObject(rawEvent)) {
    return { ok: false, error: "Invalid outcome event" };
  }

  const id = requiredTrimmed(rawEvent.id, OUTCOME_ID_MAX);
  const source = requiredTrimmed(rawEvent.source, OUTCOME_ENUM_MAX);
  const userAction = requiredTrimmed(rawEvent.userAction, OUTCOME_ENUM_MAX);
  const outcome = requiredTrimmed(rawEvent.outcome, OUTCOME_ENUM_MAX);
  const suggestedMoveSummary = requiredTrimmed(
    rawEvent.suggestedMoveSummary,
    OUTCOME_SUMMARY_MAX,
  );

  if (!id || !source || !userAction || !outcome || !suggestedMoveSummary) {
    return { ok: false, error: "Invalid outcome event" };
  }

  const createdAtRaw = typeof rawEvent.createdAt === "string"
    ? rawEvent.createdAt
    : "";
  const createdAtMs = Date.parse(createdAtRaw);
  if (Number.isNaN(createdAtMs)) {
    return { ok: false, error: "Invalid outcome createdAt" };
  }

  const row: OutcomeRow = {
    id,
    user_id: userId,
    source,
    user_action: userAction,
    outcome,
    suggested_move_summary: suggestedMoveSummary,
    client_created_at: new Date(createdAtMs).toISOString(),
  };

  const adviceType = truncateOptionalStringToMax(
    rawEvent.adviceType,
    OUTCOME_ADVICE_TYPE_MAX,
  );
  if (adviceType) row.advice_type = adviceType;

  const adviceId = truncateOptionalStringToMax(
    rawEvent.adviceId,
    OUTCOME_ADVICE_ID_MAX,
  );
  if (adviceId) row.advice_id = adviceId;

  const userTier = truncateOptionalStringToMax(
    rawEvent.userTier,
    OUTCOME_USER_TIER_MAX,
  );
  if (userTier) row.user_tier = userTier;

  return { ok: true, row };
}
