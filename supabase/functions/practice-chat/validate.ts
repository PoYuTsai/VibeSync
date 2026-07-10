// practice-chat 請求驗證（純函式、零依賴、可 deno test）。
// 手寫驗證：schema 很小（mode + turns），不引第三方以保持測試零依賴。
// 失敗一律 throw Error("invalid_*")，由 handler 轉 400。

import {
  type PracticeLearningMode,
  type PracticeMode,
} from "./quota_decision.ts";
import {
  isProfileId,
  type PracticeProfile,
  resolvePracticeProfile,
} from "./practice_persona.ts";
import { containsRawImageFilename } from "./prompt_sanitizer.ts";
import type { PartnerMood, PartnerState } from "./temperature.ts";

// 單次 prompt payload 上限。長 visible thread 由 client 送近期逐字稿 + memorySummary，
// 不再把 3 輪當產品上限；這裡只防止一次 request 塞爆 prompt。
export const MAX_TURNS = 130;
export const MAX_TEXT_LEN = 500; // 單則訊息字數上限
export const MAX_MEMORY_SUMMARY_LEN = 1000;
export const MAX_SESSION_ID_LEN = 64;
export const MAX_VISIBLE_THREAD_ID_LEN = 128;

export type TurnRole = "user" | "ai";

export interface PracticeTurn {
  role: TurnRole;
  text: string;
}

export type AppliedHintType = "warm_up" | "steady";

export interface AppliedHintTurn {
  turnIndex: number;
  type: AppliedHintType;
  originalHintText: string;
  sentText: string;
  exact: boolean;
}

export interface PracticeChatRequest {
  mode: PracticeMode;
  practiceMode: PracticeLearningMode;
  /**
   * client 攜帶的溫度三元組分數（續聊同一位保溫用）。選填：缺值時 server 以
   * ledger 權威值→難度起始值 fallback；ledger 建檔後 client 值一律被忽略。
   */
  temperatureScore?: number;
  familiarityScore?: number;
  sessionId: string;
  turns: PracticeTurn[];
  profile: PracticeProfile;
  /** 本輪是第幾輪；舊 client 缺值 fallback 1。 */
  roundIndex: number;
  /** Earlier local-thread summary. Evidence only; never sent to classifier. */
  memorySummary?: string;
  /** local 顯示用 thread id；僅供 log，絕不當作授權身份。 */
  visiblePracticeThreadId?: string;
  /** Last local AI partner state. Seed only; server ledger wins when present. */
  continuationPartnerState?: PartnerState;
  /** 使用者原封不動套用的新手 Hint 類型；只作學習評分保護，不作授權。 */
  appliedHintType?: AppliedHintType;
  appliedHintText?: string;
  /** Debrief 專用：本場哪些 user turn 是由 Hint 建議而來，用於提示責任拆解。 */
  appliedHintTurns?: AppliedHintTurn[];
  /**
   * hint/debrief 模式的冪等 key（client 產 uuid；失敗重試沿用同 id）。選填：舊
   * client 缺值走現行為（無冪等），向後相容。格式比照翻牌 requestId。
   */
  requestId?: string;
  /**
   * Hint-only transport intent. Missing means legacy client; explicit false is
   * a formal request from a prefetch-aware client; true is background prefetch.
   */
  prefetch?: boolean;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isPartnerMood(value: unknown): value is PartnerMood {
  return value === "neutral" ||
    value === "curious" ||
    value === "amused" ||
    value === "comfortable" ||
    value === "guarded" ||
    value === "annoyed";
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
    if (
      raw.practiceMode !== "standard" &&
      raw.practiceMode !== "beginner" &&
      raw.practiceMode !== "game"
    ) {
      throw new Error("invalid_practiceMode");
    }
    practiceMode = raw.practiceMode;
  }

  let temperatureScore: number | undefined;
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

  let familiarityScore: number | undefined;
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

  let appliedHintTurns: AppliedHintTurn[] | undefined;
  if (raw.appliedHintTurns !== undefined) {
    if (
      mode !== "debrief" ||
      (practiceMode !== "beginner" && practiceMode !== "game") ||
      !Array.isArray(raw.appliedHintTurns) ||
      raw.appliedHintTurns.length === 0 ||
      raw.appliedHintTurns.length > 5
    ) {
      throw new Error("invalid_appliedHintTurns");
    }
    const seenAppliedHintTurnIndexes = new Set<number>();
    appliedHintTurns = raw.appliedHintTurns.map((item) => {
      if (!isRecord(item)) throw new Error("invalid_appliedHintTurns");
      const turnIndex = item.turnIndex;
      const type = item.type;
      const originalHintText = item.originalHintText;
      const sentText = item.sentText;
      const exact = item.exact;
      const transcriptSentText = typeof turnIndex === "number" &&
          Number.isInteger(turnIndex) &&
          turnIndex >= 0 &&
          turnIndex < turns.length
        ? turns[turnIndex]?.text
        : undefined;
      const normalizedOriginalHintText = typeof originalHintText === "string"
        ? originalHintText.trim()
        : "";
      const normalizedSentText = typeof sentText === "string"
        ? sentText.trim()
        : "";
      const normalizedTranscriptSentText =
        typeof transcriptSentText === "string" ? transcriptSentText.trim() : "";
      if (
        typeof turnIndex !== "number" ||
        !Number.isInteger(turnIndex) ||
        turnIndex < 0 ||
        turnIndex >= turns.length ||
        turns[turnIndex]?.role !== "user" ||
        (type !== "warm_up" && type !== "steady") ||
        typeof originalHintText !== "string" ||
        normalizedOriginalHintText.length === 0 ||
        originalHintText.length > MAX_TEXT_LEN ||
        containsRawImageFilename(originalHintText) ||
        typeof sentText !== "string" ||
        normalizedSentText.length === 0 ||
        sentText.length > MAX_TEXT_LEN ||
        containsRawImageFilename(sentText) ||
        normalizedSentText !== normalizedTranscriptSentText ||
        typeof exact !== "boolean"
      ) {
        throw new Error("invalid_appliedHintTurns");
      }
      if (seenAppliedHintTurnIndexes.has(turnIndex)) {
        throw new Error("invalid_appliedHintTurns");
      }
      seenAppliedHintTurnIndexes.add(turnIndex);
      return {
        turnIndex,
        type,
        originalHintText: normalizedOriginalHintText,
        sentText: normalizedTranscriptSentText,
        exact: normalizedOriginalHintText === normalizedTranscriptSentText,
      };
    });
  }

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

  // requestId：hint/debrief 模式的冪等 key（選填；缺值＝舊 client，走無冪等
  // 現行為）。格式檢查比照翻牌 requestId；chat 模式一律忽略。
  let requestId: string | undefined;
  if ((mode === "hint" || mode === "debrief") && raw.requestId !== undefined) {
    if (
      typeof raw.requestId !== "string" ||
      !REQUEST_ID_RE.test(raw.requestId)
    ) {
      throw new Error("invalid_requestId");
    }
    requestId = raw.requestId;
  }

  let prefetch: boolean | undefined;
  if (raw.prefetch !== undefined) {
    if (typeof raw.prefetch !== "boolean") {
      throw new Error("invalid_prefetch");
    }
    if (raw.prefetch === true && (mode !== "hint" || requestId === undefined)) {
      throw new Error("invalid_prefetch");
    }
    if (mode === "hint") {
      prefetch = raw.prefetch;
    }
  }

  // roundIndex：缺值 fallback 1；續聊不再由 client cap 3 輪，只收正整數。
  let roundIndex = 1;
  if (raw.roundIndex !== undefined) {
    if (
      typeof raw.roundIndex !== "number" ||
      !Number.isInteger(raw.roundIndex) ||
      raw.roundIndex < 1
    ) {
      throw new Error("invalid_roundIndex");
    }
    roundIndex = raw.roundIndex;
  }

  // visiblePracticeThreadId：選填字串，長度上限；僅供 log，不當授權身份。
  let visiblePracticeThreadId: string | undefined;
  let memorySummary: string | undefined;
  if (raw.memorySummary !== undefined) {
    if (
      typeof raw.memorySummary !== "string" ||
      raw.memorySummary.trim().length === 0 ||
      raw.memorySummary.length > MAX_MEMORY_SUMMARY_LEN ||
      containsRawImageFilename(raw.memorySummary)
    ) {
      throw new Error("invalid_memorySummary");
    }
    memorySummary = raw.memorySummary.trim();
  }

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

  let continuationPartnerState: PartnerState | undefined;
  if (raw.continuationPartnerState !== undefined) {
    if (!isRecord(raw.continuationPartnerState)) {
      throw new Error("invalid_continuationPartnerState");
    }
    const mood = raw.continuationPartnerState.mood;
    const innerThought = raw.continuationPartnerState.innerThought;
    if (
      !isPartnerMood(mood) ||
      typeof innerThought !== "string" ||
      innerThought.length > 160 ||
      containsRawImageFilename(innerThought)
    ) {
      throw new Error("invalid_continuationPartnerState");
    }
    continuationPartnerState = {
      mood,
      innerThought: innerThought.trim().replace(/\s+/g, " ").slice(0, 80),
    };
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
    memorySummary,
    visiblePracticeThreadId,
    continuationPartnerState,
    appliedHintType,
    appliedHintText,
    appliedHintTurns,
    requestId,
    prefetch,
  };
}

// ── draw_profile：獨立 request shape ───────────────────────────────────────
// 翻牌不需要 turns / sessionId / profile（server 選牌）。client 只送 requestId（冪等
// key）、選填 currentProfileId（要排除的當前 profile）、選填 visiblePracticeThreadId
// 與選填 catalogSize（client 宣告自己 catalog 的人數上限，server 據此切抽卡池）。
export interface PracticeDrawRequest {
  mode: "draw_profile";
  requestId: string;
  currentProfileId?: string;
  visiblePracticeThreadId?: string;
  catalogSize?: number;
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

  // catalogSize：選填，client 宣告自己 catalog 的人數上限（選牌切池用）。非法值
  // 一律靜默降級成 undefined（→ 切池層 fail-closed 回舊池 60），絕不 throw 400——
  // 400 會鎖死已裝機的舊 client（Edge 收緊必配 client clamp；這裡直接不收緊）。
  let catalogSize: number | undefined;
  if (
    typeof raw.catalogSize === "number" &&
    Number.isInteger(raw.catalogSize) &&
    raw.catalogSize > 0
  ) {
    catalogSize = raw.catalogSize;
  }

  return {
    mode: "draw_profile",
    requestId,
    currentProfileId,
    visiblePracticeThreadId,
    catalogSize,
  };
}
