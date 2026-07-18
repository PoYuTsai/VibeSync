import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  STREAM_ANALYZE_BASE_MAX_TOKENS,
  STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS,
  streamAnalyzeMaxTokensForStyleCount,
} from "./stream_budget.ts";

Deno.test("stream budget keeps two-style Free compact", () => {
  assertEquals(STREAM_ANALYZE_BASE_MAX_TOKENS, 3200);
  assertEquals(streamAnalyzeMaxTokensForStyleCount(2), 3200);
});

Deno.test("stream budget gives the five-style paid contract enough headroom", () => {
  assertEquals(STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS, 6000);
  assertEquals(streamAnalyzeMaxTokensForStyleCount(5), 6000);
  assertEquals(streamAnalyzeMaxTokensForStyleCount(3), 6000);
});
