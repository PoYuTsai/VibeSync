// supabase/functions/coach-follow-up/logger.ts
//
// Minimal local logger. NEVER imports from analyze-chat/logger.ts (OCR baseline
// isolation — CLAUDE.md hard rule + Codex Plan-Review §A5).
//
// Shape: one JSON line per event so Supabase Edge logs / GH Actions can grep
// reliably. Caller is responsible for not passing user free-text / prompt full
// text / Claude raw response (design §7 telemetry rules).

export type LogData = Record<string, unknown>;

function emit(level: "info" | "warn" | "error", event: string, data: LogData) {
  const line = JSON.stringify({
    level,
    event,
    ts: new Date().toISOString(),
    ...data,
  });
  if (level === "error") {
    console.error(line);
  } else if (level === "warn") {
    console.warn(line);
  } else {
    console.log(line);
  }
}

export function logInfo(event: string, data: LogData = {}): void {
  emit("info", event, data);
}

export function logWarn(event: string, data: LogData = {}): void {
  emit("warn", event, data);
}

export function logError(event: string, data: LogData = {}): void {
  emit("error", event, data);
}

/**
 * Returns first 8 chars of a user id for telemetry (privacy: avoid logging full uid).
 * Returns empty string when given empty input.
 */
export function summarizeUser(uid: string): string {
  return uid.slice(0, 8);
}
