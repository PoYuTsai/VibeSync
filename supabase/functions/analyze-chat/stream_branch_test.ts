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

Deno.test("stream fallback telemetry keeps enough gate context", async () => {
  const source = await readIndexSource();

  assert(source.includes("stream_request_fell_back_to_legacy"));
  assert(source.includes("supported: streamSupported"));
  assert(source.includes("allowed: streamAllowed"));
});

Deno.test("legacy fallback validates stream retry before waiving billing", async () => {
  const source = await readIndexSource();

  // Codex P1：isStreamRetryMode 只是 responseMode+analysisRunId，client 可控。
  // 豁免 legacy 扣費前必須驗證 run 存在、屬於本人、綁同一份對話 hash 且
  // 已扣費（charged_at）；查無此 run 直接 409，偽造 runId 拿不到免費分析。
  assert(source.includes("let streamRetryChargeWaived = false"));
  assert(source.includes("fallbackStreamStore.getRun({"));
  assert(
    source.includes(
      "streamRetryChargeWaived = fallbackStreamRun.charged_at !== null",
    ),
  );
  assert(source.includes("stream_retry_fallback_run_invalid"));

  // 扣費點只看驗證後的 flag，不看 client 可控的 isStreamRetryMode；
  // 已扣費 run 的 retry 不得在 legacy 二次 increment_usage。
  assert(
    source.includes(
      "quotaUsage.shouldChargeQuota && quotaUsage.chargedMessageCount > 0 &&\n" +
        "      !streamRetryChargeWaived",
    ),
  );
});

Deno.test("legacy fallback usage reports zero charge when billing is waived", async () => {
  const source = await readIndexSource();

  // Codex P2：豁免扣費時 usage/telemetry 不得報假扣費——Flutter 拿
  // messagesUsed / remaining 做扣費 toast 與本地額度同步。
  assert(
    source.includes("const legacyReportedCharge = streamRetryChargeWaived"),
  );
  assert(source.includes("messagesUsed: legacyReportedCharge"));
  assert(source.includes("chargedMessageCount: legacyReportedCharge"));
  assert(
    source.includes(
      "quotaUsage.shouldChargeQuota &&\n        !streamRetryChargeWaived",
    ),
  );
});
