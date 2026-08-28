import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyStageFloor,
  practiceInviteFloorFor,
  practiceStageFloorFor,
  practiceUserTurnCount,
  standardPacingLine,
} from "./practice_pacing.ts";
import { inviteMaturityFromLearningScores } from "./invite_maturity.ts";
import { buildHintDecision, buildHintMessages } from "./hint.ts";
import { buildChatMessages } from "./prompt.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";
import type { PracticeTurn } from "./validate.ts";

const profile = resolvePracticeProfile({ profileId: "practice_girl_004" });

function turns(userTurnCount: number): PracticeTurn[] {
  const out: PracticeTurn[] = [];
  for (let i = 0; i < userTurnCount; i++) {
    out.push({ role: "user", text: `使用者第${i}句` });
    out.push({ role: "ai", text: `她第${i}句` });
  }
  return out;
}

Deno.test("回合下限照球數升階，第 3／6／8 顆球是分界", () => {
  assertEquals(practiceStageFloorFor(2), null);
  assertEquals(practiceStageFloorFor(3), "personal_allowed");
  assertEquals(practiceStageFloorFor(5), "personal_allowed");
  assertEquals(practiceStageFloorFor(6), "flirt_allowed");
  assertEquals(practiceInviteFloorFor(7), null);
  assertEquals(practiceInviteFloorFor(8), "soft_invite_ready");
});

Deno.test("她 guarded／annoyed 時整組下限不套（安全網照 game）", () => {
  assertEquals(practiceStageFloorFor(9, "guarded"), null);
  assertEquals(practiceStageFloorFor(9, "annoyed"), null);
  assertEquals(practiceInviteFloorFor(9, "guarded"), null);
  assertEquals(standardPacingLine(9, "annoyed"), "");
});

Deno.test("下限只往上抬，不會把已經到位的階段拉回去", () => {
  assertEquals(
    applyStageFloor(
      { stage: "flirt_allowed", label: "可以輕推曖昧" },
      "personal_allowed",
    )
      .stage,
    "flirt_allowed",
  );
  assertEquals(
    applyStageFloor(
      { stage: "building_familiarity", label: "建立熟悉中" },
      "personal_allowed",
    ),
    { stage: "personal_allowed", label: "可以聊個人" },
  );
});

Deno.test("邀約下限抬到模糊邀約後，mood 降階仍然照舊套用", () => {
  const base = { temperatureScore: 20, familiarityScore: 10 };
  assertEquals(inviteMaturityFromLearningScores(base)?.stage, "not_ready");
  assertEquals(
    inviteMaturityFromLearningScores({
      ...base,
      stageFloor: "soft_invite_ready",
    })
      ?.stage,
    "soft_invite_ready",
  );
  // annoyed 的上限是 soft_invite_ready，下限不得突破它。
  assertEquals(
    inviteMaturityFromLearningScores({
      ...base,
      partnerMood: "annoyed",
      stageFloor: "direct_invite_ready",
    })?.stage,
    "soft_invite_ready",
  );
});

Deno.test("新手 hint：開場照舊只輕推，聊開後改口不再壓在客套問答", () => {
  const early = buildHintMessages({
    turns: turns(1),
    profile,
    practiceMode: "beginner",
    temperatureScore: 40,
  }).map((message) => message.content).join("\n");
  assert(early.includes("新手低溫或剛開場只輕推情緒"));

  const later = buildHintMessages({
    turns: turns(6),
    profile,
    practiceMode: "beginner",
    temperatureScore: 40,
  }).map((message) => message.content).join("\n");
  assert(!later.includes("新手低溫或剛開場只輕推情緒"));
  assert(later.includes("別再停在客套問答"));
});

Deno.test("新手 hint 拿到分則與繁中語感，但拿不到速約戰術", () => {
  const prompt = buildHintMessages({
    turns: turns(2),
    profile,
    practiceMode: "beginner",
    temperatureScore: 40,
  }).map((message) => message.content).join("\n");
  assert(prompt.includes("可以分則"));
  assert(prompt.includes("短不等於空"));
  assert(prompt.includes("partnerBubbleRhythm"));
  assert(!prompt.includes("速約任務"));
  assert(!prompt.includes("speedInviteLadder"));
});

Deno.test("標準模式聊開後在 NPC prompt 拿到 pacing 行；game 完全不受影響", () => {
  const standardEarly = buildChatMessages(turns(2), profile, {
    practiceMode: "standard",
  }).map((message) => message.content).join("\n");
  assert(!standardEarly.includes("pacing:"));

  const standardLater = buildChatMessages(turns(8), profile, {
    practiceMode: "standard",
  }).map((message) => message.content).join("\n");
  assert(standardLater.includes("pacing:"));
  assert(standardLater.includes("模糊邀約"));

  const game = buildChatMessages(turns(8), profile, {
    practiceMode: "game",
    temperatureScore: 40,
    familiarityScore: 20,
  }).map((message) => message.content).join("\n");
  assert(!game.includes("pacing:"));
});

Deno.test("practiceUserTurnCount 只算使用者出手數", () => {
  assertEquals(practiceUserTurnCount(turns(4)), 4);
});

// ── PR 4：推進下限吃難度 ─────────────────────────────────────────────

const challengeProfile = resolvePracticeProfile({
  profileId: "practice_girl_004",
  difficulty: "challenge",
});

Deno.test("challenge 下限延後到 5／9，且沒有純回合數的邀約下限", () => {
  assertEquals(practiceStageFloorFor(4, null, "challenge"), null);
  assertEquals(practiceStageFloorFor(5, null, "challenge"), "personal_allowed");
  assertEquals(practiceStageFloorFor(8, null, "challenge"), "personal_allowed");
  assertEquals(practiceStageFloorFor(9, null, "challenge"), "flirt_allowed");
  assertEquals(practiceInviteFloorFor(8, null, "challenge"), null);
  assertEquals(practiceInviteFloorFor(30, null, "challenge"), null);
});

Deno.test("easy／normal 明寫難度仍是 3／6／8", () => {
  for (const difficulty of ["easy", "normal"] as const) {
    assertEquals(
      practiceStageFloorFor(3, null, difficulty),
      "personal_allowed",
    );
    assertEquals(practiceStageFloorFor(6, null, difficulty), "flirt_allowed");
    assertEquals(practiceInviteFloorFor(7, null, difficulty), null);
    assertEquals(
      practiceInviteFloorFor(8, null, difficulty),
      "soft_invite_ready",
    );
  }
});

Deno.test("challenge 的 guarded／annoyed 一樣整組停用", () => {
  assertEquals(practiceStageFloorFor(9, "guarded", "challenge"), null);
  assertEquals(practiceStageFloorFor(9, "annoyed", "challenge"), null);
  assertEquals(standardPacingLine(9, "guarded", "challenge"), "");
});

Deno.test("standard challenge 的 pacing 行更慢，且不因回合數放行模糊邀約", () => {
  assertEquals(standardPacingLine(5, null, "challenge"), "");
  assert(standardPacingLine(6, null, "challenge").includes("pacing:"));
  assert(!standardPacingLine(12, null, "challenge").includes("模糊邀約"));
});

Deno.test("NPC prompt 與 Hint 守門同一份政策：challenge 第 8 顆球不放行模糊邀約", () => {
  const lowScores = { temperatureScore: 20, familiarityScore: 10 };
  const normalPrompt = buildChatMessages(turns(8), profile, {
    practiceMode: "beginner",
    ...lowScores,
  }).map((message) => message.content).join("\n");
  assert(normalPrompt.includes("inviteStage: soft_invite_ready"));

  const challengePrompt = buildChatMessages(turns(8), challengeProfile, {
    practiceMode: "beginner",
    ...lowScores,
  }).map((message) => message.content).join("\n");
  assert(challengePrompt.includes("inviteStage: not_ready"));

  const softInviteReply = {
    replyType: "warm_up" as const,
    replyText: "改天有空也可以一起去河邊走走。",
    rationale: "她提到喜歡散步，把它變成低壓共同畫面。",
  };
  const normalDecision = buildHintDecision({
    turns: turns(8),
    profile,
    practiceMode: "beginner",
    ...lowScores,
    ...softInviteReply,
  });
  assertEquals(normalDecision.inviteRoute, "soft_invite_ready");
  assertThrows(
    () =>
      buildHintDecision({
        turns: turns(8),
        profile: challengeProfile,
        practiceMode: "beginner",
        ...lowScores,
        ...softInviteReply,
      }),
    Error,
    "hint_quality_invalid_invite_route",
  );
});
