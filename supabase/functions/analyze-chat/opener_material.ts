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

/**
 * 硬檢查：沒有來源的第一人稱事實、被否定的經歷被寫成肯定、明確排除的話題
 * 被用上。命中＝這組不能交付，handler 做一次有界修正，仍不過就 502 不扣。
 */
export function checkOpenersAgainstMaterials(
  openers: Record<string, string>,
  set: OpenerMaterialSet,
): OpenerQualityFlag[] {
  const flags: OpenerQualityFlag[] = [];
  for (const [style, text] of Object.entries(openers)) {
    if (!set.senderFactAllowed && FIRST_PERSON_FACT_RE.test(text)) {
      flags.push({ code: "fabricated_sender_fact", severity: "hard", style });
    }
    // 選了「沒有經驗」的線索，句子卻是「我也養狗／我家的狗」：不論有沒有其他原文都算捏造。
    for (const topic of set.noExperienceTopics) {
      if (FIRST_PERSON_FACT_RE.test(text) && topicMentioned(text, topic)) {
        flags.push({ code: "fabricated_sender_fact", severity: "hard", style, detail: topic });
      }
    }
    for (const fact of set.negatedFacts) {
      if (/我/u.test(text) && text.includes(fact) && !/(沒|不曾|未|還沒)/u.test(text)) {
        flags.push({ code: "negation_reversed", severity: "hard", style, detail: fact });
      }
    }
    for (const topic of set.excludedTopics) {
      if (topic && text.includes(topic)) {
        flags.push({ code: "excluded_topic_used", severity: "hard", style, detail: topic });
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
