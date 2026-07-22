// --dry-run 模式的假 callClaude：不打任何網路，回傳固定樣板的合法 tool_use
// input JSON（依 fixture 動態嵌入她最新一句的原文片段，滿足逐字稿接地 gate）。
// 目的＝驗證全部 fixture 能過 buildMessages＋parser／守門不炸，非驗模型品質。
import type { ClaudeArgs } from "../../supabase/functions/practice-chat/claude.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import type { EvalFixture } from "./fixtures/types.ts";

function latestAiText(turns: PracticeTurn[]): string {
  for (let index = turns.length - 1; index >= 0; index--) {
    if (turns[index].role === "ai") return turns[index].text;
  }
  return "";
}

/**
 * 取她最新一句裡最長的連續漢字片段（截 8 字）當接地錨點。
 * fixture 設計上保證最新 ai 句一定有 ≥6 字的連續漢字片段。
 */
export function groundingChunk(turns: PracticeTurn[]): string {
  const text = latestAiText(turns).normalize("NFKC");
  const runs = (text.match(/\p{Script=Han}{4,}/gu) ?? [])
    .sort((a, b) => b.length - a.length);
  // 優先挑不含人稱/時間窗字眼的片段：她的「我這週六有空」被原樣嵌進
  // 使用者視角的樣板句時，會變成使用者自己的未接地行程主張（事實 gate 會打回）。
  const safe = runs.find((run) =>
    !/[我你妳]|週[一二三四五六日末]|禮拜|下午|晚上|明天|後天|有空/u.test(run)
  );
  const best = safe ?? runs[0] ?? "";
  if (best.length === 0) {
    return text.replace(/[\s\p{P}\p{S}]/gu, "").slice(0, 8);
  }
  return best.slice(0, 8);
}

function fakeHintInput(fixture: EvalFixture): Record<string, string> {
  const chunk = groundingChunk(fixture.turns);
  if (fixture.practiceMode === "game") {
    return {
      warmUp: `${chunk}這句我要記下來，妳的反應比我想的更有戲。`,
      steady: `被妳說${chunk}我就放心了，我本來還想裝一下酷。`,
      coaching: `Game 心法：她這句可能是在測你的反應，這輪還在累積熟悉的階段。` +
        `速約任務：先接住她說的${chunk}，回一句有畫面的答案，因為投入感還不夠，先不硬約。`,
    };
  }
  return {
    warmUp: `妳說${chunk}我整個有畫面，這段我想聽完整版。`,
    steady: `${chunk}被妳講得雲淡風輕，我反而更好奇後續了。`,
    coaching: `她願意聊${chunk}，代表話題有接住，你先回應這段感受，` +
      `再交換一件自己的日常，不用急著推進。`,
  };
}

function fakeDebriefInput(fixture: EvalFixture): Record<string, unknown> {
  const chunk = groundingChunk(fixture.turns);
  const base: Record<string, unknown> = {
    summary: `你有接住她說的${chunk}，也分享了自己的版本，整場節奏穩。`,
    strengths: [`你接住她的${chunk}，還延伸出自己的生活畫面`],
    watchouts: [
      `下次聊到${chunk}時，可以先補一句自己的感受，再問她一個具體的問題`,
    ],
    suggestedLine: `我還在想妳說的${chunk}，這段沒聽到完整版我不甘心，補個後續給我。`,
    vibe: "暖",
    dateChance: "medium",
    dateChanceReason: `她聊${chunk}時有來有回，投入是夠的，但見面窗口還沒出現。`,
    nextInviteMove: `下次可以從${chunk}延伸，問她平常的行程節奏，再看她的反應決定要不要提小約。`,
  };
  if (fixture.practiceMode === "game") {
    base.gameBreakdown = {
      phaseReached: `聊到${chunk}時，你們已經走到互相測試的階段`,
      missedVariable: `還缺一點你的生活畫面，她丟${chunk}時你給的細節不夠`,
      failureState: `${chunk}之後節奏偏硬，差點變成單向問答`,
      nextFirstLine: `我後來又想到妳說的${chunk}，越想越不對勁，妳得親自解釋一下。`,
      inviteDirection: `從${chunk}延伸聊回她的節奏，等她再開一次時間窗口就順勢提短咖啡`,
    };
  }
  return base;
}

/** 模擬單發延遲（毫秒），讓 dry-run 也能跑完整計時流程。 */
const FAKE_LATENCY_MS = 5;

export function makeFakeCallClaude(
  fixture: EvalFixture,
): (args: ClaudeArgs) => Promise<string> {
  return async (args: ClaudeArgs): Promise<string> => {
    await new Promise((resolve) => setTimeout(resolve, FAKE_LATENCY_MS));
    const input = args.forcedTool?.name === "emit_debrief_card"
      ? fakeDebriefInput(fixture)
      : fakeHintInput(fixture);
    return JSON.stringify(input);
  };
}
