// Hint prefetch state decisions. Pure helpers only: no transcript, provider
// output logging, database calls, or environment reads in this module.

export type HintRequestState = "generating" | "prefetched" | "settled";

export interface HintRequestLedgerRow {
  state: HintRequestState;
  charged: boolean;
  result: unknown;
}

export type HintPrefetchReplayDecision =
  | { kind: "miss" }
  | { kind: "invalid" }
  | { kind: "continueToClaim" }
  | { kind: "opaqueAck" }
  | { kind: "settledReplay"; result: Record<string, unknown> }
  | { kind: "prefetchedConsume"; result: Record<string, unknown> };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function decideHintPrefetchReplay(opts: {
  requestPrefetch: boolean;
  row: HintRequestLedgerRow | null;
}): HintPrefetchReplayDecision {
  const row = opts.row;
  if (row === null) return { kind: "miss" };

  // A generating row owns the provider latch, not a replayable snapshot.
  if (row.state === "generating") {
    return row.charged === false && row.result === null
      ? { kind: "continueToClaim" }
      : { kind: "invalid" };
  }

  if (row.state === "settled") {
    if (!row.charged || !isRecord(row.result)) return { kind: "invalid" };
    return opts.requestPrefetch
      ? { kind: "opaqueAck" }
      : { kind: "settledReplay", result: row.result };
  }

  if (row.charged || !isRecord(row.result)) return { kind: "invalid" };
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
  isFallback: boolean;
}): { chargeQuota: boolean; charged: boolean } {
  if (opts.isPrefetch) {
    return { chargeQuota: false, charged: false };
  }
  return {
    chargeQuota: !opts.isTestAccount && !opts.isFallback,
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
