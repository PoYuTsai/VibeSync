export const MAX_NO_CHARGE_CLARIFICATION_TURNS = 3;

export type CoachSessionTurnLike = {
  role?: unknown;
  kind?: unknown;
  content?: unknown;
};

// 使用者文字本身帶「個案證據」的結構訊號（Codex R2 審查 P2：已貼原話仍被
// 逼再貼）。只看結構、不判語意：說話者標記、兩段以上引號、「她說『…』」
// 句型、或 60 字以上的處境描述。命中＝交回模型判斷要不要再問。
const SPEAKER_LABEL_RE = /(^|[\n，。；、\s—\-–→])(我|她|他|對方)\s*[:：]/u;
const QUOTED_SPAN_RE = /[「『“"][^」』”"\n]{2,}[」』”"]/gu;
const SAID_QUOTE_RE =
  /(她|他|對方)[^，。；\n「『“"]{0,4}(說|回|傳|問|講|寫)[了我你的]{0,2}[「『“"]/u;
export function textCarriesCaseEvidence(text: unknown): boolean {
  if (typeof text !== "string") return false;
  const trimmed = text.trim();
  if (!trimmed) return false;
  if (SPEAKER_LABEL_RE.test(trimmed)) return true;
  if ((trimmed.match(QUOTED_SPAN_RE) ?? []).length >= 2) return true;
  if (SAID_QUOTE_RE.test(trimmed)) return true;
  return trimmed.length >= 60;
}

/// 整個 session 的使用者發言（本題問句＋所有 user turns）有沒有帶個案證據。
/// 看整段而不是只看本題：釐清後貼的原話留在上一張答案之前，「繼續深挖」
/// 不該再逼他貼一次；24h 內種回的上一題若含原話，也是真證據（prompt 看得到）。
export function userTextCarriesCaseEvidence(opts: {
  userQuestion?: unknown;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
}): boolean {
  if (textCarriesCaseEvidence(opts.userQuestion)) return true;
  return (opts.activeSessionTurns ?? []).some((turn) =>
    turn.role === "user" && textCarriesCaseEvidence(turn.content)
  );
}

export function countCoachClarifications(
  turns: readonly CoachSessionTurnLike[] = [],
): number {
  return turns.filter((turn) =>
    turn.role === "coach" && turn.kind === "clarification"
  ).length;
}

// 「這一題」＝最後一張正式答案之後的 turns。client 會把上一題的問答
// （24h resume）或跨天摘要種回 activeSessionTurns 當教練記憶，那些是前一題
// 的東西，不是本題的個案證據（2026-09-07 Eric 真機：同一題零證據卻直接給
// 捏造建議句，閘門因為「turns 非空」沒觸發）。
export function currentThreadTurns<T extends CoachSessionTurnLike>(
  turns: readonly T[] = [],
): readonly T[] {
  let start = 0;
  turns.forEach((turn, index) => {
    if (turn.role === "coach" && turn.kind === "answer") start = index + 1;
  });
  return turns.slice(start);
}

/// 本題已經釐清過（教練問過、使用者有機會補充）——之後才輪到模型自己判斷
/// 要不要再問或直接答。
export function clarifiedInCurrentThread(
  turns: readonly CoachSessionTurnLike[] = [],
): boolean {
  return currentThreadTurns(turns).some((turn) =>
    turn.role === "coach" && turn.kind === "clarification"
  );
}

// 固定決策閘門（2026-08-31 決策分岔案；Batch A 擴為證據制；2026-09-07 改
// 看「這一題」）：本題還沒釐清過、又沒有對方原話、非 forceAnswer 時，「要先
// 釐清還是直接回答」不交給模型擲骰——必定先免費釐清一次。「直接看正式建議」
// （forceAnswer）逃生門保留原樣。
// - global：schema 已保證 summary/snapshot/partnerHint 缺席；client 在
//   global 永遠送空 recentMessages，證據只能靠釐清後使用者貼／補。
// - partner（Batch A）：client 現況不送逐字對話，零證據時模型只能憑 traits
//   腦補個案戰術（G-01/G-03 病灶）——比照 global 強制先釐清。conversation
//   scope 不動。
export function mustClarifyFirstRound(opts: {
  forceAnswer?: boolean;
  scope?: { type?: string } | null;
  userQuestion?: unknown;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
  recentMessages?: readonly unknown[];
  conversationSummary?: string | null;
  analysisSnapshot?: unknown | null;
}): boolean {
  if (opts.forceAnswer === true) return false;
  const noThreadEvidence = !clarifiedInCurrentThread(opts.activeSessionTurns) &&
    (opts.recentMessages ?? []).length === 0 &&
    !userTextCarriesCaseEvidence(opts);
  if (opts.scope?.type === "global") return noThreadEvidence;
  if (opts.scope?.type === "partner") {
    return noThreadEvidence &&
      opts.conversationSummary == null &&
      opts.analysisSnapshot == null;
  }
  return false;
}

export function shouldForceCoachAnswerAfterClarifications(opts: {
  forceAnswer?: boolean;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
}): boolean {
  return opts.forceAnswer === true ||
    countCoachClarifications(opts.activeSessionTurns ?? []) >=
      MAX_NO_CHARGE_CLARIFICATION_TURNS;
}
