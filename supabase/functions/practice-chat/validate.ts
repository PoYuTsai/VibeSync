// practice-chat 請求驗證（純函式、零依賴、可 deno test）。
// 手寫驗證：schema 很小（mode + turns），不引第三方以保持測試零依賴。
// 失敗一律 throw Error("invalid_*")，由 handler 轉 400。

import {
  MAX_PRACTICE_ROUNDS,
  type PracticeLearningMode,
  type PracticeMode,
} from "./quota_decision.ts";
import {
  isProfileId,
  type PracticeProfile,
  resolvePracticeProfile,
} from "./practice_persona.ts";
import { containsRawImageFilename } from "./prompt_sanitizer.ts";

// 一個 visible thread 最多 3 輪、每輪 20 則 AI 回覆。debrief 會把整個 visible thread
// 的逐字稿一起送，故 turns 上界要涵蓋 3 輪：3×(20 AI + 20 user)=120，留緩衝到 130。
export const MAX_TURNS = 130;
export const MAX_TEXT_LEN = 500; // 單則訊息字數上限
export const MAX_SESSION_ID_LEN = 64;
export const MAX_VISIBLE_THREAD_ID_LEN = 128;

export type TurnRole = "user" | "ai";

export interface PracticeTurn {
  role: TurnRole;
  text: string;
}

export type AppliedHintType = "warm_up" | "steady";

export interface PracticeChatRequest {
  mode: PracticeMode;
  practiceMode: PracticeLearningMode;
  temperatureScore: number;
  familiarityScore: number;
  sessionId: string;
  turns: PracticeTurn[];
  profile: PracticeProfile;
  /** 本輪是第幾輪（1..3）；舊 client 缺值 fallback 1。 */
  roundIndex: number;
  /** local 顯示用 thread id；僅供 log，絕不當作授權身份。 */
  visiblePracticeThreadId?: string;
  /** 使用者原封不動套用的新手 Hint 類型；只作學習評分保護，不作授權。 */
  appliedHintType?: AppliedHintType;
  appliedHintText?: string;
  /**
   * hint 模式限定的冪等 key（client 產 uuid；失敗重試沿用同 id）。選填：舊
   * client 缺值走現行為（無冪等），向後相容。格式比照翻牌 requestId。
   */
  requestId?: string;
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
  if (mode !== "chat" && mode !== "debrief" && mode !== "hint") {
    throw new Error("invalid_mode");
  }

  let practiceMode: PracticeLearningMode = "standard";
  if (raw.practiceMode !== undefined) {
    if (raw.practiceMode !== "standard" && raw.practiceMode !== "beginner") {
      throw new Error("invalid_practiceMode");
    }
    practiceMode = raw.practiceMode;
  }

  let temperatureScore = 30;
  if (raw.temperatureScore !== undefined) {
    if (
      typeof raw.temperatureScore !== "number" ||
      !Number.isInteger(raw.temperatureScore) ||
      raw.temperatureScore < 0 ||
      raw.temperatureScore > 100
    ) {
      throw new Error("invalid_temperatureScore");
    }
    temperatureScore = raw.temperatureScore;
  }

  let familiarityScore = 0;
  if (raw.familiarityScore !== undefined) {
    if (
      typeof raw.familiarityScore !== "number" ||
      !Number.isInteger(raw.familiarityScore) ||
      raw.familiarityScore < 0 ||
      raw.familiarityScore > 100
    ) {
      throw new Error("invalid_familiarityScore");
    }
    familiarityScore = raw.familiarityScore;
  }

  let appliedHintType: AppliedHintType | undefined;
  if (raw.appliedHintType !== undefined) {
    if (raw.appliedHintType !== "warm_up" && raw.appliedHintType !== "steady") {
      throw new Error("invalid_appliedHintType");
    }
    appliedHintType = raw.appliedHintType;
  }

  let appliedHintText: string | undefined;
  if (raw.appliedHintText !== undefined) {
    if (
      appliedHintType === undefined ||
      typeof raw.appliedHintText !== "string" ||
      raw.appliedHintText.trim().length === 0 ||
      raw.appliedHintText.length > MAX_TEXT_LEN ||
      containsRawImageFilename(raw.appliedHintText)
    ) {
      throw new Error("invalid_appliedHintText");
    }
    appliedHintText = raw.appliedHintText.trim();
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
    if (role !== "user" && role !== "ai") {
      throw new Error(`invalid_turn_role_${i}`);
    }
    const text = t.text;
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new Error(`invalid_turn_text_${i}`);
    }
    if (text.length > MAX_TEXT_LEN) {
      throw new Error(`invalid_turn_text_len_${i}`);
    }
    return { role, text };
  });

  const aiCount = countAiTurns(turns);

  if (mode === "chat") {
    // chat：在回覆一則 user 訊息，故最後一則必須是 user。
    if (turns[turns.length - 1].role !== "user") {
      throw new Error("invalid_chat_last_turn_must_be_user");
    }
    // 注意：20 則上限「不」在此用 client count 把關——client 可少報 ai turns
    // 繞過。上限改由 server ledger（practice_chat_sessions.ai_count）在 handler
    // preflight 與 commit RPC 內以權威狀態強制。
  } else if (mode === "debrief") {
    // debrief：client payload 至少要有一來一回才有逐字稿可拆解（形狀檢查）；
    // 「是否真為已扣費 session」由 server ledger 在 handler 內把關。
    if (aiCount === 0) throw new Error("invalid_debrief_no_ai_turns");
  } else {
    if (aiCount === 0) throw new Error("invalid_hint_no_ai_turns");
    if (turns[turns.length - 1].role !== "ai") {
      throw new Error("invalid_hint_last_turn_must_be_ai");
    }
  }

  const profile = resolvePracticeProfile({
    personaId: raw.personaId,
    difficulty: raw.difficulty,
    profileId: raw.profileId,
    nameId: raw.nameId,
    professionId: raw.professionId,
    photoId: raw.photoId,
  });

  // requestId：hint 模式限定的冪等 key（選填；缺值＝舊 client，走無冪等現行為）。
  // 格式檢查比照翻牌 requestId；非 hint 模式一律忽略。
  let requestId: string | undefined;
  if (mode === "hint" && raw.requestId !== undefined) {
    if (
      typeof raw.requestId !== "string" ||
      !REQUEST_ID_RE.test(raw.requestId)
    ) {
      throw new Error("invalid_requestId");
    }
    requestId = raw.requestId;
  }

  // roundIndex：缺值 fallback 1；只收整數 1..MAX_PRACTICE_ROUNDS。
  let roundIndex = 1;
  if (raw.roundIndex !== undefined) {
    if (
      typeof raw.roundIndex !== "number" ||
      !Number.isInteger(raw.roundIndex) ||
      raw.roundIndex < 1 ||
      raw.roundIndex > MAX_PRACTICE_ROUNDS
    ) {
      throw new Error("invalid_roundIndex");
    }
    roundIndex = raw.roundIndex;
  }

  // visiblePracticeThreadId：選填字串，長度上限；僅供 log，不當授權身份。
  let visiblePracticeThreadId: string | undefined;
  if (raw.visiblePracticeThreadId !== undefined) {
    if (
      typeof raw.visiblePracticeThreadId !== "string" ||
      raw.visiblePracticeThreadId.length === 0 ||
      raw.visiblePracticeThreadId.length > MAX_VISIBLE_THREAD_ID_LEN
    ) {
      throw new Error("invalid_visiblePracticeThreadId");
    }
    visiblePracticeThreadId = raw.visiblePracticeThreadId;
  }

  return {
    mode,
    practiceMode,
    temperatureScore,
    familiarityScore,
    sessionId,
    turns,
    profile,
    roundIndex,
    visiblePracticeThreadId,
    appliedHintType,
    appliedHintText,
    requestId,
  };
}

// ── draw_profile：獨立 request shape ───────────────────────────────────────
// 翻牌不需要 turns / sessionId / profile（server 選牌）。client 只送 requestId（冪等
// key）、選填 currentProfileId（要排除的當前 profile）與選填 visiblePracticeThreadId。
export interface PracticeDrawRequest {
  mode: "draw_profile";
  requestId: string;
  currentProfileId?: string;
  visiblePracticeThreadId?: string;
}

// requestId：UUID 或安全 id 字串（client 產，server idempotency key）。長度 1..64
// 與 ledger request_id CHECK 一致；字元集限制避免奇異輸入。翻牌與 hint 冪等共用。
const REQUEST_ID_RE = /^[A-Za-z0-9._:-]{1,64}$/;

export function validateDrawRequest(raw: unknown): PracticeDrawRequest {
  if (!isRecord(raw)) throw new Error("invalid_request_body");
  if (raw.mode !== "draw_profile") throw new Error("invalid_mode");

  const requestId = raw.requestId;
  if (typeof requestId !== "string" || !REQUEST_ID_RE.test(requestId)) {
    throw new Error("invalid_requestId");
  }

  // currentProfileId：選填，但若送必須是 allowlisted profileId（堵自由文字人設）。
  let currentProfileId: string | undefined;
  if (raw.currentProfileId !== undefined) {
    if (!isProfileId(raw.currentProfileId)) {
      throw new Error("invalid_currentProfileId");
    }
    currentProfileId = raw.currentProfileId as string;
  }

  // visiblePracticeThreadId：選填字串，長度上限；僅供 log，不當授權身份。
  let visiblePracticeThreadId: string | undefined;
  if (raw.visiblePracticeThreadId !== undefined) {
    if (
      typeof raw.visiblePracticeThreadId !== "string" ||
      raw.visiblePracticeThreadId.length === 0 ||
      raw.visiblePracticeThreadId.length > MAX_VISIBLE_THREAD_ID_LEN
    ) {
      throw new Error("invalid_visiblePracticeThreadId");
    }
    visiblePracticeThreadId = raw.visiblePracticeThreadId;
  }

  return {
    mode: "draw_profile",
    requestId,
    currentProfileId,
    visiblePracticeThreadId,
  };
}
