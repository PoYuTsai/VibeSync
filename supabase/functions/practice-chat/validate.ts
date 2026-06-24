// practice-chat 請求驗證（純函式、零依賴、可 deno test）。
// 手寫驗證：schema 很小（mode + turns），不引第三方以保持測試零依賴。
// 失敗一律 throw Error("invalid_*")，由 handler 轉 400。

import { type PracticeMode } from "./quota_decision.ts";
import {
  type PracticeProfile,
  resolvePracticeProfile,
} from "./practice_persona.ts";

export const MAX_TURNS = 40; // 10 則 AI 回覆上限 → 一來一回頂多 ~20，留緩衝
export const MAX_TEXT_LEN = 500; // 單則訊息字數上限
export const MAX_SESSION_ID_LEN = 64;

export type TurnRole = "user" | "ai";

export interface PracticeTurn {
  role: TurnRole;
  text: string;
}

export interface PracticeChatRequest {
  mode: PracticeMode;
  sessionId: string;
  turns: PracticeTurn[];
  profile: PracticeProfile;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** 計算陣列中 role === "ai" 的數量。 */
export function countAiTurns(turns: PracticeTurn[]): number {
  return turns.filter((t) => t.role === "ai").length;
}

export function validateRequest(raw: unknown): PracticeChatRequest {
  if (!isRecord(raw)) throw new Error("invalid_request_body");

  const mode = raw.mode;
  if (mode !== "chat" && mode !== "debrief") {
    throw new Error("invalid_mode");
  }

  const sessionId = raw.sessionId;
  if (
    typeof sessionId !== "string" ||
    sessionId.length === 0 ||
    sessionId.length > MAX_SESSION_ID_LEN
  ) {
    throw new Error("invalid_sessionId");
  }

  const rawTurns = raw.turns;
  if (!Array.isArray(rawTurns)) throw new Error("invalid_turns");
  if (rawTurns.length === 0) throw new Error("invalid_turns_empty");
  if (rawTurns.length > MAX_TURNS) throw new Error("invalid_turns_too_many");

  const turns: PracticeTurn[] = rawTurns.map((t, i) => {
    if (!isRecord(t)) throw new Error(`invalid_turn_${i}`);
    const role = t.role;
    if (role !== "user" && role !== "ai") throw new Error(`invalid_turn_role_${i}`);
    const text = t.text;
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new Error(`invalid_turn_text_${i}`);
    }
    if (text.length > MAX_TEXT_LEN) throw new Error(`invalid_turn_text_len_${i}`);
    return { role, text };
  });

  const aiCount = countAiTurns(turns);

  if (mode === "chat") {
    // chat：在回覆一則 user 訊息，故最後一則必須是 user。
    if (turns[turns.length - 1].role !== "user") {
      throw new Error("invalid_chat_last_turn_must_be_user");
    }
    // 注意：10 則上限「不」在此用 client count 把關——client 可少報 ai turns
    // 繞過。上限改由 server ledger（practice_chat_sessions.ai_count）在 handler
    // preflight 與 commit RPC 內以權威狀態強制。
  } else {
    // debrief：client payload 至少要有一來一回才有逐字稿可拆解（形狀檢查）；
    // 「是否真為已扣費 session」由 server ledger 在 handler 內把關。
    if (aiCount === 0) throw new Error("invalid_debrief_no_ai_turns");
  }

  const profile = resolvePracticeProfile({
    personaId: raw.personaId,
    difficulty: raw.difficulty,
  });

  return { mode, sessionId, turns, profile };
}
