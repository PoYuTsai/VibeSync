import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

async function readIndexSource(): Promise<string> {
  return await Deno.readTextFile(new URL("./index.ts", import.meta.url));
}

function streamBranch(source: string): string {
  const branchStart = source.indexOf(
    'if (responseMode === "stream" && streamSupported && streamAllowed)',
  );
  const branchEnd = source.indexOf(
    'if (responseMode === "stream")',
    branchStart + 1,
  );
  return source.slice(branchStart, branchEnd);
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
  assert(source.includes("streamStore.reserveRetry({"));
  assert(source.includes("handleStreamAnalysisRequest({"));
  assert(source.includes("callClaudeStreaming("));
  assert(source.includes("buildStreamSystemPrompt("));
  assert(source.includes("streamReplyStyles"));
  assert(source.includes("requiredReplyStyles: streamReplyStyles"));
  assert(source.includes("const STREAM_ANALYZE_MAX_TOKENS = 3200"));
  assert(source.includes("max_tokens: STREAM_ANALYZE_MAX_TOKENS"));
  assert(source.includes("const STREAM_CLAUDE_TIMEOUT_MS = 120000"));
  assert(source.includes("{ timeout: STREAM_CLAUDE_TIMEOUT_MS }"));
  assert(source.includes("streamStore.chargeRun({"));
  assert(source.includes("streamStore.markDone({"));
  assert(source.includes("streamStore.markFailed({"));
});

Deno.test("stream retry reuses the stream ledger without charging again", async () => {
  const source = await readIndexSource();
  const branch = streamBranch(source);

  assert(
    source.includes('const isStreamRetryMode = responseMode === "stream"'),
  );
  assert(
    branch.includes(
      "const shouldCharge = quotaUsage.shouldChargeQuota && !accountIsTest &&\n" +
        "        !isStreamRetryMode;",
    ),
  );
  assert(
    source.includes(
      "prechargedRecommendation = streamRecommendationFromRun(streamRun)",
    ),
  );
  assert(source.includes("maxRetries: MAX_STREAM_RETRIES"));
  assert(source.includes("prechargedRecommendation,"));
});

Deno.test("stream retry reports non-charging usage and telemetry", async () => {
  const branch = streamBranch(await readIndexSource());

  assert(
    branch.includes(
      "messagesUsed: shouldCharge ? quotaUsage.chargedMessageCount : 0",
    ),
  );
  assert(
    branch.includes(
      "monthlyLimit - sub.monthly_messages_used -\n" +
        "            (shouldCharge ? quotaUsage.chargedMessageCount : 0)",
    ),
  );
  assert(
    branch.includes(
      "dailyLimit - sub.daily_messages_used -\n" +
        "            (shouldCharge ? quotaUsage.chargedMessageCount : 0)",
    ),
  );
  assert(branch.includes("shouldChargeQuota: shouldCharge"));
  assert(
    branch.includes(
      "chargedMessageCount: shouldCharge\n" +
        "                ? quotaUsage.chargedMessageCount\n" +
        "                : 0",
    ),
  );
});

Deno.test("stream failures report remaining retry slots from the ledger", async () => {
  const branch = streamBranch(await readIndexSource());

  assert(
    branch.includes("const failedRun = await streamStore.markFailed({"),
  );
  assert(branch.includes("event.retriesRemaining = Math.max("));
  assert(branch.includes("MAX_STREAM_RETRIES - failedRun.retry_count"));
});

Deno.test("stream branch does not use the two-stage run charge path", async () => {
  const source = await readIndexSource();
  const branch = streamBranch(source);

  assert(branch.includes("createSupabaseAnalysisStreamRunDriver"));
  assertFalse(branch.includes("createSupabaseAnalysisRunDriver"));
  assertFalse(branch.includes("createChargedRun"));
  assertFalse(branch.includes("create_charged_analysis_run"));
});

Deno.test("non-whitelist stream requests keep the legacy fallback path", async () => {
  const source = await readIndexSource();

  assert(source.includes("stream_request_fell_back_to_legacy"));
  assert(source.includes("supported: streamSupported"));
  assert(source.includes("allowed: streamAllowed"));
});
