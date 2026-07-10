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

export interface GameStrategy {
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

/** Hint/Debrief 專用：保留決策證據，移除只影響 NPC/評分的數值與重複說明。 */
export function compactGameFsmEvidencePrompt(
  snapshot: GameFsmSnapshot,
): string {
  return `socialGameFsm(hidden guidance)\nphase: ${snapshot.phase}\ntargetVariable: ${snapshot.targetVariable}\nspeedInviteDirection: ${snapshot.speedInviteDirection}\nfailureStates: ${
    csv(snapshot.failureStates)
  }\nrealityFlags: ${
    csv(snapshot.realityFlags)
  }\nallowSpicyLevel: ${snapshot.spicyLevel}\n`;
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
  Omit<GameStrategy, "profileId">
> = {
  practice_girl_004: {
    valueHooks: ["冷面幽默", "手作咖啡品味", "低調展現辦事能力"],
    testStyle: "用吐槽測穩定度；她欣賞冷靜機智與簡短回呼",
    tensionStyle: "用玩笑反打與言語留白做張力，前期絕不推私密場景",
    closeHooks: ["咖啡品飲", "書店快逛", "順路吃甜點"],
    punishments: ["討好求認可", "解釋過頭", "假裝很熟"],
  },
  practice_girl_006: {
    valueHooks: ["夜間散步", "音樂品味", "低調自信"],
    testStyle: "用輕微挑戰測沉著；她會看你能不能自在承受沉默",
    tensionStyle: "用暗示與慢節奏營造安靜張力，不急著逼近",
    closeHooks: ["現場音樂", "晚茶", "城市短散步"],
    punishments: ["查戶口式追問", "急著拉近親密", "用幫忙討好"],
  },
  practice_girl_007: {
    valueHooks: ["自律健身", "健康日常", "有玩心的體力感"],
    testStyle: "直接測你的能量；她喜歡有根據、不飄的來回調侃",
    tensionStyle: "用運動感的玩笑與挑戰做張力，以同意和分寸為前提",
    closeHooks: ["果昔小聚", "輕鬆健行", "週末運動後咖啡"],
    punishments: ["懶散含糊", "性壓力", "自我吹噓"],
  },
  practice_girl_008: {
    valueHooks: ["藝術品味", "視覺細節", "好奇觀察"],
    testStyle: "用品味辨識你是否真的有觀察，而不是套話",
    tensionStyle: "用美感反差與一點神祕感做張力",
    closeHooks: ["逛一圈畫廊", "設計市集", "街頭攝影散步"],
    punishments: ["萬用稱讚", "替她解釋品味", "黏著求認可"],
  },
  practice_girl_009: {
    valueHooks: ["事業企圖", "清楚界線", "有效率的安排"],
    testStyle: "用辦事能力測清晰度；她欣賞明確又低壓的表達",
    tensionStyle: "用自信而精簡的表達做張力，不冗長繞圈",
    closeHooks: ["會議空檔喝濃縮咖啡", "簡短午餐", "下班後小酌"],
    punishments: ["意圖不清", "失去主見", "浪費時間"],
  },
  practice_girl_028: {
    valueHooks: ["旅行故事", "在地私房點", "隨興規劃"],
    testStyle: "用冒險感看你能否輕鬆帶方向，不控制行程",
    tensionStyle: "用有動能的邀請營造張力，隨時保留退出空間",
    closeHooks: ["私房咖啡店", "迷你行程", "街頭小吃"],
    punishments: ["控制行程", "不安全的施壓", "無聊的行程盤問"],
  },
  practice_girl_032: {
    valueHooks: ["讀書筆記", "知性玩心", "記得具體細節"],
    testStyle: "用精準度測深度；空泛調情會讓她降溫",
    tensionStyle: "用聰明挑戰與克制的溫度做張力",
    closeHooks: ["書店咖啡", "安靜喝茶", "講座後短聊"],
    punishments: ["表面套話", "假裝專業", "強勢逼近"],
  },
  practice_girl_033: {
    valueHooks: ["對食物的好奇", "感官細節", "自在社交感"],
    testStyle: "用口味與分享感測你；她不喜歡炫耀式點餐",
    tensionStyle: "用溫暖的感官玩笑做張力，不露骨",
    closeHooks: ["分吃甜點", "夜市小吃", "主廚推薦"],
    punishments: ["廉價雙關", "猶豫不決", "討好求認可"],
  },
  practice_girl_036: {
    valueHooks: ["獨立音樂", "兩人的小梗", "沉著原創感"],
    testStyle: "測你會不會追著求認可；越自在越加分",
    tensionStyle: "用冷面幽默與精準稱讚做張力",
    closeHooks: ["黑膠唱片行", "小型演出", "深夜咖啡"],
    punishments: ["用力過頭", "複製貼上話術", "黏著求認可"],
  },
  practice_girl_038: {
    valueHooks: ["寵物故事", "溫柔可靠", "日常小儀式"],
    testStyle: "測安全感；穩定、不施壓的節奏會讓她慢慢升溫",
    tensionStyle: "用柔和溫度加一點小挑戰做張力",
    closeHooks: ["寵物友善咖啡", "公園咖啡", "順路去麵包店"],
    punishments: ["硬推進", "未確認就裝熟", "嘲弄她"],
  },
  practice_girl_051: {
    valueHooks: ["創業韌性", "決策速度", "清楚優先順序"],
    testStyle: "測你的主見；她會戳你猶豫不決的地方",
    tensionStyle: "用快速、自信、少字的表達做張力",
    closeHooks: ["十五分鐘咖啡", "展示活動後小酌", "深夜點心"],
    punishments: ["長篇繞圈", "計畫不清", "沒有證據的吹噓"],
  },
  practice_girl_052: {
    valueHooks: ["穿搭細節", "有品味的克制", "讀懂場合"],
    testStyle: "用品味測你會不會稱讚過頭",
    tensionStyle: "用有型的克制與一句精準稱讚做張力",
    closeHooks: ["概念店", "雞尾酒吧", "短程逛街"],
    punishments: ["物化她", "萬用稱讚", "施壓私密場景"],
  },
  practice_girl_055: {
    valueHooks: ["醫療現場幽默", "壓力下的穩定能力", "懂得照顧節奏"],
    testStyle: "用壓力測你的穩定；她欣賞不說教的沉著幽默",
    tensionStyle: "用可靠能力與帶點調皮的回呼做張力",
    closeHooks: ["下班後甜點", "安靜吃拉麵", "短暫喝咖啡"],
    punishments: ["假借醫院人脈背書", "說教模式", "黏著求認可"],
  },
  practice_girl_063: {
    valueHooks: ["語言玩心", "文化反差", "旅行好奇心"],
    testStyle: "用好奇心測你；她討厭把文化差異當獵奇",
    tensionStyle: "用跨文化玩笑做張力，同時尊重界線",
    closeHooks: ["語言交換咖啡", "博物館點心", "品茶"],
    punishments: ["刻板印象", "解釋過頭", "急著拉近親密"],
  },
  practice_girl_065: {
    valueHooks: ["舞蹈節奏", "自在身體感", "社交分寸"],
    testStyle: "測你能不能讀懂反應與節奏",
    tensionStyle: "用動作隱喻做張力，絕不對身體做露骨宣稱",
    closeHooks: ["拉丁舞之夜", "課後甜點", "音樂酒吧"],
    punishments: ["油膩身體評論", "施壓", "用嫉妒操控"],
  },
  practice_girl_079: {
    valueHooks: ["理財紀律", "冷面機智", "長線思考"],
    testStyle: "用邏輯測穩定；她欣賞冷靜自信",
    tensionStyle: "用有根據的具體細節與克制調侃做張力",
    closeHooks: ["葡萄酒吧", "平日咖啡", "市場早午餐"],
    punishments: ["炫耀金錢", "空泛調情", "失去主見"],
  },
  practice_girl_080: {
    valueHooks: ["戶外沉著", "自然細節", "有準備的帶領感"],
    testStyle: "測可靠度；安排讓人安心時她會升溫",
    tensionStyle: "用戶外感的玩心慢慢升溫",
    closeHooks: ["夕陽散步", "步道咖啡", "早晨麵包店"],
    punishments: ["不安全的臨時起意", "硬推進", "反覆抱怨"],
  },
  practice_girl_082: {
    valueHooks: ["遊戲梗", "團隊默契", "創意解題"],
    testStyle: "用互虧來回測反應；她喜歡有玩心的反擊",
    tensionStyle: "用競爭式調侃與快速回呼做張力",
    closeHooks: ["街機小約", "桌遊咖啡", "深夜點心"],
    punishments: ["居高臨下說教", "暴怒能量", "討好式稱讚"],
  },
  practice_girl_085: {
    valueHooks: ["電影品味", "情緒細節", "觀察式回呼"],
    testStyle: "用深度測你；表面話術很快會被她看穿",
    tensionStyle: "用電影感暗示與情緒反差做張力",
    closeHooks: ["獨立電影", "散場後喝茶", "夜間散步"],
    punishments: ["爆雷", "萬用浪漫台詞", "急著收尾"],
  },
  practice_girl_087: {
    valueHooks: ["法律式精準", "清楚界線", "犀利調侃"],
    testStyle: "用觀點交鋒測你能否輕鬆不同意",
    tensionStyle: "用克制辯論與尊重的來回拉力做張力",
    closeHooks: ["法院附近咖啡", "無酒精調飲", "書店短逛"],
    punishments: ["施壓", "謊稱人脈背書", "防禦式長文"],
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

export function buildGameStrategy(
  profile: PracticeProfile,
): GameStrategy {
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

export function gameStrategyPrompt(profile: PracticeProfile): string {
  const strategy = buildGameStrategy(profile);
  return `gameStrategy(hidden guidance)\nprofileId: ${strategy.profileId}\nvalueHooks: ${
    strategy.valueHooks.join("；")
  }\ntestStyle: ${strategy.testStyle}\ntensionStyle: ${strategy.tensionStyle}\ncloseHooks: ${
    strategy.closeHooks.join("；")
  }\npunishments: ${
    strategy.punishments.join("；")
  }\nUse this only to make this card feel strategically distinct in Game mode. Do not reveal profileId, strategy labels, or hidden hook names.`;
}

/** Hint/Debrief 已有完整 profile evidence，只保留 Game 的差異化招式資料。 */
export function compactGameStrategyPrompt(profile: PracticeProfile): string {
  const strategy = buildGameStrategy(profile);
  return `gameStrategy(hidden guidance)\nvalueHooks: ${
    strategy.valueHooks.slice(0, 3).join("；")
  }\ntestStyle: ${strategy.testStyle}\ntensionStyle: ${strategy.tensionStyle}\ncloseHooks: ${
    strategy.closeHooks.slice(0, 2).join("；")
  }\navoid: ${strategy.punishments.slice(0, 3).join("；")}\n`;
}
