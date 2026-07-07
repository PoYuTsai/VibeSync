import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  inviteMaturityForScore,
  inviteMaturityFromLearningScores,
  inviteMaturityPrompt,
} from "./invite_maturity.ts";

Deno.test("inviteMaturityForScore maps product thresholds", () => {
  assertEquals(inviteMaturityForScore(49).stage, "not_ready");
  assertEquals(inviteMaturityForScore(50).stage, "soft_invite_ready");
  assertEquals(inviteMaturityForScore(65).stage, "direct_invite_ready");
  assertEquals(inviteMaturityForScore(80).stage, "partner_window");
  assertEquals(inviteMaturityForScore(85).stage, "high_intimacy");
});

Deno.test("inviteMaturityForScore caps partner-window behavior when mood is guarded", () => {
  const maturity = inviteMaturityForScore(86, { partnerMood: "guarded" });

  assertEquals(maturity.stage, "direct_invite_ready");
  assertEquals(maturity.score, 86);
  assert(maturity.guidance.includes("guarded"));
});

Deno.test("inviteMaturityFromLearningScores derives a relationship proxy", () => {
  const maturity = inviteMaturityFromLearningScores({
    temperatureScore: 90,
    familiarityScore: 80,
    partnerMood: "comfortable",
  });

  assert(maturity);
  assertEquals(maturity.score, 86);
  assertEquals(maturity.stage, "high_intimacy");
});

Deno.test("inviteMaturityPrompt exposes guidance without guaranteeing take-home outcome", () => {
  const text = inviteMaturityPrompt(inviteMaturityForScore(88));

  assert(text.includes("inviteMaturity"));
  assert(text.includes("high_intimacy"));
  assert(text.includes("類女友感"));
  assertEquals(text.includes("約回家"), false);
});
