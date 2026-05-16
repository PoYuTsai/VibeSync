import {
  assert,
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasOpenerProfileSubstance,
  normalizeOpenerProfileInfo,
} from "./opener_profile.ts";

Deno.test("normalize: non-object inputs collapse to empty object", () => {
  assertEquals(normalizeOpenerProfileInfo(null), {});
  assertEquals(normalizeOpenerProfileInfo(undefined), {});
  assertEquals(normalizeOpenerProfileInfo("string"), {});
  assertEquals(normalizeOpenerProfileInfo(42), {});
  assertEquals(normalizeOpenerProfileInfo(true), {});
});

Deno.test("normalize: all-string profile is preserved and trimmed", () => {
  const out = normalizeOpenerProfileInfo({
    name: "  Alice  ",
    bio: "designer in Taipei",
    interests: "咖啡, 爬山",
    meetingContext: "從共同朋友認識",
  });
  assertEquals(out, {
    name: "Alice",
    bio: "designer in Taipei",
    interests: "咖啡, 爬山",
    meetingContext: "從共同朋友認識",
  });
});

Deno.test("normalize: array values are dropped (regression for opener quota bypass)", () => {
  // The exact bypass shape Codex flagged: an array interests slips
  // through JS template-literal coercion ("興趣：${["咖啡"]}" === "興趣：咖啡")
  // while a strict string-only check sees no substance. Both consumers
  // must now agree the field is missing.
  const out = normalizeOpenerProfileInfo({
    name: "Alice",
    interests: ["咖啡", "音樂"],
  });
  assertEquals(out, { name: "Alice" });
  assertStrictEquals(out.interests, undefined);
});

Deno.test("normalize: object values are dropped", () => {
  const out = normalizeOpenerProfileInfo({
    bio: { nested: "trying to inject" },
    meetingContext: { foo: "bar" },
  });
  assertEquals(out, {});
});

Deno.test("normalize: number/boolean values are dropped", () => {
  const out = normalizeOpenerProfileInfo({
    name: 42,
    bio: true,
    interests: 0,
    meetingContext: false,
  });
  assertEquals(out, {});
});

Deno.test("normalize: empty and whitespace-only strings are dropped", () => {
  const out = normalizeOpenerProfileInfo({
    name: "",
    bio: "   ",
    interests: "\t\n",
    meetingContext: "  real content  ",
  });
  assertEquals(out, { meetingContext: "real content" });
});

Deno.test("normalize: unknown keys are ignored", () => {
  const out = normalizeOpenerProfileInfo({
    bio: "ok",
    age: "30",
    job: "engineer",
    __proto__: "evil",
  });
  assertEquals(out, { bio: "ok" });
});

Deno.test("normalize: null values are dropped", () => {
  const out = normalizeOpenerProfileInfo({
    name: null,
    bio: null,
    interests: "real",
    meetingContext: null,
  });
  assertEquals(out, { interests: "real" });
});

Deno.test("hasSubstance: empty profile → false (free opener path)", () => {
  assert(!hasOpenerProfileSubstance({}));
});

Deno.test("hasSubstance: name-only profile → false (name alone is too thin to charge)", () => {
  assert(!hasOpenerProfileSubstance({ name: "Alice" }));
});

Deno.test("hasSubstance: bio alone → true (chargeable)", () => {
  assert(hasOpenerProfileSubstance({ bio: "designer in Taipei" }));
});

Deno.test("hasSubstance: interests alone → true (chargeable)", () => {
  assert(hasOpenerProfileSubstance({ interests: "咖啡, 爬山" }));
});

Deno.test("hasSubstance: meetingContext alone → true (chargeable)", () => {
  assert(hasOpenerProfileSubstance({ meetingContext: "從共同朋友認識" }));
});

Deno.test("hasSubstance: array-interests payload should NOT yield substance via normalize", () => {
  // End-to-end regression for the Codex P1: a request with non-string
  // interests must not be billable as substance, period.
  const normalized = normalizeOpenerProfileInfo({
    name: "Alice",
    interests: ["咖啡"],
  });
  assert(!hasOpenerProfileSubstance(normalized));
});

Deno.test("hasSubstance: mixed bio-string + interests-array → true via bio, interests dropped", () => {
  const normalized = normalizeOpenerProfileInfo({
    bio: "designer",
    interests: ["咖啡"],
  });
  assert(hasOpenerProfileSubstance(normalized));
  assertStrictEquals(normalized.interests, undefined);
});
