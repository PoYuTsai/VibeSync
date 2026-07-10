// social-game FSM v2 pure rules tests.
// Run: deno test supabase/functions/practice-chat/game_fsm_test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyGameLearningDelta,
  buildGameStrategy,
  evaluateGameFsm,
  hasExplicitSrGameStrategy,
} from "./game_fsm.ts";
import { applyLearningClassification } from "./temperature.ts";
import { GIRL_PROFILES, resolvePracticeProfile } from "./practice_persona.ts";

Deno.test("evaluateGameFsm accumulates BORING when user interrogates instead of sharing", () => {
  const snapshot = evaluateGameFsm({
    turns: [
      { role: "user", text: "你幾歲？住哪？做什麼？" },
      { role: "ai", text: "你查戶口喔 XD" },
      { role: "user", text: "那你下班都去哪？今天在哪？" },
    ],
    temperatureScore: 30,
    familiarityScore: 12,
    partnerMood: "neutral",
  });

  assert(snapshot.failureStates.includes("BORING"));
  assert(snapshot.hidden.inv <= 10);
  assertEquals(snapshot.targetVariable, "Value + Emotion");
});

Deno.test("evaluateGameFsm flags GREASY when low familiarity over-escalates", () => {
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "今晚直接去我家睡啦" }],
    temperatureScore: 42,
    familiarityScore: 18,
    partnerMood: "neutral",
  });

  assert(snapshot.failureStates.includes("GREASY"));
  assert(snapshot.failureStates.includes("GHOST_RISK"));
  assertEquals(snapshot.spicyLevel, "L0");
  assert(snapshot.hidden.safety < 40);
});

Deno.test("evaluateGameFsm moves frame points and heat on test pass or fail", () => {
  const pass = evaluateGameFsm({
    turns: [{ role: "user", text: "好啦我承認我有點太會加戲，但至少不無聊吧" }],
    temperatureScore: 55,
    familiarityScore: 45,
    partnerMood: "amused",
    classification: {
      connection: "caught",
      impact: "medium",
      testHandling: "passed",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "amused",
      moodConfidence: 0.8,
      innerThought: "他有接住我的吐槽。",
    },
  });
  const fail = evaluateGameFsm({
    turns: [{ role: "user", text: "我哪有，我只是正常問而已，不要想太多" }],
    temperatureScore: 55,
    familiarityScore: 45,
    partnerMood: "guarded",
    classification: {
      connection: "defensive",
      impact: "medium",
      testHandling: "failed",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "guarded",
      moodConfidence: 0.8,
      innerThought: "他好像有點急著解釋。",
    },
  });

  assert(pass.hidden.fp > fail.hidden.fp);
  assert(pass.hidden.heatBias > 0);
  assert(fail.hidden.heatBias < 0);
  assert(fail.failureStates.includes("FRAME_COLLAPSE"));
});

Deno.test("evaluateGameFsm advances soft invite toward close when maturity is high enough", () => {
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "那下次找一間你會想吐槽的咖啡店走走？" }],
    temperatureScore: 76,
    familiarityScore: 68,
    partnerMood: "comfortable",
  });

  assertEquals(snapshot.phase, "P5_CLOSE");
  assert(snapshot.hidden.inv >= 60);
  assertEquals(snapshot.speedInviteDirection, "direct_invite_low_pressure");
});

Deno.test("applyGameLearningDelta scales game deltas but clamps the amplitude", () => {
  const basePositive = applyLearningClassification({
    heatScore: 50,
    familiarityScore: 50,
  }, {
    connection: "caught",
    impact: "strong",
    testHandling: "passed",
    boundary: "safe",
    hintAlignment: "none",
    partnerMood: "amused",
    moodConfidence: 0.9,
    innerThought: "他接得很穩。",
  });
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "你這題有陷阱吧，我接，但不照劇本走" }],
    temperatureScore: 50,
    familiarityScore: 50,
    partnerMood: "amused",
    classification: basePositive.classification,
  });
  const gamePositive = applyGameLearningDelta({
    judgement: basePositive,
    currentTemperature: 50,
    currentFamiliarity: 50,
    snapshot,
  });

  assert(gamePositive.delta >= basePositive.delta + 4);
  assert(gamePositive.familiarityDelta >= basePositive.familiarityDelta + 3);
  assert(gamePositive.delta <= 18);

  const baseNegative = applyLearningClassification({
    heatScore: 50,
    familiarityScore: 50,
  }, {
    connection: "overstepped",
    impact: "strong",
    testHandling: "none",
    boundary: "overstep",
    hintAlignment: "none",
    partnerMood: "guarded",
    moodConfidence: 1,
    innerThought: "這太快了。",
  });
  const greasy = evaluateGameFsm({
    turns: [{ role: "user", text: "去我家睡啦" }],
    temperatureScore: 50,
    familiarityScore: 20,
    partnerMood: "guarded",
    classification: baseNegative.classification,
  });
  const gameNegative = applyGameLearningDelta({
    judgement: baseNegative,
    currentTemperature: 50,
    currentFamiliarity: 50,
    snapshot: greasy,
  });

  assertEquals(gameNegative.delta, -18);
  assertEquals(gameNegative.familiarityDelta, -18);
});

Deno.test("evaluateGameFsm marks fake familiarity and social proof as reality-anchor traps", () => {
  const snapshot = evaluateGameFsm({
    turns: [{
      role: "user",
      text:
        "我是陳醫師的學生，最近在北醫實習的牙醫師 Bruce，上次經過你們診所跟 Joyce 要的 Line",
    }],
    temperatureScore: 35,
    familiarityScore: 10,
    partnerMood: "neutral",
  });

  assert(snapshot.realityFlags.includes("social_proof_attempt"));
  assert(snapshot.realityFlags.includes("fake_familiarity"));
  assert(snapshot.failureStates.includes("FRAME_OVERREACH"));
  assertEquals(snapshot.spicyLevel, "L0");
});

Deno.test("buildGameStrategy derives distinct SR hooks", () => {
  const srMia = resolvePracticeProfile({ profileId: "practice_girl_004" });
  const srNora = resolvePracticeProfile({ profileId: "practice_girl_006" });

  const mia = buildGameStrategy(srMia);
  const nora = buildGameStrategy(srNora);

  assert(mia);
  assert(nora);
  assert(mia.valueHooks.join("|") !== nora.valueHooks.join("|"));
  assert(mia.closeHooks.length > 0);
  assert(mia.punishments.length > 0);
});

Deno.test("buildGameStrategy gives non-SR cards concrete fallback hooks from tags", () => {
  const normalAlice = resolvePracticeProfile({
    profileId: "practice_girl_001",
  });

  const strategy = buildGameStrategy(normalAlice);

  assert(strategy, "non-SR card should still get a concrete strategy");
  assertEquals(strategy.profileId, "practice_girl_001");
  assertEquals(hasExplicitSrGameStrategy("practice_girl_001"), false);
  assert(strategy.valueHooks.length > 0);
  assert(strategy.closeHooks.length > 0);
  assert(strategy.punishments.length > 0);
  assert(strategy.testStyle.trim().length > 0);
  assert(strategy.tensionStyle.trim().length > 0);
  const girl = normalAlice.girl;
  const hookText = [...strategy.valueHooks, ...strategy.closeHooks].join("|");
  assert(
    [...girl.interestTags, ...girl.lifestyleTags].some((tag) =>
      hookText.includes(tag)
    ),
    "fallback hooks should be derived from this card's own tags",
  );
});

Deno.test("every card in the pool gets a non-empty Game strategy regardless of rarity", () => {
  const seenRarities = new Set<string>();
  for (const girl of GIRL_PROFILES) {
    seenRarities.add(girl.rarity);
    const profile = resolvePracticeProfile({ profileId: girl.profileId });
    const strategy = buildGameStrategy(profile);
    assert(
      strategy,
      `${girl.profileId} (${girl.rarity}) should get a strategy`,
    );
    assert(
      strategy.valueHooks.length > 0,
      `${girl.profileId} should have valueHooks`,
    );
    assert(
      strategy.closeHooks.length > 0,
      `${girl.profileId} should have closeHooks`,
    );
    assert(
      strategy.punishments.length > 0,
      `${girl.profileId} should have punishments`,
    );
  }
  assert(seenRarities.has("sr"));
  assert(seenRarities.has("r"));
  assert(seenRarities.has("n"));
});

Deno.test("every SR card has an explicit Game strategy track", () => {
  const srProfiles = GIRL_PROFILES.filter((girl) => girl.rarity === "sr");

  assertEquals(srProfiles.length > 0, true);
  for (const girl of srProfiles) {
    const profile = resolvePracticeProfile({ profileId: girl.profileId });
    const strategy = buildGameStrategy(profile);
    assert(strategy, `${girl.profileId} should have an SR Game strategy`);
    assert(
      hasExplicitSrGameStrategy(girl.profileId),
      `${girl.profileId} should not rely on fallback derivation`,
    );
    assert(strategy.valueHooks.length >= 2);
    assert(strategy.closeHooks.length >= 2);
    assert(strategy.punishments.length >= 1);
  }
});

Deno.test("every explicit SR Game strategy uses Traditional Chinese prompt values", () => {
  const srProfiles = GIRL_PROFILES.filter((girl) => girl.rarity === "sr");

  for (const girl of srProfiles) {
    assert(
      hasExplicitSrGameStrategy(girl.profileId),
      `${girl.profileId} should have an explicit SR Game strategy`,
    );
    const strategy = buildGameStrategy(
      resolvePracticeProfile({ profileId: girl.profileId }),
    );
    const promptValues = [
      ...strategy.valueHooks,
      strategy.testStyle,
      strategy.tensionStyle,
      ...strategy.closeHooks,
      ...strategy.punishments,
    ];

    for (const value of promptValues) {
      assert(
        !/[A-Za-z]/.test(value),
        `${girl.profileId} leaked English prompt value: ${value}`,
      );
    }
  }
});
