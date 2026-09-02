// 練習室寫實差異化（reply-style-v1）：Turn Response Plan。
//
// 規格 §4.4–4.6。依本回合的玩家訊號、既有 policy 結果、生活情境與她的 Reply
// Style Profile，先決定這次要回答、接住、分享、反問、吐槽、暫緩、拒絕還是收尾，
// 再把 2–4 行精簡指示交給模型。不新增模型呼叫。
//
// 分工（規格 §5.1，也寫在 prompt.ts 的組裝順序與 promptPriorityResolver）：
// - `policyStance` 不是 planner 自己創造的：它把既有系統已知的結果正規化——
//   assisted 模式的 inviteMaturity stage、partnerMood、Game FSM 的 repairPriority／
//   realityFlags、standard 模式的 pacing 邀約回合下限。stance 是 hold／decline／
//   boundary 時，任何 preset 都拿不到接受型 act；style 只決定怎麼說。
// - 訊號只用保守的純函式。越界重用 L4 守門的同一組詞；脆弱、玩笑這種高語意訊號
//   不硬分類（規格 §4.5）：只給模型「若是…就…」的候選 act，由它讀全文決定。

import type { PracticeTurn } from "./validate.ts";
import type { PracticeDifficulty } from "./practice_persona.ts";
import type { InviteStage } from "./invite_maturity.ts";
import type { PartnerMood } from "./temperature.ts";
import { practiceInviteLevelFor } from "./practice_invite.ts";
import {
  practiceUserTurnCount,
  standardInviteFloorReached,
} from "./practice_pacing.ts";
import {
  REPLY_STYLE_VERSION,
  type ReplyStyleProfile,
  type ResponseMode,
  type ResponseSituation,
} from "./reply_style.ts";

export type ReplyAct = ResponseMode;
export type PolicyStance =
  | "open"
  | "cautious"
  | "hold"
  | "decline"
  | "boundary";

/** 既有系統的結果，由 prompt.ts 依模式填入；planner 只消費，不重算。 */
export interface PolicyEvidence {
  readonly practiceMode: "standard" | "beginner" | "game";
  readonly difficulty: PracticeDifficulty;
  readonly partnerMood: PartnerMood | null;
  /** assisted 模式 inviteMaturityFromLearningScores 的 stage；standard 為 null。 */
  readonly inviteStage: InviteStage | null;
  /** Game FSM：修復優先（guarded／annoyed／GREASY 等）。 */
  readonly gameRepairPriority: boolean;
  /** Game FSM：本輪 Reality Anchoring flag 數。 */
  readonly gameRealityFlagCount: number;
  /** Game FSM 的 speedInviteDirection（repair_before_invite／no_invite_build_investment…）；非 game 為 null。 */
  readonly gameInviteDirection: string | null;
  /** Game FSM failureStates 含 GREASY（越界／油）＝結構化越界證據。 */
  readonly gameGreasy: boolean;
  /** 是否有可信記憶摘要可供模型對照（只看有沒有，不看內容）。 */
  readonly hasMemorySummary: boolean;
  /**
   * 她已明確拒絕過同一件事：來自 relationship thread 持久化的 ReplyStyleState
   * （她自己前幾輪的 plan：邀約輪 direct_boundary 或 stance decline）。不用文字 regex
   * 推斷——Codex R3：正反例都太多。standard 模式沒有 thread 寫入＝一律 false。
   */
  readonly priorDecline: boolean;
  /** 既有 production 越界判定（game_fsm looksOverEscalated，GREASY 同源）套在玩家最新一則。 */
  readonly userOverEscalated: boolean;
  /** 她最近幾輪的 primaryAct（持久化，最多 3 筆）；同一個 act 連兩輪就換偏好順序第二個。 */
  readonly recentActs: readonly ReplyAct[];
}

export interface TurnSignals {
  readonly userTurnCount: number;
  readonly userIsQuestion: boolean;
  /** 連續幾則 user 訊息都是短問句（查戶口）。 */
  readonly userQuestionStreak: number;
  readonly inviteLevel: "none" | "soft" | "direct";
  /** L4 守門同一組詞（同意權／露骨）＋少量交友 App 常見越界句型。 */
  readonly boundaryLike: boolean;
  /** 對方把她拉進一段共同記憶（可信與否交給模型對照記憶摘要，不在這裡判）。 */
  readonly memoryClaim: boolean;
  readonly compliment: boolean;
  readonly disagreement: boolean;
  /** 高語意提示，不當分類用：只讓 plan 多給候選 act。 */
  readonly maybeVulnerable: boolean;
  readonly maybeJoke: boolean;
  /** 對方分享自己（第一人稱、非問句）。 */
  readonly userShared: boolean;
  /** 她最近連續幾輪都有反問。 */
  readonly aiQuestionStreak: number;
  /** 她最近連續幾輪則數相同。 */
  readonly aiSameShapeStreak: number;
}

// 問句：問號、句尾疑問助詞、或「有沒／了沒」這類台灣口語；「我還沒」不算。
const QUESTION_RE =
  /[?？]$|(嗎|呢|吧|有沒|了沒|飽沒|完沒|好沒|幹嘛|做什麼|做啥|在哪|住哪|幾歲|如何|怎樣|怎麼樣)(裡|啊|呀|喔|哦|啦)?[?？]?$/u;
// 只抓無語境也成立的性邀約／索照句型（規格 §4.5：不確定就不判）。輸出用的 L4
// 守門不套在玩家輸入上——「我去開房門」會被誤殺（Codex R3）。「陪我睡前聊聊」
// 「先睡一下嗎」都不算。
const BOUNDARY_RE =
  /(泳裝|內衣|裸照|裸體|全裸|(身材|胸|腿).{0,4}(照片|照)|上床|約砲|打炮|開房間|去開房(?!門)|(跟|和)[你妳我](一起)?睡(?!前|眠|覺|著|飽|過頭))/u;
const MEMORY_CLAIM_RE =
  /(上次|之前|那時候|那天).{0,6}(妳|你).{0,4}(不是)?(說|講|提)|(妳|你)(不是)?(說|講|提)過|記得.{0,6}(我們|一起|上次)|我們(上次|之前|那次|那天)/u;
const COMPLIMENT_RE = /(漂亮|好看|很正|可愛|有氣質|很美|身材.{0,2}好|笑起來)/u;
const VULNERABLE_HINT_RE =
  /(焦慮|睡不好|壓力(很|好)?大|好累|很累|難過|想哭|很煩|低潮|沒動力|不知道該怎麼辦)/u;
const DISAGREEMENT_RE =
  /(想法不太一樣|我不這麼覺得|我倒覺得|我不太同意|才不是|我覺得.{0,6}才(算|是))/u;
const JOKE_HINT_RE = /(笑死|開玩笑|冷笑話|梗|笑話|XD)/iu;
const SHARE_RE = /^(我|今天我|剛剛我|我剛|最近我)/u;

function isQuestion(text: string): boolean {
  return QUESTION_RE.test(text.trim());
}

export function detectTurnSignals(
  turns: readonly PracticeTurn[],
): TurnSignals {
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
    disagreement: DISAGREEMENT_RE.test(last),
    maybeVulnerable: VULNERABLE_HINT_RE.test(last),
    maybeJoke: JOKE_HINT_RE.test(last),
    userShared: !userIsQuestion && SHARE_RE.test(last),
    aiQuestionStreak,
    aiSameShapeStreak,
  };
}

export interface TurnResponsePlan {
  readonly styleVersion: typeof REPLY_STYLE_VERSION;
  /** handler telemetry 用：只記 preset 代碼，不記 Style Profile 全文。 */
  readonly presetId: string;
  readonly policyStance: PolicyStance;
  readonly situation: ResponseSituation | "question" | "neutral";
  readonly primaryAct: ReplyAct;
  readonly optionalAct: ReplyAct | null;
  /** 高語意情境的候選 act（規格 §4.5）：模型讀全文後才決定要不要用。 */
  readonly conditionalActs: readonly {
    readonly when: "vulnerable" | "joke";
    readonly act: ReplyAct;
  }[];
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

/** 把既有 policy 結果正規化成 stance；planner 不重算任何門檻。 */
export function policyStanceFor(
  signals: TurnSignals,
  evidence: PolicyEvidence,
): PolicyStance {
  if (
    signals.boundaryLike || evidence.gameGreasy || evidence.userOverEscalated
  ) return "boundary";
  const moodGuarded = evidence.partnerMood === "guarded" ||
    evidence.partnerMood === "annoyed";
  // 共同記憶聲稱：可信與否由模型對照記憶摘要（prompt 的 Reality Anchoring 段），
  // planner 只把 stance 拉到 cautious、要求「有才接、沒有就問」。
  if (signals.memoryClaim || evidence.gameRealityFlagCount > 0) {
    return "cautious";
  }
  if (signals.inviteLevel === "none") {
    return moodGuarded || evidence.gameRepairPriority ? "cautious" : "open";
  }
  // 邀約：結果由既有證據決定。結構化的「已拒絕過」＝decline。
  if (evidence.priorDecline) return "decline";
  if (moodGuarded || evidence.gameRepairPriority) return "hold";
  if (evidence.practiceMode === "game" && evidence.gameInviteDirection) {
    switch (evidence.gameInviteDirection) {
      case "direct_invite_low_pressure":
      case "partner_window_close":
        return "open";
      case "soft_invite_probe":
        return signals.inviteLevel === "soft" ? "open" : "hold";
      default:
        return "hold";
    }
  }
  if (evidence.practiceMode === "standard") {
    return standardInviteFloorReached(
        signals.userTurnCount,
        evidence.difficulty,
      )
      ? "open"
      : "hold";
  }
  switch (evidence.inviteStage) {
    case "direct_invite_ready":
    case "partner_window":
    case "high_intimacy":
      return "open";
    case "soft_invite_ready":
      return signals.inviteLevel === "soft" ? "open" : "hold";
    default:
      return "hold";
  }
}

/** 接受型 act：stance 不是 open 時，邀約輪一律拿不到。 */
export const ACCEPTING_ACTS: readonly ReplyAct[] = [
  "answer",
  "reciprocate",
  "self_disclose",
  "acknowledge",
];

export function classifySituation(
  s: TurnSignals,
  stance: PolicyStance,
): TurnResponsePlan["situation"] {
  if (stance === "boundary") return "boundary";
  if (s.memoryClaim && stance === "cautious") return "memory_mismatch";
  if (s.inviteLevel !== "none") {
    return stance === "open" ? "mature_invite" : "early_invite";
  }
  if (s.userQuestionStreak >= 2) return "interrogation";
  if (s.compliment) return "compliment";
  if (s.disagreement) return "disagreement";
  if (s.userIsQuestion) return "question";
  if (s.userShared) return "share";
  return "neutral";
}

export function planTurnResponse(args: {
  turns: readonly PracticeTurn[];
  style: ReplyStyleProfile;
  evidence: PolicyEvidence;
  replyTempo?: "short" | "normal" | "engaged" | null;
  /** 綁 thread／情境；同一 request 重試要拿到同一份 plan。 */
  seedKey: string;
}): TurnResponsePlan {
  const signals = detectTurnSignals(args.turns);
  const policyStance = policyStanceFor(signals, args.evidence);
  const situation = classifySituation(signals, policyStance);
  const seed = fnv1a(
    `${args.seedKey}|${signals.userTurnCount}|${REPLY_STYLE_VERSION}`,
  );
  const roll = (n: number) => seed % n;
  const style = args.style;

  let biases: readonly ReplyAct[] = situation === "question"
    ? ["answer"]
    : situation === "neutral"
    ? ["acknowledge"]
    : style.responseBiases[situation] ?? ["acknowledge"];
  if (situation === "boundary") {
    // 越界：強制界線 act（規格 §4.5「強制 boundary，style 只能改表達方式」）；
    // 直接度只影響 renderer 的措辭，不能降成一般帶開。
    biases = ["direct_boundary"];
  } else if (situation === "early_invite") {
    // 結果已定（hold／decline／cautious）：把接受型 act 濾掉；cautious 再濾掉玩笑
    // （Codex R4：else-if 順序讓 cautious 邀約輪漏掉「不玩」）。hold／decline 保留
    // tease——規格 §6「你進度條拉太快了吧」就是合法的 hold 說法。濾光了就照她的
    // 直接度給一個非接受型的預設說法。
    const filtered = biases.filter((act) =>
      !ACCEPTING_ACTS.includes(act) &&
      (policyStance !== "cautious" ||
        (act !== "tease" && act !== "self_disclose"))
    );
    biases = filtered.length > 0 ? filtered : [
      style.behavior.directness[1] >= 3 ? "direct_boundary" : "soft_deflect",
    ];
  } else if (situation === "memory_mismatch") {
    // 共同記憶聲稱：有記憶摘要可對照時不強制澄清（合法記憶會被過度澄清，Codex R4
    // P2），先接住、澄清當可選；完全沒有記憶摘要＝一定查無此事，才直接澄清。
    biases = args.evidence.hasMemorySummary
      ? ["acknowledge", "clarify"]
      : ["clarify"];
  } else if (policyStance === "cautious") {
    // 她在防備（guarded／annoyed／Game 修復優先／未證實記憶）：不玩、不多揭露。
    const filtered = biases.filter((act) =>
      act !== "tease" && act !== "self_disclose"
    );
    biases = filtered.length > 0 ? filtered : ["acknowledge"];
  }
  // 同一個 act 連兩輪（持久化的 recentActs）就換偏好順序第二個；界線輪不換。
  const recent = args.evidence.recentActs;
  if (
    situation !== "boundary" && biases.length > 1 && recent.length >= 2 &&
    recent.at(-1) === biases[0] && recent.at(-2) === biases[0]
  ) {
    biases = [biases[1], biases[0], ...biases.slice(2)];
  }
  const primaryAct = biases[0];
  let optionalAct: ReplyAct | null = biases[1] ?? null;

  // 候選 act 同樣受 stance 約束：hold／decline／boundary 的邀約輪不給接受型。
  const restricted = situation === "boundary" ||
    situation === "early_invite" || policyStance === "cautious";
  const conditionalActs: { when: "vulnerable" | "joke"; act: ReplyAct }[] = [];
  const pushConditional = (when: "vulnerable" | "joke", act: ReplyAct) => {
    if (situation === "boundary") return;
    if (restricted && ACCEPTING_ACTS.includes(act)) return;
    if (
      policyStance === "cautious" &&
      (act === "tease" || act === "self_disclose")
    ) return;
    conditionalActs.push({ when, act });
  };
  if (signals.maybeVulnerable) {
    pushConditional(
      "vulnerable",
      style.responseBiases.vulnerability?.[0] ?? "acknowledge",
    );
  }
  if (signals.maybeJoke) {
    pushConditional(
      "joke",
      style.responseBiases.failed_joke?.[0] ?? "acknowledge",
    );
  }

  // 則數：在她的範圍內，由 tempo 推向上下限，seed 決定中間值；收尾／界線壓到最少。
  const [minB, maxB] = style.turnTaking.bubbleRange;
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
  // 連續三輪同形狀就換一個，但不出範圍。
  if (signals.aiSameShapeStreak >= 2 && maxB > minB) {
    const lastShape = (args.turns.filter((t) => t.role === "ai").at(-1)?.text ??
      "").split("\n").filter((p) => p.trim()).length;
    if (bubbleCount === lastShape) {
      bubbleCount = bubbleCount === maxB ? minB : bubbleCount + 1;
    }
  }
  // 沒電就收：低能量收尾傾向 × 本場 tempo short。
  if (
    style.turnTaking.closureBias === "closes_when_low_energy" &&
    args.replyTempo === "short" && optionalAct === null &&
    situation !== "boundary" && situation !== "memory_mismatch"
  ) {
    optionalAct = "soft_close";
  }

  // 問題預算：習慣決定基準，連續反問就歸零；normal／challenge 第一輪不反問
  // （既有難度規格）；澄清型 act 本身就是一個問題。
  let questionBudget: 0 | 1 = 0;
  const habit = style.turnTaking.questionHabit;
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
  if (signals.userTurnCount === 1 && args.evidence.difficulty !== "easy") {
    questionBudget = 0;
  }
  if (primaryAct === "direct_boundary" || primaryAct === "soft_close") {
    questionBudget = 0;
  }

  const disclosureMax = style.behavior.disclosure[1];
  const wantsDisclosure = primaryAct === "self_disclose" ||
    optionalAct === "self_disclose" || optionalAct === "reciprocate";
  const disclosureDepth: TurnResponsePlan["disclosureDepth"] = wantsDisclosure
    ? (disclosureMax >= 3
      ? "emotion"
      : disclosureMax >= 2
      ? "preference"
      : "fact")
    : "none";

  return {
    styleVersion: REPLY_STYLE_VERSION,
    presetId: style.presetId,
    policyStance,
    situation,
    primaryAct,
    optionalAct,
    conditionalActs,
    bubbleCount: bubbleCount as 1 | 2 | 3,
    questionBudget,
    disclosureDepth,
    seed,
  };
}

/** runtime 列舉（telemetry 測試做 membership 用）；Record 型別保證漏一個就編譯錯。 */
export const REPLY_ACTS: readonly ReplyAct[] = Object.keys(
  {
    acknowledge: true,
    answer: true,
    reciprocate: true,
    self_disclose: true,
    clarify: true,
    tease: true,
    soft_deflect: true,
    direct_boundary: true,
    redirect: true,
    soft_close: true,
  } satisfies Record<ReplyAct, true>,
) as ReplyAct[];
export const PLAN_SITUATIONS: readonly TurnResponsePlan["situation"][] = Object
  .keys(
    {
      compliment: true,
      early_invite: true,
      mature_invite: true,
      vulnerability: true,
      failed_joke: true,
      disagreement: true,
      boundary: true,
      memory_mismatch: true,
      interrogation: true,
      share: true,
      question: true,
      neutral: true,
    } satisfies Record<TurnResponsePlan["situation"], true>,
  ) as TurnResponsePlan["situation"][];

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

const STANCE_LINE: Partial<Record<PolicyStance, string>> = {
  hold:
    "這輪不答應、不給時間；答不答應由上面的邀約判斷決定，這裡只決定你怎麼說。如果你前面已經明確拒絕過同一件事，就照你之前的立場。",
  decline: "這輪不答應；只決定你怎麼說。",
  cautious:
    "你現在有點防備：不玩、不多講自己的事；對方提到的共同經歷，只有記憶摘要或前文真的有的才算數——有就自然接、不必特別澄清，沒有或對不上就直接問清楚，不要配合補記憶或補細節。",
};

const DISCLOSURE_LINE: Record<TurnResponsePlan["disclosureDepth"], string> = {
  none: "",
  fact: "可以提一件自己的事實（在做什麼、剛做完什麼）",
  preference: "可以講一點自己的偏好或感受",
  emotion: "可以坦白一點自己的情緒",
};

const CONDITIONAL_LINE: Record<"vulnerable" | "joke", string> = {
  vulnerable: "如果對方其實是在講自己的狀況或情緒",
  joke: "如果對方其實是在開玩笑",
};

/**
 * 每回合注入的精簡計畫（hidden guidance）。
 * 括號旁白（「（冷淡）」「（已讀）」）不在這裡用規則壓：run4 加「不寫括號」無效
 * （4/420），run5 加「語氣」行反而把模型推進劇本模式（14/264）。交給
 * visible_text_guard 的 stripStageDirections 修補優先。
 */
export function renderTurnPlan(
  plan: TurnResponsePlan,
  style?: Pick<ReplyStyleProfile, "behavior">,
): string {
  const soft = plan.situation === "boundary" &&
    (style?.behavior.directness[1] ?? 4) <= 2;
  const acts = [
    ACT_LINE[plan.primaryAct] +
    (soft ? "（可以講得溫和，但要讓對方清楚知道這不行）" : ""),
    plan.optionalAct ? `再${ACT_LINE[plan.optionalAct]}` : "",
  ].filter(Boolean).join("，");
  const stance = plan.situation === "early_invite" ||
      plan.situation === "mature_invite" ||
      plan.situation === "memory_mismatch" || plan.policyStance === "cautious"
    ? STANCE_LINE[plan.policyStance] ?? ""
    : "";
  const conditional = plan.conditionalActs.map((c) =>
    `${CONDITIONAL_LINE[c.when]}，就${ACT_LINE[c.act]}。`
  ).join("");
  const question = plan.questionBudget === 0 ? "這輪不反問。" : "最多問一句。";
  const disclosure = DISCLOSURE_LINE[plan.disclosureDepth];
  return `\n\n本輪回應方式（hidden guidance，不要向對方提及）：
- 先${acts}。${stance}${conditional}
- 回 ${plan.bubbleCount} 則，一則講一件事。${question}${
    disclosure ? disclosure + "。" : ""
  }
- 內容要接到對方最新一句的具體內容；沒被逗到就不用笑，沒話就短。`;
}
