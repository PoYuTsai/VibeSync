import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

async function read(relativeUrl: string): Promise<string> {
  return await Deno.readTextFile(new URL(relativeUrl, import.meta.url));
}

Deno.test("AnalyzeChat mode guard runs before subscription, quota, or model work", async () => {
  const source = await read("./index.ts");
  const guard = source.indexOf("const modeResolution = resolveRequestMode({");
  const subscription = source.indexOf("// Check subscription");
  const streamBranch = source.indexOf(
    'if (responseMode === "stream" && streamSupported && streamAllowed)',
  );

  assert(guard >= 0);
  assert(subscription > guard);
  assert(streamBranch > subscription);
});

Deno.test("AnalyzeChat has exactly one executable response mode", async () => {
  const source = await read("./index.ts");

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
  const source = await read("./index.ts");
  const start = source.indexOf("const plainAnalyzeRequest =");
  const end = source.indexOf("const modeResolution =", start);
  const classifier = source.slice(start, end);

  assert(start >= 0);
  assert(end > start);
  assert(classifier.includes("!recognizeOnly"));
  assertFalse(classifier.includes("images"));
});

Deno.test("Flutter AnalyzeChat client exposes stream start and retry only", async () => {
  const notifier = await read(
    "../../../lib/features/analysis/data/notifiers/streaming_analyze_notifier.dart",
  );
  const service = await read(
    "../../../lib/features/analysis/data/services/analysis_service.dart",
  );
  const preview = await read(
    "../../../lib/features/analysis/domain/entities/analysis_recommendation_preview.dart",
  );
  const loadingWidgets = await read(
    "../../../lib/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart",
  );
  const source = `${notifier}\n${service}\n${preview}\n${loadingWidgets}`;

  assert(source.includes("analyzeStream("));
  assert(source.includes("retryStream()"));
  assert(service.includes("contentType != 'application/x-ndjson'"));
  assertEquals(source.match(/analyzeQuick/g)?.length ?? 0, 0);
  assertEquals(source.match(/analyzeFull/g)?.length ?? 0, 0);
  assertEquals(source.match(/retryFull/g)?.length ?? 0, 0);
  assertEquals(source.match(/_shouldUseStreamingFull/g)?.length ?? 0, 0);
  assertEquals(source.match(/quickResult/g)?.length ?? 0, 0);
  assertEquals(source.match(/FullAnalysisPlaceholder/g)?.length ?? 0, 0);
  assertEquals(source.match(/FullAnalysisRetryCard/g)?.length ?? 0, 0);
});
