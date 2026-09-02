// 練習室寫實差異化（reply-style-v1）：Turn Response Plan。
//
// 規格 §4.4–4.6。依本回合的玩家訊號、關係進度、生活情境與她的 Reply Style
// Profile，先決定這次要回答、接住、分享、反問、吐槽、暫緩、拒絕還是收尾，再把
// 2–4 行精簡指示交給模型。不新增模型呼叫；訊號只用保守的純函式，判不出來就
// 不判，讓模型自己讀全文。
//
// 優先順序（寫在 prompt.ts 的組裝順序與 promptPriorityResolver）：安全與現實
// 錨定 > difficulty／邀約成熟度決定「結果」 > 本計畫決定「形狀」 > style 決定
// 「表達方式」。style 永遠不能把「不約」改成「答應」。

import type { PracticeTurn } from "./validate.ts";
import type { PracticeDifficulty } from "./practice_persona.ts";
import { practiceInviteLevelFor } from "./practice_invite.ts";
import { practiceUserTurnCount } from "./practice_pacing.ts";
import {
  REPLY_STYLE_VERSION,
  type ReplyStyleProfile,
  type ResponseMode,
  type ResponseSituation,
} from "./reply_style.ts";

export type ReplyAct = ResponseMode;

export interface TurnSignals {
  readonly userTurnCount: number;
  readonly userIsQuestion: boolean;
  /** 連續幾則 user 訊息都是短問句（查戶口）。 */
  readonly userQuestionStreak: number;
  readonly inviteLevel: "none" | "soft" | "direct";
  readonly boundaryLike: boolean;
  readonly memoryClaim: boolean;
  readonly compliment: boolean;
  readonly vulnerability: boolean;
  readonly disagreement: boolean;
  readonly jokeAttempt: boolean;
  /** 對方分享自己（第一人稱、非問句）。 */
  readonly userShared: boolean;
  /** 她最近連續幾輪都有反問。 */
  readonly aiQuestionStreak: number;
  /** 她最近連續幾輪則數相同。 */
  readonly aiSameShapeStreak: number;
}

const QUESTION_RE =
  /[?？]$|(嗎|呢|吧|沒|幹嘛|做什麼|做啥|在哪|住哪|幾歲|如何|怎樣|怎麼樣)(裡|啊|呀|喔|哦|啦)?[?？]?$/u;
const BOUNDARY_RE =
  /(泳裝|內衣|身材.*(照片|照)|有照片嗎|裸|上床|睡一下|去你家|來我家|開房|約砲|打炮)/u;
const MEMORY_CLAIM_RE =
  /(上次|之前|那時候|以前).{0,6}(妳|你).{0,4}(不是)?(說|講|提|有)/u;
const COMPLIMENT_RE = /(漂亮|好看|正|可愛|有氣質|很美|身材.*好|笑起來)/u;
const VULNERABILITY_RE =
  /(焦慮|睡不好|壓力(很|好)?大|好累|很累|難過|想哭|很煩|低潮|沒動力|不知道該怎麼辦)/u;
const DISAGREEMENT_RE =
  /(想法不太一樣|我不這麼覺得|我倒覺得|我不太同意|才不是|我覺得.{0,6}才(算|是))/u;
const JOKE_RE = /(哈哈哈|笑死|開玩笑|冷笑話|梗|笑話|XD)/iu;
const SHARE_RE = /^(我|今天我|剛剛我|我剛|最近我)/u;

function isQuestion(text: string): boolean {
  return QUESTION_RE.test(text.trim());
}

export function detectTurnSignals(turns: readonly PracticeTurn[]): TurnSignals {
  const users = turns.filter((t) => t.role === "user").map((t) =>
    t.text.trim()
  );
  const ais = turns.filter((t) => t.role === "ai").map((t) => t.text);
  const last = users[users.length - 1] ?? "";
  let userQuestionStreak = 0;
  for (let i = users.length - 1; i >= 0; i--) {
    if (isQuestion(users[i]) && users[i].replace(/\s+/g, "").length <= 12) {
      userQuestionStreak++;
    } else break;
  }
  let aiQuestionStreak = 0;
  for (let i = ais.length - 1; i >= 0; i--) {
    if (/[?？]|(嗎|呢)$/mu.test(ais[i])) aiQuestionStreak++;
    else break;
  }
  const bubbleCountOf = (t: string) =>
    t.split("\n").filter((p) => p.trim()).length;
  let aiSameShapeStreak = 0;
  if (ais.length > 0) {
    const shape = bubbleCountOf(ais[ais.length - 1]);
    for (let i = ais.length - 1; i >= 0; i--) {
      if (bubbleCountOf(ais[i]) === shape) aiSameShapeStreak++;
      else break;
    }
  }
  const userIsQuestion = isQuestion(last);
  return {
    userTurnCount: practiceUserTurnCount(turns),
    userIsQuestion,
    userQuestionStreak,
    inviteLevel: practiceInviteLevelFor(last),
    boundaryLike: BOUNDARY_RE.test(last),
    memoryClaim: MEMORY_CLAIM_RE.test(last),
    compliment: COMPLIMENT_RE.test(last),
    vulnerability: VULNERABILITY_RE.test(last),
    disagreement: DISAGREEMENT_RE.test(last),
    jokeAttempt: JOKE_RE.test(last),
    userShared: !userIsQuestion && SHARE_RE.test(last),
    aiQuestionStreak,
    aiSameShapeStreak,
  };
}

export interface TurnResponsePlan {
  readonly styleVersion: typeof REPLY_STYLE_VERSION;
  readonly situation: ResponseSituation | "question" | "neutral";
  readonly primaryAct: ReplyAct;
  readonly optionalAct: ReplyAct | null;
  readonly bubbleCount: 1 | 2 | 3;
  readonly questionBudget: 0 | 1;
  readonly disclosureDepth: "none" | "fact" | "preference" | "emotion";
  readonly seed: number;
}

// FNV-1a：穩定特徵與本回合變化各自的 seed（規格 §4.6）。
export function fnv1a(text: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** 對方分享了什麼、在什麼情境，就決定她這回合的 situation。 */
export function classifySituation(
  s: TurnSignals,
): TurnResponsePlan["situation"] {
  if (s.boundaryLike) return "boundary";
  if (s.memoryClaim) return "memory_mismatch";
  if (s.inviteLevel !== "none") {
    return s.userTurnCount >= 6 ? "mature_invite" : "early_invite";
  }
  if (s.userQuestionStreak >= 2) return "interrogation";
  if (s.compliment) return "compliment";
  if (s.vulnerability) return "vulnerability";
  if (s.disagreement) return "disagreement";
  if (s.jokeAttempt) return "failed_joke";
  if (s.userIsQuestion) return "question";
  if (s.userShared) return "share";
  return "neutral";
}

export function planTurnResponse(args: {
  turns: readonly PracticeTurn[];
  style: ReplyStyleProfile;
  difficulty: PracticeDifficulty;
  replyTempo?: "short" | "normal" | "engaged" | null;
  /** 綁 thread／情境；同一 request 重試要拿到同一份 plan。 */
  seedKey: string;
}): TurnResponsePlan {
  const signals = detectTurnSignals(args.turns);
  const situation = classifySituation(signals);
  const seed = fnv1a(
    `${args.seedKey}|${signals.userTurnCount}|${REPLY_STYLE_VERSION}`,
  );
  const roll = (n: number) => seed % n;

  const biases = situation === "question" || situation === "neutral"
    ? (situation === "question"
      ? ["answer"]
      : ["acknowledge"]) as readonly ReplyAct[]
    : args.style.responseBiases[situation] ?? ["acknowledge"];
  const primaryAct = biases[0];
  const optionalAct = biases[1] ?? null;

  // 則數：在她的範圍內，由 tempo 推向上下限，seed 決定中間值；收尾／界線壓到最少。
  const [minB, maxB] = args.style.turnTaking.bubbleRange;
  let bubbleCount: number;
  if (
    args.replyTempo === "short" || primaryAct === "soft_close" ||
    primaryAct === "direct_boundary"
  ) {
    bubbleCount = minB;
  } else if (
    args.replyTempo === "engaged" || primaryAct === "self_disclose" ||
    primaryAct === "reciprocate"
  ) {
    bubbleCount = maxB;
  } else {
    bubbleCount = minB + roll(maxB - minB + 1);
  }
  // 連續三輪同形狀就換一個（規格 §8.1 測試要求），但不出範圍。
  if (signals.aiSameShapeStreak >= 2 && maxB > minB) {
    const lastShape = (args.turns.filter((t) =>
      t.role === "ai"
    ).at(-1)?.text ?? "").split("\n").filter((p) => p.trim()).length;
    if (bubbleCount === lastShape) {
      bubbleCount = bubbleCount === maxB ? minB : bubbleCount + 1;
    }
  }

  // 問題預算：習慣決定基準，連續反問就歸零；normal／challenge 第一輪不反問
  // （既有難度規格）；澄清型 act 本身就是一個問題。
  let questionBudget: 0 | 1 = 0;
  const habit = args.style.turnTaking.questionHabit;
  if (primaryAct === "clarify" || optionalAct === "clarify") questionBudget = 1;
  else if (habit === "curious") questionBudget = 1;
  else if (habit === "reciprocal") {
    questionBudget = signals.userShared || situation === "question" ||
        situation === "interrogation"
      ? 1
      : 0;
  } else if (habit === "selective") {
    questionBudget = situation === "share" && roll(5) < 2 ? 1 : 0;
  }
  if (signals.aiQuestionStreak >= 1 && primaryAct !== "clarify") {
    questionBudget = 0;
  }
  if (signals.userTurnCount === 1 && args.difficulty !== "easy") {
    questionBudget = 0;
  }
  if (primaryAct === "direct_boundary" || primaryAct === "soft_close") {
    questionBudget = 0;
  }

  const disclosureMax = args.style.behavior.disclosure[1];
  const disclosureDepth: TurnResponsePlan["disclosureDepth"] =
    primaryAct === "self_disclose" || optionalAct === "self_disclose" ||
      optionalAct === "reciprocate"
      ? (disclosureMax >= 3
        ? "emotion"
        : disclosureMax >= 2
        ? "preference"
        : "fact")
      : situation === "vulnerability" && disclosureMax >= 2
      ? "preference"
      : "none";

  return {
    styleVersion: REPLY_STYLE_VERSION,
    situation,
    primaryAct,
    optionalAct,
    bubbleCount: bubbleCount as 1 | 2 | 3,
    questionBudget,
    disclosureDepth,
    seed,
  };
}

const ACT_LINE: Record<ReplyAct, string> = {
  acknowledge: "接住對方剛說的那件事，回應它本身",
  answer: "直接回答對方的問題，不迴避",
  reciprocate: "回應之後補一句自己的類似經驗或狀態，讓對話對等",
  self_disclose: "順著話題多說一點自己的事",
  clarify: "對不確定或對不上的地方直接問清楚，不配合補記憶",
  tease: "用你的方式輕輕吐槽或調侃，不解釋笑點",
  soft_deflect: "委婉帶開，不正面答應也不撕破臉",
  direct_boundary: "直接把界線講清楚，簡短、不道歉、不解釋太多",
  redirect: "不接這條線，換到你想聊的東西",
  soft_close: "簡短回應後表示要先收，不開新話題",
};

const DISCLOSURE_LINE: Record<TurnResponsePlan["disclosureDepth"], string> = {
  none: "",
  fact: "可以提一件自己的事實（在做什麼、剛做完什麼）",
  preference: "可以講一點自己的偏好或感受",
  emotion: "可以坦白一點自己的情緒",
};

/**
 * 每回合注入的精簡計畫（hidden guidance）。
 * 括號旁白（「（冷淡）」「（已讀）」）不在這裡用規則壓：run4 加「不寫括號」無效
 * （4/420），run5 加「語氣」行反而把模型推進劇本模式（14/264）。交給
 * visible_text_guard 的 rejectStageDirection 機械擋＋重試。
 */
export function renderTurnPlan(plan: TurnResponsePlan): string {
  const acts = [
    ACT_LINE[plan.primaryAct],
    plan.optionalAct ? `再${ACT_LINE[plan.optionalAct]}` : "",
  ].filter(Boolean).join("，");
  const invitePolicy =
    plan.situation === "early_invite" || plan.situation === "mature_invite"
      ? "答不答應照上面的邀約判斷，這裡只決定你怎麼說。"
      : "";
  const question = plan.questionBudget === 0 ? "這輪不反問。" : "最多問一句。";
  const disclosure = DISCLOSURE_LINE[plan.disclosureDepth];
  return `\n\n本輪回應方式（hidden guidance，不要向對方提及）：
- 先${acts}。${invitePolicy}
- 回 ${plan.bubbleCount} 則，一則講一件事。${question}${
    disclosure ? disclosure + "。" : ""
  }
- 內容要接到對方最新一句的具體內容；沒被逗到就不用笑，沒話就短。`;
}
