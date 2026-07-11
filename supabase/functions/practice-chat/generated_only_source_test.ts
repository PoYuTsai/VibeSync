import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const handler = await Deno.readTextFile(
  new URL("./handler.ts", import.meta.url),
);

Deno.test("runtime Hint and Debrief never construct canned fallback success", () => {
  assertEquals(handler.includes("buildFallbackHintResult"), false);
  assertEquals(handler.includes("buildFallbackDebriefCard"), false);
  assertEquals(handler.includes("practice_chat_debrief_fallback_used"), false);
  assertEquals(
    handler.includes("practice_chat_game_hint_fallback_used"),
    false,
  );
  assertEquals(
    handler.includes("practice_chat_beginner_hint_fallback_used"),
    false,
  );
});

Deno.test("generated-only success and retry contracts stay explicit", () => {
  for (
    const expected of [
      'generationSource: "model"',
      "fallbackUsed: false",
      'error: "practice_hint_generation_retryable"',
      'error: "practice_debrief_generation_retryable"',
      '"release_practice_hint_generation"',
      '"release_practice_debrief_generation"',
      '"resolve_practice_hint_decision"',
    ]
  ) {
    assert(handler.includes(expected), expected);
  }
});

Deno.test("Hint terminal failure logs only a stable class, never provider text", () => {
  const start = handler.indexOf(
    "const failureClass = hintLastFailureClass ??",
  );
  const end = handler.indexOf("if (requestIsPrefetch)", start);
  assert(start >= 0 && end > start);
  const terminalCatch = handler.slice(start, end);
  assert(terminalCatch.includes("failureClass"));
  assertEquals(terminalCatch.includes("getErrorMessage"), false);
  assertEquals(terminalCatch.includes("error:"), false);
});
