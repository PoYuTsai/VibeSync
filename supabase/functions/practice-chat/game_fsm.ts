import type { InviteStage } from "./invite_maturity.ts";
import type { PracticeProfile } from "./practice_persona.ts";
import {
  clampTemperature,
  type LearningJudgement,
  type PartnerMood,
  type RelationshipStage,
  relationshipStageFor,
  temperatureBandFor,
  type TurnClassification,
} from "./temperature.ts";
import type { PracticeTurn } from "./validate.ts";

export type GameFsmPhase =
  | "P1_OPEN"
  | "P2_VALUE"
  | "P3_TEST"
  | "P4_TENSION"
  | "P5_CLOSE";

export type GameFailureState =
  | "BORING"
  | "TOOL_GUY"
  | "GREASY"
  | "FRAME_COLLAPSE"
  | "ENGINE_STALL"
  | "GHOST_RISK"
  | "FRAME_OVERREACH";

export type GameRealityFlag =
  | "social_proof_attempt"
  | "fake_familiarity"
  | "OBVIOUS_TRAP"
  | "FRAME_OVERREACH";

export type GameSpicyLevel = "L0" | "L1" | "L2" | "L3";

export interface GameHiddenVariables {
  pv: number;
  fp: number;
  inv: number;
  safety: number;
  heatBias: number;
}

export interface GameFsmSnapshot {
  phase: GameFsmPhase;
  targetVariable: string;
  speedInviteDirection: string;
  hidden: GameHiddenVariables;
  failureStates: GameFailureState[];
  realityFlags: GameRealityFlag[];
  spicyLevel: GameSpicyLevel;
}

export interface SrGameStrategy {
  profileId: string;
  valueHooks: string[];
  testStyle: string;
  tensionStyle: string;
  closeHooks: string[];
  punishments: string[];
}

const GAME_HEAT_DELTA_MIN = -12;
const GAME_HEAT_DELTA_MAX = 12;
const GAME_FAMILIARITY_DELTA_MIN = -12;
const GAME_FAMILIARITY_DELTA_MAX = 12;

function clampScore(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function clampDelta(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return 0;
  const rounded = Math.round(value);
  if (rounded === 0 && value > 0) return 1;
  if (rounded === 0 && value < 0) return -1;
  return Math.max(min, Math.min(max, rounded));
}

function normalized(text: string): string {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/\s+/g, "");
}

function userTexts(turns: PracticeTurn[]): string[] {
  return turns.filter((turn) => turn.role === "user").map((turn) => turn.text);
}

function latestUserText(turns: PracticeTurn[]): string {
  const users = userTexts(turns);
  return users[users.length - 1] ?? "";
}

function includesAny(text: string, patterns: readonly string[]): boolean {
  return patterns.some((pattern) => text.includes(pattern));
}

function questionPressureScore(texts: string[]): number {
  const questionWords = [
    "幾歲",
    "住哪",
    "住哪裡",
    "在哪",
    "哪裡人",
    "做什麼",
    "工作",
    "下班都去哪",
    "今天在哪",
    "收入",
    "交過",
  ];
  return texts.reduce((score, raw) => {
    const text = normalized(raw);
    const marks = (raw.match(/[?？]/g) ?? []).length;
    const wordHits = questionWords.filter((word) => text.includes(word))
      .length;
    const hasSelfDisclosure = includesAny(text, [
      "我也",
      "我剛",
      "我今天",
      "我自己",
      "我以前",
      "我喜歡",
    ]);
    return score + marks + wordHits - (hasSelfDisclosure ? 1 : 0);
  }, 0);
}

function looksOverEscalated(text: string): boolean {
  const compact = normalized(text);
  return includesAny(compact, [
    "開房",
    "上床",
    "去我家睡",
    "來我家睡",
    "去你家睡",
    "去妳家睡",
    "一起睡",
    "睡你",
    "睡妳",
    "睡我",
    "親你",
    "親妳",
    "直接來我家",
    "今晚去我家",
  ]);
}

function looksLikeToolGuy(texts: string[]): boolean {
  const joined = normalized(texts.join("\n"));
  const helpHits = [
    "我幫你",
    "我載你",
    "我請你",
    "我買給你",
    "我送你",
    "我可以教你",
    "我替你",
  ].filter((pattern) => joined.includes(pattern)).length;
  return helpHits >= 2;
}

function looksLikeFrameCollapse(text: string): boolean {
  const compact = normalized(text);
  return includesAny(compact, [
    "我不是那個意思",
    "你不要誤會",
    "我哪有",
    "我只是",
    "拜託",
    "真的啦",
    "對不起啦",
    "不要想太多",
  ]);
}

function looksLikeEngineStall(texts: string[]): boolean {
  if (texts.length < 3) return false;
  const recent = texts.slice(-3).map((text) => normalized(text));
  return recent.every((text) => text.length <= 8) &&
    recent.some((text) =>
      ["嗯", "哈哈", "好喔", "是喔", "不知道"].includes(text)
    );
}

function looksLikeSoftInvite(text: string): boolean {
  const compact = normalized(text);
  return includesAny(compact, [
    "下次",
    "改天",
    "有空",
    "咖啡",
    "吃飯",
    "走走",
    "逛逛",
    "你會想去",
    "找一間",
  ]);
}

function realityFlagsFor(text: string): GameRealityFlag[] {
  const compact = normalized(text);
  const flags = new Set<GameRealityFlag>();
  if (
    includesAny(compact, [
      "介紹",
      "給我你的line",
      "給的line",
      "朋友給",
      "同事給",
      "同學給",
      "joyce",
      "陳醫師",
    ])
  ) {
    flags.add("social_proof_attempt");
  }
  if (
    includesAny(compact, [
      "上次",
      "見過",
      "你們診所",
      "你同事",
      "你朋友",
      "你家人",
      "我知道你住哪",
      "我知道你在哪",
      "我知道你今天",
      "我記得你",
    ])
  ) {
    flags.add("fake_familiarity");
  }
  if (flags.size > 0) {
    flags.add("OBVIOUS_TRAP");
    flags.add("FRAME_OVERREACH");
  }
  return [...flags];
}

function basePhaseFor(opts: {
  relationshipStage: RelationshipStage;
  inviteStage?: InviteStage | null;
  partnerMood?: PartnerMood | null;
  softInvite: boolean;
}): GameFsmPhase {
  if (opts.partnerMood === "guarded" || opts.partnerMood === "annoyed") {
    return "P3_TEST";
  }
  if (
    opts.softInvite ||
    opts.inviteStage === "direct_invite_ready" ||
    opts.inviteStage === "partner_window" ||
    opts.inviteStage === "high_intimacy"
  ) {
    return "P5_CLOSE";
  }
  if (opts.relationshipStage === "flirt_allowed") return "P4_TENSION";
  if (opts.relationshipStage === "personal_allowed") return "P2_VALUE";
  return "P1_OPEN";
}

function targetVariableFor(
  phase: GameFsmPhase,
  failures: readonly GameFailureState[],
): string {
  if (failures.includes("GREASY")) return "safety + Frame";
  if (failures.includes("BORING")) return "Value + Emotion";
  if (failures.includes("FRAME_COLLAPSE")) return "Frame + safety";
  return {
    P1_OPEN: "familiarity",
    P2_VALUE: "Value + Emotion",
    P3_TEST: "Frame + safety",
    P4_TENSION: "Emotion + heat",
    P5_CLOSE: "Investment + invite",
  }[phase];
}

function speedInviteDirectionFor(opts: {
  phase: GameFsmPhase;
  inviteStage?: InviteStage | null;
  partnerMood?: PartnerMood | null;
  failures: readonly GameFailureState[];
  softInvite: boolean;
}): string {
  if (
    opts.failures.includes("GREASY") ||
    opts.failures.includes("FRAME_OVERREACH") ||
    opts.partnerMood === "annoyed"
  ) {
    return "repair_before_invite";
  }
  if (opts.partnerMood === "guarded") return "no_private_scene_soften";
  if (opts.inviteStage === "partner_window") return "partner_window_close";
  if (
    opts.softInvite ||
    opts.inviteStage === "direct_invite_ready" ||
    opts.inviteStage === "high_intimacy"
  ) {
    return "direct_invite_low_pressure";
  }
  if (opts.inviteStage === "soft_invite_ready" || opts.phase === "P5_CLOSE") {
    return "soft_invite_probe";
  }
  return "no_invite_build_investment";
}

function spicyLevelFor(opts: {
  temperatureScore: number;
  familiarityScore: number;
  partnerMood?: PartnerMood | null;
  failures: readonly GameFailureState[];
  realityFlags: readonly GameRealityFlag[];
}): GameSpicyLevel {
  if (
    opts.realityFlags.length > 0 ||
    opts.failures.includes("GREASY") ||
    opts.failures.includes("GHOST_RISK") ||
    opts.partnerMood === "annoyed"
  ) {
    return "L0";
  }
  if (
    opts.failures.includes("FRAME_COLLAPSE") ||
    opts.partnerMood === "guarded"
  ) {
    return "L1";
  }
  if (opts.temperatureScore >= 75 && opts.familiarityScore >= 65) return "L3";
  if (opts.temperatureScore >= 60 && opts.familiarityScore >= 45) return "L2";
  return "L1";
}

function classificationBias(
  classification?: TurnClassification,
): Pick<GameHiddenVariables, "fp" | "safety" | "heatBias"> {
  if (!classification) {
    return { fp: 0, safety: 0, heatBias: 0 };
  }
  let fp = 0;
  let safety = 0;
  let heatBias = 0;
  if (classification.testHandling === "passed") {
    fp += 24;
    heatBias += 8;
  } else if (classification.testHandling === "failed") {
    fp -= 26;
    heatBias -= 8;
  }
  if (classification.connection === "caught") heatBias += 4;
  if (classification.connection === "defensive") {
    fp -= 10;
    heatBias -= 5;
  }
  if (classification.connection === "overstepped") {
    safety -= 28;
    heatBias -= 10;
  }
  if (classification.boundary === "pushy") safety -= 14;
  if (classification.boundary === "overstep") safety -= 34;
  return { fp, safety, heatBias };
}

export function evaluateGameFsm(opts: {
  turns: PracticeTurn[];
  temperatureScore: number;
  familiarityScore: number;
  partnerMood?: PartnerMood | null;
  relationshipStage?: RelationshipStage;
  inviteStage?: InviteStage | null;
  classification?: TurnClassification;
}): GameFsmSnapshot {
  const temperature = clampTemperature(opts.temperatureScore);
  const familiarity = clampTemperature(opts.familiarityScore);
  const texts = userTexts(opts.turns);
  const latest = latestUserText(opts.turns);
  const latestCompact = normalized(latest);
  const relationshipStage = opts.relationshipStage ??
    relationshipStageFor(familiarity, temperature).stage;
  const failures = new Set<GameFailureState>();
  const realityFlags = realityFlagsFor(latest);
  const pressure = questionPressureScore(texts);
  const softInvite = looksLikeSoftInvite(latest);
  const overEscalated = looksOverEscalated(latest);
  const classification = opts.classification;

  if (pressure >= 4) failures.add("BORING");
  if (looksLikeToolGuy(texts)) failures.add("TOOL_GUY");
  if (
    overEscalated ||
    classification?.connection === "overstepped" ||
    classification?.boundary === "overstep"
  ) {
    failures.add("GREASY");
  }
  if (
    classification?.testHandling === "failed" ||
    looksLikeFrameCollapse(latest)
  ) {
    failures.add("FRAME_COLLAPSE");
  }
  if (looksLikeEngineStall(texts)) failures.add("ENGINE_STALL");
  const unsafeBoundary = classification !== undefined &&
    classification.boundary !== "safe";
  if (
    opts.partnerMood === "annoyed" ||
    (opts.partnerMood === "guarded" &&
      (overEscalated || unsafeBoundary)) ||
    failures.has("GREASY")
  ) {
    failures.add("GHOST_RISK");
  }
  if (realityFlags.includes("FRAME_OVERREACH")) {
    failures.add("FRAME_OVERREACH");
  }

  const bias = classificationBias(classification);
  const pv = clampScore(
    temperature * 0.35 +
      familiarity * 0.25 +
      (includesAny(latestCompact, ["我喜歡", "我剛", "我今天", "我自己"])
        ? 16
        : 0) -
      pressure * 4,
  );
  const fp = clampScore(
    50 + bias.fp -
      (failures.has("FRAME_COLLAPSE") ? 20 : 0) +
      (classification?.testHandling === "passed" ? 12 : 0),
  );
  const inv = clampScore(
    familiarity * 0.45 +
      temperature * 0.25 +
      (softInvite ? 40 : 0) -
      (failures.has("BORING") ? 18 : 0),
  );
  const safety = clampScore(
    74 + bias.safety -
      (failures.has("GREASY") ? 40 : 0) -
      (realityFlags.length > 0 ? 30 : 0) -
      (opts.partnerMood === "guarded" ? 16 : 0) -
      (opts.partnerMood === "annoyed" ? 28 : 0),
  );
  const phase = basePhaseFor({
    relationshipStage,
    inviteStage: opts.inviteStage ?? null,
    partnerMood: opts.partnerMood ?? null,
    softInvite,
  });
  const failureStates = [...failures];
  const targetVariable = targetVariableFor(phase, failureStates);
  const speedInviteDirection = speedInviteDirectionFor({
    phase,
    inviteStage: opts.inviteStage ?? null,
    partnerMood: opts.partnerMood ?? null,
    failures: failureStates,
    softInvite,
  });
  const spicyLevel = spicyLevelFor({
    temperatureScore: temperature,
    familiarityScore: familiarity,
    partnerMood: opts.partnerMood,
    failures: failureStates,
    realityFlags,
  });

  return {
    phase,
    targetVariable,
    speedInviteDirection,
    hidden: {
      pv,
      fp,
      inv,
      safety,
      heatBias: bias.heatBias -
        (failures.has("GREASY") ? 8 : 0) -
        (failures.has("BORING") ? 3 : 0),
    },
    failureStates,
    realityFlags,
    spicyLevel,
  };
}

export function applyGameLearningDelta(opts: {
  judgement: LearningJudgement;
  currentTemperature: number;
  currentFamiliarity: number;
  snapshot: GameFsmSnapshot;
}): LearningJudgement {
  const hasSafetyFailure = opts.snapshot.failureStates.some((state) =>
    state === "GREASY" ||
    state === "GHOST_RISK" ||
    state === "FRAME_OVERREACH"
  );
  const hasFrameFailure = opts.snapshot.failureStates.includes(
    "FRAME_COLLAPSE",
  );
  const positiveHeatScale = opts.snapshot.hidden.fp >= 65 ? 1.45 : 1.3;
  const positiveFamiliarityScale = opts.snapshot.hidden.inv >= 55 ? 1.35 : 1.2;
  const negativeScale = hasSafetyFailure ? 1.35 : hasFrameFailure ? 1.2 : 1.1;

  const heatRaw = opts.judgement.delta >= 0
    ? opts.judgement.delta * positiveHeatScale
    : opts.judgement.delta * negativeScale;
  const familiarityRaw = opts.judgement.familiarityDelta >= 0
    ? opts.judgement.familiarityDelta * positiveFamiliarityScale
    : opts.judgement.familiarityDelta * negativeScale;
  const heatDelta = clampDelta(
    heatRaw,
    GAME_HEAT_DELTA_MIN,
    GAME_HEAT_DELTA_MAX,
  );
  const familiarityDelta = clampDelta(
    familiarityRaw,
    GAME_FAMILIARITY_DELTA_MIN,
    GAME_FAMILIARITY_DELTA_MAX,
  );
  const score = clampTemperature(opts.currentTemperature + heatDelta);
  const familiarityScore = clampTemperature(
    opts.currentFamiliarity + familiarityDelta,
  );
  const stage = relationshipStageFor(familiarityScore, score);
  return {
    ...opts.judgement,
    score,
    delta: heatDelta,
    band: temperatureBandFor(score),
    familiarityScore,
    familiarityDelta,
    stage: stage.stage,
    stageLabel: stage.label,
  };
}

function csv(values: readonly string[]): string {
  return values.length === 0 ? "none" : values.join(", ");
}

export function gameFsmEvidencePrompt(snapshot: GameFsmSnapshot): string {
  return `socialGameFsm(hidden guidance)\nphase: ${snapshot.phase}\ntargetVariable: ${snapshot.targetVariable}\nspeedInviteDirection: ${snapshot.speedInviteDirection}\nvisibleVariables: heat/familiarity only; never reveal hidden variables\nhiddenVariables: pv=${snapshot.hidden.pv}, fp=${snapshot.hidden.fp}, inv=${snapshot.hidden.inv}, safety=${snapshot.hidden.safety}, heatBias=${snapshot.hidden.heatBias}\nfailureStates: ${
    csv(snapshot.failureStates)
  }\nrealityFlags: ${
    csv(snapshot.realityFlags)
  }\nallowSpicyLevel: ${snapshot.spicyLevel}\ndeltaClamp: heat ${GAME_HEAT_DELTA_MIN}..+${GAME_HEAT_DELTA_MAX}, familiarity ${GAME_FAMILIARITY_DELTA_MIN}..+${GAME_FAMILIARITY_DELTA_MAX}\nUse failure states internally only. BORING means stop interviewing and add Value/Emotion. TOOL_GUY means stop buying approval. GREASY means repair safety and lower sexual/private pressure. FRAME_COLLAPSE means stop over-explaining. ENGINE_STALL means add a concrete hook. GHOST_RISK means reduce pressure. FRAME_OVERREACH/Reality flags mean confirm, tease, or doubt instead of validating fake familiarity.\n`;
}

function uniqueNonEmpty(values: readonly string[], maxItems: number): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const trimmed = value.trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    result.push(trimmed);
    if (result.length >= maxItems) break;
  }
  return result;
}

function testStyleFor(profile: PracticeProfile): string {
  const types = profile.consistencyTest.types.join(", ");
  const propensity = profile.consistencyTest.propensity;
  if (profile.personaId === "teasing_humor") {
    return `高頻吐槽測試；常用 ${types}，用幽默反打過關，不要自證。`;
  }
  if (profile.personaId === "cool_rational") {
    return `冷靜篩選測試；常用 ${types}，用穩定觀點過關，不要油。`;
  }
  if (profile.personaId === "clear_boundaries") {
    return `邊界測試；常用 ${types}，用尊重與分寸過關，不要硬推。`;
  }
  return `${propensity} 測試頻率；常用 ${types}，接住情緒後再丟球。`;
}

function tensionStyleFor(profile: PracticeProfile): string {
  if (profile.personaId === "teasing_humor") {
    return "用玩笑、反打和留白做張力；可以辣，但不能粗俗。";
  }
  if (profile.personaId === "playful_extrovert") {
    return "用節奏、活動畫面和輕調侃做張力；避免黏或說教。";
  }
  if (profile.personaId === "cool_rational") {
    return "用穩定框架和聰明留白做張力；少誇，多有主見。";
  }
  if (profile.personaId === "clear_boundaries") {
    return "用安全感與成熟感做張力；任何私密推進都要慢。";
  }
  return "用生活感和低壓靠近做張力；先暖，不急著撩。";
}

export function buildSrGameStrategy(
  profile: PracticeProfile,
): SrGameStrategy | null {
  if (profile.girl.rarity !== "sr") return null;
  const girl = profile.girl;
  return {
    profileId: girl.profileId,
    valueHooks: uniqueNonEmpty([
      ...girl.interestTags.map((tag) => `聊「${tag}」時先給畫面再問她`),
      ...girl.lifestyleTags.map((tag) => `接她的生活節奏：${tag}`),
      ...girl.reactionModel.likes,
    ], 4),
    testStyle: testStyleFor(profile),
    tensionStyle: tensionStyleFor(profile),
    closeHooks: uniqueNonEmpty([
      ...girl.interestTags.map((tag) => `把 ${tag} 轉成低壓小場景`),
      ...girl.lifestyleTags.map((tag) => `順著 ${tag} 丟低壓邀約`),
      girl.reactionModel.inviteThreshold,
    ], 3),
    punishments: uniqueNonEmpty([
      ...girl.reactionModel.coolsWhen,
      ...girl.reactionModel.dislikes,
    ], 4),
  };
}

export function srGameStrategyPrompt(profile: PracticeProfile): string {
  const strategy = buildSrGameStrategy(profile);
  if (!strategy) return "";
  return `srGameStrategy(hidden guidance)\nprofileId: ${strategy.profileId}\nvalueHooks: ${
    strategy.valueHooks.join("；")
  }\ntestStyle: ${strategy.testStyle}\ntensionStyle: ${strategy.tensionStyle}\ncloseHooks: ${
    strategy.closeHooks.join("；")
  }\npunishments: ${
    strategy.punishments.join("；")
  }\nUse this only to make this SR card feel strategically distinct in Game mode. Do not reveal profileId, strategy labels, or hidden hook names.`;
}
