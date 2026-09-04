// Phase 3.8 診斷工具：把 artifact 的逐字稿逐輪重建 bundle，數強制問他（askUserFocus）真的觸發幾場、沒觸發卡在哪個條件。
// Phase 4.0 另外數三個分人強弱 consumer 的實際觸發：低容忍的 forced ask_intent、高 initiative 的 self_disclose、高 persistence 的 persist 候選組。
// 用法：deno run --allow-read --allow-env tools/practice-agency-eval/replay_plan.ts <artifact.json>
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  type ConversationAgencyState,
  nextConversationAgencyState,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import { detectTurnSignals } from "../../supabase/functions/practice-chat/turn_response_plan.ts";
import { buildBakeoffContextFixture } from "../practice-difficulty-bakeoff/bakeoff.ts";
import { saltedThreadId, threadSaltOfArtifactMeta } from "./run_agency.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
const file = Deno.args[0];
// Phase 4.3：production 的分類器在 chat 生成**之後**才跑，所以 artifact 裡沒有
// 每一輪當時的 `aiChallengedThisTurn`。回放預設把它當成缺席（＝assisted 退回
// standard 的保守近似）；`--ai-clarified=1|0` 可以模擬「她每一輪都真的在澄清」
// ／「每一輪都只是問內容問題」兩個上下界，把 production 行為夾在中間。
const aiClarifiedArg = Deno.args.find((x) => x.startsWith("--ai-clarified="));
const aiClarified = aiClarifiedArg === undefined
  ? null
  : aiClarifiedArg.slice("--ai-clarified=".length) === "1";
const art = JSON.parse(await Deno.readTextFile(file));
// Phase 4.2：artifact 用 `--thread-salt` 跑的話，thread id 每個 repeat 都不同，
// 回放要照同一支 `saltedThreadId` 算，否則 seed 對不上（骰子面會不一樣）。
const threadSalt = threadSaltOfArtifactMeta(art.meta);
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
      visiblePracticeThreadId: saltedThreadId(threadSalt, s.repeat),
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
    // Phase 4.0 consumer 觸發計數（分母＝這個探針位置的全部輪次）。
    const setId = bundle.agencyDecision?.decision.allowedActSetId;
    if (bundle.agencyDecision?.applied) {
      // Phase 4.3：policy 層的強制／候選組分佈（差集用），與 3.8 的
      // `forced`（＝強制問他一件事 askUserFocus）是兩件事，前綴分開。
      const dec = bundle.agencyDecision.decision;
      bump(pid, `p43:${dec.policyMode}`);
      if (dec.forcedAct) bump(pid, `p43:act:${dec.forcedAct}`);
      bump(pid, `p43:set:${dec.allowedActSetId}`);
    }
    if (bundle.agencyDecision?.applied) {
      if (bundle.agencyDecision.decision.forcedAct === "ask_intent") {
        bump(pid, "p4:forcedAskIntent");
      }
      if (setId?.startsWith("answer_or_challenge_persist")) {
        bump(pid, "p4:persistSet");
      }
    }
    // Codex R2 P1：只數 Phase 4.0 initiative 分支的自曝（agency on、玩家這句是純
    // 反應詞、profile initiative ≥3）；A25.p9／A26.p9 那種 self_share 輪的
    // self_disclose 是既有 reply-style bias，不算。
    if (
      plan.optionalAct === "self_disclose" &&
      bundle.agencyDecision?.enabled === true &&
      bundle.agencyDecision.decision.evidence.utteranceShape === "reaction" &&
      (bundle.agencyDecision.profile?.initiative ?? 0) >= 3
    ) bump(pid, "p4:selfDisclose");
    if (!forced) {
      const sig = detectTurnSignals(turns);
      const ag = bundle.agencyDecision;
      const why = ag?.applied
        ? "applied"
        : sig.aiQuestionStreak > 0
        ? "streak"
        : sig.userIsQuestion
        ? "userQ"
        // Phase 4.2：停滯輪（純反應詞）不強制問他。
        : ag?.decision.evidence.utteranceShape === "reaction"
        ? "reaction"
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
    // Phase 4.3：與 production 對齊——`handler.ts` 是「旗標 on 就一定推進狀態」
    // （Codex round-1 新項 P1-1：`applied` 只是「有沒有注入 guidance」，不是狀態
    // 機的閘門）。舊版回放多一個 `applied || askedUser` 條件，修復輪不推進，
    // 會讓 `aiClarifiedLastTurn`／`repairedAtUserTurns` 的軌跡跟正式路徑不同。
    if (bundle.agencyDecision) {
      agencyState = nextConversationAgencyState(
        agencyState,
        bundle.agencyDecision.decision,
        aiClarified === null ? null : { aiChallengedThisTurn: aiClarified },
        askedUser,
      );
    }
    turns.push({ role: "ai", text: t.reply });
  }
}
console.log(JSON.stringify(counts, null, 1));
