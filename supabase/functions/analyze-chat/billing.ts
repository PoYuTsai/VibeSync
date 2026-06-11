// supabase/functions/analyze-chat/billing.ts
//
// ADR #19 r3（規格凍結 @ ad10718 + 4000 字補遺）— analyze-chat 全對話字數
// 合併計費。本模組是純函式層：不打 DB、不打網路，所有 I/O（確認回應、
// idempotency claim、log）由 index.ts 負責。
//
// 分段帶（整數閉區間，作用對象 = 本次「計費字數」billableChars，
// 即 baseline 扣除後的字數差；定案 #7：soft_cap 每次分析各自算）：
//   1~40        → 1 則
//   41~400      → ceil(chars/40) = 2~10 則
//   401~2000    → 一律 10 則（緩衝帶）
//   2001~4000   → 固定 20 則，新 client 需確認（乙案）；legacy → cap 10 + log
//   4001+       → reject「內容過長，請分批分析」，不扣費，新舊 client 一視同仁
//
// 字數定義（r2 規格 #4，本輪不重開）：
// - UTF-16 code units（JS `String.length` ≡ Dart `String.length`）。
// - 計算對象 = sanitized + trim 後的 payload `content`。
// - 不做 NFC/NFD normalization、不移除 zero-width，零寬字元照算。
// - `quotedReplyPreview` 不入字數池（規格 #7）。
// - Dart 鏡像：`lib/core/services/message_calculator.dart`，mirror tests
//   共用同一組字串樣本，兩端結果必須一致。
//
// Capability contract（定案 #6 / Codex r3-P1-1）：
// - 新 client 所有 analyze 請求必送 `billingProtocolVersion: 3`。
// - 「舊 client」定義 = 無 capability 訊號的請求，僅此類走 legacy ruleset。
// - baseline 推導層級（previousAnalyzedCharCount / previousAnalyzedCount）
//   與 ruleset 正交：欄位決定 baseline，capability 決定規則。

export const CHARS_PER_MESSAGE_UNIT = 40;
export const SOFT_CAP_UNITS = 10;
export const SOFT_CAP_BAND_MAX_CHARS = 2000;
export const OVERCHARGE_UNITS = 20;
export const MAX_BILLABLE_CHARS = 4000;
export const BILLING_PROTOCOL_VERSION = 3;

/// 單一字數 helper（規格 #8）：billing 與任何 server-side 估算都必須走這裡。
export function countPayloadChars(
  messages: Array<{ content: string }>,
): number {
  let total = 0;
  for (const msg of messages) {
    total += msg.content.trim().length;
  }
  return total;
}

export type BillingBand =
  | { band: "standard"; units: number }
  | { band: "overcharge"; units: number }
  | { band: "reject" };

/**
 * 分段帶查表（兩端鏡像；Dart 鏡像必須同此閉區間）。
 * 0 字 → floor 1：「每按一次分析，最少扣 1 則」（r2 已知接受，有成本基礎）。
 */
export function bandForBillableChars(chars: number): BillingBand {
  if (chars > MAX_BILLABLE_CHARS) {
    return { band: "reject" };
  }
  if (chars > SOFT_CAP_BAND_MAX_CHARS) {
    return { band: "overcharge", units: OVERCHARGE_UNITS };
  }
  return {
    band: "standard",
    units: Math.min(
      SOFT_CAP_UNITS,
      Math.max(1, Math.ceil(chars / CHARS_PER_MESSAGE_UNIT)),
    ),
  };
}

export type BillingPath =
  /** 新欄位 previousAnalyzedCharCount 直接當 baseline。 */
  | "char_baseline"
  /** 舊欄位 previousAnalyzedCount：用 payload 前 N 則推回 baseline。 */
  | "legacy_count_derived"
  /**
   * 舊 client 長對話摘要壓縮（Codex r2 P1）：N > payload.length 且帶
   * conversationSummary/clipped 訊號是合法路徑，user-safe 只扣 floor 1。
   * 定案 #6b（Codex r3-P1-2）：此路徑永遠 floor 1，不被任何 cap 覆蓋。
   */
  | "legacy_count_exceeds_payload_clipped"
  /** N 越界 / 非數字且無 clipped 訊號：全額計費 + caller log 告警。 */
  | "legacy_invalid_full"
  /** 完全沒有 baseline（首次分析或欄位缺失）：全額計費。 */
  | "full_no_baseline";

export type BillingOutcome =
  /** 直接扣 chargedMessageCount。 */
  | "charge"
  /**
   * 新 client 2001~4000 確認帶：無有效確認 → index.ts 回
   * OVERCHARGE_CONFIRMATION_REQUIRED 不扣費；有效確認 → 扣 20（idempotent）。
   */
  | "requires_confirmation"
  /** 4001+：reject「內容過長，請分批分析」，不扣費。 */
  | "reject_too_long";

export interface BillingResolution {
  outcome: BillingOutcome;
  /** charge / requires_confirmation 時的則數；reject 時為 0。 */
  chargedMessageCount: number;
  /** 本次計費字數 = totalChars - baselineChars（≥ 0）。 */
  billableChars: number;
  billingPath: BillingPath;
  totalChars: number;
  baselineChars: number;
  /** 無 billingProtocolVersion 訊號 = 舊 client（定案 #6）。 */
  isLegacyClient: boolean;
  /** true → caller 必須 log `legacy_over2000_capped`（定案 #6c）。 */
  legacyOver2000Capped: boolean;
}

/**
 * ADR #19 規格 #1（r2 保留）+ r3 分段帶/capability/precedence。
 *
 * 安全前提（規格 #5）：server 先部署時，舊 client 只送 previousAnalyzedCount，
 * 必須走推導式 fallback 只扣字數差；「缺新欄位即整段全額」已於 Codex r1 否決。
 *
 * `previousAnalyzedCharCount` / `billingProtocolVersion` 由 index.ts 先驗證
 * （非法值 400），進到這裡只會是 undefined 或合法值。
 * `previousAnalyzedCount` 維持對舊 client 寬容：非法值不 400，降級為
 * 全額計費並由 caller log 告警。
 */
export function resolveBilling({
  messages,
  billingProtocolVersion,
  previousAnalyzedCharCount,
  previousAnalyzedCount,
  hasClippedContextSignal,
}: {
  messages: Array<{ content: string }>;
  billingProtocolVersion?: number;
  previousAnalyzedCharCount?: number;
  previousAnalyzedCount?: unknown;
  hasClippedContextSignal: boolean;
}): BillingResolution {
  const totalChars = countPayloadChars(messages);
  const isLegacyClient = billingProtocolVersion == null;

  // --- Baseline 三層 fallback（r2 規格 #1，與 ruleset 正交） ---
  let baselineChars: number;
  let billingPath: BillingPath;

  if (previousAnalyzedCharCount != null) {
    // 第一層：字數 baseline。clipped payload 可能讓 baseline 大於本次
    // payload 總字數（diff 為負），clamp 後走 floor 1，user-safe。
    baselineChars = Math.min(
      Math.floor(previousAnalyzedCharCount),
      totalChars,
    );
    billingPath = "char_baseline";
  } else if (previousAnalyzedCount != null) {
    // 第二層：舊欄位訊息數 baseline → 推回字數差。
    const n = previousAnalyzedCount;
    if (
      typeof n === "number" && Number.isInteger(n) && n >= 0 &&
      n <= messages.length
    ) {
      baselineChars = countPayloadChars(messages.slice(0, n));
      billingPath = "legacy_count_derived";
    } else if (
      typeof n === "number" && Number.isInteger(n) && n > messages.length &&
      hasClippedContextSignal
    ) {
      // 舊 client 摘要壓縮後 requestMessages 只剩近段但 N 是全量計數，
      // 不是越界攻擊。baseline = 當次 payload 全字數 → 只扣 floor 1。
      baselineChars = totalChars;
      billingPath = "legacy_count_exceeds_payload_clipped";
    } else {
      // N 非整數 / 負數 / 越界且無 clipped 訊號 → 全額 + caller log 告警。
      baselineChars = 0;
      billingPath = "legacy_invalid_full";
    }
  } else {
    // 第三層：無任何 baseline（首次分析）→ 全額。
    baselineChars = 0;
    billingPath = "full_no_baseline";
  }

  const billableChars = totalChars - baselineChars;

  // --- Legacy precedence (b)（定案 #6b / Codex r3-P1-2）---
  // clipped 合法路徑永遠 floor 1，先於任何分段帶 / cap / reject 判定。
  // billableChars 此時必為 0，4000 上限（作用在 billable chars）天然不觸發。
  if (billingPath === "legacy_count_exceeds_payload_clipped") {
    return {
      outcome: "charge",
      chargedMessageCount: 1,
      billableChars,
      billingPath,
      totalChars,
      baselineChars,
      isLegacyClient,
      legacyOver2000Capped: false,
    };
  }

  const band = bandForBillableChars(billableChars);

  // 4001+ 硬上限（補遺）：新舊 client 一視同仁 reject，不扣費。
  if (band.band === "reject") {
    return {
      outcome: "reject_too_long",
      chargedMessageCount: 0,
      billableChars,
      billingPath,
      totalChars,
      baselineChars,
      isLegacyClient,
      legacyOver2000Capped: false,
    };
  }

  if (band.band === "overcharge") {
    if (isLegacyClient) {
      // Legacy precedence (c)（定案 #6c）：舊 client 無法確認，
      // user-safe 以 soft_cap 10 收 + caller log `legacy_over2000_capped`。
      return {
        outcome: "charge",
        chargedMessageCount: SOFT_CAP_UNITS,
        billableChars,
        billingPath,
        totalChars,
        baselineChars,
        isLegacyClient,
        legacyOver2000Capped: true,
      };
    }
    return {
      outcome: "requires_confirmation",
      chargedMessageCount: band.units,
      billableChars,
      billingPath,
      totalChars,
      baselineChars,
      isLegacyClient,
      legacyOver2000Capped: false,
    };
  }

  return {
    outcome: "charge",
    chargedMessageCount: band.units,
    billableChars,
    billingPath,
    totalChars,
    baselineChars,
    isLegacyClient,
    legacyOver2000Capped: false,
  };
}

// ---------------------------------------------------------------------------
// 確認綁定（定案 #5 / Codex r3-P1-3 · 終審實作建議：hash 優先）
// ---------------------------------------------------------------------------

/**
 * 確認綁定 hash：SHA-256 hex，輸入 = trim 後的各則 content 以 U+0000 串接
 * 的 UTF-8 bytes。
 *
 * - 與計費字數同一組輸入（trim、不 normalize）→ client 可 byte-for-byte
 *   鏡像（Dart `package:crypto` sha256）。
 * - 刻意不用 conversation_hash.ts（它做 NFC normalize + 涵蓋非計費欄位，
 *   語義是「分析上下文是否漂移」；這裡語義是「用戶確認扣費的內容」）。
 * - U+0000 分隔避免訊息邊界歧義（["ab","c"] ≠ ["a","bc"]），且 U+0000
 *   不可能出現在 trim 後的合法訊息內容開頭/結尾。
 */
export async function computeBillingPayloadHash(
  messages: Array<{ content: string }>,
): Promise<string> {
  const joined = messages.map((msg) => msg.content.trim()).join("\u0000");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(joined),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export interface OverchargeConfirmation {
  payloadHash: string;
  billableChars: number;
  confirmationId: string;
}

/**
 * 新欄位嚴格驗證（與 previousAnalyzedCharCount 同策略：只有新 client 會送，
 * 非法值 400；舊欄位才寬容降級）。capability 訊號 = 整數且 ≥ 3：
 * 1/2 從未存在過，收到即視為畸形請求。
 */
export function parseBillingProtocolVersion(
  raw: unknown,
): { ok: true; value: number | undefined } | { ok: false } {
  if (raw == null) return { ok: true, value: undefined };
  if (
    typeof raw !== "number" || !Number.isInteger(raw) ||
    raw < BILLING_PROTOCOL_VERSION
  ) {
    return { ok: false };
  }
  return { ok: true, value: raw };
}

const PAYLOAD_HASH_PATTERN = /^[0-9a-f]{64}$/;
const MAX_CONFIRMATION_ID_LENGTH = 128;

export function parseConfirmedOvercharge(
  raw: unknown,
):
  | { ok: true; value: OverchargeConfirmation | undefined }
  | { ok: false } {
  if (raw == null) return { ok: true, value: undefined };
  if (typeof raw !== "object" || Array.isArray(raw)) return { ok: false };
  const record = raw as Record<string, unknown>;
  const { payloadHash, billableChars, confirmationId } = record;
  if (
    typeof payloadHash !== "string" || !PAYLOAD_HASH_PATTERN.test(payloadHash)
  ) {
    return { ok: false };
  }
  if (
    typeof billableChars !== "number" || !Number.isInteger(billableChars) ||
    billableChars <= 0
  ) {
    return { ok: false };
  }
  if (
    typeof confirmationId !== "string" || confirmationId.length === 0 ||
    confirmationId.length > MAX_CONFIRMATION_ID_LENGTH
  ) {
    return { ok: false };
  }
  return {
    ok: true,
    value: { payloadHash, billableChars, confirmationId },
  };
}

export type ConfirmationValidity = "valid" | "missing" | "mismatch";

/**
 * 確認有效性（定案 #5）：hash 必須綁定（內容不可變）+ billableChars 必須
 * 相符（用戶在確認框看到的數字必須正是實扣依據；mirror tests 保證兩端
 * 字數一致，不符即代表 client 計算或顯示有 bug，寧可重新確認）。
 * 不符 → caller 回新的 OVERCHARGE_CONFIRMATION_REQUIRED，絕不拿舊確認
 * 扣新內容。
 */
export function validateOverchargeConfirmation({
  confirmation,
  serverPayloadHash,
  serverBillableChars,
}: {
  confirmation: OverchargeConfirmation | undefined;
  serverPayloadHash: string;
  serverBillableChars: number;
}): ConfirmationValidity {
  if (!confirmation) return "missing";
  if (confirmation.payloadHash !== serverPayloadHash) return "mismatch";
  if (confirmation.billableChars !== serverBillableChars) return "mismatch";
  return "valid";
}
