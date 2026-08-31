// ADMIN_V2 feature flag 與 shadow-read adapter（B0）。
// 不論旗標開關，回傳給呼叫端的永遠是 legacy 讀取結果，可見輸出不變；
// 旗標開啟時額外跑新讀取並回報「匿名結構差異」：只有路徑與型別標籤，
// 永不包含 email、user id、原文或任何欄位值。關旗標即回滾，不需刪 schema。

export function isAdminV2Enabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  const value = env.ADMIN_V2?.trim().toLowerCase();
  return value === "1" || value === "true";
}

export interface ShadowDiff {
  equal: boolean;
  /** 例如 "$.items[]: string vs number"、"$.total: value-mismatch"。 */
  mismatches: string[];
}

export interface ShadowReadResult<T> {
  /** 一律是 legacy 結果。 */
  value: T;
  /** 旗標關閉時為 null。 */
  shadow: ShadowDiff | null;
}

const MAX_MISMATCHES = 20;
const MAX_DEPTH = 6;

function typeTag(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function walk(a: unknown, b: unknown, path: string, depth: number, out: string[]): void {
  if (out.length >= MAX_MISMATCHES) return;
  const tagA = typeTag(a);
  const tagB = typeTag(b);
  if (tagA !== tagB) {
    out.push(`${path}: ${tagA} vs ${tagB}`);
    return;
  }
  if (depth >= MAX_DEPTH) return;
  if (tagA === "array") {
    const arrA = a as unknown[];
    const arrB = b as unknown[];
    if (arrA.length !== arrB.length) {
      out.push(`${path}: array-length ${arrA.length} vs ${arrB.length}`);
    }
    const shared = Math.min(arrA.length, arrB.length);
    for (let i = 0; i < shared; i += 1) {
      // 匿名化：索引一律寫成 []，避免差異報告洩漏列位置與筆數細節。
      walk(arrA[i], arrB[i], `${path}[]`, depth + 1, out);
    }
    return;
  }
  if (tagA === "object") {
    const objA = a as Record<string, unknown>;
    const objB = b as Record<string, unknown>;
    for (const key of new Set([...Object.keys(objA), ...Object.keys(objB)])) {
      if (!(key in objA)) out.push(`${path}.${key}: missing vs ${typeTag(objB[key])}`);
      else if (!(key in objB)) out.push(`${path}.${key}: ${typeTag(objA[key])} vs missing`);
      else walk(objA[key], objB[key], `${path}.${key}`, depth + 1, out);
      if (out.length >= MAX_MISMATCHES) return;
    }
    return;
  }
  // 同型別的純量：只記「值不同」，永不記值本身。
  if (a !== b) out.push(`${path}: value-mismatch`);
}

export function structuralDiff(legacy: unknown, next: unknown): ShadowDiff {
  const mismatches: string[] = [];
  walk(legacy, next, "$", 0, mismatches);
  return { equal: mismatches.length === 0, mismatches };
}

/**
 * 旗標關閉：只跑 legacy，完全不碰 nextRead。
 * 旗標開啟：仍回傳 legacy 結果，新讀取只用來產生匿名結構差異；
 * 新讀取失敗絕不影響可見輸出。
 */
export async function shadowRead<T>(
  legacyRead: () => Promise<T> | T,
  nextRead: () => Promise<unknown> | unknown,
  env: Record<string, string | undefined> = process.env,
): Promise<ShadowReadResult<T>> {
  const value = await legacyRead();
  if (!isAdminV2Enabled(env)) return { value, shadow: null };
  try {
    const next = await nextRead();
    return { value, shadow: structuralDiff(value, next) };
  } catch {
    return { value, shadow: { equal: false, mismatches: ["$: next-read-error"] } };
  }
}
