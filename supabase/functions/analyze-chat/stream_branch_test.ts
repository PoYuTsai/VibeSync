import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

async function readIndexSource(): Promise<string> {
  return await Deno.readTextFile(new URL("./index.ts", import.meta.url));
}

async function readRetryLeaseMigration(): Promise<string> {
  return await Deno.readTextFile(
    new URL(
      "../../migrations/20260813003000_stream_analysis_retry_lease.sql",
      import.meta.url,
    ),
  );
}

function streamBranch(source: string): string {
  const branchStart = source.indexOf(
    'if (responseMode === "stream") {\n      const streamReplyStyles',
  );
  const branchEnd = source.indexOf("let claudeResult;", branchStart);
  return source.slice(branchStart, branchEnd);
}

function streamFailClosedBranch(source: string): string {
  const branchStart = source.indexOf(
    'if (\n      responseMode === "stream" && (!streamSupported || !streamAllowed)\n    )',
  );
  const branchEnd = source.indexOf("const claimStore =", branchStart);
  return source.slice(branchStart, branchEnd);
}

Deno.test("stream branch is gated and uses the stream ledger", async () => {
  const source = await readIndexSource();

  assert(source.includes(
    'if (responseMode === "stream") {\n      const streamReplyStyles',
  ));
  assert(source.includes("isStreamingAllowed({"));
  assert(source.includes("streamStore.createPendingRun({"));
  assert(source.includes("streamStore.reserveRetry({"));
  assert(source.includes("handleStreamAnalysisRequest({"));
  assert(source.includes("callClaudeStreaming("));
  assert(source.includes("buildStreamSystemPrompt("));
  assert(source.includes("streamReplyStyles"));
  assert(source.includes("requiredReplyStyles: streamReplyStyles"));
  assert(source.includes("streamAnalyzeMaxTokensForStyleCount("));
  assert(source.includes("max_tokens: streamMaxOutputTokens"));
  assert(source.includes("maxOutputTokens: streamMaxOutputTokens"));
  assert(
    source.includes(
      'let streamThinkingDisabled = selectedModel === "claude-sonnet-5"',
    ),
  );
  assert(source.includes("thinking: streamThinkingDisabled"));
  assert(
    source.includes(
      'streamThinkingDisabled = claude.model === "claude-sonnet-5"',
    ),
  );
  assert(source.includes('? { type: "disabled" }'));
  assert(source.includes("const STREAM_CLAUDE_TIMEOUT_MS = 120000"));
  assert(source.includes("const STREAM_PROVIDER_MAX_ATTEMPTS = 3"));
  assert(source.includes("{ timeout: STREAM_CLAUDE_TIMEOUT_MS }"));
  assertEquals(
    streamBranch(source).split("timeoutMs: STREAM_CLAUDE_TIMEOUT_MS").length -
      1,
    3,
  );
  assertEquals(
    streamBranch(source).split(
      "providerMaxAttempts: STREAM_PROVIDER_MAX_ATTEMPTS",
    ).length - 1,
    2,
  );
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

Deno.test("stream reconnect replays done runs before reserving a retry", async () => {
  const source = await readIndexSource();
  const branch = streamBranch(source);
  const loadRun = branch.indexOf("streamStore.getRun({");
  const resume = branch.indexOf("handleStreamAnalysisResume({");
  const reserveRetry = branch.indexOf("streamStore.reserveRetry({");

  assert(loadRun >= 0);
  assert(resume > loadRun);
  assert(reserveRetry > resume);
  assert(branch.includes('streamRun.status === "done"'));
  assert(branch.includes('streamRun.status === "pending"'));
  assert(branch.includes('streamRun.status === "charged"'));
  assert(branch.includes("streamRun.final_result_json ||"));
  assert(source.includes("finalResult: run.final_result_json"));
});

Deno.test("stream retry reservation becomes an in-flight lease", async () => {
  const source = await readRetryLeaseMigration();

  assert(source.includes("status = 'charged'"));
  assert(source.includes("AND status = 'failed'"));
  assert(source.includes("AND final_result_json IS NULL"));
  assert(source.includes("AND charged_at IS NOT NULL"));
  assert(source.includes("AND retry_count < p_max_retries"));
});

Deno.test("stream retry accepts thin precharged recommendation (Codex r1 P2)", async () => {
  const source = await readIndexSource();

  // 方案二件4：瘦卡 fallback 扣費（message 空、raw 帶 expectedReaction）
  // 的已扣費 run 必須可 resume；否則 streamRecommendationFromRun 回 null
  // → STREAM_RUN_NOT_RETRYABLE，已扣費卻不可續跑。
  assert(source.includes("const thinResume = message.length === 0"));
  assert(source.includes("isThinRecommendationEvent(raw)"));
  assert(source.includes("message.length === 0 && !thinResume"));
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

Deno.test("stream request fails closed instead of calling the legacy model path", async () => {
  const source = await readIndexSource();
  const branch = streamFailClosedBranch(source);

  assert(branch.includes("stream_request_rejected_without_fallback"));
  assert(branch.includes('"STREAM_MODE_UNAVAILABLE"'));
  assert(branch.includes('"STREAM_MODE_UNSUPPORTED_FOR_REQUEST"'));
  assert(branch.includes("shouldChargeQuota: false"));
  assert(branch.includes("return jsonResponse"));
  assertFalse(branch.includes("callClaudeWithFallback"));
  assertFalse(source.includes("stream_request_fell_back_to_legacy"));
  assertFalse(source.includes("streamRetryChargeWaived"));
});
