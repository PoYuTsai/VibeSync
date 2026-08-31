// 後台 B1 管理員安全閘門共用契約。
// role/capability、MFA/AAL2、absolute/idle timeout、撤銷／版本失效、reauth freshness
// 與 audit allowlist 全部只在這裡定義；middleware、server helper 與 auth route
// 一律經 resolveAdminAccess 走同一份規則，不得各自發明。
// ADMIN_V2 關閉時只跑注入的 legacy 檢查、輸出相容；開啟時禁止 email fallback，
// 任何未知或缺失狀態一律 fail closed。錯誤只回固定 generic 字串，不洩漏
// email、token、reason 細節或底層 RPC／資料庫錯誤。

// 帶 .ts 副檔名：讓 node --test 的 type stripping 與 Next bundler 都吃得下同一份檔。
import { isAdminV2Enabled } from "./admin-v2.ts";

export const ADMIN_SESSION_ABSOLUTE_MS = 12 * 60 * 60 * 1000;
export const ADMIN_SESSION_IDLE_MS = 30 * 60 * 1000;
export const ADMIN_REAUTH_FRESH_MS = 10 * 60 * 1000;

export type AdminRole = "owner" | "founder_admin";

export type AdminCapability =
  | "ops.read"
  | "incident.ack"
  | "dual.confirm"
  | "sensitive.execute";

// capability 單一真相：Owner 可執行後續受控敏感操作；
// Founder Admin 以營運讀取、事故確認與雙人確認為主，不取得敏感執行權。
const ROLE_CAPABILITIES: Record<AdminRole, readonly AdminCapability[]> = {
  owner: ["ops.read", "incident.ack", "dual.confirm", "sensitive.execute"],
  founder_admin: ["ops.read", "incident.ack", "dual.confirm"],
};

export function capabilitiesForRole(role: AdminRole): readonly AdminCapability[] {
  return ROLE_CAPABILITIES[role];
}

export function hasCapability(role: AdminRole, capability: AdminCapability): boolean {
  return ROLE_CAPABILITIES[role].includes(capability);
}

/** 給瀏覽器看的固定訊息；deny reason 是內部資訊，永不出現在 response body。 */
export const PUBLIC_AUTH_ERROR = {
  unauthorized: "Unauthorized",
  forbidden: "Forbidden",
  loginFailed: "Login failed",
} as const;

export type AdminDenyReason =
  | "not-admin"
  | "disabled"
  | "mfa-required"
  | "revoked"
  | "version-mismatch"
  | "absolute-timeout"
  | "idle-timeout"
  | "invalid-record";

export type Aal = "aal1" | "aal2" | "unknown";

/**
 * 從已由 Supabase 驗證過的 access token 取 AAL claim。
 * 這裡只解 payload 不驗簽——簽章真偽必須先由 supabase.auth.getUser() 確認。
 * 任何解不開、格式不對、缺 claim 的情況一律 "unknown"（fail closed）。
 * 不用 Buffer：middleware 跑在 Edge runtime，只用 atob/TextDecoder。
 */
export function getAalFromAccessToken(token: string | null | undefined): Aal {
  if (!token) return "unknown";
  const parts = token.split(".");
  if (parts.length !== 3) return "unknown";
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const bin = atob(padded);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    const payload: unknown = JSON.parse(new TextDecoder().decode(bytes));
    const aal = (payload as { aal?: unknown } | null)?.aal;
    if (aal === "aal2") return "aal2";
    if (aal === "aal1") return "aal1";
    return "unknown";
  } catch {
    return "unknown";
  }
}

export interface AdminIdentityV2 {
  role: string;
  isActive: boolean;
  sessionVersion: number;
}

/** prevSeenAt 是本次觸碰「之前」的 last_seen_at：idle 用它判斷，逾時不因觸碰復活。 */
export interface AdminSessionRecordV2 {
  createdAt: string | null;
  prevSeenAt: string | null;
  lastReauthAt: string | null;
  sessionVersion: number | null;
  revokedAt: string | null;
}

export type AdminSessionEvaluation =
  | { ok: true; role: AdminRole; capabilities: readonly AdminCapability[] }
  | { ok: false; reason: AdminDenyReason };

function parseMs(value: string | null): number | null {
  if (value == null) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

function isAdminRole(role: string): role is AdminRole {
  return role === "owner" || role === "founder_admin";
}

/** 單一 session 判定契約：缺料、未知、逾時、撤銷、版本不符全部 fail closed。 */
export function evaluateAdminSessionV2(input: {
  aal: Aal;
  identity: AdminIdentityV2 | null;
  session: AdminSessionRecordV2 | null;
  now: Date;
}): AdminSessionEvaluation {
  const { aal, identity, session, now } = input;
  if (aal !== "aal2") return { ok: false, reason: "mfa-required" };
  if (!identity) return { ok: false, reason: "not-admin" };
  if (!isAdminRole(identity.role)) return { ok: false, reason: "invalid-record" };
  if (!identity.isActive) return { ok: false, reason: "disabled" };
  if (!session) return { ok: false, reason: "invalid-record" };
  if (session.revokedAt != null) return { ok: false, reason: "revoked" };
  if (session.sessionVersion !== identity.sessionVersion) {
    return { ok: false, reason: "version-mismatch" };
  }
  const createdMs = parseMs(session.createdAt);
  const prevSeenMs = parseMs(session.prevSeenAt);
  if (createdMs == null || prevSeenMs == null) return { ok: false, reason: "invalid-record" };
  const nowMs = now.getTime();
  if (nowMs - createdMs > ADMIN_SESSION_ABSOLUTE_MS) {
    return { ok: false, reason: "absolute-timeout" };
  }
  if (nowMs - prevSeenMs > ADMIN_SESSION_IDLE_MS) {
    return { ok: false, reason: "idle-timeout" };
  }
  return { ok: true, role: identity.role, capabilities: capabilitiesForRole(identity.role) };
}

/** reauth freshness：敏感操作要求最近重新驗證；缺值或爛時間戳一律不新鮮。 */
export function isReauthFresh(lastReauthAt: string | null | undefined, now: Date): boolean {
  const ms = parseMs(lastReauthAt ?? null);
  if (ms == null) return false;
  const age = now.getTime() - ms;
  return age >= 0 && age <= ADMIN_REAUTH_FRESH_MS;
}

export type SensitiveOpDecision =
  | { ok: true }
  | { ok: false; reason: "capability-denied" | "reauth-required" };

/** 敏感操作 gate 基線：要有 sensitive.execute capability＋新鮮 reauth。B2–B8 不得繞過。 */
export function canPerformSensitiveOp(
  role: AdminRole,
  lastReauthAt: string | null | undefined,
  now: Date,
): SensitiveOpDecision {
  if (!hasCapability(role, "sensitive.execute")) {
    return { ok: false, reason: "capability-denied" };
  }
  if (!isReauthFresh(lastReauthAt, now)) {
    return { ok: false, reason: "reauth-required" };
  }
  return { ok: true };
}

// --- Audit allowlist 契約 ---
// 欄位固定，值先在這裡驗過才進 RPC；schema CHECK 是第二道防線（規則逐字同源）。
// target_ref 只收不透明結構化參照 <kind>:sha256:<64 位小寫 hex>；
// reason 只收固定 reason code enum。自由文字、空白、電話、prompt 原文、
// email、API key／JWT 之類的 secret 在結構上就進不來。

const AUDIT_RESULTS = ["success", "denied", "failure"] as const;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;
const ACTION_RE = /^[a-z0-9][a-z0-9_.:-]{0,99}$/u;
const REQUEST_ID_RE = /^[A-Za-z0-9._:-]{1,100}$/u;

/** 與 migration 的 target_ref CHECK 共用同一份 pattern 字串（測試逐字比對）。 */
export const AUDIT_TARGET_REF_PATTERN = "^[a-z][a-z0-9_]{0,31}:sha256:[0-9a-f]{64}$";
const AUDIT_TARGET_REF_RE = new RegExp(AUDIT_TARGET_REF_PATTERN, "u");

/** 與 migration 的 reason CHECK 共用同一份 enum（測試逐字比對）。 */
export const AUDIT_REASON_CODES = [
  "incident_response",
  "support_request",
  "billing_review",
  "security_review",
  "scheduled_maintenance",
  "data_correction",
  "legal_request",
  "dual_control_approval",
] as const;

export type AuditReasonCode = (typeof AUDIT_REASON_CODES)[number];

export interface AuditEventV2 {
  actorUserId: string;
  action: string;
  result: (typeof AUDIT_RESULTS)[number];
  targetRef: string | null;
  reason: AuditReasonCode | null;
  approverUserId: string | null;
  requestId: string | null;
}

const AUDIT_ALLOWED_KEYS = new Set([
  "actorUserId",
  "action",
  "result",
  "targetRef",
  "reason",
  "approverUserId",
  "requestId",
]);

export function buildAuditEvent(
  input: Record<string, unknown>,
): { ok: true; event: AuditEventV2 } | { ok: false; error: string } {
  for (const key of Object.keys(input)) {
    if (!AUDIT_ALLOWED_KEYS.has(key)) return { ok: false, error: "audit-field-not-allowed" };
  }
  const { actorUserId, action, result, targetRef, reason, approverUserId, requestId } = input;
  if (typeof actorUserId !== "string" || !UUID_RE.test(actorUserId)) {
    return { ok: false, error: "audit-invalid-actor" };
  }
  if (typeof action !== "string" || !ACTION_RE.test(action)) {
    return { ok: false, error: "audit-invalid-action" };
  }
  if (typeof result !== "string" || !(AUDIT_RESULTS as readonly string[]).includes(result)) {
    return { ok: false, error: "audit-invalid-result" };
  }
  if (targetRef != null && (typeof targetRef !== "string" || !AUDIT_TARGET_REF_RE.test(targetRef))) {
    return { ok: false, error: "audit-invalid-target-ref" };
  }
  if (
    reason != null &&
    (typeof reason !== "string" || !(AUDIT_REASON_CODES as readonly string[]).includes(reason))
  ) {
    return { ok: false, error: "audit-invalid-reason" };
  }
  if (approverUserId != null && (typeof approverUserId !== "string" || !UUID_RE.test(approverUserId))) {
    return { ok: false, error: "audit-invalid-approver" };
  }
  if (requestId != null && (typeof requestId !== "string" || !REQUEST_ID_RE.test(requestId))) {
    return { ok: false, error: "audit-invalid-request-id" };
  }
  return {
    ok: true,
    event: {
      actorUserId,
      action,
      result: result as AuditEventV2["result"],
      targetRef: (targetRef as string | undefined) ?? null,
      reason: (reason as AuditReasonCode | undefined) ?? null,
      approverUserId: (approverUserId as string | undefined) ?? null,
      requestId: (requestId as string | undefined) ?? null,
    },
  };
}

// --- 共用 server gate ---

/** admin_v2_touch_session 的回列（snake_case 來自 SQL）。 */
interface TouchSessionRow {
  role: string;
  is_active: boolean;
  account_session_version: number;
  session_created_at: string | null;
  prev_seen_at: string | null;
  last_reauth_at: string | null;
  session_version: number | null;
  revoked_at: string | null;
}

export interface ResolveAdminAccessInput {
  accessToken: string | null | undefined;
  /** 旗標關閉時的 legacy 檢查；旗標開啟時永遠不會被呼叫（禁止 email fallback）。 */
  legacyCheck: () => PromiseLike<{ allowed: boolean; error?: string }>;
  /** supabase.rpc("admin_v2_touch_session") 的包裝（PostgREST builder 是 thenable）。 */
  touchSession: () => PromiseLike<{ data: unknown; error: unknown }>;
  /** best-effort：逾時／版本失效時把 session 標記撤銷，避免觸碰復活。 */
  revokeSession?: () => PromiseLike<unknown>;
  env?: Record<string, string | undefined>;
  now?: Date;
}

export type ResolveAdminAccessResult =
  | { allowed: true; mode: "legacy" }
  | {
      allowed: true;
      mode: "v2";
      role: AdminRole;
      capabilities: readonly AdminCapability[];
      lastReauthAt: string | null;
    }
  // legacy deny 帶回 legacyError：旗標關閉的消費端要它一比一重現 pre-B1 可見輸出
  // （session route 的 detail 欄位）。v2 deny 永遠只有 generic publicError。
  | { allowed: false; mode: "legacy"; status: 403; publicError: string; legacyError?: string }
  | { allowed: false; mode: "v2"; status: 401 | 403; publicError: string };

const REVOKE_ON_DENY: ReadonlySet<AdminDenyReason> = new Set([
  "absolute-timeout",
  "idle-timeout",
  "version-mismatch",
]);

export async function resolveAdminAccess(
  input: ResolveAdminAccessInput,
): Promise<ResolveAdminAccessResult> {
  const env = input.env ?? process.env;
  if (!isAdminV2Enabled(env)) {
    const legacy = await input.legacyCheck();
    if (!legacy.allowed) {
      return {
        allowed: false,
        mode: "legacy",
        status: 403,
        publicError: PUBLIC_AUTH_ERROR.forbidden,
        legacyError: legacy.error,
      };
    }
    return { allowed: true, mode: "legacy" };
  }

  const now = input.now ?? new Date();
  const aal = getAalFromAccessToken(input.accessToken);
  let row: TouchSessionRow | null = null;
  try {
    const { data, error } = await input.touchSession();
    if (error != null || !Array.isArray(data)) {
      return { allowed: false, mode: "v2", status: 401, publicError: PUBLIC_AUTH_ERROR.unauthorized };
    }
    row = (data[0] as TouchSessionRow | undefined) ?? null;
  } catch {
    return { allowed: false, mode: "v2", status: 401, publicError: PUBLIC_AUTH_ERROR.unauthorized };
  }

  const evaluation = evaluateAdminSessionV2({
    aal,
    identity:
      row == null
        ? null
        : {
            role: row.role,
            isActive: row.is_active === true,
            sessionVersion: row.account_session_version,
          },
    session:
      row == null || row.session_created_at == null
        ? null
        : {
            createdAt: row.session_created_at,
            prevSeenAt: row.prev_seen_at,
            lastReauthAt: row.last_reauth_at,
            sessionVersion: row.session_version,
            revokedAt: row.revoked_at,
          },
    now,
  });

  if (!evaluation.ok) {
    if (REVOKE_ON_DENY.has(evaluation.reason) && input.revokeSession) {
      try {
        await input.revokeSession();
      } catch {
        // best-effort：撤銷失敗不改變本次 deny 結果。
      }
    }
    return { allowed: false, mode: "v2", status: 403, publicError: PUBLIC_AUTH_ERROR.forbidden };
  }

  return {
    allowed: true,
    mode: "v2",
    role: evaluation.role,
    capabilities: evaluation.capabilities,
    lastReauthAt: row?.last_reauth_at ?? null,
  };
}
