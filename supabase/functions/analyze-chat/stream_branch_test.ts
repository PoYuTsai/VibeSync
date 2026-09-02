import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

// stream 分支已抽到 analyze_stream_handler.ts；index.ts 留 dispatch 與
// fail-closed gate。corpus 串接兩檔（index 在前）。
async function readIndexSource(): Promise<string> {
  const index = await Deno.readTextFile(
    new URL("./analyze_chat_handler.ts", import.meta.url),
  );
  const streamHandler = await Deno.readTextFile(
    new URL("./analyze_stream_handler.ts", import.meta.url),
  );
  return `${index}\n${streamHandler}`;
}

async function readStreamHandlerSource(): Promise<string> {
  return await Deno.readTextFile(
    new URL("./analyze_stream_handler.ts", import.meta.url),
  );
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
    "export async function handleAnalyzeStream(",
  );
  assert(branchStart >= 0, "handleAnalyzeStream 定位失敗");
  return source.slice(branchStart);
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
  const streamHandlerSource = await readStreamHandlerSource();

  assert(source.includes(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  ));
  assert(source.includes("const streamReplyStyles"));
  assert(source.includes("isStreamingAllowed({"));
  assert(source.includes("deps.store.createPendingRun({"));
  assert(source.includes("deps.store.reserveRetry({"));
  assert(source.includes("handleStreamAnalysisRequest({"));
  assert(source.includes("(deps.callModel ?? callClaudeStreaming)("));
  assert(source.includes("buildAnalyzeStreamSystemPrompt("));
  assertFalse(streamHandlerSource.includes('from "./stream_prompt.ts"'));
  assertFalse(
    streamHandlerSource.includes('from "./analyze_prompt/system_prompt.ts"'),
  );
  assertFalse(streamHandlerSource.includes("SYSTEM_PROMPT"));
  assert(source.includes("streamReplyStyles"));
  assert(source.includes("requiredReplyStyles: streamReplyStyles"));
  assert(source.includes("streamAnalyzeMaxTokensForStyleCount("));
  assert(source.includes("max_tokens: streamMaxOutputTokens"));
  assert(source.includes("maxOutputTokens: streamMaxOutputTokens"));
  assert(
    source.includes(
      'let streamThinkingDisabled = deps.selectedModel === "claude-sonnet-5"',
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
  assert(source.includes("deps.store.chargeRun({"));
  assert(source.includes("deps.store.markDone({"));
  assert(source.includes("deps.store.markFailed({"));
});

Deno.test("stream retry reuses the stream ledger without charging again", async () => {
  const source = await readIndexSource();
  const branch = streamBranch(source);

  assert(
    source.includes('const isStreamRetryMode = responseMode === "stream"'),
  );
  assert(
    branch.includes(
      "const shouldCharge = deps.quotaUsage.shouldChargeQuota &&\n" +
        "    !deps.accountIsTest &&\n" +
        "    !(analysisRunId !== null);",
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
  const loadRun = branch.indexOf("deps.store.getRun({");
  const resume = branch.indexOf("handleStreamAnalysisResume({");
  const reserveRetry = branch.indexOf("deps.store.reserveRetry({");

  assert(loadRun >= 0);
  assert(resume > loadRun);
  assert(reserveRetry > resume);
  assert(branch.includes('streamRun.status === "done"'));
  assert(branch.includes('streamRun.status === "pending"'));
  assert(branch.includes('streamRun.status === "charged"'));
  assert(branch.includes("streamRun.final_result_json ||"));
  // Phase 2a：回放給 client 前剝掉 server-only 快照（發散計畫）。
  assert(
    source.includes(
      "finalResult: stripClientHiddenFinalResult(run.final_result_json)",
    ),
  );
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
      "messagesUsed: shouldCharge ? deps.quotaUsage.chargedMessageCount : 0",
    ),
  );
  assert(
    branch.includes(
      "deps.monthlyLimit - deps.subMonthlyUsed -\n" +
        "        (shouldCharge ? deps.quotaUsage.chargedMessageCount : 0)",
    ),
  );
  assert(
    branch.includes(
      "deps.dailyLimit - deps.subDailyUsed -\n" +
        "        (shouldCharge ? deps.quotaUsage.chargedMessageCount : 0)",
    ),
  );
  assert(branch.includes("shouldChargeQuota: shouldCharge"));
  assert(
    branch.includes(
      "chargedMessageCount: shouldCharge\n" +
        "            ? deps.quotaUsage.chargedMessageCount\n" +
        "            : 0",
    ),
  );
});

Deno.test("stream failures report remaining retry slots from the ledger", async () => {
  const branch = streamBranch(await readIndexSource());

  assert(
    branch.includes("const failedRun = await deps.store.markFailed({"),
  );
  assert(branch.includes("event.retriesRemaining = Math.max("));
  assert(branch.includes("MAX_STREAM_RETRIES - failedRun.retry_count"));
});

Deno.test("stream branch does not use the two-stage run charge path", async () => {
  const source = await readIndexSource();
  const branch = streamBranch(source);

  // store 建構已移到 index dispatch（narrow port 注入）。
  assert(source.includes("createSupabaseAnalysisStreamRunDriver"));
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
