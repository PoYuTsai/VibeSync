import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

async function read(relativeUrl: string): Promise<string> {
  return await Deno.readTextFile(new URL(relativeUrl, import.meta.url));
}

Deno.test("AnalyzeChat mode guard runs before subscription, quota, or model work", async () => {
  const source = await read("./analyze_chat_handler.ts");
  const guard = source.indexOf("const modeResolution = resolveRequestMode({");
  const subscription = source.indexOf("// Check subscription");
  const streamBranch = source.indexOf(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  );

  assert(guard >= 0);
  assert(subscription > guard);
  assert(streamBranch > subscription);
});

Deno.test("AnalyzeChat has exactly one executable response mode", async () => {
  const source = await read("./analyze_chat_handler.ts");

  assert(source.includes('responseMode === "stream"'));
  assertFalse(source.includes('if (responseMode === "quick")'));
  assertFalse(source.includes('if (responseMode === "full")'));
  assertFalse(source.includes("stream_request_fell_back_to_legacy"));
  assertFalse(source.includes("streamRetryChargeWaived"));

  for (
    const removedModule of [
      "analysis_run_store.ts",
      "anchor_drift.ts",
      "full_response.ts",
      "quick_prompt.ts",
      "quick_response.ts",
    ]
  ) {
    assertFalse(source.includes(removedModule));
  }
});

Deno.test("plain screenshot analysis cannot bypass the streaming-only guard", async () => {
  // 行為驗證：request_shape_test.ts 鎖「有圖無草稿＝plain_analyze」、
  // analyze_chat_handler_test.ts 鎖 plain legacy → 410。這裡守住 index.ts
  // 的 streaming-only guard 仍掛在 shape union 的 plain_analyze 上。
  const source = await read("./analyze_chat_handler.ts");
  assert(
    source.includes(
      'const plainAnalyzeRequest = requestShape.kind === "plain_analyze";',
    ),
  );
});

Deno.test("stream fail-closed rejection precedes overcharge claim", async () => {
  const source = await read("./analyze_chat_handler.ts");
  const rejection = source.indexOf(
    'logWarn("stream_request_rejected_without_fallback"',
  );
  const claim = source.indexOf("claimStore.claim");
  const claimedLog = source.indexOf(
    'logInfo("overcharge_confirmation_claimed"',
  );
  const generator = source.indexOf(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  );
  const generatorEnd = source.indexOf("let claudeResult;", generator);

  assert(rejection >= 0);
  assert(claim > rejection);
  assert(claimedLog > rejection);
  assert(generator > claim);
  assert(generatorEnd > generator);
  assert(
    source.slice(rejection, claim).includes("shouldChargeQuota: false"),
  );
  assertEquals(
    source.match(/stream_request_rejected_without_fallback/g)?.length ?? 0,
    1,
  );
  assertFalse(
    source.slice(generator, generatorEnd).includes(
      "stream_request_rejected_without_fallback",
    ),
  );
  assertFalse(
    source.slice(generator, generatorEnd).includes(
      "callClaudeWithFallback",
    ),
  );
});

Deno.test("Flutter AnalyzeChat client exposes stream start and retry only", async () => {
  // 現行唯一 production seam：StreamingAnalyzeNotifier.start →
  // _client.stream(AnalyzeStreamRequest(...))；retryStream 保留。
  const notifier = await read(
    "../../../lib/features/analysis/data/notifiers/streaming_analyze_notifier.dart",
  );
  assert(notifier.includes("Future<void> start({"));
  assert(notifier.includes("_client.stream(AnalyzeStreamRequest("));
  assert(notifier.includes("Future<void> retryStream()"));

  // NDJSON content-type guard 在 stream client（wire decode 歸 data 層）。
  const streamClient = await read(
    "../../../lib/features/analysis/data/services/analyze_stream_client.dart",
  );
  assert(streamClient.includes("contentType != 'application/x-ndjson'"));
});

async function* dartFiles(dir: URL): AsyncGenerator<URL> {
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isDirectory) {
      yield* dartFiles(new URL(`${entry.name}/`, dir));
    } else if (entry.name.endsWith(".dart")) {
      yield new URL(entry.name, dir);
    }
  }
}

Deno.test("no quick/full fallback identifiers anywhere in lib/features/analysis", async () => {
  // 遞迴掃整個 feature 樹（固定檔名清單掃不到搬移後的新檔）。
  const bannedTokens = [
    "analyzeQuick",
    "analyzeFull",
    "retryFull",
    "_shouldUseStreamingFull",
    "quickResult",
    "FullAnalysisPlaceholder",
    "FullAnalysisRetryCard",
  ];
  const root = new URL("../../../lib/features/analysis/", import.meta.url);

  const violations: string[] = [];
  const scanned: string[] = [];
  for await (const file of dartFiles(root)) {
    scanned.push(file.pathname);
    const source = await Deno.readTextFile(file);
    for (const token of bannedTokens) {
      if (source.includes(token)) {
        violations.push(`${file.pathname}: ${token}`);
      }
    }
  }

  // 掃描器假綠防護：樹必須非空且涵蓋 notifier 與 Work C 抽出的 sections。
  assert(scanned.length > 0);
  assert(
    scanned.some((path) => path.endsWith("streaming_analyze_notifier.dart")),
  );
  assert(scanned.some((path) => path.includes("/presentation/sections/")));
  assertEquals(violations, []);
});
