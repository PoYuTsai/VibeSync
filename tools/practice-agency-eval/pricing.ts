// 練習室黑箱評測的**單一定價來源**（Phase 4.5c）。
//
// 為什麼要有這支：Haiku 4.5 的四個單價原本同時散在三個地方——`run_agency.ts`
// 的 `estimateHaikuCostUsd`（USD／1K token）、README 各輪的成本外推、以及
// `scripts/practice_agency_telemetry.py` 的 `HAIKU_PRICE`（USD／1M token）。
// 三份數字漂掉的時候不會有任何測試變紅，只會讓兩份報告對同一批 usage 算出
// 不同金額。這支把 TypeScript 側的三處收成一份常數＋一支估價函式。
//
// **跨語言同步點（唯一，改動時兩邊都要改）**：
//   - 這個檔的 `HAIKU_4_5_PRICING`
//   - `scripts/practice_agency_telemetry.py` 的 `HAIKU_PRICE`
// 那支 Python 是 production telemetry 的唯讀監看腳本，不在本工具目錄下、也不
// import 這裡的常數（Deno ↔ Python 沒有共用來源），所以只能靠這條註解與
// README「Phase 4.5c 評測工具」節的說明維持一致。
//
// 單位一律是 **USD／1M token**（跟 Anthropic 官方牌價與那支 Python 同一個
// 口徑；舊的 USD／1K 寫法已經退掉，避免兩種單位並存時看錯一個數量級）。

/** 一個模型的四格 token 單價（USD／1M token）。 */
export interface TokenPricing {
  readonly inputPerMTok: number;
  readonly outputPerMTok: number;
  readonly cacheReadPerMTok: number;
  readonly cacheWritePerMTok: number;
}

/**
 * Anthropic 官方 prompt cache 的標準乘數：讀 0.1×base input、5 分鐘 ephemeral
 * 寫 1.25×base input。`supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS` 只有 input／output 兩格，沒有算這兩格。
 */
export const CACHE_READ_MULTIPLIER = 0.1;
export const CACHE_WRITE_MULTIPLIER = 1.25;

const withCacheTiers = (
  inputPerMTok: number,
  outputPerMTok: number,
): TokenPricing => ({
  inputPerMTok,
  outputPerMTok,
  cacheReadPerMTok: inputPerMTok * CACHE_READ_MULTIPLIER,
  cacheWritePerMTok: inputPerMTok * CACHE_WRITE_MULTIPLIER,
});

/**
 * Haiku 4.5（`claude-haiku-4-5-20251001`）：input $1／M、output $5／M，
 * cache read $0.10／M、cache write $1.25／M（Anthropic 官方牌價，也是
 * `scripts/practice_agency_telemetry.py` 的 `HAIKU_PRICE` 用的那一組）。
 *
 * **已知不一致（Phase 4.5c 發現，本輪不改 production）**：
 * `supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS["claude-haiku-4-5-20251001"]` 是 $0.0008／$0.004 每 1K token
 * ＝ $0.80／$4.00 每 M，比官方牌價低 20%（那是 Haiku 3.5 的價）。
 * `run_agency.ts` 之前抄的是 logger.ts 那一組，所以 README 4.3／4.4／4.5b 各節
 * 記的 Anthropic 金額是**低估約 20%**（例如 4.5b 的 $1.6608 實際約 $2.08）。
 * 這裡改吃官方牌價、跟那支 Python 對齊；logger.ts 屬於 production Edge
 * Function，不在本輪授權範圍，只記錄不改。
 */
export const HAIKU_4_5_PRICING: TokenPricing = withCacheTiers(1, 5);

/**
 * Sonnet 5（`claude-sonnet-5`）：input $2／M、output $10／M，
 * 抄自 `supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS["claude-sonnet-5"]`（$0.002／$0.010 每 1K token，未 export）。
 * cache 兩格用同一組官方乘數推出來（$0.20／$2.50 每 M），跟 Haiku 同一條規則。
 * **待 Eric 補**：repo 裡只有 logger.ts 這一處記載，而同一張表的 Haiku 那格
 * 已經證實是過期價（見上），所以這組 $2／$10 也**沒有跟官方牌價對拍過**；
 * 真的要拿它報成本之前要先請 Eric 確認。
 *
 * 目前工具目錄只有 `hint_debrief_spotcheck.ts` 打 Sonnet，而它不估價；這格
 * 先放在這裡，等下一支要估 Sonnet 成本的工具直接吃，不要再抄第二份。
 */
export const SONNET_5_PRICING: TokenPricing = withCacheTiers(2, 10);

/** `callClaude` 的 `onUsage` 回呼形狀（四格 token 數）。 */
export interface TokenUsage {
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cacheReadInputTokens: number;
  readonly cacheCreationInputTokens: number;
}

/** 四格 token 數 × 四格單價 → USD。 */
export function estimateCostUsd(
  usage: TokenUsage,
  pricing: TokenPricing,
): number {
  return (
    (usage.inputTokens * pricing.inputPerMTok +
      usage.outputTokens * pricing.outputPerMTok +
      usage.cacheReadInputTokens * pricing.cacheReadPerMTok +
      usage.cacheCreationInputTokens * pricing.cacheWritePerMTok) / 1_000_000
  );
}
