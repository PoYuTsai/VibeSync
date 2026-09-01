// Analyze V2 message decision (Phase 1b): the single source of truth for the
// three no-send decisions and the charge payload they produce.
//
// Everything here is capability-gated by the request's analysisContractVersion.
// A v1 client never sees a no-send decision: the reframer keeps validating the
// first decision with validateDecisionChargeEvent exactly as before.

import type { AnalysisEvidenceLinkage } from "./reframer.ts";
import type { StreamEvent } from "./stream_events.ts";
import {
  hasPromptInjection,
  hasUnsafeRecommendation,
  textField,
} from "./stream_recommendation_guardrail.ts";

export const NO_SEND_DECISION_KINDS = [
  "do_not_send",
  "acknowledge_and_stop",
  "need_context",
] as const;
export type NoSendDecisionKind = typeof NO_SEND_DECISION_KINDS[number];

export const ANALYSIS_ACTIONS = [
  "stop",
  "connect",
  "extend",
  "filter",
  "invite",
  "pause",
] as const;

/// Newest analysis contract a client may declare. 1 (or absent) is the v1
/// five-style contract; 2 adds no-send decisions and replyMode none/single.
export const ANALYSIS_CONTRACT_VERSION_V2 = 2;

export interface StreamNoSendRecommendationForCharge {
  decisionKind: NoSendDecisionKind;
  // Kept as an explicit null so existing readers of `.selectedStyle` on the
  // charge payload union keep type-checking; the DB stores NULL for it.
  selectedStyle: null;
  action: string;
  reason: string;
  stopCondition: string;
  closingMessage?: string;
  raw: StreamEvent | Record<string, unknown>;
  analysisDecisionV2: Record<string, unknown>;
  // Phase 0 charge-time snapshots, same optional semantics as the send payload.
  analysisInventory?: Record<string, unknown>;
  analysisEvidenceLinkage?: AnalysisEvidenceLinkage;
}

export function isNoSendDecisionKind(
  value: unknown,
): value is NoSendDecisionKind {
  return typeof value === "string" &&
    (NO_SEND_DECISION_KINDS as readonly string[]).includes(value);
}

export function isNoSendChargePayload(
  value: unknown,
): value is StreamNoSendRecommendationForCharge {
  return typeof value === "object" && value !== null &&
    isNoSendDecisionKind((value as { decisionKind?: unknown }).decisionKind);
}

export function replyModeForDecision(
  kind: NoSendDecisionKind,
): "single" | "none" {
  return kind === "acknowledge_and_stop" ? "single" : "none";
}

/// Strict request capability parse, same policy as billingProtocolVersion:
/// absent => v1; anything that is not integer 1 or 2 => 400.
export function parseAnalysisContractVersion(
  raw: unknown,
): { ok: true; value: number } | { ok: false } {
  if (raw == null) return { ok: true, value: 1 };
  if (
    typeof raw !== "number" || !Number.isInteger(raw) || raw < 1 ||
    raw > ANALYSIS_CONTRACT_VERSION_V2
  ) {
    return { ok: false };
  }
  return { ok: true, value: raw };
}

export type NoSendDecisionValidation =
  | { ok: true; payload: StreamNoSendRecommendationForCharge }
  | {
    ok: false;
    code: "STREAM_MALFORMED_RECOMMENDATION" | "STREAM_UNSAFE_RECOMMENDATION";
    reason: string;
  };

/// Charge-time validation of a no-send `analysis.decision`. Mirrors the DB
/// rule in charge_stream_analysis_run_v2: an empty-shell decision never
/// charges quota.
export function validateNoSendDecisionEvent(
  event: StreamEvent | Record<string, unknown>,
): NoSendDecisionValidation {
  const kind = event.messageDecision;
  if (event.type !== "analysis.decision" || !isNoSendDecisionKind(kind)) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "expected a no-send analysis.decision event",
    };
  }
  const action = textField(event.action);
  if (!(ANALYSIS_ACTIONS as readonly string[]).includes(action)) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "no-send decision action is required",
    };
  }
  const reason = textField(event.reason);
  const stopCondition = textField(event.stopCondition);
  const closingMessage = textField(event.closingMessage);
  if (!reason || !stopCondition) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "no-send decision reason and stopCondition are required",
    };
  }
  if (kind === "acknowledge_and_stop" && !closingMessage) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "acknowledge_and_stop requires closingMessage",
    };
  }
  const modelAuthoredText = `${reason}\n${stopCondition}\n${closingMessage}`;
  if (
    hasPromptInjection(modelAuthoredText) ||
    hasUnsafeRecommendation(modelAuthoredText)
  ) {
    return {
      ok: false,
      code: "STREAM_UNSAFE_RECOMMENDATION",
      reason: "no-send decision failed hard safety rules",
    };
  }
  const payload: StreamNoSendRecommendationForCharge = {
    decisionKind: kind,
    selectedStyle: null,
    action,
    reason,
    stopCondition,
    ...(closingMessage ? { closingMessage } : {}),
    raw: event,
    analysisDecisionV2: {},
  };
  payload.analysisDecisionV2 = noSendDecisionV2Snapshot(payload);
  return { ok: true, payload };
}

/// The typed decision the client and Phase 0 telemetry read. Only vetted
/// fields leave the server; the raw model event stays in recommendation_json.
export function noSendDecisionV2Snapshot(
  payload: StreamNoSendRecommendationForCharge,
): Record<string, unknown> {
  return {
    schemaVersion: 2,
    messageDecision: payload.decisionKind,
    replyMode: replyModeForDecision(payload.decisionKind),
    action: payload.action,
    reason: payload.reason,
    stopCondition: payload.stopCondition,
    ...(payload.closingMessage
      ? { closingMessage: payload.closingMessage }
      : {}),
  };
}

/// The wire event forwarded to the client for a no-send decision (fresh or
/// resumed). Never the raw model event.
export function noSendDecisionEvent(
  payload: StreamNoSendRecommendationForCharge,
): Record<string, unknown> & { type: "analysis.decision" } {
  return { type: "analysis.decision", ...noSendDecisionV2Snapshot(payload) };
}

/// Resume: rebuild the charge payload from recommendation_json written by
/// serializeRecommendation. Returns null for anything that is not a no-send
/// anchor so the v1 send path stays in charge of its own shape.
export function noSendChargePayloadFromStored(
  stored: Record<string, unknown>,
): StreamNoSendRecommendationForCharge | null {
  if (!isNoSendDecisionKind(stored.decisionKind)) return null;
  const action = textField(stored.action);
  const reason = textField(stored.reason);
  const stopCondition = textField(stored.stopCondition);
  const closingMessage = textField(stored.closingMessage);
  if (!action || !reason || !stopCondition) return null;
  if (stored.decisionKind === "acknowledge_and_stop" && !closingMessage) {
    return null;
  }
  const raw = typeof stored.raw === "object" && stored.raw !== null &&
      !Array.isArray(stored.raw)
    ? stored.raw as Record<string, unknown>
    : stored;
  const payload: StreamNoSendRecommendationForCharge = {
    decisionKind: stored.decisionKind,
    selectedStyle: null,
    action,
    reason,
    stopCondition,
    ...(closingMessage ? { closingMessage } : {}),
    raw,
    analysisDecisionV2: {},
  };
  payload.analysisDecisionV2 = noSendDecisionV2Snapshot(payload);
  return payload;
}

/// recommendation_json shape for a charged no-send run; the DB RPC checks the
/// same four fields before charging.
export function serializeNoSendRecommendation(
  payload: StreamNoSendRecommendationForCharge,
): Record<string, unknown> {
  return {
    decisionKind: payload.decisionKind,
    action: payload.action,
    reason: payload.reason,
    stopCondition: payload.stopCondition,
    ...(payload.closingMessage
      ? { closingMessage: payload.closingMessage }
      : {}),
    raw: payload.raw,
    analysisDecisionV2: payload.analysisDecisionV2,
    ...(payload.analysisInventory
      ? { analysisInventory: payload.analysisInventory }
      : {}),
    ...(payload.analysisEvidenceLinkage
      ? { analysisEvidenceLinkage: payload.analysisEvidenceLinkage }
      : {}),
  };
}

/// Reads the persisted/merged final result. Used by post-processing to skip
/// canned-reply backfill: a no-send result legitimately has zero reply cards.
export function noSendDecisionFromResult(
  result: Record<string, unknown> | null | undefined,
): NoSendDecisionKind | null {
  const decision = result?.analysisDecisionV2;
  if (typeof decision !== "object" || decision === null) return null;
  const kind = (decision as { messageDecision?: unknown }).messageDecision;
  return isNoSendDecisionKind(kind) ? kind : null;
}
