import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isStreamingAllowed,
  parseStreamWhitelist,
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

Deno.test("isStreamingAllowed denies non-whitelisted accounts", () => {
  assertFalse(isStreamingAllowed({
    email: "friend@example.com",
    flagOn: true,
    whitelist: "eric19921204@gmail.com,chiang688041@gmail.com",
  }));
});

Deno.test("isStreamingAllowed denies missing email", () => {
  assertFalse(isStreamingAllowed({
    email: null,
    flagOn: true,
    whitelist: "eric19921204@gmail.com",
  }));
});
