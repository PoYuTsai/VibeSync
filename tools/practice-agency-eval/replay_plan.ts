// Phase 3.8 診斷工具：把 artifact 的逐字稿逐輪重建 bundle，數強制問他（askUserFocus）真的觸發幾場、沒觸發卡在哪個條件。
// 用法：deno run --allow-read --allow-env tools/practice-agency-eval/replay_plan.ts <artifact.json>
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  type ConversationAgencyState,
  nextConversationAgencyState,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import { detectTurnSignals } from "../../supabase/functions/practice-chat/turn_response_plan.ts";
import {
  BAKEOFF_THREAD_ID,
  buildBakeoffContextFixture,
} from "../practice-difficulty-bakeoff/bakeoff.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
const file = Deno.args[0];
const art = JSON.parse(await Deno.readTextFile(file));
const counts: Record<string, Record<string, number>> = {};
const bump = (p: string, k: string) => {
  counts[p] ??= {};
  counts[p][k] = (counts[p][k] ?? 0) + 1;
};
for (const s of art.results) {
  const profile = resolvePracticeProfile({
    profileId: s.profileId,
    difficulty: s.difficulty,
  });
  const fx = buildBakeoffContextFixture(profile);
  const chatContext = {
    sceneContext: fx.sceneContext,
    acquaintanceOrigin: fx.acquaintanceOrigin,
    memorySummary: fx.memorySummary,
    timeContext: fx.timeContext,
    herRecentMomentsBlock: fx.herRecentMomentsBlock,
  };
  const turns: PracticeTurn[] = [];
  let agencyState: ConversationAgencyState | null = null;
  for (const t of s.turns) {
    if (t.role !== "user") {
      turns.push({ role: "ai", text: t.reply });
      continue;
    }
    turns.push({ role: "user", text: t.userText });
    const bundle = buildChatPromptBundle(turns, profile, {
      replyStyle: true,
      agencyMode: "on",
      visiblePracticeThreadId: BAKEOFF_THREAD_ID,
      partnerState: null,
      styleState: null,
      agencyState,
      practiceMode: "beginner",
      temperatureScore: 40,
      familiarityScore: 10,
      ...chatContext,
    } as any);
    const pid = t.probe?.id ?? "p1";
    const plan = bundle.responsePlan!;
    const forced = plan.askUserFocus !== undefined;
    bump(pid, forced ? "forced" : "not");
    if (!forced) {
      const sig = detectTurnSignals(turns);
      const ag = bundle.agencyDecision;
      const why = ag?.applied
        ? "applied"
        : sig.aiQuestionStreak > 0
        ? "streak"
        : sig.userIsQuestion
        ? "userQ"
        : agencyState?.askedAboutUser
        ? "asked"
        : (plan.situation !== "neutral" && plan.situation !== "share")
        ? `sit:${plan.situation}`
        : (plan.primaryAct === "soft_close" ||
            plan.primaryAct === "direct_boundary")
        ? `act:${plan.primaryAct}`
        : "other";
      bump(pid, "why:" + why);
    }
    const askedUser = forced;
    if (bundle.agencyDecision && (bundle.agencyDecision.applied || askedUser)) {
      agencyState = nextConversationAgencyState(
        agencyState,
        bundle.agencyDecision.decision,
        null,
        askedUser,
      );
    }
    turns.push({ role: "ai", text: t.reply });
  }
}
console.log(JSON.stringify(counts, null, 1));
