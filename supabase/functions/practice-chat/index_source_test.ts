import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

function indexOfRequired(snippet: string): number {
  const index = source.indexOf(snippet);
  assert(index >= 0, `Expected index.ts to contain: ${snippet}`);
  return index;
}

Deno.test("hint mode is temporarily rejected before chat/debrief side effects", () => {
  const validateIndex = indexOfRequired("request = validateRequest(rawBody)");
  const hintGuardIndex = indexOfRequired('request.mode === "hint"');
  const hintErrorIndex = indexOfRequired('"practice_hint_not_available"');
  const apiKeyIndex = indexOfRequired('Deno.env.get("DEEPSEEK_API_KEY")');
  const subscriptionIndex = indexOfRequired('.from("subscriptions")');
  const ledgerIndex = indexOfRequired('.from("practice_chat_sessions")');
  const debriefIndex = indexOfRequired('request.mode === "debrief"');
  const chatGenerationIndex = indexOfRequired("buildChatMessages(");

  assert(
    validateIndex < hintGuardIndex,
    "hint guard must run after validateRequest accepts the request",
  );
  assertEquals(
    source.slice(hintGuardIndex, apiKeyIndex).includes(
      'jsonResponse({ error: "practice_hint_not_available" }, 403)',
    ),
    true,
  );
  assert(
    hintErrorIndex < apiKeyIndex,
    "hint rejection must not require DEEPSEEK_API_KEY",
  );
  for (
    const [label, index] of [
      ["subscription lookup", subscriptionIndex],
      ["ledger lookup", ledgerIndex],
      ["debrief branch", debriefIndex],
      ["chat generation", chatGenerationIndex],
    ] as const
  ) {
    assert(
      hintGuardIndex < index,
      `hint guard must happen before ${label}`,
    );
  }
});
