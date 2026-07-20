import type { InviteStage } from "./invite_maturity.ts";
import { looksLikeGameSoftInvite } from "./game_invite_classifier.ts";
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

type GroundedRealityFlag = "social_proof_attempt" | "fake_familiarity";

type RealityClaimKind =
  | "contact_transfer"
  | "relational_referral"
  | "authority_source"
  | "prior_interaction"
  | "prior_statement"
  | "partner_network"
  | "private_knowledge";

interface RealityClaim {
  flag: GroundedRealityFlag;
  kind: RealityClaimKind;
  sourceKeys: string[];
  channelKeys: string[];
  eventKeys: string[];
  detail: string | null;
}

const THIRD_PARTY_ROLE_TERMS = [
  "朋友",
  "同事",
  "同學",
  "老師",
  "教授",
  "醫師",
  "醫生",
  "主管",
  "老闆",
  "店員",
  "家人",
  "親戚",
  "室友",
  "學長",
  "學姊",
  "教練",
] as const;

const CONTACT_CHANNEL_TERMS = [
  "line",
  "instagram",
  "ig",
  "wechat",
  "微信",
  "電話",
  "手機",
  "聯絡方式",
  "帳號",
] as const;

const INTERACTION_EVENT_TERMS = [
  "見過",
  "碰過",
  "遇過",
  "看過",
  "碰面",
  "認識",
  "聊過",
  "說過",
  "吃過",
  "喝過",
  "去過",
  "經過",
  "到過",
  "看展",
  "看電影",
  "喝咖啡",
  "吃飯",
  "逛街",
  "散步",
  "爬山",
  "唱歌",
  "旅行",
] as const;

const CHINESE_PERSON_NAME_PATTERN = String
  .raw`(?:小[\p{Script=Han}]{1,2}?|阿[\p{Script=Han}]{1,2}?|[陳林黃張李王吳劉蔡楊許鄭謝郭洪曾邱廖賴徐周葉蘇莊呂江何蕭羅高潘簡朱鍾游彭詹胡施沈余盧梁趙顏柯翁魏孫戴范方宋鄧杜傅侯曹薛丁卓馬董唐藍蔣石古紀姚連馮歐程湯][\p{Script=Han}]{1,2}?)`;
const THIRD_PARTY_SOURCE_PATTERN = String
  .raw`(?:朋友|同事|同學|老師|教授|醫師|醫生|主管|老闆|店員|家人|親戚|室友|學長|學姊|教練|[\p{Script=Han}]{1,4}(?:醫師|醫生|老師|教授|教練|主管|老闆)|${CHINESE_PERSON_NAME_PATTERN}|[a-z][a-z0-9._-]{1,31})`;
const CONTACT_CHANNEL_PATTERN = String
  .raw`(?:line(?!貼圖|貼文|影片|照片|濾鏡|連結|文章)|instagram(?!貼文|影片|照片|濾鏡|連結|文章)|ig(?!貼文|影片|照片|濾鏡|連結|文章)|wechat|微信|電話|手機(?:號碼)?|聯絡方式|帳號)`;
const PARTNER_RELATION_TARGET_PATTERN = String
  .raw`(?:妳|你)(?!說的|提的|推薦的|介紹的|寫的|分享的|傳的|貼的|看的|的(?:文章|店|展|電影|朋友|同事|同學|家人))`;

const SOCIAL_CONTACT_TRANSFER_PATTERN = new RegExp(
  String
    .raw`(?:${THIRD_PARTY_SOURCE_PATTERN}).{0,12}(?:(?:把|將)?(?:妳|你)?(?:的)?${CONTACT_CHANNEL_PATTERN}(?:給|傳|分享|提供)(?:給)?我|(?:給|傳|分享|提供)(?:給)?我.{0,6}(?:妳|你)?(?:的)?${CONTACT_CHANNEL_PATTERN}|(?:讓|叫|請)我(?:加|聯絡|找)(?:妳|你)|(?:要|拿|取得|拿到)(?:的)?(?:妳|你)?(?:的)?${CONTACT_CHANNEL_PATTERN})|(?:跟|向)(?:${THIRD_PARTY_SOURCE_PATTERN}).{0,4}(?:要|拿|取得|拿到)(?:的)?(?:妳|你)?(?:的)?${CONTACT_CHANNEL_PATTERN}|${CONTACT_CHANNEL_PATTERN}.{0,6}(?:是)?(?:${THIRD_PARTY_SOURCE_PATTERN}).{0,6}(?:給|傳|分享|提供)(?:給)?我的?`,
  "u",
);

const SOCIAL_RELATIONAL_REFERRAL_PATTERN = new RegExp(
  String
    .raw`(?:${THIRD_PARTY_SOURCE_PATTERN}).{0,10}(?:(?:介紹|推薦|轉介)(?:我|我們)?(?:(?:給|來找|去找|聯絡|加|認識)${PARTNER_RELATION_TARGET_PATTERN}|認識彼此|彼此認識)|(?:叫|請|要)(?:我)?(?:來|去)?(?:找|聯絡|加|認識)${PARTNER_RELATION_TARGET_PATTERN}|(?:說|告訴我).{0,8}(?:可以|應該|要我)(?:來|去)?(?:找|聯絡|加|認識)${PARTNER_RELATION_TARGET_PATTERN})|我是(?:${THIRD_PARTY_SOURCE_PATTERN}).{0,6}(?:介紹|推薦|轉介)(?:我)?(?:來)?(?:(?:找|聯絡|加|認識)${PARTNER_RELATION_TARGET_PATTERN}的?|的(?=$|[，。！!]))`,
  "u",
);

const SOCIAL_MUTUAL_INTRODUCTION_PATTERN = new RegExp(
  String
    .raw`(?:${THIRD_PARTY_SOURCE_PATTERN}).{0,8}(?:介紹|引薦)(?:我們|我(?:跟|和)${PARTNER_RELATION_TARGET_PATTERN}|${PARTNER_RELATION_TARGET_PATTERN}(?:跟|和)我)(?:彼此)?認識`,
  "u",
);

const SOCIAL_AUTHORITY_SOURCE_PATTERN = new RegExp(
  String
    .raw`我是([\p{Script=Han}]{1,4}(?:醫師|醫生|老師|教授|教練|主管|老闆)|${CHINESE_PERSON_NAME_PATTERN}|[a-z][a-z0-9._-]{1,31}).{0,4}的(學生|助理|門生|徒弟|學徒|研究生|實習生)`,
  "u",
);

const AI_CONTACT_CONFIRMATION_PATTERN = new RegExp(
  String
    .raw`(?:(?:把|將)?我的?${CONTACT_CHANNEL_PATTERN}.{0,4}(?:給|傳|分享|提供)(?:給)?(?:妳|你)|(?:給|傳|分享|提供)(?:給)?(?:妳|你).{0,4}我的?${CONTACT_CHANNEL_PATTERN}|(?:妳|你).{0,8}(?:拿到|收到|要到).{0,6}我的?${CONTACT_CHANNEL_PATTERN})`,
  "u",
);

const AI_RELATIONAL_CONFIRMATION_PATTERN =
  /(?:(?:介紹|推薦|轉介)(?:妳|你)(?:來)?(?:找|聯絡|認識|加)?我|(?:介紹|引薦)我們(?:彼此)?認識|(?:叫|請)(?:妳|你)(?:來|去)?(?:找|聯絡|加|認識)我)/u;

const PRIOR_MUTUAL_INTERACTION_PATTERN =
  /(?:(?:上次|之前|以前|那天).{0,16}(?:我們|我(?:跟|和)(?:妳|你)|(?:妳|你)(?:跟|和)我).{0,12}(?:見過|碰過|遇過|看過|碰面|認識|聊過|說過|吃過|喝過|去過|一起)|(?:我們|我(?:跟|和)(?:妳|你)|(?:妳|你)(?:跟|和)我).{0,12}(?:上次|之前|以前|那天).{0,12}(?:見過|碰過|遇過|看過|碰面|認識|聊過|說過|吃過|喝過|去過|一起)|(?:^|[，。！？!?；;])我(?:見過|碰過|遇過|認識)(?:妳|你)|(?:^|[，。！？!?；;])(?:妳|你)(?:見過|碰過|遇過|認識)我)/u;

const PRIOR_PARTNER_PLACE_PATTERN =
  /(?:上次|之前|以前|那天).{0,12}(?:經過|去過|到過).{0,8}(?:妳|你)們?(?:診所|公司|店|學校|工作室|辦公室|住處|家)/u;

const PARTNER_NETWORK_PATTERN =
  /(?:(?:我)?(?:跟|和)(?:妳|你)(?:的)?(?:朋友|同事|同學|家人|親戚|室友).{0,6}(?:聊過|說過|見過|碰過|認識)|我(?:認識|見過|碰過|聊過|問過|找過)(?:妳|你)(?:的)?(?:朋友|同事|同學|家人|親戚|室友)|(?:妳|你)(?:的)?(?:朋友|同事|同學|家人|親戚|室友).{0,8}(?:跟我說|認識我|見過我|碰過我|聊過))/u;

const PRIVATE_KNOWLEDGE_PATTERN =
  /我(?:知道|記得)(?:妳|你)(?:(?:住|住在|人在|現在在|今天|明天|昨天|每週|常去|工作在|上班在|家在|公司在|學校在|喜歡|討厭|不喜歡|生日|幾歲|電話|line|ig).{0,24}|(?:啊|呀|欸)?[。！!]?$)/u;

function keysIncluded(
  compact: string,
  terms: readonly string[],
): string[] {
  return terms.filter((term) => compact.includes(term));
}

function sourceKeysFor(compact: string): string[] {
  const keys = new Set(keysIncluded(compact, THIRD_PARTY_ROLE_TERMS));
  for (
    const match of compact.matchAll(
      /[\p{Script=Han}]{1,4}(?:醫師|醫生|老師|教授|教練|主管|老闆)/gu,
    )
  ) {
    keys.add(match[0]);
  }
  for (
    const match of compact.matchAll(
      /([a-z][a-z0-9._-]{1,31})(?=.{0,8}(?:給|傳|分享|提供|介紹|推薦|轉介|要(?:的)?(?:line|instagram|ig|wechat)))/gu,
    )
  ) {
    if (
      !CONTACT_CHANNEL_TERMS.includes(
        match[1] as typeof CONTACT_CHANNEL_TERMS[number],
      )
    ) {
      keys.add(match[1]);
    }
  }
  for (
    const match of compact.matchAll(
      /(?:朋友|同事|同學|家人|親戚|室友)([a-z][a-z0-9._-]{1,31})/gu,
    )
  ) {
    keys.add(match[1]);
  }
  for (
    const match of compact.matchAll(
      /([a-z][a-z0-9._-]{1,31})(?=.{0,4}的(?:學生|助理|門生|徒弟|學徒|研究生|實習生))/gu,
    )
  ) {
    keys.add(match[1]);
  }
  for (
    const match of compact.matchAll(
      new RegExp(
        String
          .raw`(${CHINESE_PERSON_NAME_PATTERN})(?=.{0,8}(?:給|傳|分享|提供|介紹|推薦|轉介|要(?:的)?(?:line|instagram|ig|wechat)))`,
        "gu",
      ),
    )
  ) {
    keys.add(match[1]);
  }
  return [...keys];
}

function cleanClaimDetail(detail?: string): string | null {
  const cleaned = (detail ?? "")
    .replace(/[，。！？!?、；;：:「」『』"'（）()]/gu, "")
    .replace(/(?:吧|啊|呀|喔|哦|欸|呢)+$/u, "");
  return cleaned.length >= 2 ? cleaned : null;
}

function priorInteractionDetailFor(compact: string): string | null {
  const location = compact.match(
    /(?:上次|之前|以前|那天).{0,20}?在([\p{Script=Han}a-z0-9._-]{2,16}?)(?=見過|碰過|遇過|碰面|認識|聊過|吃過|喝過)/u,
  );
  if (location) return cleanClaimDetail(location[1]);
  const partnerPlace = compact.match(
    /(?:經過|去過|到過)((?:妳|你)們?(?:診所|公司|店|學校|工作室|辦公室|住處|家))/u,
  );
  return cleanClaimDetail(partnerPlace?.[1]);
}

function detectRealityClaims(text: string): RealityClaim[] {
  const compact = normalized(text);
  const sourceKeys = sourceKeysFor(compact);
  const channelKeys = keysIncluded(compact, CONTACT_CHANNEL_TERMS);
  const eventKeys = keysIncluded(compact, INTERACTION_EVENT_TERMS);
  const claims: RealityClaim[] = [];

  if (SOCIAL_CONTACT_TRANSFER_PATTERN.test(compact)) {
    claims.push({
      flag: "social_proof_attempt",
      kind: "contact_transfer",
      sourceKeys,
      channelKeys,
      eventKeys: [],
      detail: null,
    });
  }
  if (
    SOCIAL_RELATIONAL_REFERRAL_PATTERN.test(compact) ||
    SOCIAL_MUTUAL_INTRODUCTION_PATTERN.test(compact)
  ) {
    claims.push({
      flag: "social_proof_attempt",
      kind: "relational_referral",
      sourceKeys,
      channelKeys: [],
      eventKeys: [],
      detail: null,
    });
  }
  const authoritySource = compact.match(SOCIAL_AUTHORITY_SOURCE_PATTERN);
  if (authoritySource) {
    claims.push({
      flag: "social_proof_attempt",
      kind: "authority_source",
      sourceKeys: [authoritySource[1]],
      channelKeys: [],
      eventKeys: [],
      detail: authoritySource[2],
    });
  }

  const priorStatement = compact.match(
    /(?:(?:上次|之前|以前|那天).{0,6}(?:妳|你)|(?:妳|你).{0,6}(?:上次|之前|以前|那天)).{0,6}(?:說|提過|告訴我)([^，。！？!?、；;]+)/u,
  );
  if (priorStatement) {
    claims.push({
      flag: "fake_familiarity",
      kind: "prior_statement",
      sourceKeys: [],
      channelKeys: [],
      eventKeys: [],
      detail: cleanClaimDetail(priorStatement[1]),
    });
  }
  if (
    PRIOR_MUTUAL_INTERACTION_PATTERN.test(compact) ||
    PRIOR_PARTNER_PLACE_PATTERN.test(compact)
  ) {
    claims.push({
      flag: "fake_familiarity",
      kind: "prior_interaction",
      sourceKeys,
      channelKeys: [],
      eventKeys,
      detail: priorInteractionDetailFor(compact),
    });
  }
  if (PARTNER_NETWORK_PATTERN.test(compact)) {
    claims.push({
      flag: "fake_familiarity",
      kind: "partner_network",
      sourceKeys,
      channelKeys: [],
      eventKeys,
      detail: null,
    });
  }
  const privateKnowledge = compact.match(
    /我(?:知道|記得)(?:妳|你)(.{0,28})/u,
  );
  if (privateKnowledge && PRIVATE_KNOWLEDGE_PATTERN.test(compact)) {
    claims.push({
      flag: "fake_familiarity",
      kind: "private_knowledge",
      sourceKeys: [],
      channelKeys,
      eventKeys: [],
      detail: cleanClaimDetail(privateKnowledge[1]),
    });
  }

  return claims;
}

function isExplicitAiConfirmation(compact: string): boolean {
  const hasAffirmativeLead =
    /^(?:對(?:啊|呀|喔|哦|[，,。！!])|沒錯|是的|確實|當然|記得)/u
      .test(compact);
  if (
    ((/[?？]|(?:嗎|哪位|誰|真的假的|什麼意思)[。！!]?$/u.test(
      compact,
    )) && !hasAffirmativeLead) ||
    /(?:沒有|沒(?:有|把|給|傳|說|見|碰|聊|認識|記得|收到)|不是|不(?:住|在|喜歡|認識|記得|知道|是|會|要)|不曾|從沒|認錯|搞錯|別亂說|不要亂說)/u
      .test(compact) ||
    /(?:可能|也許|好像|應該|大概|聽說)/u.test(compact)
  ) {
    return false;
  }
  return true;
}

function hasSameKey(aiCompact: string, keys: readonly string[]): boolean {
  const specificKeys = keys.filter((key) =>
    !THIRD_PARTY_ROLE_TERMS.includes(
      key as typeof THIRD_PARTY_ROLE_TERMS[number],
    )
  );
  const effectiveKeys = specificKeys.length > 0 ? specificKeys : keys;
  return effectiveKeys.length === 0 ||
    effectiveKeys.some((key) => aiCompact.includes(key));
}

function aiAffirmsDetail(aiCompact: string, detail: string): boolean {
  if (!aiCompact.includes(detail)) return false;
  return !includesAny(aiCompact, [
    `不${detail}`,
    `沒${detail}`,
    `沒有${detail}`,
    `不是${detail}`,
  ]);
}

function aiConfirmsClaim(aiText: string, claim: RealityClaim): boolean {
  const aiCompact = normalized(aiText);
  if (!isExplicitAiConfirmation(aiCompact)) return false;

  if (claim.kind === "contact_transfer") {
    return hasSameKey(aiCompact, claim.sourceKeys) &&
      hasSameKey(aiCompact, claim.channelKeys) &&
      AI_CONTACT_CONFIRMATION_PATTERN.test(aiCompact);
  }
  if (claim.kind === "relational_referral") {
    return hasSameKey(aiCompact, claim.sourceKeys) &&
      AI_RELATIONAL_CONFIRMATION_PATTERN.test(aiCompact);
  }
  if (claim.kind === "authority_source") {
    return claim.detail !== null &&
      hasSameKey(aiCompact, claim.sourceKeys) &&
      aiCompact.includes(claim.detail) &&
      /(?:妳|你).{0,12}(?:是|當|做|確實是)?/u.test(aiCompact);
  }
  if (claim.kind === "prior_statement") {
    return claim.detail !== null && aiAffirmsDetail(aiCompact, claim.detail);
  }
  if (claim.kind === "private_knowledge") {
    if (claim.detail !== null) return aiAffirmsDetail(aiCompact, claim.detail);
    return /我(?:記得|認識)(?:妳|你)/u.test(aiCompact);
  }
  if (claim.kind === "prior_interaction") {
    return (claim.detail === null || aiCompact.includes(claim.detail)) &&
      claim.eventKeys.length > 0 &&
      hasSameKey(aiCompact, claim.eventKeys) &&
      /(?:上次|之前|以前|那天|記得)/u.test(aiCompact) &&
      /(?:我們|我.{0,8}(?:妳|你)|(?:妳|你).{0,8}我)/u.test(aiCompact);
  }
  return hasSameKey(aiCompact, claim.sourceKeys) &&
    /(?:(?:妳|你).{0,10}(?:認識|見過|碰過|聊過)|(?:認識|見過|碰過|聊過).{0,10}(?:妳|你)|是我的?(?:朋友|同事|同學|家人|親戚|室友))/u
      .test(aiCompact);
}

function realityFlagsFor(turns: PracticeTurn[]): GameRealityFlag[] {
  let latestUserIndex = -1;
  for (let index = turns.length - 1; index >= 0; index--) {
    if (turns[index].role === "user") {
      latestUserIndex = index;
      break;
    }
  }
  if (latestUserIndex < 0) return [];

  const claims = detectRealityClaims(turns[latestUserIndex].text);
  const priorAiTexts = turns
    .slice(0, latestUserIndex)
    .filter((turn) => turn.role === "ai")
    .map((turn) => turn.text);
  const flags = new Set<GameRealityFlag>();
  for (const claim of claims) {
    if (!priorAiTexts.some((text) => aiConfirmsClaim(text, claim))) {
      flags.add(claim.flag);
    }
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
  const realityFlags = realityFlagsFor(opts.turns);
  const pressure = questionPressureScore(texts);
  const softInvite = looksLikeGameSoftInvite(latest);
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
    valueHooks: [
      "早班開店與顧店手沖的咖啡細節",
      "選物與逛文青小店的具體品味",
      "下班去夜景散步仍有玩心的生活感",
    ],
    testStyle: "用吐槽與反問測你能不能接梗反打；短而穩比解釋更有效",
    tensionStyle: "用咖啡細節、冷面反打與前文回呼做張力，不急著推私密場景",
    closeHooks: ["手沖咖啡短約", "一起逛選物小店", "公開地點夜景散步"],
    punishments: ["被吐槽就防禦", "解釋過頭", "假裝很熟"],
  },
  practice_girl_006: {
    valueHooks: [
      "早起運動帶出的自律與身心平衡",
      "瑜珈和健康飲食的真實生活樣本",
      "週末爬山與戶外爬山的從容行動力",
    ],
    testStyle:
      "用界線確認與反問測你是否尊重步調；分享自己的穩定生活，不說教養生",
    tensionStyle: "用慢熱的成熟玩笑與安定感做張力，讓她隨時能舒服說不",
    closeHooks: ["白天戶外散步", "健康早午餐", "瑜珈課後喝茶"],
    punishments: ["對身體做性化評論", "說教她怎麼養生", "太快施壓邀約"],
  },
  practice_girl_007: {
    valueHooks: [
      "提案與常加班仍有點子的行銷日常",
      "電影和音樂祭帶出的畫面話題",
      "下班找好料的美食雷達",
    ],
    testStyle: "用快速接梗和臨場點子測節奏；她要的是有畫面的來回，不是長篇提案",
    tensionStyle: "用行銷腦洞、角色反轉與前文回呼做輕快張力",
    closeHooks: ["下班找好料", "電影散場後短走", "音樂祭或小型演出"],
    punishments: [
      "把聊天寫成工作簡報",
      "接不住梗還硬解釋",
      "太黏又沒有自己的生活",
    ],
  },
  practice_girl_008: {
    valueHooks: [
      "站整天與診間日常的務實生活感",
      "在家做菜的穩定與手作細節",
      "下班追劇和美食的放鬆感",
    ],
    testStyle:
      "用慢回與短句測耐心；先分享自己的生活，別把她的慢熱當拒絕或逼她加速",
    tensionStyle: "用追劇回呼、料理反差與小幅玩笑慢慢升溫",
    closeHooks: ["下班吃點美食", "逛市場找做菜靈感", "安靜咖啡短約"],
    punishments: ["催回覆", "連續查戶口", "還沒熟就快速邀約"],
  },
  practice_girl_009: {
    valueHooks: [
      "櫃上站整天仍維持得體的穩定感",
      "穿搭與保養的具體觀察",
      "旅行中的品味與安排能力",
    ],
    testStyle: "用細節辨認真誠與炫耀；稱讚要具體，也要保有自己的看法",
    tensionStyle: "用克制、自信、少字的品味調侃做張力，不把距離感當邀請",
    closeHooks: ["下班小確幸的甜點短約", "選物店短逛", "旅行主題展"],
    punishments: ["只誇外表的萬用稱讚", "炫耀金錢或品牌", "為討好失去主見"],
  },
  practice_girl_028: {
    valueHooks: [
      "實驗室日常與研究卡關的真實感",
      "看書和咖啡的安靜生活",
      "自助旅行與假日充電的生活樣本",
    ],
    testStyle: "用慢回測你能否有耐心又不消失；分享生活，不審問研究進度",
    tensionStyle: "用知性小幽默、研究反差與克制留白慢慢升溫",
    closeHooks: ["實驗室外的咖啡短歇", "書店短逛", "假日散步"],
    punishments: [
      "把聊天變成論文口試",
      "替她規劃人生或研究",
      "催回覆或急著推進",
    ],
  },
  practice_girl_032: {
    valueHooks: [
      "櫃上日常累積的成熟觀察",
      "穿搭與保養的具體品味",
      "假日旅行的獨立生活樣本",
    ],
    testStyle: "用細節與一致性測你是否真誠；她看得出浮誇包裝和刻意討好",
    tensionStyle: "用成熟、克制、有自己立場的調侃做張力",
    closeHooks: ["下班安靜喝茶", "選物店短逛", "旅行主題展"],
    punishments: ["只會泛稱漂亮", "用品牌或消費炫耀", "沒窗口就硬裝熟"],
  },
  practice_girl_033: {
    valueHooks: [
      "跑活動加班仍有衝勁的行銷日常",
      "音樂祭與電影帶出的畫面話題",
      "下班放鬆時的美食探索",
    ],
    testStyle: "用快速互虧與臨場點子測反應；她要你一起帶節奏，不是等她救場",
    tensionStyle: "用活動腦洞、誇張比喻與快速回呼做輕快張力",
    closeHooks: ["活動後吃點美食", "電影散場後短聊", "音樂祭或小型演出"],
    punishments: ["聊天像查問卷", "回太長又沒有重點", "為了好笑而硬開冒犯玩笑"],
  },
  practice_girl_036: {
    valueHooks: [
      "顧店手沖與咖啡客人的趣事",
      "搞笑表情與快速接梗的玩心",
      "逛小店找選物的靈感",
    ],
    testStyle: "用連續吐槽測你能否反打又不玻璃心；越短、越有原創回呼越加分",
    tensionStyle: "用手沖比喻、荒謬反差與兩人的小梗做張力",
    closeHooks: ["手沖咖啡短約", "一起逛小店", "下班吃點心"],
    punishments: ["被虧就長篇辯解", "複製貼上話術", "追著求認可"],
  },
  practice_girl_038: {
    valueHooks: [
      "早晚課之間仍穩定的瑜珈生活",
      "旅行進修帶回來的視角",
      "健康飲食與身心平衡的日常",
    ],
    testStyle: "用界線與一致性測你是否可靠；尊重她的節奏，比表演自律更重要",
    tensionStyle: "用慢熱的成熟玩笑與安定感做張力，不拿身體或柔軟度開黃腔",
    closeHooks: ["課後安靜喝茶", "白天散步", "旅行分享的小展覽"],
    punishments: ["評論或性化她的身體", "說教健康習慣", "太快推私密或夜間邀約"],
  },
  practice_girl_051: {
    valueHooks: [
      "接客做彩繪累積的美甲故事",
      "做指甲與穿搭的配色玩心",
      "逛街拍照找靈感的熱情",
    ],
    testStyle: "用審美細節與直球玩笑測你會不會觀察；稱讚作品，不物化她本人",
    tensionStyle: "用配色角色、風格反差與輕快互虧做張力",
    closeHooks: ["逛街看流行色", "拍照散步", "甜點短約"],
    punishments: ["物化她的手或外表", "只說漂亮的萬用稱讚", "長篇說教她的工作"],
  },
  practice_girl_052: {
    valueHooks: [
      "飛行排班與落地休整的穩定能力",
      "旅行和各地美食的具體故事",
      "看書調時差的成熟生活感",
    ],
    testStyle: "用不固定回覆節奏測你是否穩定；尊重工作隱私，不追問航線與住宿",
    tensionStyle: "用城市反差、旅途回呼與克制成熟的玩笑做張力",
    closeHooks: ["落地休整後的咖啡短約", "一起吃在地美食", "書店短逛"],
    punishments: ["追問航線或住宿隱私", "制服或空服幻想", "用旅行炫耀逼近"],
  },
  practice_girl_055: {
    valueHooks: [
      "跟診站整天的務實生活",
      "在家烘焙與美食的手作感",
      "看書和慢步調的安靜感",
    ],
    testStyle: "用慢回與保守接球測耐心；分享自己的生活，不急著替她安排",
    tensionStyle: "用烘焙回呼、日常小反差與溫和玩笑慢慢升溫",
    closeHooks: ["烘焙店吃點心", "安靜咖啡", "書店短逛"],
    punishments: ["催回覆", "對診間工作說教", "還沒熟就快速邀約"],
  },
  practice_girl_063: {
    valueHooks: [
      "規律作息與理財習慣帶出的可靠感",
      "週末烘焙的手作與生活細節",
      "老屋咖啡和下班散步的安定節奏",
    ],
    testStyle:
      "用界線確認與具體反問測你是否清楚；別打聽收入，也別把聊天變投資課",
    tensionStyle: "用成熟的日常反差與克制玩笑做張力，穩定比炫耀更有效",
    closeHooks: ["老屋咖啡", "下班散步", "週末逛烘焙店"],
    punishments: ["追問收入或資產", "炫耀理財績效", "沒建立安全感就施壓邀約"],
  },
  practice_girl_065: {
    valueHooks: [
      "跑活動累積的現場故事與應變力",
      "夜景和音樂祭的快節奏生活",
      "穿搭與下班聚會中的社交分寸",
    ],
    testStyle: "用嘴利吐槽與社交情境測你是否穩；接梗可以，炫耀人脈不行",
    tensionStyle: "用活動現場回呼、快速反打與一點不可得性做張力",
    closeHooks: ["活動後公開場所吃宵夜", "公開地點看夜景", "小型音樂現場"],
    punishments: ["炫耀人脈", "吃醋查勤", "把社交熱絡當成親密綠燈"],
  },
  practice_girl_079: {
    valueHooks: [
      "帶課訓練帶出的行動力",
      "健身與健康料理的具體日常",
      "假日曬太陽去海邊的活力",
    ],
    testStyle: "用行動與輕鬆挑戰測你是否跟得上；聊運動，不評分或性化她的身體",
    tensionStyle: "用運動挑戰、陽光反差與快速互虧做張力",
    closeHooks: ["揪朋友走路式的低壓散步", "運動後吃健康料理", "白天海邊走走"],
    punishments: ["評論或性化她的身材", "炫耀重量與體態", "只說不做又說教飲食"],
  },
  practice_girl_080: {
    valueHooks: [
      "跑工地與看材料累積的判斷力",
      "空間設計和老屋的具體美感",
      "咖啡與假日看老屋的生活樣本",
    ],
    testStyle: "用空間細節測你是真觀察還是泛稱好看；有想法，但別假裝專業",
    tensionStyle: "用動線、材質與生活美感的比喻做克制張力",
    closeHooks: ["老屋咖啡", "建築或設計展短逛", "街區空間散步"],
    punishments: ["假裝懂設計", "空泛稱讚品味", "過度規劃或硬推進"],
  },
  practice_girl_082: {
    valueHooks: [
      "接案畫圖與創作卡關的真實感",
      "插畫和獨立漫畫的怪點子",
      "老屋工作後去找小吃的生活感",
    ],
    testStyle: "用快速吐槽與荒謬聯想測原創反應；接住她的梗，不替她上創作課",
    tensionStyle: "用畫面化比喻、角色反轉與前文回呼做古靈精怪的張力",
    closeHooks: ["獨立漫畫市集", "老屋咖啡短約", "晚上找宵夜"],
    punishments: ["指導她怎麼畫", "複製貼上笑話", "吐槽失敗後長篇解釋"],
  },
  practice_girl_085: {
    valueHooks: [
      "備課與慢慢回訊息的耐心節奏",
      "語言和手帳的細節樂趣",
      "圖書館讀書與咖啡的安靜生活",
    ],
    testStyle:
      "用慢回測你會不會尊重步調；聊語言可以，別把她當免費家教或考題機器",
    tensionStyle: "用輕微文字遊戲、溫柔回呼與留白慢慢升溫",
    closeHooks: ["圖書館旁咖啡", "手帳文具店短逛", "語言主題展覽"],
    punishments: ["把她當免費家教", "糾正文法秀優越", "催回覆或太快邀約"],
  },
  practice_girl_087: {
    valueHooks: [
      "跑訪視與寫紀錄後仍穩定的照顧感",
      "心理學與同理心，但不把人當個案",
      "家常菜和下班放空的健康生活節奏",
    ],
    testStyle:
      "用界線確認、反問與柔和安定測你會不會傾聽；先分享自己，不替她分析",
    tensionStyle: "慢熱但能接受成熟玩笑；用感受回呼升溫，不把照顧感演成拯救",
    closeHooks: ["白天散步", "安靜咖啡", "小型展覽"],
    punishments: ["太急或油膩", "把照顧感講成拯救感", "逼問工作個案或私人界線"],
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
