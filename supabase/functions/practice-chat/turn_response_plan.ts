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
import {
  AGENCY_ACTS,
  type AgencyApplication,
  type AgencyMode,
  agencyPolicyFor,
  agencyThresholdsFor,
  type ConversationAgencyProfile,
  type ConversationAgencyState,
  detectAgencyEvidence,
  isAcceptingPlanAct,
  isClarifyingAct,
  isQuestionText,
  type PlanAct,
  utteranceShapeOf,
} from "./conversation_agency.ts";

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
    if (isQuestionText(users[i]) && users[i].replace(/\s+/g, "").length <= 12) {
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
  const userIsQuestion = isQuestionText(last);
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
  /**
   * conversation-agency-v1 Phase 3.8（AGENCY-05 結構刀）：這一輪 planner 強制她
   * 問他一件事時才存在＝認識管道的 `curiosityFocus`；renderer 印成
   * 「這輪問他一件事：X」取代泛用的「最多問一句」。只在 agency 旗標 on 出現。
   */
  readonly askUserFocus?: string;
}

/**
 * Phase 3.8：強制「這場問他一次」的視窗（第 2～6 個 user 回合）與排除的 persona
 * questionHabit。預設不排除任何型（Eric 2026-09-04：做成開關不寫死）——要讓最冷的
 * 角色一場都不問，把 "rare" 放進集合即可。
 */
/**
 * Phase 4.2（Eric 2026-09-05 拍板：「規則綁對方給了什麼，不綁第幾回合；回合數
 * 只當上限防呆」）：這兩個數字現在數的是**玩家給了內容的回合**，不是原始回合序號。
 */
export const ASK_USER_WINDOW_USER_TURNS: readonly [number, number] = [2, 6];
/**
 * Phase 4.2：原始 user 回合數的硬上限（防呆）。沒有這條，一場全是「哈哈」
 * 「嗯嗯」的對話會把窗口無限往後推。
 */
export const ASK_USER_WINDOW_MAX_USER_TURNS = 10;
export const ASK_USER_EXCLUDED_HABITS: ReadonlySet<
  ReplyStyleProfile["turnTaking"]["questionHabit"]
> = new Set();

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

/**
 * conversation-agency-v1（Codex P1「與 reply-style 解耦」）：agency block 獨立
 * 於 style／planTurnResponse 計算，`PRACTICE_REPLY_STYLE_ENABLED` 關閉時一樣
 * 能算出結構證據與 bounded／forced act。呼叫端（`buildChatPromptBundle`）先用
 * `classifySituation` 算出 `situation`（不論有沒有 style 都能算），再傳進來；
 * agency 只接管既有 planner 判不出東西的 `neutral` 輪——安全、越界、邀約、記憶
 * 衝突、查戶口、稱讚、不同意、問句、分享的既有優先權一律不動。
 */
export function computeAgencyDecision(args: {
  turns: readonly PracticeTurn[];
  situation: TurnResponsePlan["situation"];
  /** 省略／off＝與接線前逐字相同（回傳 null，不算任何東西）。 */
  agencyMode?: AgencyMode;
  /** assisted 模式 thread 的 recent_facts.conversationAgency；standard 傳 null。 */
  agencyState?: ConversationAgencyState | null;
  /** 難度只調門檻與口氣，不關掉 agency（報告 §7.4）；省略＝一般難度。 */
  difficulty?: "easy" | "normal" | "challenge";
  /** Game 模式套挑戰難度門檻＋既有 Game FSM 優先權（由呼叫端保留）。 */
  isGame?: boolean;
  /**
   * Phase 4.0：角色的對話主體強弱（`agencyProfileFor`）。難度表是 base，
   * profile 只做位移；省略／null＝逐字沿用難度表。
   */
  agencyProfile?: ConversationAgencyProfile | null;
}): AgencyApplication | null {
  const agencyMode = args.agencyMode ?? "off";
  if (agencyMode === "off") return null;
  const thresholds = agencyThresholdsFor(
    args.difficulty ?? "normal",
    args.isGame ?? false,
    args.agencyProfile ?? null,
  );
  const raw = agencyPolicyFor(
    detectAgencyEvidence(args.turns, args.agencyState ?? null),
    thresholds,
  );
  const decision = args.situation === "neutral" ? raw : {
    ...raw,
    situation: null,
    forcedAct: null,
    allowedActs: [] as readonly PlanAct[],
    allowedActSetId: "none",
  };
  return {
    decision,
    applied: agencyMode === "on" && decision.situation !== null,
    enabled: agencyMode === "on",
    profile: args.agencyProfile ?? null,
  };
}

export function planTurnResponse(args: {
  turns: readonly PracticeTurn[];
  style: ReplyStyleProfile;
  evidence: PolicyEvidence;
  replyTempo?: "short" | "normal" | "engaged" | null;
  /** 綁 thread／情境；同一 request 重試要拿到同一份 plan。 */
  seedKey: string;
  /**
   * 呼叫端（`buildChatPromptBundle`）已用 `computeAgencyDecision` 算好的結果；
   * 只用來調整則數（hold／收尾壓到最少），不擁有計算邏輯——`TurnResponsePlan`
   * 本身只管 style，agency 决策住在 bundle 的 `agencyDecision` 欄位。
   */
  agency?: AgencyApplication | null;
  /**
   * Phase 3.8：認識管道的首要好奇點；只在 agency 旗標 on 時由 bundle 傳入，
   * off／shadow 傳 null＝這一段完全不套用（plan 逐字與接線前相同）。
   */
  askUserFocus?: string | null;
  /** Phase 3.8：這一場已經強制問過一次（thread state）。 */
  askedAboutUser?: boolean;
  /**
   * Phase 4.0：角色的對話主體強弱；只在 agency 旗標 on 時由 bundle 傳入，
   * off／shadow 傳 null＝`initiative` 這一段完全不套用（plan 逐字不變）。
   */
  agencyProfile?: ConversationAgencyProfile | null;
}): TurnResponsePlan {
  const signals = detectTurnSignals(args.turns);
  const policyStance = policyStanceFor(signals, args.evidence);
  const situation = classifySituation(signals, policyStance);
  const agency = args.agency ?? null;
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
  if (
    agency?.applied &&
    (agency.decision.forcedAct === "hold_position" ||
      agency.decision.forcedAct === "end_low_value_loop")
  ) {
    bubbleCount = minB;
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

  // Phase 4.0 `initiative`（報告 §7.3「只在有自身興趣或對話停滯時允許開自己的
  // 題，不等於替玩家救場」）：高主動的人在**對話停滯**的輪次有機率開一個自己的
  // 題（`self_disclose`）。
  //
  // Codex R1 P1：`situation === "neutral"` 本身不是停滯——「今天超熱的 我剛下班」
  // 是 `self_share`，有兩件可回應的內容，卻也會落到 neutral。所以停滯要一個
  // **結構**訊號：`utteranceShape === "reaction"`（玩家這句只由招呼／情緒反應詞
  // 構成，`REACTION_RE`，不含第一人稱、不是問句、不是明示換題）。這一句本身
  // 沒有可接的內容，她要嘛收尾要嘛自己開題，正是報告說的「對話停滯」。
  // 報告的另一半「有自身興趣」**沒有結構訊號可用**（那要判語意，本檔的界線是
  // 只認句法標記），所以不做——這一刀只做停滯那一半。
  //
  // 刻意不搶的幾種輪次：`agency.applied`（她正在澄清／質疑）、
  // `optionalAct !== null`（她已經有第二個動作，例如低能量收尾）、
  // `policyStance === "cautious"`（她在防備，上面才剛把 self_disclose 濾掉）、
  // 玩家在問她（含「我剛下班，妳今天呢？」這種分享＋問句，Codex R1 P2-1 的
  // 同一條界線）、第一個 user 回合（首輪不主動開題）。
  //
  // 機率：initiative 3＝1/5 輪、4＝2/5 輪，≤2 不觸發。Codex R1 P2：用自己的
  // hash 域（seedKey|回合|initiative），不共用 `roll`——否則 initiative 與
  // `bubbleCount` 會是同一個 seed 的確定函數，兩個決定綁在同一個骰面上。
  // 仍然是 seed 決定的（同一 request 重試拿到同一份 plan）。
  //
  // 與 Phase 3.8 的 `forceAskUser` 可共存：那一把刀只動 `questionBudget`，
  // 這一把只動 `optionalAct`，兩者的條件也一致（都要求 `!agency.applied`、
  // 非問句、userTurnCount ≥ 2）。
  const initiative = args.agencyProfile?.initiative ?? 0;
  if (
    agency?.enabled === true && !agency.applied &&
    agency.decision.evidence.utteranceShape === "reaction" &&
    situation === "neutral" && optionalAct === null &&
    policyStance !== "cautious" && !signals.userIsQuestion &&
    signals.userTurnCount >= 2 && initiative >= 3 &&
    fnv1a(`${args.seedKey}|${signals.userTurnCount}|initiative`) % 5 <
      initiative - 2
  ) {
    // `disclosureDepth` 下面會因為 optionalAct 自然變成非 none（既有邏輯）。
    optionalAct = "self_disclose";
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
  // Phase 3.8 結構刀（AGENCY-05）：3.7 黑箱證明在 prompt 加一行「想先知道 X」
  // 零效果——34/40 場的 habit 是 rare／selective／reciprocal，上面算出來的預算
  // 多半是 0，計畫行印「這輪不反問」就把那一行壓掉了。改在這裡動形狀：agency on、
  // 前六個 user 回合、玩家這句連貫（agency 沒介入）且不是在問她、她上一則沒在問、
  // 這場還沒問過 → 預算強制 1，renderer 印「這輪問他一件事：X」。一場只強制一次
  // （thread state `askedAboutUser` 黏住），之後多常問回到 persona 的習慣。
  // Phase 4.2（Codex R1 P1 → Eric 2026-09-05 拍板）：窗口從「第 2～6 個 user
  // 回合」改成「玩家**給了內容**的回合數在 [2,6] 內」。原本第 2～6 回合全是
  // 「哈哈」「嗯嗯」時，第 7 回合他終於講了東西也會因為 `userTurnCount > 6`
  // 而永遠不再強制，Phase 3.8 的保證在純反應場次整場失效。Eric 的原則是「規則
  // 綁對方給了什麼，不綁第幾回合；回合數只當上限防呆」，所以純反應詞輪不計入
  // 計數，原始回合數只留一條硬上限（`ASK_USER_WINDOW_MAX_USER_TURNS`）。
  //
  // `utteranceShapeOf` 判 `reaction` 的分支在 `previousAiAskedQuestion` 之前
  // （`REACTION_RE` 先判），所以這裡傳 false 不影響結果，也不必重建每一輪的
  // 「她上一則有沒有在問」——不新增偵測器，用的是同一支純函式。
  const contentUserTurnCount =
    args.turns.filter((t) =>
      t.role === "user" && utteranceShapeOf(t.text, false) !== "reaction"
    ).length;
  const forceAskUser = agency?.enabled === true &&
    typeof args.askUserFocus === "string" &&
    args.askUserFocus.trim().length > 0 &&
    args.askedAboutUser !== true &&
    !agency.applied &&
    // situation neutral／share 已經排除問句，這裡再明寫一次：玩家在問她（含
    // 「我剛下班，妳今天呢？」這種分享＋問句）就不搶著問他（Codex R1 P2-1）。
    !signals.userIsQuestion &&
    // Phase 4.2：停滯輪（玩家這句只有招呼／情緒反應詞，`utteranceShape ===
    // "reaction"`）不強制問他認識管道。Phase 4 完整黑箱在 A29（「哈哈」「嗯嗯」）
    // 量到 forced ask 38/40，同一個探針位置兩輪累積 `accommodating_invention`
    // 4/80——他這句沒給任何內容，被逼著問「你那天怎麼會出現在我工作的那邊」時，
    // 模型只能自己補一個共同場景出來。等下一輪他真的講了東西再問。
    agency.decision.evidence.utteranceShape !== "reaction" &&
    contentUserTurnCount >= ASK_USER_WINDOW_USER_TURNS[0] &&
    contentUserTurnCount <= ASK_USER_WINDOW_USER_TURNS[1] &&
    signals.userTurnCount <= ASK_USER_WINDOW_MAX_USER_TURNS &&
    signals.aiQuestionStreak === 0 &&
    (situation === "neutral" || situation === "share") &&
    primaryAct !== "direct_boundary" && primaryAct !== "soft_close" &&
    !ASK_USER_EXCLUDED_HABITS.has(habit);
  if (forceAskUser) questionBudget = 1;

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
    ...(forceAskUser ? { askUserFocus: args.askUserFocus as string } : {}),
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

// conversation-agency-v1 的 act 說明（報告 §7.2）。這些是 decision rule，不是台詞：
// 刻意不寫任何範例句，不然 100 位角色會共用同一句口頭禪（報告 §13 第 8 點）。
// Codex 補（item C）：ask_intent／challenge_relevance 改成「只問，不替他補
// 意思」——舊版 ask_intent 已經有「不要自己猜一個」，這裡統一成同一句收尾
// 「不要在同一句替他補上你猜的意思或話題」，三個 act 一致；hold_position
// 明講「他沒回答之前話題就晾著」（不是接著新詞聊）。刻意不寫任何範例句，
// 不然 100 位角色會共用同一句口頭禪（報告 §13 第 8 點）。
const AGENCY_ACT_LINE: Partial<Record<PlanAct, string>> = {
  acknowledge: "他這句本來就講得通就自然接，但不要替他補他沒說的意圖或背景",
  // Phase 2.5：`asked_with_guess` 與 `accommodating_invention` 兩種失敗都發生在
  // 「有問，但同一則裡又補了東西」——補的可能是猜測（他的意圖），也可能是她
  // 自己剛好相關的經歷（A12「清邁」→「之前休假有去過」）。兩種都明寫。
  ask_intent:
    "不確定他在講什麼，就直接問他的意思或跟前面哪件事有關；同一則裡不要補猜測，也不要順口講你自己跟這個詞有關的經歷",
  challenge_relevance:
    "說這跟剛剛在聊的對不上，要他講清楚；同一則裡不要補猜測，也不要順口講你自己跟這個詞有關的經歷",
  return_to_topic: "拉回你剛才問的、或還沒聊完的那件事",
  hold_position:
    "維持你剛才的保留：他沒把話講清楚、沒回答你之前，這個問題就晾著，不要接著他丟的新詞往下聊",
  end_low_value_loop: "這串聊不下去了，短短收掉，不要再接新的詞",
  // 單獨列出來只為了型別完整；欠債輪實際渲染的是下面 `AGENCY_SET_LINE`
  // 那一句二選一，不會逐一列出候選。
  accept_if_answered: "他這句真的接得上前面就接受，接不上就說他沒回答你",
};

/**
 * Phase 3.0：整組候選一起渲染成**一句條件式**，而不是「挑一個最合理的：A；B」
 * 清單。
 *
 * 為什麼：欠債輪的兩個候選（`accept_if_answered`／`challenge_relevance`）不是
 * 兩個平行選項，而是同一個判斷的兩個分支——「他到底有沒有回答」。列成清單時
 * 模型會把它讀成「兩個都可以，挑順的」，實測就是挑「接受」；寫成 if/else 才
 * 逼它先做那個判斷。清單語法留給真正平行的候選（`fragment_no_context_v1`）。
 */
const AGENCY_SET_LINE: Record<string, string> = {
  answer_or_challenge_v1:
    "先判斷他這句接不接得上：真的回答了你上一句、或本來就跟前面在聊的事對得上，就接受、順著講下去；對不上就直接說他沒回答你、又跳到別的，不要順著新名詞聊",
  answer_or_challenge_easy_v1:
    "先判斷他這句接不接得上：真的回答了你上一句、或跟前面在聊的事對得上，就接受、順著講下去；拿不準就先接住；真的完全對不上才說他沒回答你、又跳到別的",
  // Phase 4.0：高 topicPersistence 的人多一個出口——不一定要質疑，也可以直接
  // 把話拉回自己上一題。句尾加一個分句，前半段與上面兩條逐字相同。
  answer_or_challenge_persist_v1:
    "先判斷他這句接不接得上：真的回答了你上一句、或本來就跟前面在聊的事對得上，就接受、順著講下去；對不上就直接說他沒回答你、又跳到別的，不要順著新名詞聊；或直接把話拉回你上一題",
  answer_or_challenge_persist_easy_v1:
    "先判斷他這句接不接得上：真的回答了你上一句、或跟前面在聊的事對得上，就接受、順著講下去；拿不準就先接住；真的完全對不上才說他沒回答你、又跳到別的；或直接把話拉回你上一題",
};

/** 獨立於 TurnResponsePlan：style 開或關都能算，只吃 agencyDecision 本身。 */
export function agencyActsLine(agency: AgencyApplication | null): string {
  if (!agency?.applied) return "";
  const line = (act: PlanAct) =>
    AGENCY_ACT_LINE[act] ?? ACT_LINE[act as ReplyAct];
  if (agency.decision.policyMode === "forced" && agency.decision.forcedAct) {
    return line(agency.decision.forcedAct);
  }
  const setLine = AGENCY_SET_LINE[agency.decision.allowedActSetId];
  if (setLine) return setLine;
  return `讀完整段對話，挑一個最合理的（只挑一個）：${
    agency.decision.allowedActs.map(line).join("；")
  }`;
}

/**
 * 強制「只問意思」那一輪的回覆形狀：一則、只有問句、不接話題、不解讀。
 *
 * 這是 `asked_with_guess`（有問但同一則又夾帶猜測）唯一的結構化出口——文案層
 * 已經寫過「不要在同一句裡又補猜測」而黑箱量不到效果（2026-09-04 README 待辦
 * 第 2 條），所以這裡直接改回覆形狀：則數壓成 1、問題預算 1。
 */
export function isForcedAskIntent(agency: AgencyApplication | null): boolean {
  return Boolean(
    agency?.applied && agency.decision.policyMode === "forced" &&
      agency.decision.forcedAct === "ask_intent",
  );
}

const FORCED_ASK_INTENT_SHAPE = "只問，不猜、不接話題：回 1 則，就一個問句。";

/**
 * Phase 2.6：`asked_with_guess` 的第二刀。
 *
 * Phase 2.5 只有 forced `ask_intent` 那一輪換了回覆形狀（1 則、只有問句），
 * 而 2026-09-06 的 policy 路徑拆解（`tools/practice-agency-eval/policy_breakdown.ts`）
 * 顯示夾帶猜測的**主要來源根本不是那條**：bounded 18.1%（98/541，其中
 * `low_coherence_v1` 21.9%、`topic_shift_v1` 16.2%）＞ forced ask_intent
 * 15.0%（18/120）＞ no_override 1.3%（11/830）。bounded 那幾條的文案層早就
 * 寫了「同一則裡不要替他補猜測」，黑箱量不到效果——壓得住的是形狀，不是字。
 *
 * 所以把同一把結構刀延伸到「這一輪的候選清單裡沒有『接住』」的每一種情形：
 * 候選 act 全部是 agency act（ask_intent／challenge_relevance／
 * return_to_topic／hold_position／end_low_value_loop）就算。反過來說，只要
 * 清單裡有 `acknowledge`（easy 的第一個片段、P1-c 的
 * `answer_candidate_with_debt_v1`），順著聊本來就是合法選項，形狀不動。
 */
export function isAgencyClarifyOnlyTurn(
  agency: AgencyApplication | null,
): boolean {
  const acts = agency?.applied ? agency.decision.allowedActs : [];
  return acts.length > 0 && !acts.some(isAcceptingPlanAct) &&
    acts.every((a) => (AGENCY_ACTS as readonly PlanAct[]).includes(a));
}

const AGENCY_CLARIFY_ONLY_SHAPE =
  "回 1 則，就做這一件事：不替他補你猜的意思，也不要順著他丟的詞講你自己的事。";

/**
 * 跨輪立場行。**只有 planner 已經 forced 質疑／維持立場的那一輪才印**。
 *
 * Codex round-2 P1-2：舊版掛在
 * `previousAiAskedQuestion && answer_candidate && unresolvedCount > 0`，
 * 那正好是 `answer_candidate_with_debt_v1`（bounded {acknowledge,
 * return_to_topic}）的條件——結構層根本分不出「貓」有沒有回答「你最喜歡哪種
 * 動物」，這句話卻先替模型斷言「他沒回答」，把 bounded 的兩個選項偏壓成
 * `return_to_topic`，等於 P1-c 修掉的誤質疑又從文案繞回來。
 *
 * 現在只認 forced：`hold_position`／`challenge_relevance` 是結構層真的下了
 * 「不退讓」決定的兩個 act，那時候這句話才與候選清單一致。
 */
function agencyStanceLine(agency: AgencyApplication | null): string {
  if (!agency?.applied) return "";
  const forced = agency.decision.forcedAct;
  return forced === "hold_position" || forced === "challenge_relevance"
    ? "你上一句已經在問他了，他沒回答就別放過，不要自己把問題吞掉。"
    : "";
}

const CONDITIONAL_LINE: Record<"vulnerable" | "joke", string> = {
  vulnerable: "如果對方其實是在講自己的狀況或情緒",
  joke: "如果對方其實是在開玩笑",
};

/**
 * Phase 3.0（Eric 2026-09-04 銳化）：**每一輪都印**的第一步——先讀整段的
 * 邏輯，不是只讀最新一句。
 *
 * 為什麼是常設而不是條件式：結構層（`conversation_agency.ts`）只認得出
 * 「沒有句法標記的片段」這一種不連貫；「他這幾句合起來說不通」是語意判斷，
 * 只有看得到完整逐字稿的模型做得到，而模型預設會逐句反應。這一行是**唯一**
 * 把「整段」變成明確第一步的地方，所以不能綁在任何偵測器上（綁了就等於用
 * regex 判語意——踩坑「純函式訊號層硬判高語意」）。
 *
 * 刻意寫成通用句、不出現任何情境詞（地名、清單、亂碼），Eric 的回報是地名，
 * 但同一個形態換成人名／品牌／術語一樣要成立（A26 就是為了證明這件事）。
 */
const AGENCY_WHOLE_THREAD_STEP =
  "回之前先看整段：他最近幾句合起來合不合邏輯、有沒有接你上一句。不合，就先講這件事再說別的——一個「？」或一句「你打這麼多東西是什麼意思」都可以，不必幫他把話接圓。";

/**
 * Phase 3.0 規則 5（不助理式軟化）的**條件式**版本，走既有 conditionalActs
 * 的語法（「如果…，就…」）但不綁 regex 偵測器。
 *
 * 2026-09-06 已經測過「把規則 5 從鐵則搬進 turn plan」＝零效果（README
 * item 4）。這一輪的差別是它**不搬**：鐵則那條留著，這裡多一條每輪都在的
 * 條件式——診斷指出失敗形態是「否認＋解釋」，而同一份 turn plan 的第一行
 * 是「先接住對方剛說的那件事」，模型照做就把「接住」做成了解釋自己。這行
 * 直接把那個情境下的合法輸出列出來（不爽／疏遠／嘲／沉默），讓「接住」在
 * 這一格有別的落點。
 */
const AGENCY_NO_SOFTENING_CONDITIONAL =
  "如果他是在抱怨、不滿或質疑你：照你的性格回（不爽、疏遠、嘲、沉默都可以），不道歉、不解釋、不安撫。";

/**
 * 每回合注入的精簡計畫（hidden guidance）。
 * 括號旁白（「（冷淡）」「（已讀）」）不在這裡用規則壓：run4 加「不寫括號」無效
 * （4/420），run5 加「語氣」行反而把模型推進劇本模式（14/264）。交給
 * visible_text_guard 的 stripStageDirections 修補優先。
 */
export function renderTurnPlan(
  plan: TurnResponsePlan,
  style?: Pick<ReplyStyleProfile, "behavior">,
  agency?: AgencyApplication | null,
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
  // 澄清型 act 不吃問題預算（報告 §P0-2：「不查戶口」被誤寫成「不要好奇」）。
  // Codex P2：既有 planner 自己判成 clarify（primaryAct／optionalAct）時也要
  // 豁免，不能只看 agency 已 applied 的 allowedActs——不然 primaryAct 是
  // clarify、但問題預算被別的規則（例如首輪查戶口門檻）壓回 0 時，這裡會跟
  // ACT_LINE 的「直接問清楚」自相矛盾地印出「這輪不反問」。
  const agencyApplied = agency?.applied ?? false;
  const clarifyingAllowed = plan.primaryAct === "clarify" ||
    plan.optionalAct === "clarify" ||
    (agencyApplied &&
      (agency?.decision.allowedActs.some(isClarifyingAct) ?? false));
  const forcedAsk = isForcedAskIntent(agency ?? null);
  const clarifyOnly = isAgencyClarifyOnlyTurn(agency ?? null);
  // Phase 3.8：強制問他一件事的輪次，把泛用的「最多問一句」換成具體的好奇點。
  const question = plan.askUserFocus !== undefined && !forcedAsk
    // 3.8 黑箱：v1「這輪問他一件事：X，一句就好」管道好奇點 10/40 場；v2 改成
    // 「只有這件事…別問其他問題」反而掉到 2/40（模型被綁緊就整句不問或照問晚餐）。
    // 留 v1 措辭。
    ? `這輪問他一件事：${plan.askUserFocus}，一句就好。`
    : plan.questionBudget === 1 || forcedAsk
    ? "最多問一句。"
    : clarifyingAllowed
    ? "這輪不主動查他的基本資料；問清楚他這句的意思或拉回前一題不算。"
    : "這輪不反問。";
  const disclosure = DISCLOSURE_LINE[plan.disclosureDepth];
  const agencyLine = agencyActsLine(agency ?? null);
  const first = agencyLine ? agencyLine : `先${acts}`;
  // Phase 3.0：這一行原本的前半（「回應依整段脈絡，不必服從最新一個詞」）與
  // 後半（「問清楚或指出跳題時就只做那件事」）已經分別由常設的整段檢查行與
  // `AGENCY_CLARIFY_ONLY_SHAPE`／act 說明講過，重複三次只會排擠後面的規則
  // （踩坑「prompt 規則堆太多後面幾條會被模型直接忽略」）。只留這裡獨有的那半句。
  const tail = agencyApplied
    ? "「接住」也可以是說你聽不懂、不相關，或前一題還沒回答"
    : "內容要接到對方最新一句的具體內容";
  // forced ask_intent 那一輪，形狀由 agency 決定（1 則、只有問句），style 的
  // bubbleCount／disclosure 讓路——這一輪本來就不該有自我揭露。
  // Phase 3.8 v3 形狀刀（已退回）：曾把強制輪鎖成「回 1 則，就一個問句：問他 X」
  // ——離線重跑 planner 證明強制在 36/40 場真的觸發，但生成模型只有一半照做、
  // 15% 問到 X（v1 措辭反而 10/40 場問到管道好奇點）。瓶頸是模型對「問指定問題」
  // 的服從率，不是觸發；形狀行再綁也綁不到，留 v1 的問題行。
  const shapeLine = forcedAsk
    ? FORCED_ASK_INTENT_SHAPE
    : clarifyOnly
    ? AGENCY_CLARIFY_ONLY_SHAPE
    : `回 ${plan.bubbleCount} 則，一則講一件事。${question}${
      disclosure ? disclosure + "。" : ""
    }`;
  // 旗標 on 的常設兩行：`enabled` 而不是 `applied`——A21 那種「玩家在抱怨」的
  // 輪次結構上是 question／neutral，agency 根本不介入，但規則 5 正是要在那裡
  // 生效。shadow 的 `enabled` 是 false，輸出因此與 off 逐字相同。
  const enabled = agency?.enabled ?? false;
  const wholeThread = enabled ? `- ${AGENCY_WHOLE_THREAD_STEP}\n` : "";
  const noSoftening = enabled ? AGENCY_NO_SOFTENING_CONDITIONAL : "";
  return `\n\n本輪回應方式（hidden guidance，不要向對方提及）：
${wholeThread}- ${first}。${stance}${conditional}${noSoftening}${
    agencyStanceLine(agency ?? null)
  }
- ${shapeLine}
- ${tail}；沒被逗到就不用笑，沒話就短。`;
}
