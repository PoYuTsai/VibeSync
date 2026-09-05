// 練習室成本保險絲（Phase 5 WP2）：Anthropic 當日花費超標時強制退回 DeepSeek。
//
// 設計來源：docs/plans/2026-09-05-practice-room-phase5-plan.md §4 WP2、§2 D8。
//
// ── 三條鐵則 ──────────────────────────────────────────────────────────────
// 1. **燒斷是降級不是報錯**：`shouldDegrade` 為真只改 `chatModelFor` 的結果，
//    不進任何 throw 路徑。
// 2. **DB 讀寫失敗一律 fail-open**：當成沒燒斷、記一行 warn 就繼續。保險絲
//    壞掉的代價是多花錢，不是對話失敗（計畫 §7 風險 1）。
// 3. **旗標留空＝零 DB 讀寫**：`parseCostFuseBudget` 回 null 時 handler 連
//    select 都不發，四面（messages／response／rpc／telemetry）逐位元組等於
//    接線前（`agency_flag_off_equivalence_test.ts` 釘住）。
//
// ── 涵蓋範圍 ──────────────────────────────────────────────────────────────
// 算 **整個 practice-chat 的 Anthropic 花費**：chat 生成路徑的 Haiku 4.5，
// 加上 hint／debrief 走 `single_shot.ts` 的 Sonnet 5 → Haiku 4.5（Codex R1
// P1：需求是「Anthropic 當日花費」，不是只有 chat）。DeepSeek 一律不算。
//
// **降級只發生在 chat 輪**：hint／debrief 沒有 DeepSeek 退路，燒斷後仍照舊打
// Sonnet，只是它們的花費會被記進當日累計，把 chat 更快壓進降級。
//
// ── 已知天花板（Codex R1 判過、Eric 接受，不修）──────────────────────────
// 1. **讀取與准入不原子**：每一輪是「先 select 今天燒多少 → 決定要不要降級 →
//    打模型 → 事後累加」，中間沒有鎖。所有同時在途的請求都會讀到同一個
//    「還沒燒斷」，於是全部放行。**超支上限 ≈ 同時在途請求數 × 單輪 Anthropic
//    成本**（chat 一輪 Haiku 約 $0.002，一次檢討 Sonnet 約 $0.015）。
//    所以這是**粗護欄不是硬額度**：它保證的是「不會失控地一路燒下去」，
//    不是「當日不超過 N 美金」。真要硬額度得把准入也做成一次 RPC
//    （讀寫同一個 statement），那是另一包的事。
// 2. **`practice_chat_cost_fuse_blown` 一天一筆只在兩個前提下成立**：預算沒被
//    中途改過、而且累加 RPC 的**回應真的送達**。預算調高之後會再跨一次門檻 →
//    再寫一筆；RPC 已提交但回應遺失（逾時／連線斷）那一次就會缺一筆。
//    它只是 telemetry——**當日花費的真相是 `practice_chat_daily_cost` 表**，
//    對帳要查表，不要數這個事件。
// 3. **UTC 日以請求開始時間（`requestNow`）固定**：跨午夜的那一輪整輪記在
//    前一天。單輪金額相對日預算是小數，刻意不為了這個多帶一次時鐘。
import {
  estimateCostUsd,
  HAIKU_4_5_PRICING,
  SONNET_5_PRICING,
  type TokenUsage,
} from "../_shared/model_pricing.ts";
import { CLAUDE_SONNET_MODEL } from "./claude.ts";
import { logWarn } from "./logger.ts";

/** 旗標名：數值（USD／日）；空／未設／非正數＝關。 */
export const COST_FUSE_ENV = "PRACTICE_COST_FUSE_DAILY_USD";
export const COST_FUSE_TABLE = "practice_chat_daily_cost";
export const COST_FUSE_RPC = "increment_practice_chat_daily_cost";

/**
 * DB 逾時（Codex R2 P1）。保險絲是護欄，不能反過來拖垮它保護的請求：
 * 讀是每一輪 chat 的前置（擋在模型呼叫前面），寫是回應前的最後一步，
 * 所以讀給得比寫緊。逾時＝失敗＝fail-open（當成沒燒斷、只 warn）。
 */
export const COST_FUSE_READ_TIMEOUT_MS = 1_500;
export const COST_FUSE_WRITE_TIMEOUT_MS = 2_500;

/**
 * 給一個 promise 加死線。逾時就 reject（呼叫端一律走既有的 fail-open catch）。
 * `clearTimeout` 放在 `finally`：不清掉的話 Deno 的測試 timer sanitizer 會紅，
 * production 也會多留一個沒用的 timer 到期。
 */
async function withDeadline<T>(
  work: Promise<T>,
  timeoutMs: number,
): Promise<T> {
  let handle: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<never>((_resolve, reject) => {
        handle = setTimeout(
          () => reject(new Error("cost_fuse_timeout")),
          timeoutMs,
        );
      }),
    ]);
  } finally {
    if (handle !== undefined) clearTimeout(handle);
  }
}

/** supabase 的 select／rpc 共同回傳形狀。 */
interface CostFuseDbResult {
  data: unknown;
  error: { message: string } | null;
}

/** cost_fuse 只用得到 supabase client 的這兩支（避免跟 handler 循環 import）。 */
export interface CostFuseSupabaseClient {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(
    fn: string,
    params: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

/**
 * 旗標字串 → 每日預算（USD）。空／未設／非正數／非數字一律 null＝保險絲關。
 * fail-closed 的方向刻意是「關」而不是「開」：亂填一個值不該讓所有人被降級。
 */
export function parseCostFuseBudget(raw: string | undefined): number | null {
  if (raw === undefined) return null;
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  const value = Number(trimmed);
  if (!Number.isFinite(value) || value <= 0) return null;
  return value;
}

/** 到達門檻就算燒斷（`>=`）：預算是上限，不是「超過才算」。 */
export function shouldDegrade(
  spentUsdToday: number,
  budgetUsd: number,
): boolean {
  return spentUsdToday >= budgetUsd;
}

/**
 * 累計用的日界是 **UTC 日**。保險絲是成本護欄不是報表：跨日在哪個時區切不影響
 * 「一天燒不超過 N 美金」，用 UTC 可以免掉時區換算這個額外的出錯面。
 */
export function utcDay(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/** 髒值（null／字串亂碼／NaN）一律當成讀不到。 */
function finiteNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

/**
 * 今天已經燒掉多少（USD）。沒有列＝0；**讀不到一律回 null**，呼叫端據此
 * fail-open（當成沒燒斷）。
 */
export async function readSpentUsdToday(
  supabase: CostFuseSupabaseClient,
  day: string,
  /** 逾時（不是一般 DB 錯誤）時響一次，供呼叫端記 telemetry。 */
  onTimeout?: () => void,
): Promise<number | null> {
  try {
    // `from()` 是 `any`（PracticeSupabaseClient 的既有形狀），所以泛型要明寫。
    const { data, error } = await withDeadline<CostFuseDbResult>(
      supabase
        .from(COST_FUSE_TABLE)
        .select("spent_usd")
        .eq("day", day)
        .maybeSingle(),
      COST_FUSE_READ_TIMEOUT_MS,
    );
    if (error) {
      logWarn("practice_chat_cost_fuse_read_failed", {
        day,
        error: error.message,
      });
      return null;
    }
    if (data === null || data === undefined) return 0;
    // PostgREST 的 numeric 可能回字串。
    const spent = finiteNumber((data as { spent_usd?: unknown }).spent_usd);
    if (spent === null) {
      logWarn("practice_chat_cost_fuse_read_failed", {
        day,
        error: "invalid_spent_usd",
      });
      return null;
    }
    return spent;
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (message === "cost_fuse_timeout") onTimeout?.();
    logWarn("practice_chat_cost_fuse_read_failed", { day, error: message });
    return null;
  }
}

/** RPC 回傳可能是純量、單元素陣列、或單欄物件（PostgREST 三種形狀）。 */
function scalarFromRpc(data: unknown): number | null {
  const first = Array.isArray(data) ? data[0] : data;
  if (first !== null && typeof first === "object") {
    const values = Object.values(first as Record<string, unknown>);
    return values.length === 1 ? finiteNumber(values[0]) : null;
  }
  return finiteNumber(first);
}

/**
 * 一次 Anthropic 呼叫的估算花費（USD）。`model` 決定吃哪一組單價：
 * Sonnet 5 走 `SONNET_5_PRICING`，其餘（practice-chat 只會是 Haiku 4.5）走
 * `HAIKU_4_5_PRICING`。單價本體在 `_shared/model_pricing.ts`。
 */
export function anthropicCostUsd(usage: TokenUsage, model: string): number {
  return estimateCostUsd(
    usage,
    model === CLAUDE_SONNET_MODEL ? SONNET_5_PRICING : HAIKU_4_5_PRICING,
  );
}

/**
 * 把本請求付掉的 Anthropic 花費累加進今天，回傳 `{ usd, before, after }`。
 * `before` 是**累加前**的總額（`after - usd`），呼叫端用
 * `before < budget <= after` 判斷「這一次剛好跨過門檻」→
 * `practice_chat_cost_fuse_blown` 一天恰好一筆。那個減法之所以可信，是因為
 * `after` 來自單一 statement 的 `ON CONFLICT DO UPDATE ... RETURNING`
 * （併發下不會兩個請求都看到同一個 before）。
 *
 * `usd <= 0`（這一輪沒打 Anthropic）＝完全不打 RPC；失敗一律回 null ＋ 一行 warn。
 */
export async function recordAnthropicCost(
  supabase: CostFuseSupabaseClient,
  day: string,
  usd: number,
  /** 逾時（不是一般 DB 錯誤）時響一次，供呼叫端記 telemetry。 */
  onTimeout?: () => void,
): Promise<{ usd: number; before: number; after: number } | null> {
  if (!(usd > 0)) return null;
  try {
    const { data, error } = await withDeadline(
      supabase.rpc(COST_FUSE_RPC, { p_day: day, p_usd: usd }),
      COST_FUSE_WRITE_TIMEOUT_MS,
    );
    if (error) {
      logWarn("practice_chat_cost_fuse_write_failed", {
        day,
        error: error.message,
      });
      return null;
    }
    const after = scalarFromRpc(data);
    if (after === null) {
      logWarn("practice_chat_cost_fuse_write_failed", {
        day,
        error: "invalid_rpc_result",
      });
      return null;
    }
    return { usd, before: after - usd, after };
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (message === "cost_fuse_timeout") onTimeout?.();
    logWarn("practice_chat_cost_fuse_write_failed", { day, error: message });
    return null;
  }
}
