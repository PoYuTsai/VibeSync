import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildPracticeAiLogRow,
  buildPracticeGenerationTelemetry,
  classifyPracticeGenerationFailure,
  countPromptChars,
  sanitizePracticeFailureCode,
} from "./telemetry.ts";

Deno.test("practice generation telemetry emits the fixed queryable shape", () => {
  const telemetry = buildPracticeGenerationTelemetry({
    mode: "hint",
    practiceMode: "game",
    attempt: 2,
    attemptDurationMs: 1234.9,
    failureClass: "schema_invalid",
    fallbackUsed: true,
    failoverUsed: true,
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
    failoverUsed: true,
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
      failoverUsed: false,
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
    failoverUsed: true,
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
    "failoverUsed",
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
    failoverUsed: "yes",
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
    failoverUsed: false,
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
    [
      new Error(
        "semantic_adjudication_failed:semantic_adjudication_repair_unverified:semantic_adjudication_deadline_exceeded",
      ),
      "timeout",
    ],
    [new Error("practice_debrief_deadline_exceeded"), "timeout"],
    [new Error("hint_l4_unsafe"), "visible_text_guard"],
    [new Error("debrief_internal_label_leak"), "visible_text_guard"],
    [new Error("hint_canned_visible_text"), "visible_text_guard"],
    [new SyntaxError("Unexpected token '<'"), "invalid_json"],
    [
      new Error(
        "semantic_adjudication_failed:semantic_adjudication_invalid_json",
      ),
      "invalid_json",
    ],
    [new Error("hint_missing_warmUp"), "schema_invalid"],
    [new Error("debrief_not_object"), "schema_invalid"],
    [new Error("debrief_game_breakdown_missing_fields"), "schema_invalid"],
    [new Error("debrief_quality_invalid_not_grounded"), "schema_invalid"],
    [new Error("debrief_hint_assessment_evidence_invalid"), "schema_invalid"],
    [
      new Error(
        "semantic_adjudication_failed:semantic_adjudication_candidate_unverified:semantic_fact_verification_rejected:suggestedline:user_fact_unsupported",
      ),
      "semantic_rejected",
    ],
    [
      new Error("semantic_adjudication_failed:semantic_adjudication_rejected"),
      "semantic_rejected",
    ],
    [
      new Error(
        "semantic_adjudication_failed:semantic_adjudication_fact_rejection_field_unchanged",
      ),
      "semantic_rejected",
    ],
    [
      new Error(
        "semantic_adjudication_failed:semantic_adjudication_invalid_schema",
      ),
      "schema_invalid",
    ],
    [new Error("deepseek_http_503"), "provider_error"],
    [new Error("claude_http_529"), "provider_error"],
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
      failoverUsed: true,
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

Deno.test("practice failure codes keep machine codes and reject free text", () => {
  assertEquals(
    sanitizePracticeFailureCode(
      new Error(
        "hint_quality_invalid_unsupported_detail:world:venue:located_at",
      ),
    ),
    "hint_quality_invalid_unsupported_detail:world:venue:located_at",
  );
  assertEquals(
    sanitizePracticeFailureCode(new Error("deepseek_max_tokens")),
    "deepseek_max_tokens",
  );
  assertEquals(
    sanitizePracticeFailureCode(
      new Error(
        "semantic_adjudication_failed:semantic_adjudication_invalid_schema",
      ),
    ),
    "semantic_adjudication_failed:semantic_adjudication_invalid_schema",
  );
  // 只取第一段機器碼，後續自由文字不落盤。
  assertEquals(
    sanitizePracticeFailureCode(
      new Error("claude_http_500: Internal Server Error"),
    ),
    "claude_http_500:",
  );
  // 含中文（可能夾用戶內容）→ 整筆拒收。
  assertEquals(sanitizePracticeFailureCode(new Error("練習室生成失敗")), null);
  assertEquals(
    sanitizePracticeFailureCode(new Error("被拒絕 hint_quality_invalid")),
    null,
  );
  assertEquals(sanitizePracticeFailureCode(new Error("   ")), null);
  assertEquals(sanitizePracticeFailureCode(undefined), null);
  // 超長截斷，且截斷後仍須通過字元白名單與已知前綴。
  const longCode = sanitizePracticeFailureCode(
    new Error(`hint_${"x".repeat(300)}`),
  );
  assertEquals(longCode, `hint_${"x".repeat(115)}`);
});

// P2 對抗審：sanitizePracticeFailureCode 先前只過 charset，靠呼叫點恰好安全；
// 收斂成「必須以已知前綴開頭才收」，未知/自訂機器碼一律丟棄不落盤。
Deno.test("practice failure codes require a known machine-code prefix", () => {
  // 已知前綴（claude.ts / deepseek.ts / hint.ts / debrief_card.ts /
  // practice_persona.ts / validate.ts / telemetry.ts classifyPracticeGenerationFailure
  // 掃出的實際 throw 前綴）一律保留。
  for (
    const code of [
      "hint_quality_invalid_unsupported_detail:third_party:name:is_named",
      "hint_not_object",
      "hint_l4_unsafe",
      "debrief_quality_invalid_unsupported_detail",
      "debrief_l4_unsafe",
      "claude_timeout",
      "claude_http_500",
      "deepseek_max_tokens",
      "deepseek_timeout",
      "invalid_personaid",
      "practice_hint_lineage_resolution_failed",
      "schema_invalid_x",
      "timeout",
      "timeout_provider_x",
      "provider_error_x",
      "visible_text_guard_x",
      "unsupported_detail_x",
      "semantic_adjudication_failed:semantic_adjudication_invalid_schema",
    ]
  ) {
    assertEquals(sanitizePracticeFailureCode(new Error(code)), code, code);
  }

  // 未知/自訂機器碼（非已知前綴開頭）一律丟棄，即使 charset 合法。
  for (
    const code of [
      "foo_bar",
      "custom_error_code",
      "my_own_failure",
      "timeoutsecret",
      "timeout:secret",
      "x_unrecognized",
    ]
  ) {
    assertEquals(sanitizePracticeFailureCode(new Error(code)), null, code);
  }
});

Deno.test("durable ai_logs row sanitizes failure codes", () => {
  const row = buildPracticeAiLogRow({
    userId: "11111111-2222-3333-4444-555555555555",
    model: "deepseek-v4-flash",
    telemetry: {
      mode: "hint",
      practiceMode: "game",
      attempt: 2,
      attemptDurationMs: null,
      failureClass: "schema_invalid",
      fallbackUsed: false,
      failoverUsed: true,
      totalDurationMs: 9012,
      promptChars: 4300,
    },
    attemptDurationsMs: [9001],
    failureClasses: ["provider_error", "schema_invalid"],
    failureCodes: [
      "deepseek_max_tokens",
      "hint_quality_invalid_unsupported_detail:world:venue:located_at",
      "夾帶用戶內容的訊息",
    ],
  });
  assertEquals(row.request_body.failureCodes, [
    "deepseek_max_tokens",
    "hint_quality_invalid_unsupported_detail:world:venue:located_at",
  ]);
  assertFalse(JSON.stringify(row).includes("夾帶"));

  // 舊呼叫端沒帶 failureCodes 也要有穩定空陣列形狀。
  const legacyRow = buildPracticeAiLogRow({
    userId: "11111111-2222-3333-4444-555555555555",
    model: "deepseek-v4-flash",
    telemetry: {
      mode: "hint",
      practiceMode: "game",
      attempt: 1,
      attemptDurationMs: null,
      failureClass: null,
      fallbackUsed: false,
      failoverUsed: false,
      totalDurationMs: 1200,
      promptChars: 100,
    },
    attemptDurationsMs: [1200],
    failureClasses: [],
  });
  assertEquals(legacyRow.request_body.failureCodes, []);
});
