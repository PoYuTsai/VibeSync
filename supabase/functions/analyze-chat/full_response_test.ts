// supabase/functions/analyze-chat/full_response_test.ts
//
// Unit tests for parseFullPayload:
// NO_JSON / INVALID_JSON / strict success / repaired success / array rejection
// / code-fence handling.

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { parseFullPayload } from "./full_response.ts";

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

Deno.test("parseFullPayload: NO_JSON when content is an array", () => {
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
