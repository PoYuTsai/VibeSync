// 重播測試（健檢 F47）：錄下的 Sonnet 5.5 原始輸出原樣餵回伺服器的串流處理，送給 App 的事件、
// 狀態碼、有沒有扣額度、落帳的結果，都要跟期望值一模一樣。改伺服器處理（reframer、post_process、
// 串流事件、先別回選單）時，這支會指出哪一案哪裡變了；有意的改動用
// tools/ci/regen-analyze-replay-fixtures.ts 重產期望值，審查時看差異。不呼叫模型、不連網。
import "./test_fetch_dispatcher.ts";
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  normalizeReplayOutcome,
  replayAnalyzeStream,
} from "./analyze_replay_harness.ts";
import fixtures from "./testdata/analyze_replay_fixtures.json" with {
  type: "json",
};

const stubFetch = (() =>
  Promise.resolve(
    new Response("{}", {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  )) as typeof fetch;

Deno.test("重播：錄音涵蓋語料每一案，而且有送出、先別回、收尾三種決定", () => {
  assertEquals(fixtures.cases.length, fixtures.meta.cases);
  const kinds = new Set(
    fixtures.cases.map((c) =>
      (c.expected.events as Record<string, unknown>[]).find((e) =>
        e.type === "analysis.decision"
      )?.messageDecision
    ),
  );
  for (const kind of ["send", "do_not_send", "acknowledge_and_stop"]) {
    assertEquals(kinds.has(kind), true, kind);
  }
});

for (const replayCase of fixtures.cases) {
  Deno.test(`重播：${replayCase.name}`, async () => {
    const original = globalThis.fetch;
    globalThis.fetch = stubFetch;
    try {
      assertEquals(
        normalizeReplayOutcome(await replayAnalyzeStream(replayCase)),
        replayCase.expected,
      );
    } finally {
      globalThis.fetch = original;
    }
  });
}
