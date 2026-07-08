import type { InviteStage } from "./invite_maturity.ts";
import { scrubRawImageFilenames } from "./prompt_sanitizer.ts";
import type { PracticeLearningMode } from "./quota_decision.ts";
import type { PartnerMood, PartnerState } from "./temperature.ts";

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
}) {
  const memorySummary = str(opts.memorySummary, 1000);
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
      source: "practice_chat",
      aiTurnCount: opts.aiTurnCount,
      inviteStage: opts.inviteStage,
    },
  };
}
