import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import { calculateCost } from "./logger.ts";

Deno.test("calculateCost locks Sonnet 5 standard $2/$10 MTok pricing", () => {
  assertEquals(calculateCost("claude-sonnet-5", 1000, 0), 0.002);
  assertEquals(calculateCost("claude-sonnet-5", 0, 1000), 0.010);
  assertEquals(calculateCost("claude-sonnet-5", 1000, 1000), 0.012);
});

Deno.test("calculateCost includes prompt cache writes and reads", () => {
  assertAlmostEquals(
    calculateCost("claude-sonnet-5", 1000, 1000, 1000, 1000),
    0.0147,
    1e-12,
  );
});

Deno.test("Sonnet 5 token cost is 2.5x Haiku", () => {
  const sonnet = calculateCost("claude-sonnet-5", 1000, 1000);
  const haiku = calculateCost("claude-haiku-4-5-20251001", 1000, 1000);

  assertEquals(sonnet / haiku, 2.5);
});

Deno.test("unknown model IDs use conservative Sonnet pricing", () => {
  assertEquals(
    calculateCost("future-model-id", 1000, 1000),
    calculateCost("claude-sonnet-4-6", 1000, 1000),
  );
});
