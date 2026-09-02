import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  DIVERGENCE_PLAN_EXTRA_TOKENS,
  STREAM_ANALYZE_BASE_MAX_TOKENS,
  STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS,
  streamAnalyzeMaxTokensForStyleCount,
} from "./stream_budget.ts";

Deno.test("stream budget keeps two-style Free compact", () => {
  assertEquals(STREAM_ANALYZE_BASE_MAX_TOKENS, 4500);
  assertEquals(streamAnalyzeMaxTokensForStyleCount(2), 4500);
});

Deno.test("stream budget gives the five-style paid contract enough headroom", () => {
  assertEquals(STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS, 6000);
  assertEquals(streamAnalyzeMaxTokensForStyleCount(5), 6000);
  assertEquals(streamAnalyzeMaxTokensForStyleCount(3), 6000);
});

Deno.test("divergence plan adds a fixed reserve on top of the style budget only when requested", () => {
  assertEquals(streamAnalyzeMaxTokensForStyleCount(2, {}), 4500);
  assertEquals(
    streamAnalyzeMaxTokensForStyleCount(2, { divergencePlan: true }),
    4500 + DIVERGENCE_PLAN_EXTRA_TOKENS,
  );
  assertEquals(
    streamAnalyzeMaxTokensForStyleCount(5, { divergencePlan: true }),
    6000 + DIVERGENCE_PLAN_EXTRA_TOKENS,
  );
});
