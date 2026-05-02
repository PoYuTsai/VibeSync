// supabase/functions/coach-follow-up/logger_test.ts
//
// Smoke tests for logger shape. These don't verify console output (Deno doesn't
// give a clean way to capture console.log without monkey-patching), but they do
// confirm the helpers don't throw and that summarizeUser truncates correctly.

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";

Deno.test("logInfo / logWarn / logError do not throw with empty data", () => {
  // Capture and silence stdout/stderr for the duration of these calls so test
  // output stays clean.
  const origLog = console.log;
  const origWarn = console.warn;
  const origErr = console.error;
  console.log = () => {};
  console.warn = () => {};
  console.error = () => {};
  try {
    logInfo("test_event");
    logWarn("test_event");
    logError("test_event");
  } finally {
    console.log = origLog;
    console.warn = origWarn;
    console.error = origErr;
  }
});

Deno.test("logInfo emits JSON line with level + event + ts + payload", () => {
  const captured: string[] = [];
  const origLog = console.log;
  console.log = (line: string) => captured.push(line);
  try {
    logInfo("coach_follow_up_invoked", { phase: "prepareInvite", tier: "free" });
  } finally {
    console.log = origLog;
  }
  assertEquals(captured.length, 1);
  const parsed = JSON.parse(captured[0]);
  assertEquals(parsed.level, "info");
  assertEquals(parsed.event, "coach_follow_up_invoked");
  assertEquals(parsed.phase, "prepareInvite");
  assertEquals(parsed.tier, "free");
  assertEquals(typeof parsed.ts, "string");
});

Deno.test("logError routes to stderr, logWarn routes to stderr (warn channel)", () => {
  const errLines: string[] = [];
  const warnLines: string[] = [];
  const origErr = console.error;
  const origWarn = console.warn;
  console.error = (line: string) => errLines.push(line);
  console.warn = (line: string) => warnLines.push(line);
  try {
    logError("e", { errorClass: "schema_invalid" });
    logWarn("w", { phase: "prepareInvite" });
  } finally {
    console.error = origErr;
    console.warn = origWarn;
  }
  assertEquals(errLines.length, 1);
  assertEquals(warnLines.length, 1);
  assertEquals(JSON.parse(errLines[0]).level, "error");
  assertEquals(JSON.parse(warnLines[0]).level, "warn");
});

Deno.test("summarizeUser truncates to first 8 chars", () => {
  assertEquals(summarizeUser("abcdef0123456789"), "abcdef01");
});

Deno.test("summarizeUser returns empty string for empty input", () => {
  assertEquals(summarizeUser(""), "");
});

Deno.test("summarizeUser leaves short uid untouched", () => {
  assertEquals(summarizeUser("abc"), "abc");
});
