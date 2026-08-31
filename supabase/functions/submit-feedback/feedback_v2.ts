// B2：ADMIN_V2 開啟時的 metadata-only feedback 分流契約。
// 純函式、零外部依賴：旗標解析、client idempotency key 與 RPC 參數組裝都在
// 這裡；index.ts 只負責接線。旗標關閉時 index.ts 完全不會呼叫本檔的組裝
// 函式，legacy 行為一比一不變。
//
// V2 僅保存固定 enum／短 metadata 與不可逆參照。任何留言、對話片段、AI
// 回應或其他自由文字都不屬於本檔的輸入型別，因此不能進資料庫、通知內容或
// request_ref 的雜湊素材。

/**
 * client 端必須產生 UUID v4/v7 idempotency key。固定成 UUID 而非「任意
 * 看似不透明字串」，避免使用者文字或其可讀編碼被拿來衍生 request_ref。
 */
export const CLIENT_REQUEST_KEY_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** 與 admin-dashboard/lib/operations/admin-v2.ts 的 isAdminV2Enabled 同語意。 */
export function isAdminV2FeedbackEnabled(
  value: string | null | undefined,
): boolean {
  const normalized = value?.trim().toLowerCase();
  return normalized === "1" || normalized === "true";
}

/**
 * V2 一律要求 client 明確帶 UUID v4/v7 idempotency key；不接受任意文字或
 * 其可讀編碼，避免那些內容被拿來衍生 request_ref。
 */
export function normalizeClientRequestKey(value: unknown): string | undefined {
  return typeof value === "string" && CLIENT_REQUEST_KEY_PATTERN.test(value)
    ? value
    : undefined;
}

/** V2 只留下已知訂閱層級，不把任意 client 字串當 metadata 保存。 */
export const FEEDBACK_USER_TIERS = [
  "free",
  "starter",
  "essential",
  "premium",
  "other",
] as const;

/** V2 只記 provider family，不保存使用者傳來的模型文字或版本字串。 */
export const FEEDBACK_MODEL_FAMILIES = [
  "anthropic",
  "deepseek",
  "zai",
  "other",
] as const;

export function sanitizeUserTier(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase();
  return (FEEDBACK_USER_TIERS as readonly string[]).includes(normalized)
    ? normalized
    : "other";
}

/** 將 app 控制的模型識別子收斂成固定 provider family，永不保存原字串。 */
export function sanitizeModelUsed(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase();
  if (!normalized) return undefined;
  if (normalized.startsWith("claude-")) return "anthropic";
  if (normalized.startsWith("deepseek-")) return "deepseek";
  if (normalized.startsWith("zai") || normalized.startsWith("glm-")) return "zai";
  return "other";
}

export interface FeedbackV2RpcParams {
  p_user_ref: string;
  p_request_ref: string;
  p_rating: string;
  p_category: string | null;
  p_user_tier: string | null;
  p_model_used: string | null;
}

/**
 * idempotency material 只包含 stable user id 與受格式約束的 client key。
 * 同一個 key 可安全重試；不同 key 即使 metadata 完全相同也會形成新提交。
 */
export function buildFeedbackRequestKey(input: {
  userId: string;
  clientRequestKey: string;
}): string {
  return JSON.stringify([
    "feedback-v2-request",
    input.userId,
    input.clientRequestKey,
  ]);
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * 組 admin_v2_submit_feedback 的 allowlist RPC 參數。兩個參照皆不可逆，且
 * request_ref 只由 client idempotency key 決定，沒有任何自由文字來源。
 */
export async function buildFeedbackV2RpcParams(input: {
  userId: string;
  clientRequestKey: string;
  rating: string;
  category?: string;
  userTier?: unknown;
  modelUsed?: unknown;
}): Promise<FeedbackV2RpcParams> {
  const [userHex, requestHex] = await Promise.all([
    sha256Hex(`feedback-v2-user:${input.userId}`),
    sha256Hex(buildFeedbackRequestKey(input)),
  ]);
  return {
    p_user_ref: `user:sha256:${userHex}`,
    p_request_ref: `request:sha256:${requestHex}`,
    p_rating: input.rating,
    p_category: input.category ?? null,
    p_user_tier: sanitizeUserTier(input.userTier) ?? null,
    p_model_used: sanitizeModelUsed(input.modelUsed) ?? null,
  };
}
