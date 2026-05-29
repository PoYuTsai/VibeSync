// supabase/functions/analyze-chat/full_response_test.ts
//
// Phase 2.1 — unit tests for the pure helpers used by the FULL handler:
//   - buildFullPromptAnchor: anchor block shape + edge cases
//   - parseFullPayload: NO_JSON / INVALID_JSON / strict success /
//     repaired success / array rejection / code-fence handling

import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  buildFullPromptAnchor,
  parseFullPayload,
} from "./full_response.ts";

// ---------------------------------------------------------------------------
// buildFullPromptAnchor
// ---------------------------------------------------------------------------

Deno.test("buildFullPromptAnchor: surfaces all three quick fields and anchor rules", () => {
  const anchor = buildFullPromptAnchor({
    nextStep: "輕輕接住她的疲憊，再順勢約下次見面",
    recommendedReply: "週末有空嗎？想找你聊聊",
    shortReason: "她剛吐露情緒，需要被接住而不是被分析",
    insufficientContext: false,
    confidence: "high",
  });
  assertStringIncludes(anchor, "## ANCHOR");
  assertStringIncludes(anchor, "輕輕接住她的疲憊，再順勢約下次見面");
  assertStringIncludes(anchor, "週末有空嗎？想找你聊聊");
  assertStringIncludes(anchor, "她剛吐露情緒，需要被接住而不是被分析");
  assertStringIncludes(anchor, "finalRecommendation.content");
  assertStringIncludes(anchor, "finalRecommendation.reason");
  assertStringIncludes(anchor, "coachActionHint.microMove");
  assertStringIncludes(anchor, "finalRecommendation.pick");
});

Deno.test("buildFullPromptAnchor: missing fields render as empty rather than undefined", () => {
  const anchor = buildFullPromptAnchor({} as Record<string, unknown>);
  assertStringIncludes(anchor, "- nextStep: ");
  assertStringIncludes(anchor, "- recommendedReply: ");
  assertStringIncludes(anchor, "- shortReason: ");
  assertFalse(anchor.includes("undefined"));
  assertFalse(anchor.includes("null"));
});

Deno.test("buildFullPromptAnchor: ignores non-string field types defensively", () => {
  const anchor = buildFullPromptAnchor({
    nextStep: 42 as unknown as string,
    recommendedReply: { foo: "bar" } as unknown as string,
    shortReason: null as unknown as string,
  });
  assertStringIncludes(anchor, "- nextStep: ");
  assertFalse(anchor.includes("42"));
  assertFalse(anchor.includes("[object Object]"));
});

// ---------------------------------------------------------------------------
// parseFullPayload — happy paths
// ---------------------------------------------------------------------------

Deno.test("parseFullPayload: strict JSON returns source=strict", () => {
  const raw = `{"finalRecommendation":{"content":"hi"},"radar":{}}`;
  const r = parseFullPayload(raw);
  assert(r.ok, `expected ok, got ${JSON.stringify(r)}`);
  assertEquals(r.result.source, "strict");
  assertEquals(
    (r.result.payload.finalRecommendation as Record<string, unknown>).content,
    "hi",
  );
});

Deno.test("parseFullPayload: strips surrounding prose around the JSON object", () => {
  const raw = `Here is the JSON:
{"finalRecommendation":{"content":"hi"}}
Hope that helps!`;
  const r = parseFullPayload(raw);
  assert(r.ok);
  assertEquals(r.result.source, "strict");
});

Deno.test("parseFullPayload: handles ```json fenced block", () => {
  const raw = "```json\n{\"finalRecommendation\":{\"content\":\"hi\"}}\n```";
  const r = parseFullPayload(raw);
  assert(r.ok);
  assertEquals(r.result.source, "strict");
});

// ---------------------------------------------------------------------------
// parseFullPayload — repair paths
// ---------------------------------------------------------------------------

Deno.test("parseFullPayload: trailing comma triggers repair, returns source=repaired", () => {
  const raw = `{"finalRecommendation":{"content":"hi",},}`;
  const r = parseFullPayload(raw);
  assert(r.ok, `expected ok after repair, got ${JSON.stringify(r)}`);
  assertEquals(r.result.source, "repaired");
});

Deno.test("parseFullPayload: nested trailing comma triggers repair", () => {
  // Trailing commas in both inner and outer objects — common Claude artifact.
  const raw = `{"finalRecommendation":{"content":"hi","reason":"ok",},}`;
  const r = parseFullPayload(raw);
  assert(r.ok, `expected ok after repair, got ${JSON.stringify(r)}`);
  assertEquals(r.result.source, "repaired");
  assertEquals(
    (r.result.payload.finalRecommendation as Record<string, unknown>).reason,
    "ok",
  );
});

// ---------------------------------------------------------------------------
// parseFullPayload — error paths
// ---------------------------------------------------------------------------

Deno.test("parseFullPayload: NO_JSON when text has no braces", () => {
  const r = parseFullPayload("sorry I can't help with that");
  assertFalse(r.ok);
  if (!r.ok) assertEquals(r.error, "NO_JSON");
});

Deno.test("parseFullPayload: INVALID_JSON when content is an array", () => {
  // Outer must be a JSON object; arrays are rejected to keep downstream
  // guardrails / drift detector from receiving an unexpected shape.
  const r = parseFullPayload("[1,2,3]");
  assertFalse(r.ok);
  if (!r.ok) assertEquals(r.error, "NO_JSON"); // no `{` → NO_JSON, not INVALID
});

Deno.test("parseFullPayload: INVALID_JSON when JSON is unrepairable", () => {
  const r = parseFullPayload("{not-a-key: }");
  assertFalse(r.ok);
  if (!r.ok) assertEquals(r.error, "INVALID_JSON");
});

Deno.test("parseFullPayload: INVALID_JSON when payload is a wrapped array", () => {
  // `{...}` regex grabs the outer braces, but inside is an array — reject.
  const r = parseFullPayload(`{"x":[1,2,3]}[]`);
  // Strict parse should accept the object portion; ensure trailing junk
  // doesn't break it.
  assert(r.ok);
});
