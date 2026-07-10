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

const GAME_HEAT_DELTA_MIN = -18;
const GAME_HEAT_DELTA_MAX = 18;
const GAME_FAMILIARITY_DELTA_MIN = -18;
const GAME_FAMILIARITY_DELTA_MAX = 18;

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
  const positiveHeatScale = opts.snapshot.hidden.fp >= 65 ? 2 : 1.75;
  const positiveFamiliarityScale = opts.snapshot.hidden.inv >= 55 ? 1.8 : 1.6;
  const negativeScale = hasSafetyFailure ? 1.8 : hasFrameFailure ? 1.55 : 1.35;

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

const EXPLICIT_SR_GAME_STRATEGIES: Record<
  string,
  Omit<SrGameStrategy, "profileId">
> = {
  practice_girl_004: {
    valueHooks: ["dry humor", "craft coffee", "small competence flex"],
    testStyle: "teasing tests; she rewards calm wit and concise callbacks",
    tensionStyle: "playful verbal tension, never push private scenes early",
    closeHooks: ["coffee tasting", "quick bookstore loop", "dessert detour"],
    punishments: ["needy approval", "over-explaining", "fake familiarity"],
  },
  practice_girl_006: {
    valueHooks: ["night walk", "music taste", "low-key confidence"],
    testStyle: "soft challenge; she checks if your frame survives silence",
    tensionStyle: "quiet tension through implication and slower tempo",
    closeHooks: ["live music", "late tea", "short city walk"],
    punishments: ["interviewing", "rushing intimacy", "tool-guy favors"],
  },
  practice_girl_007: {
    valueHooks: ["fitness discipline", "healthy routines", "playful stamina"],
    testStyle: "direct energy test; she likes grounded banter",
    tensionStyle: "athletic teasing and challenge, consent-forward",
    closeHooks: ["smoothie stop", "easy hike", "weekend workout cafe"],
    punishments: ["lazy vagueness", "sexual pressure", "bragging"],
  },
  practice_girl_008: {
    valueHooks: ["art taste", "visual details", "curious observation"],
    testStyle: "taste filter; she notices whether you actually observe",
    tensionStyle: "aesthetic contrast and light mystery",
    closeHooks: ["gallery loop", "design market", "photo walk"],
    punishments: ["generic compliments", "explaining her taste", "neediness"],
  },
  practice_girl_009: {
    valueHooks: ["career drive", "sharp boundaries", "efficient plans"],
    testStyle: "competence test; she rewards clarity and low pressure",
    tensionStyle: "confident compression, no rambling",
    closeHooks: ["espresso between meetings", "short lunch", "after-work bar"],
    punishments: ["unclear intent", "frame collapse", "time wasting"],
  },
  practice_girl_028: {
    valueHooks: ["travel stories", "local gems", "spontaneous planning"],
    testStyle: "adventure filter; she checks if you can lead lightly",
    tensionStyle: "inviting momentum with easy opt-outs",
    closeHooks: ["hidden cafe", "mini itinerary", "street food stop"],
    punishments: ["controlling plans", "unsafe pressure", "boring logistics"],
  },
  practice_girl_032: {
    valueHooks: ["book notes", "intellectual play", "specific memory"],
    testStyle: "precision test; vague flirting cools her off",
    tensionStyle: "smart challenge and understated warmth",
    closeHooks: ["bookstore coffee", "quiet tea", "lecture after-chat"],
    punishments: ["surface-level lines", "fake expertise", "pushiness"],
  },
  practice_girl_033: {
    valueHooks: ["food curiosity", "sensory detail", "social ease"],
    testStyle: "taste and generosity test; she dislikes show-off ordering",
    tensionStyle: "warm sensory teasing without explicitness",
    closeHooks: ["dessert split", "night market bite", "chef's pick"],
    punishments: ["cheap innuendo", "indecision", "approval seeking"],
  },
  practice_girl_036: {
    valueHooks: ["indie music", "private jokes", "calm originality"],
    testStyle: "coolness test; she checks if you chase validation",
    tensionStyle: "deadpan tension and selective compliments",
    closeHooks: ["vinyl shop", "small gig", "late cafe"],
    punishments: ["trying too hard", "copy-paste lines", "neediness"],
  },
  practice_girl_038: {
    valueHooks: ["pet stories", "gentle reliability", "daily rituals"],
    testStyle: "safety test; she warms to steady, non-pushy pacing",
    tensionStyle: "soft warmth with tiny playful challenge",
    closeHooks: ["pet-friendly cafe", "park coffee", "bakery errand"],
    punishments: ["hard escalation", "unverified familiarity", "mocking"],
  },
  practice_girl_051: {
    valueHooks: ["startup grit", "decision speed", "clear priorities"],
    testStyle: "frame test; she pokes at indecision",
    tensionStyle: "fast, confident, low-word-count tension",
    closeHooks: ["15-minute coffee", "demo day drink", "late snack"],
    punishments: ["rambling", "unclear plans", "bragging without proof"],
  },
  practice_girl_052: {
    valueHooks: ["fashion detail", "tasteful restraint", "scene awareness"],
    testStyle: "taste test; she notices if you over-compliment",
    tensionStyle: "stylish restraint and one precise compliment",
    closeHooks: ["concept store", "cocktail bar", "window-shopping loop"],
    punishments: ["objectifying", "generic praise", "private-scene pressure"],
  },
  practice_girl_055: {
    valueHooks: ["medical humor", "competence under stress", "care rhythm"],
    testStyle: "stress test; she values steady humor without mansplaining",
    tensionStyle: "warm competence and lightly mischievous callbacks",
    closeHooks: ["post-shift dessert", "quiet ramen", "short coffee"],
    punishments: ["fake hospital social proof", "lecture mode", "neediness"],
  },
  practice_girl_063: {
    valueHooks: ["language play", "culture contrast", "travel curiosity"],
    testStyle: "curiosity test; she dislikes exoticizing",
    tensionStyle: "cross-cultural teasing with respect and boundaries",
    closeHooks: ["language exchange cafe", "museum snack", "tea tasting"],
    punishments: ["stereotyping", "over-explaining", "rushing intimacy"],
  },
  practice_girl_065: {
    valueHooks: ["dance rhythm", "body confidence", "social calibration"],
    testStyle: "calibration test; she checks if you read cues",
    tensionStyle: "movement metaphors, never explicit body claims",
    closeHooks: ["salsa night", "dessert after class", "music bar"],
    punishments: ["greasy body comments", "pressure", "jealous framing"],
  },
  practice_girl_079: {
    valueHooks: ["finance discipline", "dry wit", "long-game thinking"],
    testStyle: "logic test; she rewards calm confidence",
    tensionStyle: "controlled teasing with grounded specifics",
    closeHooks: ["wine bar", "weekday coffee", "market brunch"],
    punishments: ["showing off money", "vague flirting", "frame collapse"],
  },
  practice_girl_080: {
    valueHooks: ["outdoor calm", "nature details", "prepared leadership"],
    testStyle: "reliability test; she warms when plans feel safe",
    tensionStyle: "fresh-air playfulness and slow burn",
    closeHooks: ["sunset walk", "trail cafe", "morning bakery"],
    punishments: ["unsafe spontaneity", "hard escalation", "complaint loops"],
  },
  practice_girl_082: {
    valueHooks: ["gaming references", "team play", "creative problem solving"],
    testStyle: "banter duel; she likes playful counters",
    tensionStyle: "competitive teasing and quick callbacks",
    closeHooks: ["arcade date", "board-game cafe", "late-night snack"],
    punishments: ["mansplaining", "rage energy", "needy compliments"],
  },
  practice_girl_085: {
    valueHooks: ["cinema taste", "emotional nuance", "observant callbacks"],
    testStyle: "depth test; she notices shallow lines",
    tensionStyle: "cinematic implication and emotional contrast",
    closeHooks: ["indie movie", "post-film tea", "night walk"],
    punishments: ["spoilers", "generic romance lines", "rushing close"],
  },
  practice_girl_087: {
    valueHooks: ["law-school precision", "boundaries", "sharp teasing"],
    testStyle: "argument test; she checks if you can disagree lightly",
    tensionStyle: "controlled debate and respectful push-pull",
    closeHooks: ["court-area coffee", "mocktail", "bookstore stop"],
    punishments: ["pressure", "lying social proof", "defensive essays"],
  },
};

export function hasExplicitSrGameStrategy(profileId: string): boolean {
  return Object.prototype.hasOwnProperty.call(
    EXPLICIT_SR_GAME_STRATEGIES,
    profileId,
  );
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
): SrGameStrategy {
  const girl = profile.girl;
  const explicit = EXPLICIT_SR_GAME_STRATEGIES[girl.profileId];
  if (explicit) {
    return {
      profileId: girl.profileId,
      ...explicit,
    };
  }
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
  return `srGameStrategy(hidden guidance)\nprofileId: ${strategy.profileId}\nvalueHooks: ${
    strategy.valueHooks.join("；")
  }\ntestStyle: ${strategy.testStyle}\ntensionStyle: ${strategy.tensionStyle}\ncloseHooks: ${
    strategy.closeHooks.join("；")
  }\npunishments: ${
    strategy.punishments.join("；")
  }\nUse this only to make this card feel strategically distinct in Game mode. Do not reveal profileId, strategy labels, or hidden hook names.`;
}
