export type BenchmarkRun = {
  caseId: string;
  runId: string;
  durationMs: number;
  status: string;
  automatedIssues: string[];
  quotedPreviewLeaks: number;
  quotedPreviewInstances: number;
};

export type ReadyValidationOptions = {
  forbiddenSubstrings?: string[];
};

const ALLOWED_STRATEGIES = new Set([
  "keep_pace",
  "build_connection",
  "move_forward",
  "clarify",
  "deescalate",
]);
const ALLOWED_SCOPES = new Set([
  "screenshot_only",
  "screenshot_plus_global_voice",
]);
const ALLOWED_CONFIDENCE = new Set(["high", "medium", "low"]);
const ALLOWED_TURN_STATES = new Set(["reply_due", "optional_follow_up"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function unicodeLength(value: string): number {
  return [...value].length;
}

function normalizedDistinctValue(value: string): string {
  return value.normalize("NFKC").trim().toLocaleLowerCase();
}

function hasExactKeys(
  value: Record<string, unknown>,
  expected: string[],
): boolean {
  const actual = Object.keys(value).toSorted();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected.toSorted()[index]);
}

function hasMarkdown(value: string): boolean {
  return /```|`[^`]+`|\*\*|__|(?:^|\n)\s{0,3}#{1,6}\s|(?:^|\n)\s*[-*+]\s/.test(
    value,
  );
}

function hasRawJson(value: string): boolean {
  const trimmed = value.trim();
  if (
    !(
      (trimmed.startsWith("{") && trimmed.endsWith("}")) ||
      (trimmed.startsWith("[") && trimmed.endsWith("]"))
    )
  ) {
    return false;
  }
  try {
    JSON.parse(trimmed);
    return true;
  } catch {
    return false;
  }
}

function validateBoundedText(
  value: unknown,
  maximum: number,
  issues: Set<string>,
  fieldIssue: string,
): value is string {
  if (
    typeof value !== "string" || unicodeLength(value.trim()) === 0 ||
    unicodeLength(value) > maximum
  ) {
    issues.add(fieldIssue);
    return false;
  }
  if (hasMarkdown(value)) issues.add("markdown_not_allowed");
  if (hasRawJson(value)) issues.add("raw_json_not_allowed");
  return true;
}

export function latencyPercentile(
  samples: number[],
  percentile: number,
): number | null {
  if (samples.length === 0) return null;
  if (!Number.isFinite(percentile) || percentile <= 0 || percentile > 1) {
    throw new RangeError("percentile must be in (0, 1]");
  }
  const sorted = samples
    .filter((sample) => Number.isFinite(sample) && sample >= 0)
    .toSorted((left, right) => left - right);
  if (sorted.length === 0) return null;
  const rank = Math.max(1, Math.ceil(percentile * sorted.length));
  return sorted[rank - 1];
}

/**
 * One-sided Wilson upper confidence bound with z=1.64485 (95%).
 * This keeps a zero-observed leak result from being misreported as proof that
 * the real-world leak rate is exactly zero.
 */
export function quoteLeakUpperBound95(
  observedLeaks: number,
  instances: number,
): number | null {
  if (instances <= 0) return null;
  if (
    !Number.isInteger(observedLeaks) || !Number.isInteger(instances) ||
    observedLeaks < 0 || observedLeaks > instances
  ) {
    throw new RangeError("leak counts must satisfy 0 <= leaks <= instances");
  }

  const z = 1.6448536269514722;
  const zSquared = z * z;
  const proportion = observedLeaks / instances;
  const denominator = 1 + zSquared / instances;
  const centre = proportion + zSquared / (2 * instances);
  const spread = z * Math.sqrt(
    proportion * (1 - proportion) / instances +
      zSquared / (4 * instances * instances),
  );
  return Math.min(1, (centre + spread) / denominator);
}

export function validateReadyResult(
  value: unknown,
  options: ReadyValidationOptions = {},
): string[] {
  const issues = new Set<string>();
  if (!isRecord(value)) return ["invalid_result"];
  if (
    !hasExactKeys(value, [
      "contractVersion",
      "requestId",
      "status",
      "source",
      "turnState",
      "cue",
      "uncertainty",
      "options",
    ])
  ) {
    issues.add("invalid_ready_shape");
  }

  if (value.contractVersion !== "keyboard-assist-v1") {
    issues.add("invalid_contract_version");
  }
  if (typeof value.requestId !== "string" || value.requestId.trim() === "") {
    issues.add("invalid_request_id");
  }
  if (value.status !== "ready") issues.add("status_not_ready");
  if (!ALLOWED_TURN_STATES.has(String(value.turnState))) {
    issues.add("invalid_turn_state");
  }
  validateBoundedText(value.cue, 120, issues, "invalid_cue");
  if (value.uncertainty !== null && typeof value.uncertainty !== "string") {
    issues.add("invalid_uncertainty");
  }

  if (!isRecord(value.source)) {
    issues.add("invalid_source");
  } else {
    if (
      !hasExactKeys(value.source, [
        "scope",
        "messageCount",
        "confidence",
        "sideConfidence",
      ])
    ) {
      issues.add("invalid_source_shape");
    }
    if (!ALLOWED_SCOPES.has(String(value.source.scope))) {
      issues.add("invalid_source_scope");
    }
    if (
      !Number.isInteger(value.source.messageCount) ||
      Number(value.source.messageCount) < 1
    ) {
      issues.add("invalid_message_count");
    }
    if (!ALLOWED_CONFIDENCE.has(String(value.source.confidence))) {
      issues.add("invalid_confidence");
    }
    if (!ALLOWED_CONFIDENCE.has(String(value.source.sideConfidence))) {
      issues.add("invalid_side_confidence");
    }
  }

  if (!Array.isArray(value.options) || value.options.length !== 3) {
    issues.add("options_must_have_three");
  } else {
    const strategies: string[] = [];
    const texts: string[] = [];
    for (const option of value.options) {
      if (!isRecord(option)) {
        issues.add("invalid_option");
        continue;
      }
      if (
        !hasExactKeys(option, ["strategy", "text", "why", "effect"])
      ) {
        issues.add("invalid_option_shape");
      }
      const strategy = String(option.strategy);
      if (!ALLOWED_STRATEGIES.has(strategy)) {
        issues.add("invalid_strategy");
      }
      strategies.push(strategy);

      if (validateBoundedText(option.text, 100, issues, "invalid_text")) {
        texts.push(normalizedDistinctValue(option.text));
      }
      validateBoundedText(option.why, 80, issues, "invalid_why");
      validateBoundedText(option.effect, 60, issues, "invalid_effect");
    }
    if (new Set(strategies).size !== strategies.length) {
      issues.add("strategy_not_distinct");
    }
    if (new Set(texts).size !== texts.length) {
      issues.add("text_not_distinct");
    }
  }

  const forbidden = (options.forbiddenSubstrings ?? [])
    .map((item) => item.normalize("NFKC").trim())
    .filter((item) => item.length > 0);
  if (forbidden.length > 0) {
    const visible = [
      value.cue,
      ...(Array.isArray(value.options)
        ? value.options.flatMap((option) =>
          isRecord(option) ? [option.text, option.why, option.effect] : []
        )
        : []),
    ]
      .filter((item): item is string => typeof item === "string")
      .join("\n")
      .normalize("NFKC");
    if (forbidden.some((item) => visible.includes(item))) {
      issues.add("unsupported_fact");
    }
  }

  return [...issues].toSorted();
}

export function validateAssistResult(value: unknown): string[] {
  if (!isRecord(value)) return ["invalid_result"];
  if (value.status === "ready") return validateReadyResult(value);
  if (value.status !== "needs_speaker_confirmation") {
    return ["unsupported_status"];
  }

  const issues = new Set<string>();
  if (
    !hasExactKeys(value, [
      "contractVersion",
      "requestId",
      "status",
      "suggestedMySide",
      "sideConfidence",
    ])
  ) {
    issues.add("invalid_speaker_confirmation_shape");
  }
  if (value.contractVersion !== "keyboard-assist-v1") {
    issues.add("invalid_contract_version");
  }
  if (typeof value.requestId !== "string" || value.requestId.trim() === "") {
    issues.add("invalid_request_id");
  }
  if (
    value.suggestedMySide !== "left" &&
    value.suggestedMySide !== "right"
  ) {
    issues.add("invalid_suggested_side");
  }
  if (value.sideConfidence !== "low") {
    issues.add("invalid_side_confidence");
  }
  return [...issues].toSorted();
}

export function aggregateBenchmark(runs: BenchmarkRun[]) {
  const readyRuns = runs.filter((run) => run.status === "ready").length;
  const quotedPreviewInstances = runs.reduce(
    (sum, run) => sum + Math.max(0, run.quotedPreviewInstances),
    0,
  );
  const observedLeaks = runs.reduce(
    (sum, run) => sum + Math.max(0, run.quotedPreviewLeaks),
    0,
  );

  return {
    totalRuns: runs.length,
    readyRuns,
    readyRate: runs.length === 0 ? null : readyRuns / runs.length,
    freshLatencyMs: {
      p50: latencyPercentile(runs.map((run) => run.durationMs), 0.5),
      p95: latencyPercentile(runs.map((run) => run.durationMs), 0.95),
    },
    automatedViolationRuns:
      runs.filter((run) => run.automatedIssues.length > 0).length,
    quotedPreview: {
      instances: quotedPreviewInstances,
      observedLeaks,
      upperBound95: quoteLeakUpperBound95(
        observedLeaks,
        quotedPreviewInstances,
      ),
    },
  };
}
