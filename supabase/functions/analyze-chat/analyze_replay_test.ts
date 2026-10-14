// 重播測試（健檢 F47）：錄下的 Sonnet 5.5 原始輸出原樣餵回伺服器的串流處理，送給 App 的事件、
// 狀態碼、有沒有扣額度、落帳的結果，都要跟期望值一模一樣。改伺服器處理（reframer、post_process、
// 串流事件、先別回選單）時，這支會指出哪一案哪裡變了；有意的改動用
// tools/ci/regen-analyze-replay-fixtures.ts 重產期望值，審查時看差異。不呼叫模型、不連網。
import "./test_fetch_dispatcher.ts";
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  normalizeReplayOutcome,
  replayAnalyzeStream,
  replayChunks,
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

// 10/14 錄的 23 案（每案第 1 次）。少一案、多一案或重複都要失敗；語料增減案例時
// 重錄並同步改這份清單。
const EXPECTED_CASES = [
  "after_meetup_followup#1",
  "boundary_friend_hint#1",
  "cold_one_word_replies#1",
  "defer_polite_reason#1",
  "defer_vague_busy#1",
  "defer_with_alternative#1",
  "first_message_after_match#1",
  "hobby_common_ground#1",
  "logistics_confirm#1",
  "long_conversation_35#1",
  "opening_boundary#1",
  "she_asks_his_opinion#1",
  "she_asks_personal_question#1",
  "she_double_texts#1",
  "she_invites_first#1",
  "she_returns_after_silence#1",
  "she_shares_bad_day#1",
  "she_teases_him#1",
  "soft_reject_after_invite#1",
  "thin_opening#1",
  "user_over_investing#1",
  "user_waiting_after_reply#1",
  "warm_question_back#1",
];

Deno.test("重播：錄音涵蓋語料每一案，而且有送出、先別回、收尾三種決定", () => {
  const names = fixtures.cases.map((c) => c.name);
  assertEquals([...names].sort(), EXPECTED_CASES);
  assertEquals(new Set(names).size, names.length);
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

Deno.test("重播切塊：接起來跟原文一字不差，最後一行沒有換行、空行都照原樣", () => {
  for (const raw of ["a\nb", "a\n\nb\n", "\n", "單行"]) {
    assertEquals(replayChunks(raw).join(""), raw);
  }
  assertEquals(replayChunks("a\nb"), ["a\n", "b"]);
  for (const c of fixtures.cases) {
    assertEquals(replayChunks(c.rawText).join(""), c.rawText, c.name);
  }
});
