import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isStreamingAllowed,
  parseStreamWhitelist,
  STREAM_ALLOW_ALL,
  STREAM_TEST_ACCOUNT,
} from "./stream_gate.ts";

Deno.test("parseStreamWhitelist trims, lowercases, drops blanks, and always includes test account", () => {
  const result = parseStreamWhitelist(
    " Eric19921204@GMAIL.COM, , chiang688041@gmail.com ",
  );

  assertEquals(result.has("eric19921204@gmail.com"), true);
  assertEquals(result.has("chiang688041@gmail.com"), true);
  assertEquals(result.has(STREAM_TEST_ACCOUNT), true);
  assertFalse(result.has(""));
});

Deno.test("parseStreamWhitelist keeps wildcard allow-all marker", () => {
  const result = parseStreamWhitelist(" * , Eric19921204@GMAIL.COM ");

  assertEquals(result.has(STREAM_ALLOW_ALL), true);
  assertEquals(result.has("eric19921204@gmail.com"), true);
});

Deno.test("isStreamingAllowed denies everyone when flag is off", () => {
  assertFalse(isStreamingAllowed({
    email: STREAM_TEST_ACCOUNT,
    flagOn: false,
    whitelist: "",
  }));
});

Deno.test("isStreamingAllowed allows test account when flag is on", () => {
  assert(isStreamingAllowed({
    email: " VibeSync.Test@Gmail.com ",
    flagOn: true,
    whitelist: "",
  }));
});

Deno.test("isStreamingAllowed allows whitelisted accounts case-insensitively", () => {
  assert(isStreamingAllowed({
    email: "ERIC19921204@gmail.com",
    flagOn: true,
    whitelist: "chiang688041@gmail.com, eric19921204@gmail.com",
  }));
});

Deno.test("isStreamingAllowed allows paid tiers outside the whitelist", () => {
  assert(isStreamingAllowed({
    email: "liam_chiang@hotmail.com",
    flagOn: true,
    whitelist: "eric19921204@gmail.com,chiang688041@gmail.com",
    tier: "essential",
  }));

  assert(isStreamingAllowed({
    email: "friend@example.com",
    flagOn: true,
    whitelist: "",
    tier: "starter",
  }));
});

Deno.test("isStreamingAllowed allows free tier outside the whitelist", () => {
  assert(isStreamingAllowed({
    email: "free@example.com",
    flagOn: true,
    whitelist: "eric19921204@gmail.com,chiang688041@gmail.com",
    tier: "free",
  }));
});

Deno.test("isStreamingAllowed allows any authenticated email when wildcard is enabled", () => {
  assert(isStreamingAllowed({
    email: "partner@example.com",
    flagOn: true,
    whitelist: " * ",
  }));
});

Deno.test("isStreamingAllowed keeps wildcard gated by the feature flag", () => {
  assertFalse(isStreamingAllowed({
    email: "partner@example.com",
    flagOn: false,
    whitelist: "*",
  }));
});

Deno.test("isStreamingAllowed no longer depends on whitelist membership", () => {
  assert(isStreamingAllowed({
    email: "friend@example.com",
    flagOn: true,
    whitelist: "eric19921204@gmail.com,chiang688041@gmail.com",
    tier: "free",
  }));
});

Deno.test("isStreamingAllowed allows missing email when auth reached the function", () => {
  assert(isStreamingAllowed({
    email: null,
    flagOn: true,
    whitelist: "eric19921204@gmail.com",
  }));
});
