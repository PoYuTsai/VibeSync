// 定價常數自測（零網路）：釘住四格單價與估價公式。
// 這裡釘的是**唯一定價來源**；`scripts/practice_agency_telemetry.py` 的
// `HAIKU_PRICE` 是同一組數字的第二份（Deno ↔ Python 沒有共用來源），改動時
// 兩邊都要改，見 pricing.ts 檔頭與 README「Phase 4.5c 評測工具」節。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  CACHE_READ_MULTIPLIER,
  CACHE_WRITE_MULTIPLIER,
  estimateCostUsd,
  HAIKU_4_5_PRICING,
  SONNET_5_PRICING,
} from "./pricing.ts";

Deno.test("Haiku 4.5 四格單價（USD／1M token）逐格釘死", () => {
  assertEquals(HAIKU_4_5_PRICING.inputPerMTok, 1);
  assertEquals(HAIKU_4_5_PRICING.outputPerMTok, 5);
  assertEquals(HAIKU_4_5_PRICING.cacheReadPerMTok, 0.1);
  assertEquals(HAIKU_4_5_PRICING.cacheWritePerMTok, 1.25);
});

Deno.test("Sonnet 5 四格單價（logger.ts 的 TOKEN_COSTS，cache 兩格用官方乘數推）", () => {
  assertEquals(SONNET_5_PRICING.inputPerMTok, 2);
  assertEquals(SONNET_5_PRICING.outputPerMTok, 10);
  assertEquals(SONNET_5_PRICING.cacheReadPerMTok, 0.2);
  assertEquals(SONNET_5_PRICING.cacheWritePerMTok, 2.5);
});

Deno.test("cache 乘數是 Anthropic 官方比例，兩個模型共用同一條規則", () => {
  assertEquals(CACHE_READ_MULTIPLIER, 0.1);
  assertEquals(CACHE_WRITE_MULTIPLIER, 1.25);
  for (const p of [HAIKU_4_5_PRICING, SONNET_5_PRICING]) {
    assertEquals(p.cacheReadPerMTok, p.inputPerMTok * CACHE_READ_MULTIPLIER);
    assertEquals(p.cacheWritePerMTok, p.inputPerMTok * CACHE_WRITE_MULTIPLIER);
  }
});

Deno.test("estimateCostUsd：四格 token 各自吃自己的單價，零 usage 是 0", () => {
  const zero = {
    inputTokens: 0,
    outputTokens: 0,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
  };
  assertEquals(estimateCostUsd(zero, HAIKU_4_5_PRICING), 0);
  // 1M input + 1M output + 1M cache read + 1M cache write
  // = 1 + 5 + 0.1 + 1.25 = $7.35。
  const oneM = estimateCostUsd({
    inputTokens: 1_000_000,
    outputTokens: 1_000_000,
    cacheReadInputTokens: 1_000_000,
    cacheCreationInputTokens: 1_000_000,
  }, HAIKU_4_5_PRICING);
  assert(Math.abs(oneM - 7.35) < 1e-9, String(oneM));
  // cache read 一定比同量的 base input 便宜、cache write 一定比較貴。
  const read = estimateCostUsd(
    { ...zero, cacheReadInputTokens: 1_000_000 },
    HAIKU_4_5_PRICING,
  );
  const base = estimateCostUsd(
    { ...zero, inputTokens: 1_000_000 },
    HAIKU_4_5_PRICING,
  );
  const write = estimateCostUsd({
    ...zero,
    cacheCreationInputTokens: 1_000_000,
  }, HAIKU_4_5_PRICING);
  assert(read < base && base < write);
});
