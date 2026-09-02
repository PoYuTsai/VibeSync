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
  repairDivergencePlanLineGlitch,
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
    "analysis.inventory",
    "analysis.decision",
    "analysis.divergence_plan",
    "analysis.recommendation",
    "analysis.reply_option",
    "analysis.metrics",
    "analysis.coach_hint",
    "analysis.report_section",
    "analysis.done",
    "analysis.error",
  ]);
});

Deno.test("parseEventLine recognizes analysis.inventory as a known-optional event", () => {
  // 球數案修法二：盤點逼進輸出契約。inventory 是 known-optional 事件，
  // parseEventLine 必須認得（不再走 unknown→null 靜默丟棄），reframer 才能
  // 純放行它，App default:break 才有事件可忽略。
  const event = parseEventLine(
    '{"type":"analysis.inventory","balls":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","disposition":"接","reason":"生活分享可延伸"}]}',
  );

  assertEquals(event, {
    type: "analysis.inventory",
    balls: [{
      sourceIndex: 1,
      sourceMessage: "剛來吃晚餐",
      disposition: "接",
      reason: "生活分享可延伸",
    }],
  });
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

Deno.test("parseEventLine keeps analysis.divergence_plan unknown unless the v2 option is on", () => {
  const raw = JSON.stringify({
    type: "analysis.divergence_plan",
    schemaVersion: 1,
  });
  // v1：跟以前一樣是 unknown line → null，不產生任何已辨識事件。
  assertEquals(parseEventLine(raw), null);
  assertEquals(parseEventLine(raw, {}), null);
  assertEquals(parseEventLine(raw, { divergencePlan: false }), null);
  const parsed = parseEventLine(raw, { divergencePlan: true });
  assertEquals(parsed?.type, "analysis.divergence_plan");
  // 其他事件不受選項影響。
  assertEquals(
    parseEventLine(JSON.stringify({ type: "analysis.inventory" }), {})?.type,
    "analysis.inventory",
  );
});

Deno.test('repairDivergencePlanLineGlitch fixes only `"sourceIndex=N"` on a divergence_plan line, regardless of field order; parseEventLine itself stays strict', () => {
  const glitched =
    '{"type":"analysis.divergence_plan","schemaVersion":1,"branchPool":[{"id":"br_3","sourceIndex=1","method":"drill_down"}]}';
  assertEquals(parseEventLine(glitched, { divergencePlan: true }), null);
  const repaired = repairDivergencePlanLineGlitch(glitched)!;
  const parsed = parseEventLine(repaired, { divergencePlan: true });
  assertEquals(parsed?.type, "analysis.divergence_plan");
  const branch = (parsed?.branchPool as Record<string, unknown>[])[0];
  assertEquals(branch.sourceIndex, 1);
  assertEquals("sourceIndex=1" in branch, false);
  // 欄位順序與空白不影響辨識。
  assert(
    repairDivergencePlanLineGlitch(
      '{"schemaVersion":1, "type" : "analysis.divergence_plan","branchPool":[{"id":"br_3","sourceIndex=2","method":"lateral"}]}',
    ),
  );
  // 同樣的手誤出現在別的事件行不修；計畫行的其他 JSON 錯誤也不修。
  assertEquals(
    repairDivergencePlanLineGlitch(
      '{"type":"analysis.reply_option","style":"extend","segments":[{"sourceIndex=1","reply":"x"}]}',
    ),
    null,
  );
  assertEquals(
    repairDivergencePlanLineGlitch(
      '{"type":"analysis.divergence_plan","schemaVersion":1,"branchPool":[{"id":"br_3","sourceIndex":1}',
    ),
    null,
  );
});
