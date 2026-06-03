import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

async function readIndexSource(): Promise<string> {
  return await Deno.readTextFile(new URL("./index.ts", import.meta.url));
}

Deno.test("stream branch is gated and uses the stream ledger", async () => {
  const source = await readIndexSource();

  assert(
    source.includes(
      'if (responseMode === "stream" && streamSupported && streamAllowed)',
    ),
  );
  assert(source.includes("isStreamingAllowed({"));
  assert(source.includes("streamStore.createPendingRun({"));
  assert(source.includes("streamStore.getRun({"));
  assert(source.includes("handleStreamAnalysisRequest({"));
  assert(source.includes("callClaudeStreaming("));
  assert(source.includes("buildStreamSystemPrompt(SYSTEM_PROMPT)"));
  assert(source.includes("streamStore.chargeRun({"));
  assert(source.includes("streamStore.markDone({"));
  assert(source.includes("streamStore.markFailed({"));
});

Deno.test("stream retry reuses the stream ledger without charging again", async () => {
  const source = await readIndexSource();

  assert(
    source.includes('const isStreamRetryMode = responseMode === "stream"'),
  );
  assert(source.includes("!isStreamRetryMode"));
  assert(
    source.includes(
      "prechargedRecommendation = streamRecommendationFromRun(streamRun)",
    ),
  );
  assert(source.includes("prechargedRecommendation,"));
});

Deno.test("stream branch does not use the two-stage run charge path", async () => {
  const source = await readIndexSource();
  const branchStart = source.indexOf(
    'if (responseMode === "stream" && streamSupported && streamAllowed)',
  );
  const branchEnd = source.indexOf(
    'if (responseMode === "stream")',
    branchStart + 1,
  );
  const streamBranch = source.slice(branchStart, branchEnd);

  assert(streamBranch.includes("createSupabaseAnalysisStreamRunDriver"));
  assertFalse(streamBranch.includes("createSupabaseAnalysisRunDriver"));
  assertFalse(streamBranch.includes("createChargedRun"));
  assertFalse(streamBranch.includes("create_charged_analysis_run"));
});

Deno.test("non-whitelist stream requests keep the legacy fallback path", async () => {
  const source = await readIndexSource();

  assert(source.includes("stream_request_fell_back_to_legacy"));
  assert(source.includes("supported: streamSupported"));
  assert(source.includes("allowed: streamAllowed"));
});
