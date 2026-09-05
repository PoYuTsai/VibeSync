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
// ── 涵蓋範圍（已知天花板）────────────────────────────────────────────────
// 只算 **chat 生成路徑的 Claude（Haiku 4.5）** 花費：那是唯一有 `onUsage`
// 回呼、拿得到四格 token 數的路徑。hint／debrief 走 `single_shot.ts`
// （Sonnet 5 → Haiku failover）目前**完全沒有 usage 回呼**，所以它們的花費
// 進不了這個累計；計畫本來就寫「提示與檢討不受保險絲影響」（它們沒有
// DeepSeek 退路），但也因此當日總額是**低估**的。要把那兩條也記進來得先把
// `onUsage` 穿到 `single_shot.ts`，那是另一包的事。
// DeepSeek 一律不算（保險絲保的是 Anthropic 帳單）。
import {
  estimateCostUsd,
  HAIKU_4_5_PRICING,
  type TokenUsage,
} from "../_shared/model_pricing.ts";
import { logWarn } from "./logger.ts";

/** 旗標名：數值（USD／日）；空／未設／非正數＝關。 */
export const COST_FUSE_ENV = "PRACTICE_COST_FUSE_DAILY_USD";
export const COST_FUSE_TABLE = "practice_chat_daily_cost";
export const COST_FUSE_RPC = "increment_practice_chat_daily_cost";

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
): Promise<number | null> {
  try {
    const { data, error } = await supabase
      .from(COST_FUSE_TABLE)
      .select("spent_usd")
      .eq("day", day)
      .maybeSingle();
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
    logWarn("practice_chat_cost_fuse_read_failed", {
      day,
      error: e instanceof Error ? e.message : String(e),
    });
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
 * 把本輪 Claude 花費累加進今天，回傳 `{ usd, before, after }`。
 * `before` 是**累加前**的總額（`after - usd`），呼叫端用
 * `before < budget <= after` 判斷「這一次剛好跨過門檻」→
 * `practice_chat_cost_fuse_blown` 一天恰好一筆。那個減法之所以可信，是因為
 * `after` 來自單一 statement 的 `ON CONFLICT DO UPDATE ... RETURNING`
 * （併發下不會兩個請求都看到同一個 before）。
 *
 * 估算金額為 0（這一輪沒打 Claude）＝完全不打 RPC；失敗一律回 null ＋ 一行 warn。
 */
export async function recordChatCost(
  supabase: CostFuseSupabaseClient,
  day: string,
  usage: TokenUsage,
): Promise<{ usd: number; before: number; after: number } | null> {
  const usd = estimateCostUsd(usage, HAIKU_4_5_PRICING);
  if (!(usd > 0)) return null;
  try {
    const { data, error } = await supabase.rpc(COST_FUSE_RPC, {
      p_day: day,
      p_usd: usd,
    });
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
    logWarn("practice_chat_cost_fuse_write_failed", {
      day,
      error: e instanceof Error ? e.message : String(e),
    });
    return null;
  }
}
