import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import { calculateCost } from "./logger.ts";
import {
  estimateCostUsd,
  HAIKU_5_5_LONG_CONTEXT_PRICING,
  HAIKU_5_5_PRICING,
  OPUS_5_5_PRICING,
  SONNET_5_5_PRICING,
} from "../_shared/model_pricing.ts";

Deno.test("calculateCost locks Sonnet 5 standard $2/$10 MTok pricing", () => {
  assertEquals(calculateCost("claude-sonnet-5", 1000, 0), 0.002);
  assertEquals(calculateCost("claude-sonnet-5", 0, 1000), 0.010);
  assertEquals(calculateCost("claude-sonnet-5", 1000, 1000), 0.012);
  assertEquals(calculateCost("claude-sonnet-5-5", 1000, 1000), 0.012);
});

Deno.test("calculateCost includes prompt cache writes and reads", () => {
  assertAlmostEquals(
    calculateCost("claude-sonnet-5", 1000, 1000, 1000, 1000),
    0.0147,
    1e-12,
  );
});

Deno.test("Sonnet 5 token cost is 2x Haiku 4.5（官方牌價 $2／$10 vs $1／$5）", () => {
  const sonnet = calculateCost("claude-sonnet-5", 1000, 1000);
  const haiku = calculateCost("claude-haiku-4-5-20251001", 1000, 1000);

  assertEquals(sonnet / haiku, 2);
});

Deno.test("unknown model IDs use conservative Sonnet pricing", () => {
  assertEquals(
    calculateCost("future-model-id", 1000, 1000),
    calculateCost("claude-sonnet-4-6", 1000, 1000),
  );
});

Deno.test("Sonnet 5.5 and Opus 5.5 cache reads are 0.05x input; other models stay 0.1x", () => {
  // 2026-10-12 官方 pricing 頁：Sonnet 5.5 $0.10／M、Opus 5.5 $0.20／M、Sonnet 5 $0.20／M。
  assertAlmostEquals(
    calculateCost("claude-sonnet-5-5", 0, 0, 0, 1_000_000),
    0.10,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-opus-5-5", 0, 0, 0, 1_000_000),
    0.20,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-sonnet-5", 0, 0, 0, 1_000_000),
    0.20,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-sonnet-5-5", 0, 0, 1_000_000, 0),
    2.50,
    1e-12,
  );
});

Deno.test("Opus 5.5 is $4 input / $20 output / $5 cache write per MTok", () => {
  assertAlmostEquals(calculateCost("claude-opus-5-5", 1_000_000, 0), 4, 1e-12);
  assertAlmostEquals(calculateCost("claude-opus-5-5", 0, 1_000_000), 20, 1e-12);
  assertAlmostEquals(
    calculateCost("claude-opus-5-5", 0, 0, 1_000_000, 0),
    5,
    1e-12,
  );
});

Deno.test("Haiku 5.5 switches the whole request to the long-context tier once the prompt exceeds 100K tokens", () => {
  // 10 萬以內：$0.10／$0.50，write $0.125、read $0.01。
  assertAlmostEquals(
    calculateCost("claude-haiku-5-5", 100_000, 0),
    0.01,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-haiku-5-5", 0, 1_000_000),
    0.50,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-haiku-5-5", 0, 0, 80_000, 20_000),
    0.0102,
    1e-12,
  );
  // 超過 10 萬（快取讀寫也算進 prompt 長度）：整次 $0.50／$2.50，write $0.625、read $0.05。
  assertAlmostEquals(
    calculateCost("claude-haiku-5-5", 100_001, 0),
    0.0500005,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-haiku-5-5", 1, 1_000, 0, 100_000),
    0.0000005 + 0.0025 + 0.005,
    1e-12,
  );
  assertAlmostEquals(
    calculateCost("claude-haiku-5-5", 0, 0, 100_001, 0),
    0.062500625,
    1e-12,
  );
});

Deno.test("logger TOKEN_COSTS matches _shared/model_pricing for the 5.5 models", () => {
  const usage = {
    inputTokens: 30_000,
    outputTokens: 2_000,
    cacheCreationInputTokens: 10_000,
    cacheReadInputTokens: 50_000,
  };
  for (
    const [model, pricing] of [
      ["claude-sonnet-5-5", SONNET_5_5_PRICING],
      ["claude-opus-5-5", OPUS_5_5_PRICING],
      ["claude-haiku-5-5", HAIKU_5_5_PRICING],
    ] as const
  ) {
    assertAlmostEquals(
      calculateCost(
        model,
        usage.inputTokens,
        usage.outputTokens,
        usage.cacheCreationInputTokens,
        usage.cacheReadInputTokens,
      ),
      estimateCostUsd(usage, pricing),
      1e-12,
      model,
    );
  }
  const longUsage = { ...usage, cacheReadInputTokens: 150_000 };
  assertAlmostEquals(
    calculateCost(
      "claude-haiku-5-5",
      longUsage.inputTokens,
      longUsage.outputTokens,
      longUsage.cacheCreationInputTokens,
      longUsage.cacheReadInputTokens,
    ),
    estimateCostUsd(longUsage, HAIKU_5_5_LONG_CONTEXT_PRICING),
    1e-12,
  );
});
