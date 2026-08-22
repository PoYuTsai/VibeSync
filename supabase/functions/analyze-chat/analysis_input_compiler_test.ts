import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  inferLatestIncomingRunStart,
  sanitizeAnalysisFragmentStartIndex,
} from "./analysis_input_compiler.ts";

Deno.test("analysis fragment start index validates against sanitized messages", () => {
  assertEquals(
    sanitizeAnalysisFragmentStartIndex(2, 4),
    { analysisFragmentStartIndex: 2 },
  );
  assertEquals(sanitizeAnalysisFragmentStartIndex(undefined, 4), {});
  assertEquals(
    sanitizeAnalysisFragmentStartIndex(4, 4),
    { error: "Invalid analysisFragmentStartIndex" },
  );
  assertEquals(
    sanitizeAnalysisFragmentStartIndex(1.5, 4),
    { error: "Invalid analysisFragmentStartIndex" },
  );
});

Deno.test("legacy client fallback finds the latest contiguous incoming run", () => {
  const messages = [
    { isFromMe: false, content: "old" },
    { isFromMe: true, content: "reply" },
    { isFromMe: false, content: "new 1" },
    { isFromMe: false, content: "new 2" },
  ];
  assertEquals(inferLatestIncomingRunStart(messages), 2);
  assertEquals(
    inferLatestIncomingRunStart([
      ...messages,
      { isFromMe: true, content: "draft" },
    ]),
    2,
  );
  assertEquals(inferLatestIncomingRunStart([]), 0);
});
