import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertPracticeTextGroundedInTurns,
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
