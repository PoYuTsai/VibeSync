// supabase/functions/analyze-chat/stream_events.ts
//
// Pure typed-event helpers for the full streaming analyze path.

export const STREAM_STYLES = [
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
] as const;

export type StreamStyle = typeof STREAM_STYLES[number];

export const STREAM_EVENT_TYPES = [
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
] as const;

export type StreamEventType = typeof STREAM_EVENT_TYPES[number];

export type StreamEvent = {
  type: StreamEventType;
  [key: string]: unknown;
};

const STREAM_STYLE_SET = new Set<string>(STREAM_STYLES);
const STREAM_EVENT_TYPE_SET = new Set<string>(STREAM_EVENT_TYPES);

export function isStreamStyle(value: unknown): value is StreamStyle {
  return typeof value === "string" && STREAM_STYLE_SET.has(value);
}

export function isStreamEventType(value: unknown): value is StreamEventType {
  return typeof value === "string" && STREAM_EVENT_TYPE_SET.has(value);
}

export function parseEventLine(line: string): StreamEvent | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return null;
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }

  const record = parsed as Record<string, unknown>;
  if (!isStreamEventType(record.type)) {
    return null;
  }

  return record as StreamEvent;
}
