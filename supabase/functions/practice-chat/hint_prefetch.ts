// Hint prefetch state decisions. Pure helpers only: no transcript, provider
// output logging, database calls, or environment reads in this module.

export type HintRequestState = "generating" | "prefetched" | "settled";

export const HINT_QUALITY_SCHEMA_VERSION = "semantic-quality-v2";

export interface HintRequestLedgerRow {
  state: HintRequestState;
  charged: boolean;
  result: unknown;
  /** Settled rows keep their prefetch provenance after formal consumption. */
  isPrefetch?: boolean;
  /** Unsafe legacy settled rows reserve their already-counted replacement. */
  legacyReplacementPending?: boolean;
}

export type HintPrefetchReplayDecision =
  | { kind: "miss" }
  | { kind: "invalid" }
  | { kind: "continueToClaim" }
  | { kind: "legacyReplacementClaim" }
  | { kind: "legacyPrefetchDiscard" }
  | { kind: "opaqueAck" }
  | { kind: "settledReplay"; result: Record<string, unknown> }
  | { kind: "prefetchedConsume"; result: Record<string, unknown> };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Only replay snapshots that are known to contain provider output.
 *
 * New snapshots carry an explicit generated-only marker. Unmarked legacy
 * payloads are never replay-certified: quota provenance can prevent a second
 * charge, but it cannot prove that visible text came from a provider.
 */
export function isExplicitModelHintResult(
  value: unknown,
): boolean {
  if (!isRecord(value)) return false;
  return value.generationSource === "model" && value.fallbackUsed === false &&
    value.qualitySchemaVersion === HINT_QUALITY_SCHEMA_VERSION;
}

export function isReplayableModelHintResult(
  value: unknown,
): value is Record<string, unknown> {
  return isRecord(value) && isExplicitModelHintResult(value);
}

export function decideHintPrefetchReplay(opts: {
  requestPrefetch: boolean;
  row: HintRequestLedgerRow | null;
}): HintPrefetchReplayDecision {
  const row = opts.row;
  if (row === null) return { kind: "miss" };

  // A generating row owns the provider latch, not a replayable snapshot.
  if (row.state === "generating") {
    if (row.legacyReplacementPending === true) {
      return { kind: "legacyReplacementClaim" };
    }
    return row.charged === false && row.result === null
      ? { kind: "continueToClaim" }
      : { kind: "invalid" };
  }

  if (row.state === "settled") {
    if (!row.charged || !isRecord(row.result)) return { kind: "invalid" };
    if (opts.requestPrefetch) return { kind: "opaqueAck" };
    return isReplayableModelHintResult(row.result) &&
        row.legacyReplacementPending !== true
      ? { kind: "settledReplay", result: row.result }
      : { kind: "legacyReplacementClaim" };
  }

  if (row.charged || !isRecord(row.result)) return { kind: "invalid" };
  if (!opts.requestPrefetch && !isExplicitModelHintResult(row.result)) {
    return { kind: "legacyPrefetchDiscard" };
  }
  return opts.requestPrefetch
    ? { kind: "opaqueAck" }
    : { kind: "prefetchedConsume", result: row.result };
}

export function isHintPrefetchEnabled(value: string | undefined): boolean {
  return value === "true";
}

export function hintRecordPolicy(opts: {
  isPrefetch: boolean;
  isTestAccount: boolean;
  quotaAlreadyPaid?: boolean;
}): { chargeQuota: boolean; charged: boolean } {
  if (opts.isPrefetch) {
    return { chargeQuota: false, charged: false };
  }
  return {
    chargeQuota: !opts.isTestAccount && opts.quotaAlreadyPaid !== true,
    charged: true,
  };
}

export type HintPrefetchTelemetryOutcome =
  | "fired"
  | "hit"
  | "miss"
  | "failed";

export type HintPrefetchTelemetryReason =
  | "disabled"
  | "gate"
  | "quota"
  | "rate_limit"
  | "timeout"
  | "visible_text_guard"
  | "invalid_json"
  | "schema_invalid"
  | "semantic_rejected"
  | "provider_error"
  | "pending"
  | "unknown";

const OUTCOMES = new Set<HintPrefetchTelemetryOutcome>([
  "fired",
  "hit",
  "miss",
  "failed",
]);
const REASONS = new Set<HintPrefetchTelemetryReason>([
  "disabled",
  "gate",
  "quota",
  "rate_limit",
  "timeout",
  "visible_text_guard",
  "invalid_json",
  "schema_invalid",
  "semantic_rejected",
  "provider_error",
  "pending",
  "unknown",
]);

export function buildHintPrefetchTelemetry(opts: {
  outcome: unknown;
  reason: unknown;
  practiceMode: "beginner" | "game";
}): {
  outcome: HintPrefetchTelemetryOutcome;
  reason: HintPrefetchTelemetryReason;
  practiceMode: "beginner" | "game";
} {
  const outcome = typeof opts.outcome === "string" &&
      OUTCOMES.has(opts.outcome as HintPrefetchTelemetryOutcome)
    ? opts.outcome as HintPrefetchTelemetryOutcome
    : "failed";
  const reason = typeof opts.reason === "string" &&
      REASONS.has(opts.reason as HintPrefetchTelemetryReason)
    ? opts.reason as HintPrefetchTelemetryReason
    : "unknown";
  return { outcome, reason, practiceMode: opts.practiceMode };
}

export function hintPrefetchAck(): { readonly prefetched: true } {
  return { prefetched: true } as const;
}
