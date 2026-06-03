// supabase/functions/analyze-chat/stream_events_test.ts
//
// Phase 2.1: pure JSONL event parsing for full streaming analyze.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isStreamStyle,
  parseEventLine,
  STREAM_EVENT_TYPES,
  STREAM_STYLES,
} from "./stream_events.ts";

Deno.test("STREAM_STYLES lists the five canonical reply styles", () => {
  assertEquals(STREAM_STYLES, [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
  ]);
  assert(isStreamStyle("extend"));
  assert(isStreamStyle("coldRead"));
  assertEquals(isStreamStyle("cold_read"), false);
});

Deno.test("STREAM_EVENT_TYPES includes the streaming contract events", () => {
  assertEquals(STREAM_EVENT_TYPES, [
    "analysis.started",
    "analysis.progress",
    "analysis.decision",
    "analysis.recommendation",
    "analysis.reply_option",
    "analysis.metrics",
    "analysis.coach_hint",
    "analysis.report_section",
    "analysis.done",
    "analysis.error",
  ]);
});

Deno.test("parseEventLine returns null for blank, partial, or non-object lines", () => {
  assertEquals(parseEventLine(""), null);
  assertEquals(parseEventLine("   "), null);
  assertEquals(parseEventLine('{"type":"analysis.decision"'), null);
  assertEquals(parseEventLine("[]"), null);
  assertEquals(parseEventLine('"hello"'), null);
  assertEquals(parseEventLine("not json"), null);
});

Deno.test("parseEventLine parses a complete minified event", () => {
  const event = parseEventLine(
    '{"type":"analysis.decision","label":"lower_pressure","message":"keep it short"}',
  );

  assertEquals(event, {
    type: "analysis.decision",
    label: "lower_pressure",
    message: "keep it short",
  });
});

Deno.test("parseEventLine rejects unknown event types", () => {
  assertEquals(parseEventLine('{"type":"analysis.nope","message":"x"}'), null);
});

Deno.test("parseEventLine keeps escaped newlines inside a single JSONL record", () => {
  const event = parseEventLine(
    '{"type":"analysis.progress","message":"line one\\nline two"}',
  );

  assertEquals(event, {
    type: "analysis.progress",
    message: "line one\nline two",
  });
});
