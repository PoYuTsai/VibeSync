import { buildServerGuardrails } from "./server_guardrails.ts";

Deno.test("buildServerGuardrails flags high-risk OCR runs", () => {
  const result = buildServerGuardrails({
    requestType: "recognize_only",
    imageCount: 2,
    latencyMs: 16000,
    timeoutMs: 15000,
    retryCount: 1,
    fallbackUsed: false,
    totalImageBytes: 900 * 1024,
    recognizedClassification: "low_confidence",
    recognizedSideConfidence: "low",
    uncertainSideCount: 2,
    groupedAdjustedCount: 1,
    inputTokens: 5200,
    outputTokens: 1100,
  });

  if (result.guardrailSeverity !== "critical") {
    throw new Error(
      `expected critical severity, got ${result.guardrailSeverity}`,
    );
  }

  for (
    const flag of [
      "slow_request",
      "near_timeout",
      "unstable_upstream",
      "heavy_image_payload",
      "nonstandard_screenshot",
      "uncertain_speaker_side",
      "structure_repaired",
      "high_token_usage",
    ]
  ) {
    if (!result.guardrailFlags.includes(flag)) {
      throw new Error(`expected guardrail flag ${flag}`);
    }
  }
});

Deno.test("buildServerGuardrails flags compressed analysis context", () => {
  const result = buildServerGuardrails({
    requestType: "analyze",
    latencyMs: 9000,
    timeoutMs: 30000,
    retryCount: 0,
    fallbackUsed: false,
    truncatedMessageCount: 20,
    conversationSummaryUsed: true,
    contextMode: "opening_plus_recent",
    inputTokens: 1800,
    outputTokens: 900,
  });

  if (result.guardrailSeverity !== "info") {
    throw new Error(`expected info severity, got ${result.guardrailSeverity}`);
  }

  if (!result.guardrailFlags.includes("compressed_context")) {
    throw new Error("expected compressed_context guardrail flag");
  }
});

Deno.test("buildServerGuardrails surfaces stripped system rows as warning", () => {
  const result = buildServerGuardrails({
    requestType: "recognize_only",
    imageCount: 1,
    latencyMs: 4200,
    timeoutMs: 15000,
    systemRowsRemovedCount: 2,
    inputTokens: 1200,
    outputTokens: 600,
  });

  if (result.guardrailSeverity !== "warning") {
    throw new Error(
      `expected warning severity, got ${result.guardrailSeverity}`,
    );
  }

  if (!result.guardrailFlags.includes("system_rows_removed")) {
    throw new Error("expected system_rows_removed guardrail flag");
  }
});
