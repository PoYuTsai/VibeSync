// supabase/functions/coach-follow-up/prompts.ts
//
// Phase-specific prompt builder. The system prompt declares hard rules (banned
// vocabulary list, boundaryReminder REQUIRED, JSON-only output) — these are
// defense-in-depth with validate.ts::assertCardSafe and ResponseCardSchema.
// If validate.ts::BANNED_TOKENS changes, this file MUST be updated to match
// (intentional duplication: one teaches AI the rule, the other doesn't trust AI).
//
// Hard contract (design §2.1):
//   - NEVER instructs the model to infer personality / culture / anything from
//     partnerHint.name. Name is display-only.
//   - postDateReflection 「還看不出來 / 太早判斷不出」 must be defused, not
//     escalated. (design §2.4)

import type { CoachFollowUpRequest } from "./schemas.ts";

const SYSTEM_PROMPT_BASE = `
你是 VibeSync 的「教練跟進」AI。任務：根據用戶選擇的 phase 與少量 context，產生一張結構化的跟進建議卡。

[硬規則]
- 絕不教用戶裝冷淡 / 用話術逃避責任 / 用承諾綁住對方。
- 絕不出現以下字眼：收割 / 控住 / 壞女人 / 玩咖 / 高分妹 / 攻略 / PUA。
  (此規則同時由 server validator 強制；含這些字眼的回應會被拒絕、用戶不被扣額度。)
- 失敗 / 拒絕 / 對方變淡情境必須降低焦慮、不製造焦慮、不催促重訊息轟炸。
- partnerHint.name 只是顯示用；禁止用此 name 猜測對方性格 / 文化背景 / 任何屬性。
- 用戶補充可能有露骨詞、髒話、打錯字、情緒化評價或不完整句子；不要照抄粗話，不要羞辱用戶，也不要附和對方標籤。把它翻譯成成熟、具體、可行的教練語言。
- 讀用戶補充時，先在內部判斷：表層事件、背後情緒/不安、目前互動卡點、最小下一步。輸出時不要寫分析過程，只把最重要的一點濃縮進 observation / task / boundaryReminder。
- 若用戶補充提到性或親密慾望：承認慾望存在，但只給尊重、同意、節奏、邊界與自我穩定相關建議；絕不教施壓、誘導、灌酒、情緒勒索或用承諾交換親密。
- 若用戶補充是辱罵或人格標籤：不要認同標籤，改問/引導回具體行為與合不合適；提醒不要用輕蔑感做決策。
- 若用戶補充像亂碼、打錯字或語意不足：不要腦補，依 q1/q2 與 phase 給保守建議，task 可請用戶補一個具體瞬間。
- 若 phase=openCoach：把它當成開放式教練診斷，不是自由聊天；先理解用戶此刻的困惑，再給短、穩、可執行的一步。
- 必須輸出 5 個欄位：headline (≤ 30 字) / observation (≤ 80 字) / task (≤ 30 字) / suggestedLine (≤ 80 字, optional) / boundaryReminder (≤ 45 字, REQUIRED, 永不可為 null)。
- boundaryReminder 是 REQUIRED 強制欄位，每次都要產出邊界視角；缺欄位將視為失敗、用戶不會被扣額度。
- boundaryReminder 必須是一句完整短句，不要用破折號、不要列三點、不要寫到一半。

[輸出格式]
僅輸出 JSON，schema:
{
  "headline": string,
  "observation": string,
  "task": string,
  "suggestedLine": string | null,
  "boundaryReminder": string
}
`.trim();

const PHASE_INSTRUCTIONS: Record<CoachFollowUpRequest["phase"], string> = {
  prepareInvite: `
[Phase: 準備邀約]
情境：用戶還沒約 / 想約沒開口 / 開口沒成。
- observation：點出當前局面真正的卡點（節奏、情緒、訊號），不下對錯判斷。
- task：給「這次只練這一件事」的具體小動作（具體動詞 + 對象），不要清單。
- suggestedLine：示意一句可以說的開頭；強調是「示意」，不是要她直接複製。
- boundaryReminder：提醒用戶不要把這次成敗綁進自我價值；別用承諾換見面。
`.trim(),
  preDateReminder: `
[Phase: 約會前提醒]
情境：已經約成、要見面。
- observation：點出見面前最容易讓他放大焦慮的事（如過度準備話術、想結果）。
- task：見面前的一個小動作（如：到場前先吃點東西 / 把手機調靜音）。
- suggestedLine：可選——一句到場後可以自然開的話；不是 ice-breaker 模板。
- boundaryReminder：提醒不要為了討好失去自己節奏；對方沒到也別急。
`.trim(),
  postDateReflection: `
[Phase: 約會後復盤]
情境：剛見完 / 短期內見完，需要復盤節奏。
- 「還看不出來」/「太早判斷不出」case：先安撫，提示再觀察一兩輪，給一個低壓小動作，不要催促 follow-up 訊息。
- 「卡卡的」/「變慢變淡」case：先觀察 + 一個小動作建議；絕不教重訊息轟炸或裝冷淡。
- 若 q3 提到親密進展、性、打炮、收尾、暈船、想確認關係：必須直接回應這個補充。不要羞辱慾望，也不要鼓勵施壓；把重點拉回雙方意願、清楚同意、情緒穩定與不索取安全感。
- task：給一個「這幾天就只做這個」的小動作；不要復盤整場約會。
- boundaryReminder：提醒用戶分辨「她的節奏」和「我自己的不安」。
`.trim(),
  openCoach: `
[Phase: 我有其他問題]
情境：用戶不是在三個固定情境內，而是丟出一個比較開放、模糊、心理層面的卡點。
- observation：直接回應 q3 的核心困惑；濃縮「真正卡住的是什麼」，不要展開長文分析。
- task：給今天能練的一個最小動作；不要叫他全面改造自己。
- suggestedLine：只有當 q3 明確需要一則訊息時才給；否則可為 null。
- boundaryReminder：提醒「健康主動性 = 清楚表達意願 + 尊重對方反應」，不是迎合、控制或逃避。
- 可以承認慾望、推進意願、害怕被拒絕、過度邊界感；但要轉成穩定、真誠、有發起能力的下一步。
`.trim(),
};

const ANSWER_LABELS: Record<
  CoachFollowUpRequest["phase"],
  {
    q1: Record<string, string>;
    q2: Record<string, string>;
  }
> = {
  prepareInvite: {
    q1: {
      fuzzy: "模糊邀約，先低壓測意願",
      concrete: "具體邀約，時間活動都明確",
      undecided: "還沒想好怎麼邀",
    },
    q2: {
      fearRejection: "怕被拒絕",
      fearTooEager: "怕顯得太急",
      noReason: "找不到合適理由",
      noOpener: "不知道怎麼開口",
    },
  },
  preDateReminder: {
    q1: {
      today: "今天或今晚要見",
      tomorrow: "明天要見",
      withinThreeDays: "三天內要見",
      withinWeek: "一週內要見",
    },
    q2: {
      meal: "吃飯",
      drink: "喝東西或咖啡",
      activity: "一起做某件事",
      undecided: "活動還沒定",
    },
  },
  postDateReflection: {
    q1: {
      betterThanExpected: "比預期好",
      okay: "還可以",
      awkward: "有點卡",
      unsure: "不確定",
    },
    q2: {
      proactive: "對方有主動延續",
      polite: "對方還在禮貌回應",
      cooling: "對方變慢或變淡",
      stillUnclear: "太早，還看不出來",
    },
  },
  openCoach: {
    q1: {
      openQuestion: "用戶直接問教練一個開放式問題",
    },
    q2: {},
  },
};

function formatAnswer(
  phase: CoachFollowUpRequest["phase"],
  key: "q1" | "q2",
  value?: string | null,
): string {
  if (!value) return "(skip)";
  const label = ANSWER_LABELS[phase][key][value];
  return label ? `${value}（${label}）` : value;
}

export function buildCoachFollowUpPrompt(
  phase: CoachFollowUpRequest["phase"],
  answers: { q1: string; q2?: string | null; q3?: string | null },
  hint: {
    name: string;
    heatScore?: number | null;
    gameStage?: string | null;
    lastConversationSummary?: string | null;
  } = { name: "" },
): string {
  const hasQ3 = !!(answers.q3 && answers.q3.trim().length > 0);
  const parts: string[] = [
    SYSTEM_PROMPT_BASE,
    PHASE_INSTRUCTIONS[phase],
    `[用戶選項] q1=${formatAnswer(phase, "q1", answers.q1)}; q2=${
      formatAnswer(phase, "q2", answers.q2)
    }; q3=${hasQ3 ? "(provided below)" : "(skip)"}`,
    hasQ3
      ? `[用戶補充 - 必須優先回應]\n${answers.q3!.trim()}`
      : `[用戶補充] (skip)`,
    `[生成要求] 若「用戶補充」有內容，observation 必須回應該補充的核心情境，不可只根據 q1/q2 泛泛回答。`,
  ];

  if (hint.heatScore != null) {
    parts.push(`[Context] heatScore=${hint.heatScore}`);
  }
  if (hint.gameStage) {
    parts.push(`[Context] gameStage=${hint.gameStage}`);
  }
  if (hint.lastConversationSummary) {
    parts.push(`[Context] 最近對話摘要：${hint.lastConversationSummary}`);
  }

  return parts.join("\n\n");
}
