import type { InviteStage } from "./invite_maturity.ts";
import { scrubRawImageFilenames } from "./prompt_sanitizer.ts";
import type { PracticeLearningMode } from "./quota_decision.ts";
import type { PartnerMood, PartnerState } from "./temperature.ts";
import {
  parseReplyStyleState,
  REPLY_STYLE_STATE_KEY,
  type ReplyStyleState,
} from "./reply_style_state.ts";
import {
  type AgencyMode,
  CONVERSATION_AGENCY_STATE_KEY,
  type ConversationAgencyState,
  parseConversationAgencyState,
} from "./conversation_agency.ts";

const PARTNER_MOODS: readonly PartnerMood[] = [
  "neutral",
  "curious",
  "amused",
  "comfortable",
  "guarded",
  "annoyed",
];

const INVITE_STAGES: readonly InviteStage[] = [
  "not_ready",
  "soft_invite_ready",
  "direct_invite_ready",
  "partner_window",
  "high_intimacy",
];

const PRACTICE_MODES: readonly PracticeLearningMode[] = [
  "standard",
  "beginner",
  "game",
];

export interface PracticeRelationshipThreadState {
  memorySummary?: string | null;
  partnerState?: PartnerState | null;
  temperatureScore?: number | null;
  familiarityScore?: number | null;
  profileId?: string | null;
  practiceMode?: PracticeLearningMode | null;
  inviteStage?: InviteStage | null;
  /** reply-style-v1 跨回合狀態（recent_facts.replyStyle）；沒有＝null。 */
  styleState?: ReplyStyleState | null;
  /** conversation-agency-v1 跨回合狀態（recent_facts.conversationAgency）。 */
  agencyState?: ConversationAgencyState | null;
  /**
   * 讀回來的整份 `recent_facts`（Codex round-2 P1-4）。RPC 是整包覆寫，
   * 舊版從零重建這個物件，任何本檔不認識的 key（別的功能寫的、未來版本寫的、
   * 另一個 client 寫的）都會在下一次 upsert 靜默消失。這裡原樣留著，
   * `buildRelationshipThreadRpcParams` 以它為底再覆寫自己負責的欄位。
   */
  recentFacts?: Record<string, unknown> | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function str(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = scrubRawImageFilenames(value).trim().replace(/\s+/g, " ");
  return trimmed ? trimmed.slice(0, max) : null;
}

function score(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.max(0, Math.min(100, Math.round(value)));
}

function mode(value: unknown): PracticeLearningMode | null {
  return typeof value === "string" &&
      PRACTICE_MODES.includes(value as PracticeLearningMode)
    ? value as PracticeLearningMode
    : null;
}

function mood(value: unknown): PartnerMood | null {
  return typeof value === "string" &&
      PARTNER_MOODS.includes(value as PartnerMood)
    ? value as PartnerMood
    : null;
}

function inviteStage(value: unknown): InviteStage | null {
  return typeof value === "string" &&
      INVITE_STAGES.includes(value as InviteStage)
    ? value as InviteStage
    : null;
}

export function parseRelationshipThreadRow(
  row: unknown,
): PracticeRelationshipThreadState | null {
  if (!isRecord(row)) return null;
  const partnerMood = mood(row.partner_mood);
  const innerThought = str(row.partner_inner_thought, 80) ?? "";
  return {
    memorySummary: str(row.memory_summary, 1000),
    partnerState: partnerMood ? { mood: partnerMood, innerThought } : null,
    temperatureScore: score(row.temperature_score),
    familiarityScore: score(row.familiarity_score),
    profileId: str(row.profile_id, 80),
    practiceMode: mode(row.practice_mode),
    inviteStage: inviteStage(row.invite_stage),
    styleState: parseReplyStyleState(row.recent_facts),
    agencyState: parseConversationAgencyState(row.recent_facts),
    recentFacts: isRecord(row.recent_facts) ? row.recent_facts : null,
  };
}

export function threadIdForPracticeRequest(opts: {
  sessionId: string;
  visiblePracticeThreadId?: string | null;
}): string {
  return opts.visiblePracticeThreadId?.trim() || opts.sessionId;
}

export function buildRelationshipThreadRpcParams(opts: {
  userId: string;
  visibleThreadId: string;
  profileId?: string | null;
  practiceMode: PracticeLearningMode;
  relationshipScore: number;
  temperatureScore?: number | null;
  familiarityScore?: number | null;
  partnerState?: PartnerState | null;
  inviteStage: InviteStage;
  memorySummary?: string | null;
  aiTurnCount: number;
  /** reply-style-v1：只有 style 層真的跑了才帶；省略＝recent_facts 與舊版逐字相同。 */
  replyStyleState?: ReplyStyleState | null;
  /** conversation-agency-v1：同上；旗標 off／shadow 一律省略或原樣帶回既有值。 */
  conversationAgencyState?: ConversationAgencyState | null;
  /**
   * 這個 thread 上一次讀回來的整份 `recent_facts`（Codex round-2 P1-4）。
   * 以它為底，只覆寫下面這幾個由本檔擁有的 key；不認識的 key 原樣留著。
   * 省略／null＝新 thread，payload 與舊版逐字相同（golden）。
   *
   * **只有 `agencyMode !== "off"` 時才會被採用**——見下面那個欄位。
   */
  existingRecentFacts?: Record<string, unknown> | null;
  /**
   * conversation-agency-v1 Phase 2.6（Codex round-1 P1-a）：保留未知 key 是
   * agency 分支帶進來的行為改動，不是既有行為。旗標 off 的 thread 必須跟
   * main 逐字相同——main 是**從零重建** `recent_facts`，未知 key 會被丟掉。
   * 舊版無條件 spread `existingRecentFacts`，等於旗標關著也偷偷改了 payload。
   * 省略＝off＝從零重建（其餘呼叫端逐字不變）。
   */
  agencyMode?: AgencyMode;
}) {
  const memorySummary = str(opts.memorySummary, 1000);
  // 旗標 off（或省略）：從零重建，跟 main 逐字相同。
  const preservedRecentFacts: Record<string, unknown> =
    opts.agencyMode && opts.agencyMode !== "off"
      ? opts.existingRecentFacts ?? {}
      : {};
  return {
    p_user_id: opts.userId,
    p_visible_thread_id: opts.visibleThreadId,
    p_profile_id: opts.profileId ?? null,
    p_practice_mode: opts.practiceMode,
    p_relationship_score: Math.max(
      0,
      Math.min(100, Math.round(opts.relationshipScore)),
    ),
    p_temperature_score: opts.temperatureScore ?? null,
    p_familiarity_score: opts.familiarityScore ?? null,
    p_partner_mood: opts.partnerState?.mood ?? null,
    p_partner_inner_thought: str(opts.partnerState?.innerThought, 80),
    p_invite_stage: opts.inviteStage,
    p_memory_summary: memorySummary,
    p_recent_facts: {
      ...preservedRecentFacts,
      source: "practice_chat",
      aiTurnCount: opts.aiTurnCount,
      inviteStage: opts.inviteStage,
      ...(opts.replyStyleState
        ? { [REPLY_STYLE_STATE_KEY]: opts.replyStyleState }
        : {}),
      ...(opts.conversationAgencyState
        ? { [CONVERSATION_AGENCY_STATE_KEY]: opts.conversationAgencyState }
        : {}),
    },
  };
}
