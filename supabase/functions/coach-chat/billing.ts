// Coach 1:1 exactly-once billing helpers（鏡像 keyboard-reply/billing.ts，
// ADR #22 範本；canonical 欄位序見設計檔 §Phase C）。
import type { CoachScope, LifecyclePhase } from "./schemas.ts";

export const COACH_CONTRACT_VERSION = "coach-exactly-once-v1";
export const COACH_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;

// 與 keyboard 範本相同的 UUID 樣式；zod .uuid() 之外的雙保險，
// 大小寫混寫在此正規化成小寫再進帳本。
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function normalizeCoachRequestId(value: unknown): string | null {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) return null;
  return value.toLowerCase();
}

export function isStrongCoachReplayHmacKey(value: unknown): value is string {
  if (typeof value !== "string" || value.length < 43) return false;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
  try {
    return atob(value).length >= 32;
  } catch {
    return false;
  }
}

export function coachReplayCutoffIso(now = new Date()): string {
  return new Date(now.getTime() - COACH_REPLAY_WINDOW_MS).toISOString();
}

export function deriveCoachScopeKey(input: {
  scope: CoachScope | null | undefined;
  conversationId: string | null | undefined;
}): string {
  if (input.scope?.type === "conversation") {
    return `conversation:${input.scope.conversationId}`;
  }
  if (input.scope?.type === "partner") {
    return `partner:${input.scope.partnerId}`;
  }
  if (typeof input.conversationId === "string" && input.conversationId !== "") {
    return `conversation:${input.conversationId}`;
  }
  return "none";
}

export async function computeCoachInputHash(input: {
  userId: string;
  userQuestion: string;
  sessionId?: string | null;
  activeSessionTurns?: ReadonlyArray<Record<string, unknown>>;
  forceAnswer?: boolean;
  scopeKey: string;
  lifecyclePhase?: LifecyclePhase | null;
  secret: string;
}): Promise<string> {
  const canonical = JSON.stringify([
    "coach-chat",
    1,
    input.userId,
    input.userQuestion,
    input.sessionId ?? null,
    input.activeSessionTurns ?? [],
    input.forceAnswer === true,
    input.scopeKey,
    input.lifecyclePhase ?? null,
  ]);
  const encoder = new TextEncoder();
  const derivedKey = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`vibesync-coach-replay-v1\u0000${input.secret}`),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    derivedKey,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(canonical),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
