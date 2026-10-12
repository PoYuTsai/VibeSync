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
 * 寫 1.25×base input（Opus 5.5／Sonnet 5.5 的讀是 0.05×，見各自常數）。`supabase/functions/analyze-chat/logger.ts` 的
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
 * `supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS["claude-haiku-4-5-20251001"]` 已是 $0.001／$0.005 每 1K token，
 * 與這裡一致（Phase 4.5c 記的 $0.80／$4 舊價已修）。
 */
export const HAIKU_4_5_PRICING: TokenPricing = withCacheTiers(1, 5);

/**
 * Sonnet 5（`claude-sonnet-5`）：input $2／M、output $10／M，
 * 抄自 `supabase/functions/analyze-chat/logger.ts` 的
 * `TOKEN_COSTS["claude-sonnet-5"]`（$0.002／$0.010 每 1K token，未 export）。
 * cache 兩格用同一組官方乘數推出來（$0.20／$2.50 每 M），跟 Haiku 同一條規則。
 * **2026-09-05 已對拍 claude.com/pricing：$2／$10 per MTok**（也是 Phase 5 計畫
 * §2 D14 成本表用的那一組），跟 logger.ts 抄來的數字一致。
 */
export const SONNET_5_PRICING: TokenPricing = withCacheTiers(2, 10);

/**
 * Sonnet 5.5（`claude-sonnet-5-5`）：與 Sonnet 5 同價 $2／$10 每 M，
 * cache write $2.50；cache read 是 0.05x＝$0.10（2026-10-12 對拍
 * platform.claude.com 的 pricing 頁；10-02 記的 0.1x＝$0.20 已修）。
 */
export const SONNET_5_5_PRICING: TokenPricing = {
  inputPerMTok: 2,
  outputPerMTok: 10,
  cacheReadPerMTok: 0.1,
  cacheWritePerMTok: 2.5,
};

/**
 * Opus 5.5（`claude-opus-5-5`）：$4／$20 每 M，cache write $5，
 * cache read 0.05x＝$0.20（2026-10-12 對拍官方 pricing 頁）。
 */
export const OPUS_5_5_PRICING: TokenPricing = {
  inputPerMTok: 4,
  outputPerMTok: 20,
  cacheReadPerMTok: 0.2,
  cacheWritePerMTok: 5,
};

/**
 * Haiku 5.5（`claude-haiku-5-5`）依整次 prompt 長度分兩級（input＋快取讀寫
 * 都算）：10 萬 token 以內 $0.10／$0.50、cache write $0.125、read $0.01；
 * 超過整次改用 `HAIKU_5_5_LONG_CONTEXT_PRICING`（2026-10-12 對拍官方 pricing 頁）。
 */
export const HAIKU_5_5_PRICING: TokenPricing = {
  inputPerMTok: 0.1,
  outputPerMTok: 0.5,
  cacheReadPerMTok: 0.01,
  cacheWritePerMTok: 0.125,
};

/** Haiku 5.5 prompt 超過 10 萬 token 的那一級：$0.50／$2.50、write $0.625、read $0.05。 */
export const HAIKU_5_5_LONG_CONTEXT_PRICING: TokenPricing = {
  inputPerMTok: 0.5,
  outputPerMTok: 2.5,
  cacheReadPerMTok: 0.05,
  cacheWritePerMTok: 0.625,
};

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
