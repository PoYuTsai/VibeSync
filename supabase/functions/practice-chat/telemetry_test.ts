import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildPracticeAiLogRow,
  buildPracticeGenerationTelemetry,
  classifyPracticeGenerationFailure,
  countPromptChars,
} from "./telemetry.ts";

Deno.test("practice generation telemetry emits the fixed queryable shape", () => {
  const telemetry = buildPracticeGenerationTelemetry({
    mode: "hint",
    practiceMode: "game",
    attempt: 2,
    attemptDurationMs: 1234.9,
    failureClass: "schema_invalid",
    fallbackUsed: true,
    totalDurationMs: 4567.8,
    promptChars: 9012.7,
  });

  assertEquals(telemetry, {
    mode: "hint",
    practiceMode: "game",
    attempt: 2,
    attemptDurationMs: 1234,
    failureClass: "schema_invalid",
    fallbackUsed: true,
    totalDurationMs: 4567,
    promptChars: 9012,
  });
});

Deno.test("practice generation telemetry keeps absent attempt metrics explicit", () => {
  assertEquals(
    buildPracticeGenerationTelemetry({
      mode: "debrief",
      practiceMode: "beginner",
      promptChars: 2500,
    }),
    {
      mode: "debrief",
      practiceMode: "beginner",
      attempt: null,
      attemptDurationMs: null,
      failureClass: null,
      fallbackUsed: false,
      totalDurationMs: null,
      promptChars: 2500,
    },
  );
});

Deno.test("practice generation telemetry drops extra transcript and response fields", () => {
  const secretTranscript = "SECRET_TRANSCRIPT_不要寫進log";
  const secretResponse = "SECRET_MODEL_REPLY_不要寫進log";
  const unsafeInput = {
    mode: "hint",
    practiceMode: "beginner",
    attempt: 1,
    attemptDurationMs: 9000,
    failureClass: "timeout",
    fallbackUsed: true,
    totalDurationMs: 9001,
    promptChars: 3000,
    transcript: secretTranscript,
    response: secretResponse,
  } as const;

  const telemetry = buildPracticeGenerationTelemetry(unsafeInput);
  const serialized = JSON.stringify(telemetry);

  assertEquals(Object.keys(telemetry).sort(), [
    "attempt",
    "attemptDurationMs",
    "failureClass",
    "fallbackUsed",
    "mode",
    "practiceMode",
    "promptChars",
    "totalDurationMs",
  ]);
  assertFalse(serialized.includes(secretTranscript));
  assertFalse(serialized.includes(secretResponse));
});

Deno.test("practice generation telemetry normalizes invalid values without echoing them", () => {
  const secret = "SECRET_UNTRUSTED_VALUE";
  const telemetry = buildPracticeGenerationTelemetry({
    mode: secret,
    practiceMode: secret,
    attempt: -1,
    attemptDurationMs: Number.NaN,
    failureClass: secret,
    fallbackUsed: "yes",
    totalDurationMs: Number.POSITIVE_INFINITY,
    promptChars: -5,
  } as never);

  assertEquals(telemetry, {
    mode: "unknown",
    practiceMode: "unknown",
    attempt: null,
    attemptDurationMs: null,
    failureClass: "unknown",
    fallbackUsed: false,
    totalDurationMs: null,
    promptChars: 0,
  });
  assertFalse(JSON.stringify(telemetry).includes(secret));
});

Deno.test("countPromptChars returns only the aggregate character count", () => {
  const messages = [
    { role: "system", content: "規則ABC" },
    { role: "user", content: "她說嗨" },
  ];

  assertEquals(countPromptChars(messages), 8);
});

Deno.test("classifyPracticeGenerationFailure maps errors to stable buckets", () => {
  const cases: Array<[unknown, string]> = [
    [new Error("deepseek_timeout"), "timeout"],
    [new Error("hint_l4_unsafe"), "visible_text_guard"],
    [new Error("debrief_internal_label_leak"), "visible_text_guard"],
    [new SyntaxError("Unexpected token '<'"), "invalid_json"],
    [new Error("hint_missing_warmUp"), "schema_invalid"],
    [new Error("debrief_not_object"), "schema_invalid"],
    [new Error("debrief_game_breakdown_missing_fields"), "schema_invalid"],
    [new Error("deepseek_http_503"), "provider_error"],
    [new Error("network connection reset"), "provider_error"],
    [new Error("unclassified SECRET_UPSTREAM_DETAIL"), "unknown"],
  ];

  for (const [error, expected] of cases) {
    const failureClass = classifyPracticeGenerationFailure(error);
    assertEquals(failureClass, expected);
    assertFalse(failureClass.includes("SECRET_UPSTREAM_DETAIL"));
  }
});

Deno.test("durable ai_logs row keeps only aggregate generation metrics", () => {
  const row = buildPracticeAiLogRow({
    userId: "11111111-2222-3333-4444-555555555555",
    model: "deepseek-v4-flash",
    telemetry: {
      mode: "hint",
      practiceMode: "game",
      attempt: 2,
      attemptDurationMs: null,
      failureClass: "timeout",
      fallbackUsed: true,
      totalDurationMs: 9012,
      promptChars: 4300,
      transcript: "SECRET_TRANSCRIPT",
    } as never,
    attemptDurationsMs: [9001, Number.NaN],
    failureClasses: ["timeout", "SECRET_ERROR"],
  });

  assertEquals(row.request_type, "practice_hint_game");
  assertEquals(row.status, "failed");
  assertEquals(row.error_code, "timeout");
  assertEquals(row.retry_count, 1);
  assertEquals(row.input_tokens, 0);
  assertEquals(row.output_tokens, 0);
  assertEquals(row.request_body.attemptDurationsMs, [9001]);
  assertEquals(row.request_body.failureClasses, ["timeout", "unknown"]);
  assertEquals(row.response_body, null);
  assertEquals(row.error_message, null);
  assertFalse(JSON.stringify(row).includes("SECRET_TRANSCRIPT"));
  assertFalse(JSON.stringify(row).includes("SECRET_ERROR"));
});
