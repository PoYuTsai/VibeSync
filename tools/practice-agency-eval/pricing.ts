// 練習室黑箱評測的**單一定價來源**（Phase 4.5c）。
//
// Phase 5 WP2 起，模型單價本體搬到
// `supabase/functions/_shared/model_pricing.ts`——成本保險絲要在 Edge Function
// 裡估價，而 Supabase 打包只跟得到 `supabase/functions/` 底下的相對 import。
// 這支保留為工具側的入口（既有 import 路徑不動），**只 re-export，不再自己
// 定義任何單價**，兩邊相等由 `pricing_test.ts` 的 identity 斷言釘住。
//
// **跨語言同步點（唯一，改動時兩邊都要改）**：
//   - `supabase/functions/_shared/model_pricing.ts` 的 `HAIKU_4_5_PRICING`
//   - `scripts/practice_agency_telemetry.py` 的 `HAIKU_PRICE`
// 那支 Python 是 production telemetry 的唯讀監看腳本，不 import 這裡的常數
// （Deno ↔ Python 沒有共用來源），所以只能靠這條註解與 README「Phase 4.5c
// 評測工具」節的說明維持一致。
//
// 單位一律是 **USD／1M token**（跟 Anthropic 官方牌價與那支 Python 同一個
// 口徑；舊的 USD／1K 寫法已經退掉，避免兩種單位並存時看錯一個數量級）。
export {
  CACHE_READ_MULTIPLIER,
  CACHE_WRITE_MULTIPLIER,
  estimateCostUsd,
  HAIKU_4_5_PRICING,
  SONNET_5_PRICING,
} from "../../supabase/functions/_shared/model_pricing.ts";
export type {
  TokenPricing,
  TokenUsage,
} from "../../supabase/functions/_shared/model_pricing.ts";

/**
 * DeepSeek 精簡分類器的**觀測單價**（USD／次呼叫），不是 token 牌價。
 * 只有評測工具用得到（Edge 端不估 DeepSeek 成本，保險絲只保 Anthropic），
 * 所以留在工具側，沒有跟著搬進 `_shared/`。
 *
 * 來源：README Phase 4.3 用餘額差反推的 $0.0002027／次，Phase 4.5b 沿用同一個
 * 數字估臂 B 的 420 次分類器呼叫。之所以用觀測單價而不是 token 牌價：這批
 * prompt（判準規則、人物卡固定欄位）在同一批次裡逐字重複，命中 DeepSeek 的
 * prompt 快取，token 牌價法算出來一直是實測的 2–5 倍（README「A27 重跑」與
 * 4.5b 兩節都記過這件事，餘額差才是可信數字）。
 *
 * 拿它做停損估算時要記得：這是「長 prompt ＋高快取命中」情境下的觀測值，
 * 換情境（更短的逐字稿、冷快取）會偏。
 */
export const DEEPSEEK_CLASSIFIER_USD_PER_CALL = 0.0002027;

/**
 * DeepSeek 聊天生成的**觀測單價**（USD／次呼叫），與上面分類器那格同一個
 * 口徑：不是 token 牌價，是餘額差反推的每次呼叫金額。
 *
 * 來源：README Phase 4.3「模型 A/B」那輪的乾淨量測——該輪還沒有分類器呼叫
 * 混進同一筆餘額差，是唯一能單獨拆出聊天單價的樣本（$0.02／680 次）。
 * 4.5c 的成本外推（mixed 每場 $0.0436～$0.0648）也是拿這個數字加權出來的。
 *
 * 精度限制：DeepSeek 餘額只有兩位小數，這是小數點後第七位的推算值，量級
 * 可信、尾數不可信。換情境（更短逐字稿、冷快取）會偏。
 */
export const DEEPSEEK_CHAT_USD_PER_CALL = 0.0000294;
