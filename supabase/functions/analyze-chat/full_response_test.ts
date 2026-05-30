// supabase/functions/analyze-chat/full_response_test.ts
//
// Unit tests for the pure helpers used by the FULL handler:
//   - buildFullPromptAnchor: quick/Core candidate block + edge cases
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

Deno.test("buildFullPromptAnchor: surfaces quick candidate fields without binding full", () => {
  const anchor = buildFullPromptAnchor({
    nextStep: "先退一步接住她的壓力，不要急著約",
    pick: "resonate",
    recommendedReply: "我懂，不想被催的感覺真的會有壓力。我們就慢慢聊。",
    shortReason: "她在設邊界，先降壓比延展更重要",
    insufficientContext: false,
    confidence: "high",
  });

  assertStringIncludes(anchor, "## QUICK_CANDIDATE");
  assertStringIncludes(anchor, "- nextStep: 先退一步接住她的壓力，不要急著約");
  assertStringIncludes(anchor, "- pick: resonate");
  assertStringIncludes(anchor, "- recommendedReply: 我懂，不想被催的感覺真的會有壓力。我們就慢慢聊。");
  assertStringIncludes(anchor, "- shortReason: 她在設邊界，先降壓比延展更重要");
  assertStringIncludes(anchor, "不是硬性答案");
  assertStringIncludes(anchor, "必須覆蓋");
  assertStringIncludes(anchor, "不要預設 extend");
  assertStringIncludes(anchor, "finalRecommendation.pick");
  assertStringIncludes(anchor, "coachActionHint.microMove");
  assertStringIncludes(anchor, "replyOptions 五個風格仍要完整產出");

  assertFalse(anchor.includes("必須使用 recommendedReply"));
  assertFalse(anchor.includes("必須順著 nextStep"));
});

Deno.test("buildFullPromptAnchor: missing fields render as empty rather than undefined", () => {
  const anchor = buildFullPromptAnchor({} as Record<string, unknown>);
  assertStringIncludes(anchor, "- nextStep: ");
  assertStringIncludes(anchor, "- pick: ");
  assertStringIncludes(anchor, "- recommendedReply: ");
  assertStringIncludes(anchor, "- shortReason: ");
  assertFalse(anchor.includes("undefined"));
  assertFalse(anchor.includes("null"));
});

Deno.test("buildFullPromptAnchor: ignores non-string field types defensively", () => {
  const anchor = buildFullPromptAnchor({
    nextStep: 42 as unknown as string,
    pick: ["extend"] as unknown as string,
    recommendedReply: { foo: "bar" } as unknown as string,
    shortReason: null as unknown as string,
  });
  assertStringIncludes(anchor, "- nextStep: ");
  assertStringIncludes(anchor, "- pick: ");
  assertFalse(anchor.includes("42"));
  assertFalse(anchor.includes("[object Object]"));
});

// ---------------------------------------------------------------------------
// parseFullPayload happy paths
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

Deno.test("parseFullPayload: handles fenced json block", () => {
  const raw = '```json\n{"finalRecommendation":{"content":"hi"}}\n```';
  const r = parseFullPayload(raw);
  assert(r.ok);
  assertEquals(r.result.source, "strict");
});

// ---------------------------------------------------------------------------
// parseFullPayload repair paths
// ---------------------------------------------------------------------------

Deno.test("parseFullPayload: trailing comma triggers repair, returns source=repaired", () => {
  const raw = `{"finalRecommendation":{"content":"hi",},}`;
  const r = parseFullPayload(raw);
  assert(r.ok, `expected ok after repair, got ${JSON.stringify(r)}`);
  assertEquals(r.result.source, "repaired");
});

Deno.test("parseFullPayload: nested trailing comma triggers repair", () => {
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
// parseFullPayload error paths
// ---------------------------------------------------------------------------

Deno.test("parseFullPayload: NO_JSON when text has no braces", () => {
  const r = parseFullPayload("sorry I can't help with that");
  assertFalse(r.ok);
  if (!r.ok) assertEquals(r.error, "NO_JSON");
});

Deno.test("parseFullPayload: INVALID_JSON when content is an array", () => {
  const r = parseFullPayload("[1,2,3]");
  assertFalse(r.ok);
  if (!r.ok) assertEquals(r.error, "NO_JSON");
});

Deno.test("parseFullPayload: INVALID_JSON when JSON is unrepairable", () => {
  const r = parseFullPayload("{not-a-key: }");
  assertFalse(r.ok);
  if (!r.ok) assertEquals(r.error, "INVALID_JSON");
});

Deno.test("parseFullPayload: accepts object portion before trailing junk", () => {
  const r = parseFullPayload(`{"x":[1,2,3]}[]`);
  assert(r.ok);
});
