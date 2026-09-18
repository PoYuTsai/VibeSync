// 開場救星兩段式：本次原料（用戶的選項、補充原文）的資料整理與確定性檢核
//（附件 §6、§10.5、§10.7）。
//
// 原則：每件原料都知道「誰說的、在講誰、確定到什麼程度、可以怎麼用」。
// 選主題不等於有經驗；妹妹的工作不是用戶的工作；用戶想邀約不等於對方答應。
// 這裡只做程式能確定的事：來源 ID／引文對得上、沒有來源的第一人稱事實、
// 明確被排除的話題、被否定的經歷又被寫成肯定。語意品質靠成對盲審。

import { isPlainObject } from "../_shared/quota.ts";
import { FIRST_PERSON_FACT_RE, OPENER_TYPES, type OpenerType } from "./opener_payload.ts";
import type {
  OpenerAnalysisSnapshot,
  OpenerContribution,
  OpenerQuestionOption,
} from "./opener_stage.ts";

export type OpenerMaterialOrigin = "option" | "user_text";
export type OpenerMaterialSubject = "sender" | "sender_family" | "recipient" | "shared_scene" | "unknown";
export type OpenerMaterialKind = "interest" | "fact" | "guess" | "goal" | "restriction" | "raw_sentence";
export type OpenerMaterialCertainty = "stated" | "prior_interaction" | "hearsay" | "guess";
export type OpenerMaterialAllowedUse = "topic" | "sender_fact" | "question" | "exclude";

export interface OpenerMaterial {
  id: string;
  origin: OpenerMaterialOrigin;
  subject: OpenerMaterialSubject;
  kind: OpenerMaterialKind;
  originalText: string;
  certainty: OpenerMaterialCertainty;
  cueId?: string;
  allowedUse: OpenerMaterialAllowedUse[];
  restrictions: string[];
}

export type OpenerInputState = "answered" | "skipped" | "no_answer" | "no_preference";

export interface OpenerMaterialSet {
  inputState: OpenerInputState;
  materials: OpenerMaterial[];
  /** 明確被排除的話題字眼（線索標籤或補充裡「不想聊 X」的 X）。 */
  excludedTopics: string[];
  /** 用戶明說「沒／不曾」的經歷片段（動詞＋受詞），輸出寫成肯定就是反轉否定。 */
  negatedFacts: string[];
  /** 用戶選「沒有經驗，只是有興趣」的線索標籤：句子裡「我＋這個線索」就是捏造。 */
  noExperienceTopics: string[];
  /** 有沒有取得可用的個人原料（「不知道／都可以」不算）。 */
  hasEffectiveMaterial: boolean;
  /** 第一人稱事實有沒有合法來源（assert_sender_fact 或用戶原文）。 */
  senderFactAllowed: boolean;
  /** 用戶選「其實想聊別的」→ 第一段方向被覆蓋成另開話題。 */
  directionOverride: "fresh_topic" | null;
}

const NO_PREFERENCE_RE = /^(不知道|不清楚|都可以|都行|都好|隨便|沒想法|沒有想法|還沒想好|沒差|沒有特別想聊的|沒特別想法|你決定|看你)[。！!～~\s]*$/u;

// 「不想聊她的工作」「先不要提我工作」「別問住哪」→ 排除字眼。
const EXCLUSION_RE =
  /(不想|不要|別|先不要|先不|不用|不需要)(聊|提|講|談|問|說|寫)(到|起)?(她的|他的|對方的|我的|我|她|他)?([^\s，,。！!？?；;、（）()]{1,10})/gu;

// 「沒養狗」「沒去過」「不曾爬過」「以前養過現在沒有」→ 被否定的經歷片段。
const NEGATED_FACT_RE =
  /(沒有|沒|不曾|未|從來沒|從沒|還沒)(養|去過|去|做過|玩過|學過|有|會|爬過|試過|吃過|看過|住過|養過|接觸過|碰過)([^\s，,。！!？?；;、只但而]{0,4})/gu;

export function isNoPreferenceText(text: string): boolean {
  return NO_PREFERENCE_RE.test(text.trim());
}

export function extractExcludedTopics(text: string): string[] {
  const out: string[] = [];
  for (const match of text.matchAll(EXCLUSION_RE)) {
    const topic = match[5]?.replace(/(了|吧|喔|啦|囉)$/u, "").trim();
    if (topic && topic.length >= 1 && !out.includes(topic)) out.push(topic);
  }
  return out;
}

export function extractNegatedFacts(text: string): string[] {
  const out: string[] = [];
  for (const match of text.matchAll(NEGATED_FACT_RE)) {
    const verb = match[2].replace(/過$/u, "");
    const object = match[3]?.trim() ?? "";
    // 「還有沒有推薦」「會不會」「去沒去過」是正反問句，不是被否定的經歷（第五輪 P066）。
    const before = text.slice(Math.max(0, (match.index ?? 0) - verb.length), match.index ?? 0);
    if (before === verb) continue;
    // 「沒有興趣」「沒有特別」不是經歷；沒有受詞的「沒有」也不算。
    if (!object || /^(興趣|特別|想|辦法|關係|差)/u.test(object)) continue;
    const fact = `${verb}${object}`;
    if (!out.includes(fact)) out.push(fact);
  }
  return out;
}

function optionMaterial(option: OpenerQuestionOption, snapshot: OpenerAnalysisSnapshot, id: string): OpenerMaterial | null {
  const cueLabel = option.cueId ? snapshot.cues.find((cue) => cue.id === option.cueId)?.label : undefined;
  switch (option.meaning) {
    case "pick_cue":
      return {
        id,
        origin: "option",
        subject: "sender",
        kind: "interest",
        originalText: cueLabel ? `想聊：${cueLabel}` : option.label,
        certainty: "stated",
        cueId: option.cueId,
        allowedUse: ["topic", "question"],
        restrictions: ["選主題不等於有相關經驗；不得寫成用戶自己有做過、有養、常去"],
      };
    case "assert_sender_fact":
      return {
        id,
        origin: "option",
        subject: "sender",
        kind: "fact",
        originalText: option.statement ?? option.label,
        certainty: "stated",
        cueId: option.cueId,
        allowedUse: ["topic", "sender_fact", "question"],
        restrictions: ["只能用這句原文的事實；不得補品種、年數、頻率、地點或其他細節"],
      };
    case "curious_without_experience":
      return {
        id,
        origin: "option",
        subject: "sender",
        kind: "interest",
        originalText: cueLabel ? `對「${cueLabel}」有興趣，但沒有相關經驗` : `${option.label}（沒有相關經驗）`,
        certainty: "stated",
        cueId: option.cueId,
        allowedUse: ["topic", "question"],
        restrictions: ["用戶沒有相關經驗：不得出現「我也」「我家」「養過的人都懂」這類共同經驗"],
      };
    case "exclude_cue":
      return {
        id,
        origin: "option",
        subject: "sender",
        kind: "restriction",
        originalText: cueLabel ? `不想聊：${cueLabel}` : option.label,
        certainty: "stated",
        cueId: option.cueId,
        allowedUse: ["exclude"],
        restrictions: ["所有候選句都不得提到這個話題"],
      };
    case "change_direction":
      return {
        id,
        origin: "option",
        subject: "sender",
        kind: "restriction",
        originalText: "這些線索都沒興趣，想聊別的",
        certainty: "stated",
        allowedUse: ["exclude"],
        restrictions: ["不得再用第一段列出的線索當主題；改走低壓新話題或用戶自己補充的方向"],
      };
    case "no_preference":
      return null;
  }
}

export function buildOpenerMaterials(input: {
  snapshot: OpenerAnalysisSnapshot;
  contribution: OpenerContribution;
  option: OpenerQuestionOption | null;
}): OpenerMaterialSet {
  const { snapshot, contribution, option } = input;
  const materials: OpenerMaterial[] = [];
  const excludedTopics: string[] = [];
  const noExperienceTopics: string[] = [];
  let negatedFacts: string[] = [];
  let senderFactAllowed = false;
  let directionOverride: "fresh_topic" | null = null;
  let noPreference = false;

  if (option) {
    const material = optionMaterial(option, snapshot, `material_${materials.length + 1}`);
    if (material) {
      materials.push(material);
      if (material.allowedUse.includes("sender_fact")) senderFactAllowed = true;
      if (option.meaning === "exclude_cue" && material.cueId) {
        const label = snapshot.cues.find((cue) => cue.id === material.cueId)?.label;
        if (label) excludedTopics.push(label);
      }
      if (option.meaning === "curious_without_experience" && material.cueId) {
        const label = snapshot.cues.find((cue) => cue.id === material.cueId)?.label;
        if (label) noExperienceTopics.push(label);
      }
      if (option.meaning === "change_direction") {
        directionOverride = "fresh_topic";
        for (const cue of snapshot.cues) excludedTopics.push(cue.label);
      }
    } else {
      noPreference = true;
    }
  }

  const freeText = contribution.freeText;
  if (freeText) {
    if (isNoPreferenceText(freeText)) {
      noPreference = true;
    } else {
      // 用戶原文＝一件完整原料：保留主體、否定、時間、程度，由生成模型在
      // materialReading 裡標主體與確定度（引文必須逐字出自這裡）。
      materials.push({
        id: `material_${materials.length + 1}`,
        origin: "user_text",
        subject: "unknown",
        kind: "raw_sentence",
        originalText: freeText,
        certainty: "stated",
        allowedUse: ["topic", "sender_fact", "question", "exclude"],
        restrictions: [
          "保留原句的主體（我／我妹／朋友／她）、否定、時間與程度，不得擴寫成沒說過的經歷",
          "她曾說過的事只能當有來源的先前互動；用戶猜的只能當待確認方向",
          "用戶的目標（想約、想問）不得寫成她的意願",
        ],
      });
      senderFactAllowed = true;
      for (const topic of extractExcludedTopics(freeText)) {
        if (!excludedTopics.includes(topic)) excludedTopics.push(topic);
      }
      // 「不聊工作」＝也不拿她自介裡的職業當開場（第五輪 P003／P140／P107）：
      // 由本局線索標籤（職業樣式）延伸，不是按情境加例外。
      for (const topic of [...excludedTopics]) {
        if (!WORK_TOPIC_RE.test(topic)) continue;
        for (const cue of snapshot.cues) {
          const profession = professionFromCueLabel(cue.label);
          if (profession && !excludedTopics.includes(profession)) excludedTopics.push(profession);
        }
      }
      negatedFacts = extractNegatedFacts(freeText);
    }
  }

  const hasEffectiveMaterial = materials.length > 0;
  const inputState: OpenerInputState = contribution.state !== "answered"
    ? contribution.state
    : hasEffectiveMaterial
    ? "answered"
    : "no_preference";
  void noPreference;
  return {
    inputState,
    materials,
    excludedTopics,
    negatedFacts,
    noExperienceTopics,
    hasEffectiveMaterial,
    senderFactAllowed,
    directionOverride,
  };
}

// ── 生成輸出的確定性檢核 ──────────────────────────────────────────────────

export interface OpenerMaterialReference {
  style: OpenerType;
  materialId: string;
  outputSpan: string;
}

export interface OpenerMaterialReadingItem {
  materialId: string;
  subject: OpenerMaterialSubject;
  kind: OpenerMaterialKind;
  certainty: OpenerMaterialCertainty;
  quote: string;
}

export interface OpenerQualityFlag {
  code:
    | "fabricated_sender_fact"
    | "negation_reversed"
    | "excluded_topic_used"
    | "sender_fact_transposed"
    | "sender_fact_extended"
    | "relative_quote_fabricated"
    | "certainty_upgraded"
    | "profile_fact_reversed"
    | "material_unused"
    | "reference_invalid"
    | "reading_quote_mismatch";
  severity: "hard" | "soft";
  style?: string;
  materialId?: string;
  detail?: string;
}

const SUBJECTS: readonly OpenerMaterialSubject[] = ["sender", "sender_family", "recipient", "shared_scene", "unknown"];
const KINDS: readonly OpenerMaterialKind[] = ["interest", "fact", "guess", "goal", "restriction", "raw_sentence"];
const CERTAINTIES: readonly OpenerMaterialCertainty[] = ["stated", "prior_interaction", "hearsay", "guess"];

/** 模型對用戶原文的主體／確定度標記：引文對不上原文就丟（soft flag）。 */
export function sanitizeMaterialReading(
  raw: unknown,
  materials: OpenerMaterial[],
): { reading: OpenerMaterialReadingItem[]; flags: OpenerQualityFlag[] } {
  const reading: OpenerMaterialReadingItem[] = [];
  const flags: OpenerQualityFlag[] = [];
  if (!Array.isArray(raw)) return { reading, flags };
  const byId = new Map(materials.map((m) => [m.id, m]));
  for (const item of raw.slice(0, 12)) {
    if (!isPlainObject(item)) continue;
    const material = typeof item.materialId === "string" ? byId.get(item.materialId) : undefined;
    const quote = typeof item.quote === "string" ? item.quote.trim() : "";
    if (!material || !quote || !material.originalText.includes(quote)) {
      flags.push({ code: "reading_quote_mismatch", severity: "soft", materialId: material?.id });
      continue;
    }
    reading.push({
      materialId: material.id,
      subject: SUBJECTS.includes(item.subject as OpenerMaterialSubject) ? item.subject as OpenerMaterialSubject : "unknown",
      kind: KINDS.includes(item.kind as OpenerMaterialKind) ? item.kind as OpenerMaterialKind : material.kind,
      certainty: CERTAINTIES.includes(item.certainty as OpenerMaterialCertainty) ? item.certainty as OpenerMaterialCertainty : "stated",
      quote,
    });
  }
  return { reading, flags };
}

/** 來源紀錄：ID 出自本局、引文片段真的在該句裡（trace matched 的前提）。 */
export function sanitizeMaterialReferences(
  raw: unknown,
  openers: Record<string, string>,
  materials: OpenerMaterial[],
): { references: OpenerMaterialReference[]; flags: OpenerQualityFlag[] } {
  const references: OpenerMaterialReference[] = [];
  const flags: OpenerQualityFlag[] = [];
  if (!Array.isArray(raw)) return { references, flags };
  const ids = new Set(materials.map((m) => m.id));
  for (const item of raw.slice(0, 20)) {
    if (!isPlainObject(item)) continue;
    const style = typeof item.style === "string" && (OPENER_TYPES as readonly string[]).includes(item.style)
      ? item.style as OpenerType
      : null;
    const materialId = typeof item.materialId === "string" ? item.materialId : null;
    const span = typeof item.outputSpan === "string" ? item.outputSpan.trim() : "";
    const text = style ? openers[style] : undefined;
    if (!style || !materialId || !ids.has(materialId) || !text || !span || !text.includes(span)) {
      flags.push({ code: "reference_invalid", severity: "soft", style: style ?? undefined, materialId: materialId ?? undefined });
      continue;
    }
    if (!references.some((ref) => ref.style === style && ref.materialId === materialId)) {
      references.push({ style, materialId, outputSpan: span });
    }
  }
  return { references, flags };
}

// ── 第五輪驗收補的確定性規則（只做能確定的部分；語意品質仍交盲審）──

const WORK_TOPIC_RE = /^(工作|職業|上班|職場|工作的事|她的工作|我的工作)$/u;
const PROFESSION_RE = /(師|助理|工程|設計|護理|老師|醫|業務|會計|店員|主管|公務|廚|導|顧問|編輯|記者|老闆)/u;
/** 線索標籤像職業（「美容師工作」「獸醫助理工作」）就取職業本體。 */
function professionFromCueLabel(label: string): string | null {
  const core = label.replace(/(的)?(工作|職業|這行|這份工作)$/u, "").trim();
  return core && core !== label.trim() && PROFESSION_RE.test(core) ? core : (PROFESSION_RE.test(core) && core.length <= 6 ? core : null);
}
/** 「柴犬：我養妳…」這種冒號／引號後的代言，不是用戶本人的自述。 */
function stripAttributedSpeech(text: string): string {
  return text.replace(/[：:「『"][^\n」』"，,。！!？?]*/gu, "");
}
const CLAUSE_SPLIT_RE = /[\n，,。！!？?；;\s]+/u;
const RELATIVE_RE = /我(妹|哥|姐|弟|媽|爸|爺|奶|朋友|同事|家人|室友|前任)/u;
const SPEECH_RE = /(說|嫌|講|抱怨|唸|念|告訴|吐槽|提過)/u;
const HEDGE_RE = /(提過|想去|還沒|應該|好像|可能|猜|不確定|考慮|打算)/u;
const COMMIT_RE = /(說好|答應|約好|承諾|已經訂|訂好了|確定了|決定了)/u;
const EXPERIENCE_RE = /(過|年|以前|曾|打工|學過|玩過|做過|養了|養過|待過|住過|去過|當過)/u;
const SENSITIVE_SELF_FACT_RE = /(過敏|生病|受傷|住院|開刀|離婚|分手|失業|負債|懷孕|憂鬱|焦慮症)/u;
const FUNCTION_CHARS = "的了過在是有也都很就還沒不對跟和與把被讓從到得著呢吧啊嗎我妳你她他牠們這那個";
const STOP_BIGRAMS = new Set(["以前", "現在", "之前", "最近", "曾經", "已經", "平常", "上次", "這次", "自己", "想聊", "興趣", "相關", "經驗", "沒有", "但沒", "聊天", "想去", "還沒", "應該", "不確", "確定", "比較", "有興", "一次", "一下", "一起", "只是", "其實", "真的", "感覺", "覺得"]);
const PROFILE_ANTONYMS: ReadonlyArray<readonly [string, string]> = [["早睡", "晚睡"], ["早起", "晚起"]];

function contentBigrams(span: string): string[] {
  const chars = [...span.replace(/[\s，,。！!？?；;、（）()「」『』：:]/gu, "")];
  const out: string[] = [];
  for (let i = 0; i + 2 <= chars.length; i++) {
    const bg = chars[i] + chars[i + 1];
    if (STOP_BIGRAMS.has(bg)) continue;
    if (FUNCTION_CHARS.includes(chars[i]) && FUNCTION_CHARS.includes(chars[i + 1])) continue;
    if (!/[\u4e00-\u9fffA-Za-z0-9]{2}/u.test(bg)) continue;
    if (!out.includes(bg)) out.push(bg);
  }
  return out;
}
function clausesOf(text: string): string[] {
  return text.split(CLAUSE_SPLIT_RE).map((c) => c.trim()).filter(Boolean);
}
/** 用戶原文裡「我＋經歷」的片段（我玩過三年樂團／我以前在寵物店打工過）；家人主體不算。 */
function senderExperienceBigrams(set: OpenerMaterialSet): string[] {
  const out: string[] = [];
  for (const m of set.materials) {
    if (m.origin !== "user_text") continue;
    for (const clause of clausesOf(m.originalText)) {
      if (!/^我/u.test(clause) || RELATIVE_RE.test(clause.slice(0, 3))) continue;
      if (!EXPERIENCE_RE.test(clause)) continue;
      for (const bg of contentBigrams(clause.replace(/^我(自己|也|們)?/u, ""))) if (!out.includes(bg)) out.push(bg);
    }
  }
  return out;
}
function userTexts(set: OpenerMaterialSet): string {
  return set.materials.filter((m) => m.origin === "user_text").map((m) => m.originalText).join("\n");
}

/** 目標型原料（想約她）：採用＝句子帶輕邀約，不是只提到咖啡。 */
const GOAL_RE = /(想約|約她|約妳|想見面|見個面|想邀|一起去)/u;
const INVITE_RE = /(約|一起|要不要|有空|哪天|改天|找一天|下次)/u;

/** 原料裡「正向內容」的雙字片段：去掉主體、被否定的經歷與排除語，純否定／純排除的原料沒有正向片段。 */
function positiveMaterialBigrams(m: OpenerMaterial, set: OpenerMaterialSet): string[] {
  let source = m.originalText.replace(/^(想聊：|對「|」有興趣，但沒有相關經驗)/gu, "");
  if (m.origin === "user_text") {
    source = source.replace(EXCLUSION_RE, "");
    for (const fact of set.negatedFacts) source = source.replace(fact, "");
    source = source.replace(/(沒有|沒|不曾|未|從來沒|從沒|還沒|不想|不要|別|不用|不必)/gu, "");
  }
  source = source.replace(/我(妹|哥|姐|弟|媽|爸|朋友|同事|室友)?|她|妳|你|自己/gu, "");
  return contentBigrams(source);
}

/** 這張卡有沒有實際用到用戶本次的原料（內容證據，不看模型自稱的 references）。 */
export function cardAdoptsMaterial(text: string, set: OpenerMaterialSet): boolean {
  if (!set.hasEffectiveMaterial) return false;
  for (const m of set.materials) {
    if (m.origin === "user_text" && GOAL_RE.test(m.originalText)) {
      if (INVITE_RE.test(text)) return true;
      continue;
    }
    for (const bg of positiveMaterialBigrams(m, set)) if (text.includes(bg)) return true;
  }
  return false;
}

/** 有沒有任何原料需要「採用證據」：只有否定／排除（「沒養過」「不聊工作」）的補充，遵守就是採用。 */
function materialsRequireAdoption(set: OpenerMaterialSet): boolean {
  return set.materials.some((m) => (m.origin === "user_text" && GOAL_RE.test(m.originalText)) || positiveMaterialBigrams(m, set).length > 0);
}

/**
 * 原料採用檢查（第五輪 A）：有有效原料時，用戶方案可見的卡至少要有一張真的用到原料；
 * 一張都沒有＝這組沒接住他這次的想法，標在排序第一張可見卡上讓修正改寫它。
 */
export function checkMaterialAdoption(input: {
  openers: Record<string, string>;
  materials: OpenerMaterialSet;
  visibleTypes: readonly OpenerType[];
  rankedPicks: readonly OpenerType[];
  /** 已被其他硬檢查標記的卡：主體顛倒或升級確定度的句子不算「有採用」。 */
  flags?: readonly OpenerQualityFlag[];
}): OpenerQualityFlag[] {
  const { openers, materials, visibleTypes, rankedPicks } = input;
  if (!materials.hasEffectiveMaterial || !materialsRequireAdoption(materials)) return [];
  const flaggedStyles = new Set((input.flags ?? []).filter((f) => f.severity === "hard").map((f) => f.style));
  const visible = visibleTypes.filter((t) => openers[t]);
  if (visible.some((t) => !flaggedStyles.has(t) && cardAdoptsMaterial(openers[t], materials))) return [];
  const target = rankedPicks.find((t) => visible.includes(t)) ?? visible[0];
  if (!target) return [];
  return [{ code: "material_unused", severity: "hard", style: target, detail: materials.materials.map((m) => m.id).join(",") }];
}

/**
 * 硬檢查：沒有來源的第一人稱事實、被否定的經歷被寫成肯定、明確排除的話題
 * 被用上、用戶經歷被轉到她身上、家人被加上引語、確定度被升級、自介事實被反轉。
 * 命中＝這組不能交付，handler 做一次有界修正，仍不過就 502 不扣。
 */
export function checkOpenersAgainstMaterials(
  openers: Record<string, string>,
  set: OpenerMaterialSet,
  snapshot?: Pick<OpenerAnalysisSnapshot, "profileText" | "cues">,
): OpenerQualityFlag[] {
  const flags: OpenerQualityFlag[] = [];
  const experienceBigrams = senderExperienceBigrams(set);
  const userText = userTexts(set);
  const userHasRelative = RELATIVE_RE.test(userText);
  const userHasSpeech = SPEECH_RE.test(userText);
  const userHedged = HEDGE_RE.test(userText);
  const profileText = snapshot
    ? [snapshot.profileText.bio, snapshot.profileText.interests, ...snapshot.cues.map((c) => c.evidence?.quote ?? "")].filter(Boolean).join("\n")
    : "";
  for (const [style, text] of Object.entries(openers)) {
    // 冒號／引號後的代言（柴犬：我養妳…）不算本人自述（第五輪 P080）。
    const selfText = stripAttributedSpeech(text);
    if (!set.senderFactAllowed && FIRST_PERSON_FACT_RE.test(selfText)) {
      flags.push({ code: "fabricated_sender_fact", severity: "hard", style });
    }
    // 選了「沒有經驗」的線索，句子卻是「我也養狗／我家的狗」：不論有沒有其他原文都算捏造。
    for (const topic of set.noExperienceTopics) {
      if (FIRST_PERSON_FACT_RE.test(selfText) && topicMentioned(selfText, topic)) {
        flags.push({ code: "fabricated_sender_fact", severity: "hard", style, detail: topic });
      }
    }
    for (const fact of set.negatedFacts) {
      if (/我/u.test(text) && text.includes(fact) && !/(沒|不曾|未|還沒)/u.test(text)) {
        flags.push({ code: "negation_reversed", severity: "hard", style, detail: fact });
      }
    }
    for (const topic of set.excludedTopics) {
      if (!topic || !text.includes(topic)) continue;
      // 「下班不聊工作吧」是遵守排除，不是使用（第五輪 P107）。
      const avoidance = new RegExp(`(不|別|先不|不用|不要|不想|不必)(聊|提|講|談|問|說)(到|起)?[^\\n，,。！!？?]{0,3}${topic.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "u");
      if (avoidance.test(text)) continue;
      flags.push({ code: "excluded_topic_used", severity: "hard", style, detail: topic });
    }
    // 用戶自己的經歷（年數／曾做過）出現在沒有「我」的句子裡＝被套到她身上（P038／P070）。
    for (const clause of clausesOf(text)) {
      const hit = experienceBigrams.find((bg) => clause.includes(bg));
      if (hit && !/我/u.test(clause)) {
        flags.push({ code: "sender_fact_transposed", severity: "hard", style, detail: hit });
        break;
      }
    }
    // 自述被加上用戶沒說的健康／人生事件（P018「現在只剩回憶跟過敏」）。
    const sensitive = text.match(SENSITIVE_SELF_FACT_RE)?.[0];
    if (sensitive && !userText.includes(sensitive) && !/(妳|她|你)/u.test(clausesOf(text).find((c) => c.includes(sensitive)) ?? "")) {
      flags.push({ code: "sender_fact_extended", severity: "hard", style, detail: sensitive });
    }
    // 家人只提供了職業／狀態，卡片卻替他們加上說過的話（P009／P022）。
    if (userHasRelative && !userHasSpeech && RELATIVE_RE.test(text) && SPEECH_RE.test(text)) {
      flags.push({ code: "relative_quote_fabricated", severity: "hard", style, detail: text.match(SPEECH_RE)?.[0] });
    }
    // 「提過想去、還沒訂」被寫成「說好要訂」（P052）。
    if (userHedged && COMMIT_RE.test(text)) {
      flags.push({ code: "certainty_upgraded", severity: "hard", style, detail: text.match(COMMIT_RE)?.[0] });
    }
    // 自介已知事實被反轉（她說貓比她早睡，卡片寫晚睡；P123）。
    if (profileText) {
      for (const [a, b] of PROFILE_ANTONYMS) {
        for (const [known, reversed] of [[a, b], [b, a]] as const) {
          if (profileText.includes(known) && !profileText.includes(reversed) && text.includes(reversed)) {
            flags.push({ code: "profile_fact_reversed", severity: "hard", style, detail: `${known}→${reversed}` });
          }
        }
      }
    }
  }
  return flags;
}

/** 線索標籤（如「養狗」「河堤滑板」）任一個雙字片段出現在句中就算提到。 */
function topicMentioned(text: string, topic: string): boolean {
  const compact = topic.replace(/[\s、，,]/g, "");
  if (compact.length <= 2) return text.includes(compact);
  for (let i = 0; i + 2 <= compact.length; i++) {
    if (text.includes(compact.slice(i, i + 2))) return true;
  }
  return false;
}

export function hardFlags(flags: OpenerQualityFlag[]): OpenerQualityFlag[] {
  return flags.filter((flag) => flag.severity === "hard");
}

/** 原料整理成 prompt 用的純文字資料區塊（不含教學文字）。 */
export function renderMaterialsForPrompt(set: OpenerMaterialSet): string {
  if (set.materials.length === 0) {
    return `本次用戶補充：無（inputState=${set.inputState}）。照現有資料正常生成，不要假裝有取得用戶個人想法。`;
  }
  const lines = set.materials.map((m) =>
    [
      `- ${m.id}｜來源=${m.origin === "option" ? "選項" : "用戶原文"}｜主體=${m.subject}｜類型=${m.kind}｜確定度=${m.certainty}` +
      (m.cueId ? `｜對應線索=${m.cueId}` : ""),
      `  原文：「${m.originalText}」`,
      `  可用：${m.allowedUse.join("、")}；限制：${m.restrictions.join("；")}`,
    ].join("\n")
  );
  const extra: string[] = [];
  if (set.excludedTopics.length) extra.push(`明確排除的話題：${set.excludedTopics.join("、")}（所有候選句都不得提到）`);
  if (set.negatedFacts.length) extra.push(`用戶明說沒有的經歷：${set.negatedFacts.join("、")}（不得寫成肯定）`);
  if (set.noExperienceTopics.length) extra.push(`用戶對「${set.noExperienceTopics.join("、")}」只有興趣、沒有經驗：不得出現「我也」「我家」「我養」這類共同經驗。`);
  if (!set.senderFactAllowed) extra.push("本次沒有任何可用的第一人稱事實：五句都不得出現「我也／我家／我養／我常」這類自述。");
  if (set.directionOverride === "fresh_topic") extra.push("用戶表示第一段列的線索都沒興趣：另開話題，不要再接那些線索。");
  return [`本次用戶補充（inputState=${set.inputState}）：`, ...lines, ...extra].join("\n");
}
