// practice-chat 結構化 log（鏡射 coach-chat/logger.ts）。使用者 id 一律匿名化。

export function logInfo(event: string, data?: Record<string, unknown>): void {
  console.log(JSON.stringify({ level: "info", event, ...(data ?? {}) }));
}

export function logWarn(event: string, data?: Record<string, unknown>): void {
  console.warn(JSON.stringify({ level: "warn", event, ...(data ?? {}) }));
}

export function logError(event: string, data?: Record<string, unknown>): void {
  console.error(JSON.stringify({ level: "error", event, ...(data ?? {}) }));
}

export function summarizeUser(userId: string): string {
  if (userId.length <= 8) return userId;
  return `${userId.slice(0, 4)}…${userId.slice(-4)}`;
}
