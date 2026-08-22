import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  resolveRequestMode,
  shouldIncludeLegacyDraftPrompt,
} from "./request_mode.ts";

Deno.test("plain AnalyzeChat accepts stream and trims its run id", () => {
  const result = resolveRequestMode({
    responseMode: "stream",
    analysisRunId: "  run-stream  ",
    plainAnalyzeRequest: true,
  });

  assertEquals(result, {
    ok: true,
    responseMode: "stream",
    analysisRunId: "run-stream",
  });
});

Deno.test("plain AnalyzeChat rejects missing or legacy response mode", () => {
  for (const responseMode of [undefined, "legacy"] as const) {
    assertEquals(
      resolveRequestMode({ responseMode, plainAnalyzeRequest: true }),
      {
        ok: false,
        status: 410,
        code: "ANALYZE_STREAMING_REQUIRED",
      },
    );
  }
});

Deno.test("quick and full are retired for every request shape", () => {
  for (const responseMode of ["quick", "full"] as const) {
    for (const plainAnalyzeRequest of [true, false]) {
      assertEquals(
        resolveRequestMode({ responseMode, plainAnalyzeRequest }),
        {
          ok: false,
          status: 410,
          code: "ANALYZE_RESPONSE_MODE_RETIRED",
        },
      );
    }
  }
});

Deno.test("unknown explicit response mode fails closed", () => {
  for (const responseMode of ["fast", "Quick", null, 1, {}]) {
    assertEquals(
      resolveRequestMode({ responseMode, plainAnalyzeRequest: false }),
      {
        ok: false,
        status: 400,
        code: "INVALID_RESPONSE_MODE",
      },
    );
  }
});

Deno.test("shared non-Analyze modes retain legacy response contract", () => {
  for (const responseMode of [undefined, "legacy"] as const) {
    const result = resolveRequestMode({
      responseMode,
      analysisRunId: "must-not-leak",
      plainAnalyzeRequest: false,
    });
    assertFalse(!result.ok);
    if (result.ok) {
      assertEquals(result.responseMode, "legacy");
      assertEquals(result.analysisRunId, null);
    }
  }
});

Deno.test("non-string or blank stream run id becomes null", () => {
  for (const analysisRunId of ["   ", 123, null, { id: "x" }]) {
    assertEquals(
      resolveRequestMode({
        responseMode: "stream",
        analysisRunId,
        plainAnalyzeRequest: true,
      }),
      {
        ok: true,
        responseMode: "stream",
        analysisRunId: null,
      },
    );
  }
});

Deno.test("draft optimization prompt is legacy-only", () => {
  assertEquals(
    shouldIncludeLegacyDraftPrompt({
      responseMode: "legacy",
      isMyMessageMode: false,
      userDraft: "想約妳喝咖啡",
    }),
    true,
  );
  assertEquals(
    shouldIncludeLegacyDraftPrompt({
      responseMode: "stream",
      isMyMessageMode: false,
      userDraft: "想約妳喝咖啡",
    }),
    false,
  );
  assertEquals(
    shouldIncludeLegacyDraftPrompt({
      responseMode: "legacy",
      isMyMessageMode: true,
      userDraft: "想約妳喝咖啡",
    }),
    false,
  );
  assertEquals(
    shouldIncludeLegacyDraftPrompt({
      responseMode: "legacy",
      isMyMessageMode: false,
      userDraft: "   ",
    }),
    false,
  );
});
