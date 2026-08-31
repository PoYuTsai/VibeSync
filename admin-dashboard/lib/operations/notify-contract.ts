// B2 通知與 break-glass 共用契約。
// 固定 red／yellow template、欄位 allowlist、dedupe/idempotency 鍵格式與
// break-glass 數值上限全部只在這裡定義；SQL（20260831180000 migration）的
// enum／pattern／interval 與本檔逐字或同值同源（測試比對）。本批不實作
// B4 worker／cron：升級門檻（15 分鐘持續／3 次重複）只是契約常數。

import { AUDIT_ACTIONS } from "./admin-gate.ts";

// --- 通知 template 契約 ---

export const NOTIFY_TEMPLATES = ["red", "yellow"] as const;
export type NotifyTemplate = (typeof NOTIFY_TEMPLATES)[number];

export const NOTIFY_DELIVERY_CLASSES = ["immediate", "daily_brief"] as const;
export type NotifyDeliveryClass = (typeof NOTIFY_DELIVERY_CLASSES)[number];

/** template → delivery class 的固定對應：red 立即、yellow 進 09:00 brief。 */
export const TEMPLATE_DELIVERY_CLASS: Record<NotifyTemplate, NotifyDeliveryClass> = {
  red: "immediate",
  yellow: "daily_brief",
};

/** yellow 升級門檻（B4 worker 的固定契約，不是每列資料）。 */
export const YELLOW_ESCALATION = {
  persistMinutes: 15,
  repeatCount: 3,
} as const;

/** 與 migration 的 reason_code CHECK 共用同一份 enum（測試逐字比對，含順序）。 */
export const NOTIFY_REASON_CODES = [
  "feedback_received",
  "breakglass_extended",
  "edge_error_spike",
  "quota_exhausted_spike",
  "payment_webhook_failure",
  "cost_spike",
] as const;
export type NotifyReasonCode = (typeof NOTIFY_REASON_CODES)[number];

/** 與 migration 的 channel CHECK 共用同一份 enum。email 只是 Discord 失敗後的窄 fallback。 */
export const NOTIFY_CHANNELS = ["discord", "email_fallback"] as const;

/** 與 migration 的欄位 CHECK 共用同一份 pattern 字串（測試逐字比對）。 */
export const NOTIFY_USER_REF_PATTERN = "^user:sha256:[0-9a-f]{64}$";
export const NOTIFY_DEDUPE_KEY_PATTERN = "^[a-z][a-z0-9_.]{0,63}:sha256:[0-9a-f]{64}$";
export const FEEDBACK_REQUEST_REF_PATTERN = "^request:sha256:[0-9a-f]{64}$";

const USER_REF_RE = new RegExp(NOTIFY_USER_REF_PATTERN, "u");
const DEDUPE_KEY_RE = new RegExp(NOTIFY_DEDUPE_KEY_PATTERN, "u");
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;

export interface NotificationEventV2 {
  template: NotifyTemplate;
  deliveryClass: NotifyDeliveryClass;
  reasonCode: NotifyReasonCode;
  dedupeKey: string;
  incidentId: string | null;
  userRef: string | null;
}

const NOTIFY_ALLOWED_KEYS = new Set([
  "template",
  "reasonCode",
  "dedupeKey",
  "incidentId",
  "userRef",
]);

/**
 * 通知欄位 allowlist 驗證：只有 incident id、不可逆 user ref、severity
 * template、safe reason code 與 dedupe 鍵；任何未知鍵或自由文字 payload
 * 一律拒絕。deliveryClass 由 template 導出，呼叫端不能自帶。
 */
export function buildNotificationEvent(
  input: Record<string, unknown>,
): { ok: true; event: NotificationEventV2 } | { ok: false; error: string } {
  for (const key of Object.keys(input)) {
    if (!NOTIFY_ALLOWED_KEYS.has(key)) return { ok: false, error: "notify-field-not-allowed" };
  }
  const { template, reasonCode, dedupeKey, incidentId, userRef } = input;
  if (typeof template !== "string" || !(NOTIFY_TEMPLATES as readonly string[]).includes(template)) {
    return { ok: false, error: "notify-invalid-template" };
  }
  if (
    typeof reasonCode !== "string" ||
    !(NOTIFY_REASON_CODES as readonly string[]).includes(reasonCode)
  ) {
    return { ok: false, error: "notify-invalid-reason-code" };
  }
  if (typeof dedupeKey !== "string" || !DEDUPE_KEY_RE.test(dedupeKey)) {
    return { ok: false, error: "notify-invalid-dedupe-key" };
  }
  if (incidentId != null && (typeof incidentId !== "string" || !UUID_RE.test(incidentId))) {
    return { ok: false, error: "notify-invalid-incident-id" };
  }
  if (userRef != null && (typeof userRef !== "string" || !USER_REF_RE.test(userRef))) {
    return { ok: false, error: "notify-invalid-user-ref" };
  }
  return {
    ok: true,
    event: {
      template: template as NotifyTemplate,
      deliveryClass: TEMPLATE_DELIVERY_CLASS[template as NotifyTemplate],
      reasonCode: reasonCode as NotifyReasonCode,
      dedupeKey,
      incidentId: (incidentId as string | undefined) ?? null,
      userRef: (userRef as string | undefined) ?? null,
    },
  };
}

// --- Break-glass 契約常數（與 migration 的 CHECK/INTERVAL 同值，測試比對）---

export const BREAKGLASS_GRANT_TTL_MS = 30 * 60 * 1000;
export const BREAKGLASS_MAX_CAPTURES = 3;
export const BREAKGLASS_CAPTURE_TTL_MS = 72 * 60 * 60 * 1000;
export const BREAKGLASS_MAX_EXTENSIONS = 1;
export const BREAKGLASS_MAX_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;

// --- audit action 擴充（B2）---
// 前五個沿用 B1 的 AUDIT_ACTIONS（逐字同序）；六個 breakglass.* 是 B2
// migration 對 admin_audit_events_v2 action CHECK 的唯一擴充。B1 的
// buildAuditEvent 仍只收 B1 action——breakglass audit 一律由 SQL RPC 在同一
// 交易內寫入，TS 不提供組裝入口。
export const AUDIT_ACTIONS_WITH_BREAKGLASS = [
  ...AUDIT_ACTIONS,
  "breakglass.activate",
  "breakglass.view",
  "breakglass.export",
  "breakglass.extend",
  "breakglass.close",
  "breakglass.purge",
] as const;

// --- ai_logs metadata 邊界 ---
// 與 migration 的 admin_ai_logs_meta_v2 view SELECT 欄位逐字同源（測試比對）。
// raw telemetry（request_body／response_body／error_message）永不在此清單。
export const AI_LOGS_META_COLUMNS = [
  "id",
  "user_id",
  "model",
  "request_type",
  "input_tokens",
  "output_tokens",
  "cost_usd",
  "latency_ms",
  "status",
  "error_code",
  "fallback_used",
  "retry_count",
  "created_at",
] as const;

export const AI_LOGS_RAW_COLUMNS = ["request_body", "response_body", "error_message"] as const;
