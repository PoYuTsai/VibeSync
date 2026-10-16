// v3 重播測試：10/15 v3.3 黑箱錄下的 Sonnet 5.5 兩段原始輸出，原樣餵回正式的 v3 流程。
// 送給 App 的事件、扣費呼叫、落帳結果都要跟期望值一模一樣；另外每一案各自檢查扣費的
// 不變條件（只扣一次、扣在第一張卡之前、done 只由送出的卡組成）。改規則、定稿或流程時，
// 這支會指出哪一案哪裡變了；有意的改動用 tools/ci/regen-guide-v3-replay-fixtures.ts
// 重產期望值，審查時看差異。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import fixtures from "../testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import { replayGuideV3, replayLines } from "./replay_harness.ts";

// 內建語料 23 案（每案第 1 次）。少一案、多一案或重複都要失敗。
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

type Event = Record<string, unknown>;

function readDecision(events: Event[]): unknown {
  return events.find((e) => e.type === "analysis.read")?.decision;
}

Deno.test("v3 重播：錄音涵蓋語料每一案，而且有出卡、收尾、先別回三種決定", () => {
  const names = fixtures.cases.map((c) => c.name);
  assertEquals([...names].sort(), EXPECTED_CASES);
  assertEquals(new Set(names).size, names.length);
  const decisions = new Set(
    fixtures.cases.map((c) => readDecision(c.expected.events as Event[])),
  );
  for (const d of ["send", "close", "hold"]) assert(decisions.has(d), d);
});

for (const replayCase of fixtures.cases) {
  Deno.test(`v3 重播：${replayCase.name}`, async () => {
    const outcome = await replayGuideV3(replayCase);
    assertEquals(outcome, replayCase.expected);

    // 不靠期望值也要成立的扣費條件。
    const events = outcome.events;
    const cards = events.filter((e) => e.type === "analysis.card");
    const done = events.at(-1)!;
    assertEquals(events[0].type, "analysis.started");
    assertEquals(done.type, "analysis.done");
    assertEquals(outcome.charges.length, 1, "每一案只扣一次");
    const decision = readDecision(events);
    if (decision === "send" || decision === "close") {
      assert(cards.length >= 1);
      const chargeAt = outcome.calls.findIndex((c) => c.startsWith("charge:"));
      assert(chargeAt > outcome.calls.indexOf("write"), "扣在寫卡開始之後");
      assertEquals(outcome.charges[0].cardTask, cards[0].task);
      assertEquals(outcome.charges[0].decisionKind, "send");
    } else {
      assertEquals(cards.length, 0);
      assertEquals(outcome.calls.includes("write"), false);
      assertEquals(outcome.charges[0].cardTask, null);
    }
    const finalCards = (done.finalResult as { cards: Event[] }).cards;
    assertEquals(
      finalCards,
      cards.map(({ type: _type, ...rest }) => rest),
      "done 只由送出的卡組成",
    );
    for (const card of cards) {
      if (card.voice === "default") {
        assert(
          !(card.messages as string[]).some((m) => m.includes("妳")),
          "預設口吻不留「妳」",
        );
      }
    }
  });
}

Deno.test("v3 重播切行：接起來跟原文一字不差", () => {
  for (const raw of ["a\nb", "a\n\nb\n", "\n", "單行"]) {
    assertEquals(replayLines(raw).join(""), raw);
  }
  for (const c of fixtures.cases) {
    assertEquals(replayLines(c.writeText).join(""), c.writeText, c.name);
  }
});
