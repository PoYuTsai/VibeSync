// B2：ADMIN_V2 開啟時的 metadata-only feedback 分流契約。
// 純函式、零外部依賴：旗標解析、redaction 與 RPC 參數組裝都在這裡，
// index.ts 只負責接線。旗標關閉時 index.ts 完全不會呼叫本檔的組裝函式，
// legacy 行為一比一不變。
//
// V2 分流原則：傳入的 conversationSnippet 與 aiResponse 一律忽略丟棄；
// 只保存 category、短描述（summary，200 字上限）、request ref 與 safe
// metadata。email 與 JWT/base64-JSON 樣式在 TS 先 redact，DB CHECK 是第二道
// 防線（inbox 的 summary CHECK 拒 '@' 與 'eyJ'）。

export const FEEDBACK_SUMMARY_MAX_LENGTH = 200;

/** 與 admin-dashboard/lib/operations/admin-v2.ts 的 isAdminV2Enabled 同語意。 */
export function isAdminV2FeedbackEnabled(
  value: string | null | undefined,
): boolean {
  const normalized = value?.trim().toLowerCase();
  return normalized === "1" || normalized === "true";
}

// email／任何含 '@' 的 token（IG handle 等）與 eyJ 開頭的 JWT/base64-JSON
// 樣式全部換成固定占位；寧可多刪，不可留下可識別資訊。
const AT_TOKEN_RE = /\S*@+\S*/g;
const JWT_LIKE_RE = /eyJ[A-Za-z0-9_.-]*/g;

/** 短描述：redact 後以「字元」截斷（不切壞 surrogate pair），空值回 undefined。 */
export function redactFeedbackSummary(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const redacted = value
    .replace(AT_TOKEN_RE, "[redacted]")
    .replace(JWT_LIKE_RE, "[redacted]")
    .trim();
  if (!redacted) return undefined;
  return [...redacted].slice(0, FEEDBACK_SUMMARY_MAX_LENGTH).join("");
}

// inbox 的 user_tier CHECK 是 '^[a-z][a-z0-9_]{0,49}$'：先正規化成小寫
// snake_case，過不了 pattern 就整個丟棄（寧缺勿錯，避免 RPC 因 CHECK 失敗
// 讓使用者看到 500）。
export function sanitizeUserTier(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return /^[a-z][a-z0-9_]{0,49}$/.test(normalized) ? normalized : undefined;
}

/** inbox 的 model_used CHECK 同源：過不了 pattern 就丟棄。 */
export function sanitizeModelUsed(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return /^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,119}$/.test(normalized)
    ? normalized
    : undefined;
}

export interface FeedbackV2RpcParams {
  p_user_ref: string;
  p_request_ref: string;
  p_rating: string;
  p_category: string | null;
  p_summary: string | null;
  p_user_tier: string | null;
  p_model_used: string | null;
}

/**
 * 冪等鍵素材：由「使用者＋原始請求內容」決定，重試（逾時後重按送出同一
 * payload）必得相同 request_ref → inbox UNIQUE 去重、不重複通知；不同回饋
 * （不同訊息的 aiResponse、不同留言）內容不同 → 不同 ref。JSON 陣列序列化
 * 保證欄位邊界無歧義；素材本身不落地，DB 只存其 sha256（不可逆）。
 * conversationSnippet／aiResponse 只進雜湊用來區分請求，永不儲存。
 */
export function buildFeedbackRequestKey(input: {
  userId: string;
  rating: string;
  category?: string;
  comment?: unknown;
  conversationSnippet?: unknown;
  aiResponse?: unknown;
  userTier?: unknown;
  modelUsed?: unknown;
}): string {
  return JSON.stringify([
    "feedback-v2",
    input.userId,
    input.rating,
    input.category ?? null,
    typeof input.comment === "string" ? input.comment : null,
    typeof input.conversationSnippet === "string"
      ? input.conversationSnippet
      : null,
    input.aiResponse === undefined
      ? null
      : JSON.stringify(input.aiResponse) ?? null,
    typeof input.userTier === "string" ? input.userTier : null,
    typeof input.modelUsed === "string" ? input.modelUsed : null,
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
 * 組 admin_v2_submit_feedback 的 RPC 參數。輸出參數表上根本沒有
 * conversationSnippet 與 aiResponse（結構上進不來）；它們只餵進
 * buildFeedbackRequestKey 的雜湊素材。user_ref 與 request_ref 都是不可逆
 * sha256 短參照；同一 payload 重試必得同一 request_ref（冪等）。
 */
export async function buildFeedbackV2RpcParams(input: {
  userId: string;
  rating: string;
  category?: string;
  comment?: unknown;
  conversationSnippet?: unknown;
  aiResponse?: unknown;
  userTier?: unknown;
  modelUsed?: unknown;
}): Promise<FeedbackV2RpcParams> {
  const [userHex, requestHex] = await Promise.all([
    sha256Hex(input.userId),
    sha256Hex(buildFeedbackRequestKey(input)),
  ]);
  return {
    p_user_ref: `user:sha256:${userHex}`,
    p_request_ref: `request:sha256:${requestHex}`,
    p_rating: input.rating,
    p_category: input.category ?? null,
    p_summary: redactFeedbackSummary(input.comment) ?? null,
    p_user_tier: sanitizeUserTier(input.userTier) ?? null,
    p_model_used: sanitizeModelUsed(input.modelUsed) ?? null,
  };
}
