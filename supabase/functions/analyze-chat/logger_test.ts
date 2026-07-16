import { assertEquals } from "jsr:@std/assert@1";

import { calculateCost } from "./logger.ts";

Deno.test("calculateCost locks Sonnet 5 launch pricing", () => {
  assertEquals(calculateCost("claude-sonnet-5", 1000, 1000), 0.012);
});

Deno.test("Sonnet 5 launch token cost is 2.5x Haiku", () => {
  const sonnet = calculateCost("claude-sonnet-5", 1000, 1000);
  const haiku = calculateCost("claude-haiku-4-5-20251001", 1000, 1000);

  assertEquals(sonnet / haiku, 2.5);
});
