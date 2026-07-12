import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertPracticeTextGroundedInTurns,
  isGenericPracticeComplimentOrEcho,
  rejectGenericPasteablePracticeText,
  rejectKnownCannedPracticeText,
} from "./practice_visible_quality.ts";

Deno.test("known canned screenshot line is rejected after punctuation normalization", () => {
  assertThrows(
    () =>
      rejectKnownCannedPracticeText(
        "妳剛說的那個點我有記住，我先分享我的版本，再聽妳的。",
        "practice_canned_visible_text",
      ),
    Error,
    "practice_canned_visible_text",
  );
});

Deno.test("generic pasteable text rejects empty coaching moves but accepts a concrete line", () => {
  assertThrows(
    () =>
      rejectGenericPasteablePracticeText(
        "先接住她",
        "practice_quality_invalid",
      ),
    Error,
    "practice_quality_invalid",
  );
  rejectGenericPasteablePracticeText(
    "妳還在賴床喔，那今天先准妳慢慢開機。",
    "practice_quality_invalid",
  );
});

Deno.test("generic compliment detector separates empty praise from a concrete move", () => {
  for (
    const line of [
      "賴床聽起來很舒服耶。",
      "腦袋沒開機感覺很真實。",
      "台南聽起來很有生活感。",
      "台南這個話題很有意思，妳可以再多分享嗎？",
      "咖啡念頭收到。",
    ]
  ) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), true, line);
  }
  for (
    const line of [
      "賴床很舒服，這場先判妳的棉被勝訴。",
      "腦袋沒開機就先慢速，妳想用音樂還是咖啡開機？",
      "咖啡念頭收到，我先押妳今天比較想放空，猜錯妳糾正我。",
    ]
  ) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), false, line);
  }
});

Deno.test("generic echo detector keeps negated admissions substantive even past the last char", () => {
  for (
    const line of [
      "抱歉我沒有記住",
      "我沒聽懂",
      "沒有聽懂",
      "店名我沒有聽到",
    ]
  ) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), false, line);
  }
  for (const line of ["我聽懂了", "我有記住喔"]) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), true, line);
  }
});

Deno.test("generic pasteable text rejects slot-filled canned acknowledgements", () => {
  for (
    const line of [
      "賴床我懂，我也是，妳呢？",
      "腦袋沒開機我懂，我也有過。",
      "賴床我懂啦，我也是，妳呢？",
      "腦袋沒開機我懂耶，我也有過。",
      "賴床我懂，我也常這樣，妳呢？",
      "沒開機我懂，我也常遇到。",
      "賴床收到，我跟妳一樣，妳呢？",
      "沒開機收到，我也差不多。",
      "賴床懂了，我也會這樣，妳呢？",
      "沒開機懂了，我也常這樣。",
      "賴床這個點我有接到，妳呢？",
      "沒開機這件事我先記住。",
      "賴床這個點我收到了，換我說說。",
      "沒開機這件事有接到，我來分享一下。",
      "哈哈我有接到，換我說一點，再聽妳的。",
      "慢慢開機這個點我接到了，換我分享一下。",
      "哈哈收到，我也有過，再聊聊妳的。",
      // The same skeletons must be rejected when they appear as a debrief's
      // suggestedLine, whose topic slot is usually even shorter.
      "哈哈我懂啦，我也是，妳呢？",
      "慢慢開機我懂，我也常這樣，妳呢？",
      "哈哈收到，我跟妳一樣，妳呢？",
      "慢慢開機懂了，我也會這樣，妳呢？",
      "哈哈這個點我收到了，換我說說。",
      "賴床收到喔，我也差不多。",
      "賴床了解，我也常這樣，妳呢？",
      "賴床懂了，我也差不多耶。",
      "賴床收到，我大概也常這樣。",
      "賴床收到，其實我也常這樣。",
      "賴床這個點我接住了，換我說說。",
      "賴床這件事我收到了，換我講一點。",
      "賴床收到，我來聊聊。",
      "她說昨晚追劇到兩點所以今天腦袋完全沒開機我明白了，我好像也常這樣，妳呢？",
      "賴床知道了，我也常這樣，妳呢？",
      "賴床我能理解，我也常這樣，妳呢？",
      "賴床有共鳴，我也會這樣，妳呢？",
      "賴床get到了，我也常這樣，妳呢？",
      "賴床這個點我懂了，換我聊我的。",
      "賴床這件事有接住，換我講我的。",
      "賴床收到，輪到我說。",
      "原來如此，我也常這樣，妳呢？",
      "我懂妳，我也常這樣。",
      "我有感，我也會這樣。",
      "我可以理解，我也常這樣。",
      "賴床懂妳，我也一樣。",
      "賴床已讀，我也常這樣，妳呢？",
      "賴床我懂，我也是，換妳？",
      "賴床喔，我也一樣欸。",
      "賴床可以，我也常這樣。",
      "賴床好，我也差不多。",
      "賴床確實，我也會這樣。",
      "賴床我也一樣，妳咧？",
      "賴床這個點有感，換我分享。",
      "賴床有收到，輪我了。",
    ]
  ) {
    assertThrows(
      () =>
        rejectGenericPasteablePracticeText(
          line,
          "practice_quality_invalid",
        ),
      Error,
      "practice_quality_invalid",
    );
  }
});

Deno.test("slot-filled canned guard preserves concrete natural replies", () => {
  for (
    const line of [
      "妳還在賴床喔，那今天先准妳慢慢開機。",
      "妳的第三個鬧鐘也投降了？那我陪妳用咖啡把腦袋叫醒。",
      "我也常賴床，尤其下雨天；妳今天是被棉被綁架嗎？",
      "賴床我懂啦，我也會這樣，尤其週一鬧鐘響三次都起不來。",
      "沒開機這件事有接到；妳昨晚是不是又追劇到兩點？",
      "賴床我懂啦，我也是；等等去跑步醒腦。",
      "賴床收到喔，我也差不多；今天是被貓踩醒。",
      "賴床這個點我接住了，換我說說被鬧鐘嚇醒的事。",
      "賴床我能理解，我昨晚趕案到三點。",
      "賴床收到，輪到我說我被貓踩醒的事。",
      "賴床知道了，我也常這樣；今天是鬧鐘壞掉。",
      "原來如此，我也常這樣，尤其週一會按掉三個鬧鐘。",
      "賴床我也一樣，今天是被貓踩醒。",
      "賴床可以，我也常這樣；等等去跑步醒腦。",
      "賴床這個點有感，換我分享昨晚趕案到三點的糗事。",
      "賴床有收到，輪我了：我今天是被鬧鐘嚇醒。",
    ]
  ) {
    rejectGenericPasteablePracticeText(line, "practice_quality_invalid");
  }
});

Deno.test("grounding gate accepts a concrete 賴床 callback and rejects generic advice", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋根本沒開機 😂" },
  ];
  assertPracticeTextGroundedInTurns({
    visibleText: "賴床模式先別硬開機，我也想再躺五分鐘。",
    turns,
    latestOnly: true,
    errorCode: "practice_not_grounded",
  });
  assertThrows(
    () =>
      assertPracticeTextGroundedInTurns({
        visibleText: "先接住她的情緒，再自然延伸話題。",
        turns,
        latestOnly: true,
        errorCode: "practice_not_grounded",
      }),
    Error,
    "practice_not_grounded",
  );
  assertEquals(turns.length, 2);
});

Deno.test("grounding gate treats common send verbs as the same concrete action", () => {
  for (const visibleText of ["我先發給妳看。", "我會發給你確認。"]) {
    assertPracticeTextGroundedInTurns({
      visibleText,
      turns: [{ role: "ai", text: "這張照片要傳給誰？" }],
      latestOnly: true,
      errorCode: "practice_quality_not_grounded",
    });
  }
});

Deno.test("grounding gate treats 那家店 and 那間店 as the same venue", () => {
  assertPracticeTextGroundedInTurns({
    visibleText: "妳問那家店，店名叫黑露。",
    turns: [{ role: "ai", text: "那間店名是什麼？" }],
    latestOnly: true,
    errorCode: "not_grounded",
  });
});

Deno.test("grounding gate never treats short, Latin, or emoji text as an automatic pass", () => {
  for (const latest of ["嗯", "OK", "Okay", "Thanks", "haha", "🙂"]) {
    assertThrows(
      () =>
        assertPracticeTextGroundedInTurns({
          visibleText: "哈哈懂，我也是，妳呢？",
          turns: [{ role: "ai", text: latest }],
          latestOnly: true,
          errorCode: "practice_not_grounded",
        }),
      Error,
      "practice_not_grounded",
    );
  }
  assertPracticeTextGroundedInTurns({
    visibleText: "嗯，這句我收到；妳現在比較想安靜一下嗎？",
    turns: [{ role: "ai", text: "嗯" }],
    latestOnly: true,
    errorCode: "practice_not_grounded",
  });
});
