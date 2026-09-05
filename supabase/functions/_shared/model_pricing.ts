// Anthropic 模型的 token 單價與估價函式——**TypeScript 側的唯一定價來源**。
//
// 為什麼放在 `_shared/` 而不是 `tools/`：Phase 4.5c 把單價收成一份時，唯一的
// 消費端是黑箱評測（`tools/practice-agency-eval/pricing.ts`）。Phase 5 WP2 的
// 成本保險絲要在 Edge Function 內估算當輪花費，而 Supabase 的 function 打包
// 只跟得到 `supabase/functions/` 底下的相對 import（practice-chat 既有的跨檔
// import 全部走 `../_shared/`，沒有一條跨出 `supabase/`）。所以常數搬到這裡，
// `tools/practice-agency-eval/pricing.ts` 改成 re-export——**唯一來源不變，
// 只是搬家**，兩邊相等由 `pricing_test.ts` 的 identity 斷言釘住。
//
// **跨語言同步點（唯一，改動時兩邊都要改）**：
//   - 這個檔的 `HAIKU_4_5_PRICING`
//   - `scripts/practice_agency_telemetry.py` 的 `HAIKU_PRICE`
// 那支 Python 是 production telemetry 的唯讀監看腳本，不 import 這裡的常數
// （Deno ↔ Python 沒有共用來源），只能靠這條註解維持一致。
//
// 單位一律是 **USD／1M token**（跟 Anthropic 官方牌價同一個口徑）。

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
 * **已知不一致（Phase 4.5c 發現，至今未改 production）**：
 * `supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS["claude-haiku-4-5-20251001"]` 是 $0.0008／$0.004 每 1K token
 * ＝ $0.80／$4.00 每 M，比官方牌價低 20%（那是 Haiku 3.5 的價）。那支是
 * analyze-chat 的觀測欄位，不在練習室路徑上，只記錄不改。
 */
export const HAIKU_4_5_PRICING: TokenPricing = withCacheTiers(1, 5);

/**
 * Sonnet 5（`claude-sonnet-5`）：input $2／M、output $10／M，
 * 抄自 `supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS["claude-sonnet-5"]`（$0.002／$0.010 每 1K token，未 export）。
 * cache 兩格用同一組官方乘數推出來（$0.20／$2.50 每 M），跟 Haiku 同一條規則。
 * **待 Eric 補**：repo 裡只有 logger.ts 這一處記載，而同一張表的 Haiku 那格
 * 已經證實是過期價（見上），所以這組 $2／$10 也**沒有跟官方牌價對拍過**。
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
