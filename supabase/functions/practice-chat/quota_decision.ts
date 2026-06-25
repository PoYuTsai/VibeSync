// practice-chat 額度決策（純函式、零副作用、可 deno test）。
//
// 安全模型（見 docs/plans/2026-06-24-practice-chat-ledger-design.md）：
//   一律以 server-side ledger（practice_chat_sessions）為準，**絕不**信任 client
//   送來的 turns 來決定扣費或上限。client turns 只當 prompt 資料。
//
// 規則：
//   一輪練習 = 扣 1 則 Coach 額度，且一輪一生只扣一次（charged 單調 false→true）。
//   - 「一輪」= 一個 billing session_id；續玩開新的 session_id（新一列、新一次扣費）。
//   - chat 扣費條件：server `charged === false` 且非測試帳號（與 client aiTurnCount 無關）。
//   - 20 則上限：以 server `ai_count` 為準（本輪 session_id 的計數）。
//   - debrief：永不扣，但須附著於已扣費 session 且有次數上限。
//   - 任何 DeepSeek 失敗由 handler 在 commit 前 return，故失敗一律不扣。
//   - 原子扣費 + 計數遞增由 RPC（commit_practice_chat_turn / claim_practice_debrief）
//     在同一交易內完成；本檔僅做 preflight 預判。
//   注意：上限值由 handler 以 p_max_replies 傳入 RPC，故改這裡即生效，毋須改已部署
//   的 RPC（其 DEFAULT 10 不被使用）。

import { normalizeTier } from "../_shared/quota.ts";

export const MAX_AI_REPLIES = 20;
export const MAX_DEBRIEFS = 3;
export const PRACTICE_QUOTA_COST = 1;
/** MVP：一個 visible thread 最多 3 輪（60 則 AI 回覆）。roundIndex 的合法上界。 */
export const MAX_PRACTICE_ROUNDS = 3;

export type PracticeMode = "chat" | "debrief";

/** 某場練習的 server 端權威狀態快照（preflight 讀取後傳入）。 */
export interface SessionLedger {
  exists: boolean;
  aiCount: number;
  charged: boolean;
  debriefCount: number;
}

/** 一場已產生 aiTurnCount 則 AI 回覆後，是否已達上限（不能再聊）。 */
export function isSessionComplete(aiTurnCount: number): boolean {
  return aiTurnCount >= MAX_AI_REPLIES;
}

/**
 * chat preflight（DeepSeek 前）：用 server ledger 判斷上限與是否需要走額度閘。
 * 權威扣費仍在 commit RPC 內以 FOR UPDATE 重判；此處只為「未達上限才打 DeepSeek」
 * 與「要扣費的人才做 quota 429 preflight」。
 * @returns atCap 是否已達 10 則上限；shouldChargePreview 預判本次是否要扣 1。
 */
export function decideChatGate(opts: {
  ledger: SessionLedger;
  isTestAccount: boolean;
  maxReplies?: number;
}): { atCap: boolean; shouldChargePreview: boolean } {
  const max = opts.maxReplies ?? MAX_AI_REPLIES;
  const atCap = opts.ledger.aiCount >= max;
  const shouldChargePreview = !opts.ledger.charged && !opts.isTestAccount;
  return { atCap, shouldChargePreview };
}

/**
 * Free 續玩閘（MVP，無新 migration）：Free 帳號只能玩第 1 輪；要續「同一位」（roundIndex>1）
 * 須升級。付費（starter/essential）不限。roundIndex 缺值已由 validate fallback 1，故 Free
 * 開全新一位（新 session、roundIndex 1）仍放行，只擋同一位續玩。
 *
 * 這是 server 正常路徑的硬閘：未知/缺 tier 一律 normalizeTier→free 而 fail-closed。
 * 但**不**宣稱 abuse-proof——沒有 per-thread ledger，惡意 client 可送 roundIndex=1 規避；
 * 此閘只保證 app 正常路徑擋住 Free 續同一位。
 * @returns allowed=false 時 reason 一律 'upgrade_required'，由 handler 轉 402。
 */
export function decideContinuationGate(opts: {
  tier: string | null | undefined;
  roundIndex: number;
}): { allowed: boolean; reason?: string } {
  if (normalizeTier(opts.tier) === "free" && opts.roundIndex > 1) {
    return { allowed: false, reason: "upgrade_required" };
  }
  return { allowed: true };
}

/**
 * debrief preflight：只有「已正式扣費（已建立）且有 AI 回覆、且未達 debrief 上限」
 * 的 session 才能拆解。堵偽造 turns 免費打 debrief、與單一付費 session 無限拆解。
 */
export function decideDebriefGate(opts: {
  ledger: SessionLedger;
  maxDebriefs?: number;
}): { allowed: boolean; reason?: string } {
  const max = opts.maxDebriefs ?? MAX_DEBRIEFS;
  const { exists, charged, aiCount, debriefCount } = opts.ledger;
  if (!exists || !charged || aiCount < 1) {
    return { allowed: false, reason: "practice_session_not_started" };
  }
  if (debriefCount >= max) {
    return { allowed: false, reason: "practice_debrief_limit" };
  }
  return { allowed: true };
}
