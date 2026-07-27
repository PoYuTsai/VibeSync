const STRING_ENUMS: Record<string, readonly string[]> = {
  event: [
    "keyboard_assist_succeeded",
    "keyboard_assist_failed",
    "keyboard_assist_replayed",
  ],
  contractVersion: ["keyboard-assist-v1"],
  cohort: ["internal", "dogfood", "rollout"],
  imageBytesBucket: ["<250K", "250-500K", "500-900K"],
  dimensionClass: ["small", "phone", "large"],
  status: ["ready", "needs_speaker_confirmation", "failed"],
  errorCode: [
    "invalid_request",
    "image_too_large",
    "unsupported_image",
    "unauthorized",
    "quota_exhausted",
    "model_rate_limited",
    "request_pending",
    "request_replay_mismatch",
    "request_not_found",
    "request_expired_no_charge",
    "unsupported_conversation",
    "provider_timeout",
    "provider_invalid_output",
    "settlement_uncertain",
    "service_unavailable",
  ],
};

const NUMBER_KEYS = new Set([
  "photoFetchMs",
  "preprocessMs",
  "uploadMs",
  "compilerMs",
  "judgeMs",
  "settlementMs",
  "totalMs",
  "attemptCount",
  "inputTokens",
  "outputTokens",
]);

const BOOLEAN_KEYS = new Set(["replay"]);

export function sanitizeKeyboardAssistTelemetry(
  input: Record<string, unknown>,
): Record<string, string | number | boolean> {
  const output: Record<string, string | number | boolean> = {};
  for (const [key, allowed] of Object.entries(STRING_ENUMS)) {
    const value = input[key];
    if (typeof value === "string" && allowed.includes(value)) {
      output[key] = value;
    }
  }
  const pipelineVersion = input.pipelineVersion;
  if (
    typeof pipelineVersion === "string" &&
    /^[a-z0-9][a-z0-9._-]{0,63}$/i.test(pipelineVersion)
  ) output.pipelineVersion = pipelineVersion;
  for (const key of NUMBER_KEYS) {
    const value = input[key];
    if (
      typeof value === "number" && Number.isFinite(value) && value >= 0
    ) output[key] = value;
  }
  for (const key of BOOLEAN_KEYS) {
    const value = input[key];
    if (typeof value === "boolean") output[key] = value;
  }
  return output;
}
