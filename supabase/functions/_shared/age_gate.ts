// 18+ 年齡閘門（AGE-01；Eric 2026-08-21 DEC-08 要求 iOS 1.0.1 送審前完成，
// 2026-10-30 定最小可行版）。
//
// - 帳號的年齡紀錄存在 auth `app_metadata.age_gate`：只有伺服器（service role）
//   寫得進去，使用者改不到；登出登入、換機、重裝都跟著帳號走。
//   形狀 `{ result: "adult" | "minor", policy: 1, at: ISO 時間 }`，不存生日：
//   App 在手機上用出生年月算出成年與否，只送結果。
// - 寫入（sync-subscription 的 `record_age_gate`）：未成年鎖住，不能改回成年
//   （填錯聯絡客服）；成年改成未成年照寫（更保守）。
// - 核心 AI 功能每次請求檢查 [checkAgeGate]。開關 secret `AGE_GATE_ENFORCE`
//   每次請求讀：沒設或其他值＝關（誰都不擋，App Store 上沒有年齡確認頁的舊版
//   不受影響）、`test`＝只擋 TEST_EMAILS、`on`＝全部。全開前要讓舊版先更新。

import { isPlainObject, TEST_EMAILS } from "./quota.ts";

export const AGE_GATE_POLICY_VERSION = 1;

export type AgeGateResult = "adult" | "minor";

export interface AgeGateRecord {
  result: AgeGateResult;
  policy: number;
  at: string;
}

/** 從 auth user 的 app_metadata 讀年齡紀錄；形狀不對就當沒有。 */
export function readAgeGateRecord(appMetadata: unknown): AgeGateRecord | null {
  if (!isPlainObject(appMetadata)) return null;
  const raw = appMetadata.age_gate;
  if (!isPlainObject(raw)) return null;
  const result = raw.result;
  const policy = raw.policy;
  const at = raw.at;
  if (result !== "adult" && result !== "minor") return null;
  if (typeof policy !== "number" || !Number.isInteger(policy) || policy < 1) {
    return null;
  }
  if (typeof at !== "string" || Number.isNaN(Date.parse(at))) return null;
  return { result, policy, at };
}

export type AgeGateEnforcement = "off" | "test" | "on";

export function parseAgeGateEnforcement(
  raw: string | null | undefined,
): AgeGateEnforcement {
  const value = (raw ?? "").trim().toLowerCase();
  if (value === "on" || value === "true") return "on";
  if (value === "test") return "test";
  return "off";
}

export interface AgeGateBlock {
  status: 403;
  body: {
    error: "AGE_GATE_REQUIRED" | "AGE_GATE_BLOCKED";
    message: string;
  };
}

export const AGE_GATE_BLOCKED_MESSAGE = "VibeSync 只提供給成年人使用。";
export const AGE_GATE_REQUIRED_MESSAGE =
  "請更新到最新版本，完成年齡確認後再使用。";

/**
 * 核心 AI 功能的年齡檢查：放在驗完使用者之後、讀請求內容與扣額度之前。
 * 回 null＝放行；回 [AgeGateBlock]＝照它的 status／body 回應。
 */
export function checkAgeGate(input: {
  user: { email?: string | null; app_metadata?: unknown };
  enforcement: string | null | undefined;
}): AgeGateBlock | null {
  const record = readAgeGateRecord(input.user.app_metadata);
  if (record?.result === "adult") return null;
  const mode = parseAgeGateEnforcement(input.enforcement);
  if (mode === "off") return null;
  if (mode === "test" && !TEST_EMAILS.includes(input.user.email ?? "")) {
    return null;
  }
  if (record?.result === "minor") {
    return {
      status: 403,
      body: { error: "AGE_GATE_BLOCKED", message: AGE_GATE_BLOCKED_MESSAGE },
    };
  }
  return {
    status: 403,
    body: { error: "AGE_GATE_REQUIRED", message: AGE_GATE_REQUIRED_MESSAGE },
  };
}

export type AgeGateWriteDecision =
  | { kind: "write"; record: AgeGateRecord }
  | { kind: "unchanged"; record: AgeGateRecord }
  | { kind: "locked"; record: AgeGateRecord };

/** 寫入規則：未成年鎖住；同結果不重寫；成年改未成年照寫；沒有紀錄照寫。 */
export function decideAgeGateWrite(
  existing: AgeGateRecord | null,
  requested: AgeGateResult,
  now: Date,
): AgeGateWriteDecision {
  if (existing?.result === "minor") {
    return requested === "minor"
      ? { kind: "unchanged", record: existing }
      : { kind: "locked", record: existing };
  }
  if (existing?.result === requested) {
    return { kind: "unchanged", record: existing };
  }
  return {
    kind: "write",
    record: {
      result: requested,
      policy: AGE_GATE_POLICY_VERSION,
      at: now.toISOString(),
    },
  };
}

export interface RecordAgeGateDeps {
  /** 寫 auth app_metadata（service role）；只傳 age_gate 這一個鍵。 */
  updateAppMetadata: (
    userId: string,
    appMetadata: { age_gate: AgeGateRecord },
  ) => Promise<{ error: { message: string } | null }>;
  now: () => Date;
}

export interface RecordAgeGateResponse {
  status: number;
  body: Record<string, unknown>;
}

/**
 * sync-subscription `mode: "record_age_gate"`：`{ result, policy }`。
 * 回 `{ ageGate: { result, policy, at } }`；未成年鎖住時回 409
 * `AGE_GATE_LOCKED`（body 也帶目前紀錄，App 照它顯示）。
 */
export async function handleRecordAgeGate(
  input: {
    user: { id: string; app_metadata?: unknown };
    body: Record<string, unknown>;
  },
  deps: RecordAgeGateDeps,
): Promise<RecordAgeGateResponse> {
  const requested = input.body.result;
  if (requested !== "adult" && requested !== "minor") {
    return { status: 400, body: { error: "invalid_age_gate_result" } };
  }
  if (input.body.policy !== AGE_GATE_POLICY_VERSION) {
    return { status: 400, body: { error: "invalid_age_gate_policy" } };
  }
  const existing = readAgeGateRecord(input.user.app_metadata);
  const decision = decideAgeGateWrite(existing, requested, deps.now());
  if (decision.kind === "locked") {
    return {
      status: 409,
      body: { error: "AGE_GATE_LOCKED", ageGate: decision.record },
    };
  }
  if (decision.kind === "write") {
    const { error } = await deps.updateAppMetadata(input.user.id, {
      age_gate: decision.record,
    });
    if (error) {
      return { status: 500, body: { error: "age_gate_record_failed" } };
    }
  }
  return { status: 200, body: { ageGate: decision.record } };
}
