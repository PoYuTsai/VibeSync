// v3 結案時間 completedAt（Eric 2026-10-20「直接修好上線」）：done 事件帶 run 原本的結案時間
//（ISO 8601 UTC），續看重播已結案的 run 時回的也是那個時間，不是重播當下；沒有 done 的失敗路徑
// 不帶。App 拿它排哪一次分析比較新。不呼叫模型、不連網。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import {
  handleStreamAnalysisResume,
  type StreamAnalysisResumeSnapshot,
} from "../stream_handler.ts";
import {
  fixtureCase,
  type FlowCase,
  RELATION_FLOW_T0,
  runFlowWithRun,
  withReadTags,
} from "./relation_flow_harness.ts";
import {
  GUIDE_V3_STALE_AFTER_MS,
  guideV3ResumeSnapshot,
  recoveredGuideV3Result,
} from "./run_shape.ts";
import {
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
} from "./v3_stream_harness.ts";

const IMPORT_ENV: Record<string, string> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  STREAM_ANALYZE_ENABLED: "true",
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) Deno.env.set(k, v);
const { createAnalyzeChatHandler } = await import("../index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

type Rec = Record<string, unknown>;

const T0 = RELATION_FLOW_T0;
/// 模型回完、流程結案的時間（比開始晚 7 秒）：completedAt 要是這個，不是開始的 T0。
const T1 = T0 + 7_000;
const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

async function* lines(text: string): AsyncGenerator<string> {
  for (const part of text.match(/[^\n]*\n|[^\n]+$/g) ?? []) yield part;
}

/// 開始時鐘在 T0；讀局面（不送型）或寫卡串流（出卡）回完之後撥到 T1。
async function runTimed(flowCase: FlowCase, extra: Rec = {}) {
  let t = T0;
  return await runFlowWithRun(flowCase, {
    now: () => t,
    callRead: () => {
      if (!flowCase.writeText) t = T1;
      return Promise.resolve({
        text: flowCase.readText,
        model: "claude-sonnet-5-5",
      });
    },
    callWrite: () =>
      Promise.resolve({
        model: "claude-sonnet-5-5",
        textStream: (async function* () {
          yield* lines(flowCase.writeText);
          t = T1;
        })(),
      }),
    ...extra,
  });
}

function doneOf(outcome: Rec): Rec | undefined {
  return (outcome.events as Rec[]).find((e) => e.type === "analysis.done");
}

Deno.test("出卡：done 事件帶結案時間（ISO 8601 UTC），是結案那一刻、不是開始的時間；done 的結果與落帳結果同一個值", async () => {
  const { outcome, run } = await runTimed(fixtureCase("she_teases_him#1"));
  const done = doneOf(outcome)!;
  const at = new Date(T1).toISOString();
  assertEquals(done.completedAt, at);
  assert(ISO_UTC.test(String(done.completedAt)));
  assertEquals((done.finalResult as Rec).completedAt, at);
  assertEquals((done.result as Rec).completedAt, at);
  assertEquals((outcome.markDone as Rec).completedAt, at);
  assertEquals((run.final_result_json as Rec).completedAt, at);
  // 結案時間只出現在 done（判讀、卡、扣費內容都沒有）。
  for (const e of outcome.events as Rec[]) {
    if (e.type !== "analysis.done") assertEquals("completedAt" in e, false);
  }
  assertEquals(JSON.stringify(outcome.charges).includes("completedAt"), false);
});

Deno.test("不送型與固定訊息（先別回、停、自傷關心、未成年）：done 照樣帶結案時間，也存進結果", async () => {
  const cases = [
    fixtureCase("cold_one_word_replies#1"),
    withReadTags("she_teases_him#1", { explicitRejection: true }),
    withReadTags("she_teases_him#1", { selfHarmSignal: true }),
    withReadTags("she_teases_him#1", { minorSignal: true }),
  ];
  for (const c of cases) {
    // 這幾種不寫卡：讀局面回完就結案。
    const { outcome } = await runTimed({ ...c, writeText: "" });
    const done = doneOf(outcome);
    assert(done, c.name);
    const decision = (outcome.events as Rec[]).find((e) =>
      e.type === "analysis.read"
    )?.decision;
    assert(
      ["hold", "stop", "care"].includes(String(decision)),
      `${c.name}：${decision}`,
    );
    assertEquals(done.completedAt, new Date(T1).toISOString(), c.name);
    assertEquals(
      (outcome.markDone as Rec).completedAt,
      new Date(T1).toISOString(),
      c.name,
    );
  }
});

Deno.test("失敗路徑（讀局面壞掉、模型出錯、一張卡都沒有）沒有 done，也就沒有結案時間；錯誤事件不變", async () => {
  const teases = fixtureCase("she_teases_him#1");
  const broken: FlowCase = { ...teases, readText: "不是 JSON" };
  const noCards: FlowCase = { ...teases, writeText: "不是一張卡\n" };
  const upstream = await runFlowWithRun(teases, {
    callRead: () => Promise.reject(new Error("upstream 500")),
  });
  for (
    const { outcome } of [
      await runTimed(broken),
      await runTimed(noCards),
      upstream,
    ]
  ) {
    assertEquals(doneOf(outcome), undefined);
    assertEquals(JSON.stringify(outcome.events).includes("completedAt"), false);
    const error = (outcome.events as Rec[]).find((e) =>
      e.type === "analysis.error"
    )!;
    assertEquals(Object.keys(error).sort(), [
      "code",
      "message",
      "recoverable",
      "type",
    ]);
    assertEquals(outcome.markDone, null);
  }
});

async function resumeEvents(
  snapshot: StreamAnalysisResumeSnapshot,
): Promise<Rec[]> {
  const response = handleStreamAnalysisResume({
    runId: "flow-run",
    conversationHash: "flow-hash",
    initialRun: snapshot,
    loadRun: () => snapshot,
    pollIntervalMs: 0,
    heartbeatIntervalMs: 0,
  });
  const text = await response.text();
  return text.split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

Deno.test("續看重播已結案的 run：done 回原本的結案時間，不是重播當下；結果也是存的那一份", async () => {
  const { run } = await runTimed(fixtureCase("she_teases_him#1"));
  const original = new Date(T1).toISOString();
  // 重播在一天之後。
  const snapshot = guideV3ResumeSnapshot(run, T1 + 86_400_000);
  assertEquals(snapshot.completedAt, original);
  assertEquals((snapshot.finalResult as Rec).completedAt, original);
  const events = await resumeEvents(snapshot);
  const done = events.find((e) => e.type === "analysis.done")!;
  assertEquals(done.completedAt, original);
  assertEquals(done.recovered, true);
  assertEquals((done.finalResult as Rec).completedAt, original);
  assertEquals("guideV3Trace" in (done.finalResult as Rec), false);
});

Deno.test("續看重組與舊結果：原請求被終止、從扣費內容重組的，用扣費時間；這個欄位之前結案的結果也用扣費時間；都不是重播當下", async () => {
  const charged = "2026-10-16T00:00:03.000Z";
  const { run } = await runTimed(fixtureCase("she_teases_him#1"));
  const cut: AnalysisStreamRun = {
    ...run,
    status: "charged",
    charged_at: charged,
    final_result_json: null,
  };
  assertEquals(recoveredGuideV3Result(cut)?.completedAt, charged);
  const stale = guideV3ResumeSnapshot(
    cut,
    Date.parse(cut.created_at) + GUIDE_V3_STALE_AFTER_MS,
  );
  assertEquals(stale.completedAt, charged);
  assertEquals((stale.finalResult as Rec).completedAt, charged);
  // 這個欄位之前就結案的：結果裡沒有 completedAt。
  const { completedAt: _drop, ...legacyResult } = run.final_result_json as Rec;
  const legacy = guideV3ResumeSnapshot(
    {
      ...run,
      charged_at: charged,
      final_result_json: legacyResult,
    },
    T1 + 86_400_000,
  );
  assertEquals(legacy.completedAt, charged);
  const done = (await resumeEvents(legacy)).find((e) =>
    e.type === "analysis.done"
  )!;
  assertEquals(done.completedAt, charged);
  // 資料庫回的扣費時間是「…+00:00」、微秒六位：換成同一種 UTC「…Z」寫法。
  assertEquals(
    recoveredGuideV3Result({
      ...cut,
      charged_at: "2026-10-16T00:00:03.123456+00:00",
    })?.completedAt,
    "2026-10-16T00:00:03.123Z",
  );
  // 還沒結案、也還沒逾時：沒有結果，就沒有結案時間。
  const pending = guideV3ResumeSnapshot(
    { ...cut, status: "pending", charged_at: null },
    Date.parse(cut.created_at) + 1_000,
  );
  assertEquals("completedAt" in pending, false);
});

Deno.test("v2 的續看重播不變：快照沒有結案時間，done 就沒有這一欄；失敗的快照只給錯誤", async () => {
  const v2: StreamAnalysisResumeSnapshot = {
    status: "done",
    finalResult: { replies: [], selectedStyle: "extend" },
    lastErrorCode: null,
    retriesRemaining: 0,
    wasCharged: true,
  };
  const done = (await resumeEvents(v2)).find((e) =>
    e.type === "analysis.done"
  )!;
  assertEquals(Object.keys(done).sort(), [
    "finalResult",
    "recovered",
    "result",
    "runId",
    "type",
  ]);
  const failed = await resumeEvents({
    status: "failed",
    finalResult: null,
    lastErrorCode: "GUIDE_V3_ABANDONED",
    retriesRemaining: 0,
    wasCharged: false,
  });
  assertEquals(failed.some((e) => e.type === "analysis.done"), false);
  assertEquals(JSON.stringify(failed).includes("completedAt"), false);
});

Deno.test("走整個 handler：done 的結案時間是這次請求當下的 UTC 時間，跟存進資料庫的一樣", async () => {
  const tags = JSON.parse(fixtureCase("she_teases_him#1").readText);
  const before = Date.now();
  const out = await runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages: [
        { isFromMe: true, content: "週末去哪玩" },
        { isFromMe: false, content: "去爬山，腿快斷了，你呢？" },
      ],
      billingProtocolVersion: 3,
      analysisContractVersion: 3,
    },
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
    },
    model: (modelBody) =>
      Promise.resolve(
        modelBody.stream === true
          ? fakeWriteResponse([
            JSON.stringify({
              card: 1,
              messages: ["爬完還能打字，體力不錯"],
              hasInventedDetail: false,
            }),
          ])
          : fakeReadResponse(tags),
      ),
  });
  const after = Date.now();
  const done = out.events.find((e) => e.type === "analysis.done")!;
  const at = String(done.completedAt);
  assert(ISO_UTC.test(at), at);
  assert(Date.parse(at) >= before && Date.parse(at) <= after, at);
  assertEquals(out.finalResult?.completedAt, at);
});
