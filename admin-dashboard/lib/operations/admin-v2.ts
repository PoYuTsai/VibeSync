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
  /**
   * 只允許固定匿名 token：path 由 "$"、"[]"（陣列元素）、".{}"（物件欄位）組成，
   * 訊息只有 type tag、"value-mismatch"、"missing"、"array-length-mismatch"、
   * "diff-truncated"、"next-read-error"、"next-read-timeout"。
   * 永不含 object key、陣列長度、欄位值、email、user id 或原文。
   */
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
// ponytail: 節點預算同時界定寬度與計算時間；巨大 payload 需要更聰明的取樣時再升級。
const MAX_NODES = 2000;
const NEXT_READ_TIMEOUT_MS = 2000;

function typeTag(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

interface DiffState {
  mismatches: string[];
  nodes: number;
  truncated: boolean;
}

function walk(a: unknown, b: unknown, path: string, depth: number, state: DiffState): void {
  if (state.truncated) return;
  if (state.mismatches.length >= MAX_MISMATCHES) {
    // 還有沒看完的節點也算截斷；equal 因已有 mismatch 本來就是 false。
    state.truncated = true;
    return;
  }
  state.nodes += 1;
  if (state.nodes > MAX_NODES) {
    state.truncated = true;
    return;
  }
  const tagA = typeTag(a);
  const tagB = typeTag(b);
  if (tagA !== tagB) {
    state.mismatches.push(`${path}: ${tagA} vs ${tagB}`);
    return;
  }
  if (tagA === "array") {
    if (depth >= MAX_DEPTH) {
      state.truncated = true;
      return;
    }
    const arrA = a as unknown[];
    const arrB = b as unknown[];
    if (arrA.length !== arrB.length) {
      // 只記「長度不同」，不記精確長度。
      state.mismatches.push(`${path}: array-length-mismatch`);
    }
    const shared = Math.min(arrA.length, arrB.length);
    for (let i = 0; i < shared; i += 1) {
      // 匿名化：索引一律寫成 []。
      walk(arrA[i], arrB[i], `${path}[]`, depth + 1, state);
      if (state.truncated) return;
    }
    return;
  }
  if (tagA === "object") {
    if (depth >= MAX_DEPTH) {
      state.truncated = true;
      return;
    }
    const objA = a as Record<string, unknown>;
    const objB = b as Record<string, unknown>;
    // 匿名化：key 一律寫成 {}；key 本身可能是 email/user id 等動態值，永不進報告。
    const anonPath = `${path}.{}`;
    // 不先 Object.keys、不配置全寬 Set：逐 key 迭代並對每個 key 收節點預算，
    // 超寬物件在預算內就截斷，寬度與工作量真正受 MAX_NODES 硬上限控制。
    // 第一趟走 A 的 key（共有 key 在此比對，A 多出的記 missing）。
    for (const key in objA) {
      if (!Object.hasOwn(objA, key)) continue;
      if (state.truncated || state.mismatches.length >= MAX_MISMATCHES) {
        state.truncated = true;
        return;
      }
      if (!Object.hasOwn(objB, key)) {
        state.nodes += 1;
        if (state.nodes > MAX_NODES) {
          state.truncated = true;
          return;
        }
        state.mismatches.push(`${anonPath}: ${typeTag(objA[key])} vs missing`);
      } else {
        walk(objA[key], objB[key], anonPath, depth + 1, state);
        if (state.truncated) return;
      }
    }
    // 第二趟只找 B 多出的 key；共有 key 已在第一趟收過預算，此處跳過的數量
    // 因此也被第一趟的預算間接限制住，不會變成無上限掃描。
    for (const key in objB) {
      if (!Object.hasOwn(objB, key) || Object.hasOwn(objA, key)) continue;
      if (state.truncated || state.mismatches.length >= MAX_MISMATCHES) {
        state.truncated = true;
        return;
      }
      state.nodes += 1;
      if (state.nodes > MAX_NODES) {
        state.truncated = true;
        return;
      }
      state.mismatches.push(`${anonPath}: missing vs ${typeTag(objB[key])}`);
    }
    return;
  }
  // 同型別的純量：只記「值不同」，永不記值本身。
  if (a !== b) state.mismatches.push(`${path}: value-mismatch`);
}

export function structuralDiff(legacy: unknown, next: unknown): ShadowDiff {
  const state: DiffState = { mismatches: [], nodes: 0, truncated: false };
  walk(legacy, next, "$", 0, state);
  // 截斷（深度／節點預算／mismatch 上限）代表沒看完，絕不可宣稱 equal。
  if (state.truncated && state.mismatches.length === 0) {
    state.mismatches.push("$: diff-truncated");
  }
  return { equal: !state.truncated && state.mismatches.length === 0, mismatches: state.mismatches };
}

const NEXT_READ_TIMED_OUT = Symbol("next-read-timed-out");

// 超時只接受有限正數，且不得高於 NEXT_READ_TIMEOUT_MS 上限；其餘壞值一律退回預設。
function clampNextReadTimeout(raw: unknown): number {
  return typeof raw === "number" && Number.isFinite(raw) && raw > 0
    ? Math.min(raw, NEXT_READ_TIMEOUT_MS)
    : NEXT_READ_TIMEOUT_MS;
}

/**
 * 旗標關閉：只跑 legacy，完全不碰 nextRead。
 * 旗標開啟：仍回傳 legacy 結果，新讀取只用來產生匿名結構差異；
 * 新讀取失敗或超時絕不影響可見輸出，legacy value 永遠先保住。
 *
 * 呼叫契約：Promise race 只能保護「非同步等待」，無法中止已在跑的同步 CPU；
 * nextRead 不得包進不受信任的同步重運算，同步部分必須自行保持 O(1) 起手、
 * 把真正的工作放在 await 之後。
 */
export async function shadowRead<T>(
  legacyRead: () => Promise<T> | T,
  nextRead: () => Promise<unknown> | unknown,
  env: Record<string, string | undefined> = process.env,
  options: { nextReadTimeoutMs?: number } = {},
): Promise<ShadowReadResult<T>> {
  const value = await legacyRead();
  if (!isAdminV2Enabled(env)) return { value, shadow: null };
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeoutMs = clampNextReadTimeout(options.nextReadTimeoutMs);
    const nextPromise = Promise.resolve().then(nextRead);
    // 超時後才失敗的新讀取不得變成 unhandled rejection。
    nextPromise.catch(() => {});
    const next = await Promise.race([
      nextPromise,
      new Promise<typeof NEXT_READ_TIMED_OUT>((resolve) => {
        timer = setTimeout(() => resolve(NEXT_READ_TIMED_OUT), timeoutMs);
      }),
    ]);
    if (next === NEXT_READ_TIMED_OUT) {
      return { value, shadow: { equal: false, mismatches: ["$: next-read-timeout"] } };
    }
    return { value, shadow: structuralDiff(value, next) };
  } catch {
    return { value, shadow: { equal: false, mismatches: ["$: next-read-error"] } };
  } finally {
    clearTimeout(timer);
  }
}
