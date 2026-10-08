/**
 * 新話題結構方案（PR #93）的「原始來源＋程式核對」原型。
 *
 * Eric 2026-10-08 要求先交免費驗證：這個檔案只在評測工具裡，沒有接進
 * handler，不影響正式路徑。對應方案的兩步：
 * - A（buildSourcePack）：從正式的使用者提示詞取出原始來源，原文照抄、編 ID；
 *   缺的就是缺。
 * - D（checkReview）：核對審稿輸出。每段標記要對得回程式切出的那一段；
 *   標成事實的段要附範圍、來源 ID 與原文，原文要逐字出現在那個來源裡、
 *   跟這一段講的是同一件事，而且那類來源撐得起這個範圍；有問題代碼就剔除；
 *   選的 5 句都要通過、★ 在其中；交付的句子依 ID 從候選原樣複製，審稿改不到。
 *
 * 句子裡有時間詞（今天、剛、這次…）、「我每次／我一定要…」或「我家」時，
 * 一定是在講事實：審稿標成看法、猜測、一般話題或招呼，程式照樣剔除；時間詞
 * 也要出現在附的原文裡。這幾道是字面規則，擋得住的有限：沒有這些字的事件或
 * 習慣被標成看法，或附的原文跟這段有關、卻撐不起多加的細節，程式核對不出來，
 * 要靠付費的審稿回測量。
 */
import { NEW_TOPIC_TOPIC_COUNT } from "../../supabase/functions/analyze-chat/new_topic_payload.ts";

export type SourceKind = "作戰板" | "關於我" | "局面" | "素材" | "今天";

export type SourceItem = {
  id: string;
  kind: SourceKind;
  text: string;
  /** 素材類型（例如「你們之間的梗」）；只有 M1 有。 */
  label?: string;
};

/** 不需要來源的五種，加上需要來源的「事實」。 */
export const REVIEW_SEGMENT_KINDS = [
  "看法",
  "問題",
  "猜測",
  "一般話題",
  "招呼語氣",
  "事實",
] as const;

/** 事實的範圍：決定哪類來源撐得起它。「習慣」包括喜好和想做的事。 */
export const REVIEW_FACT_SCOPES = [
  "事件",
  "習慣",
  "擁有",
  "說過",
  "狀態",
  "日期",
] as const;

/** 任何一個都會讓這句剔除。 */
export const REVIEW_ISSUE_CODES = [
  "編造事件",
  "加細節",
  "興趣寫成事實",
  "主詞弄反",
  "明知故問",
  "邏輯不通",
  "要猜背景",
  "施壓或評斷",
  "違反局面規則",
  "教練語",
] as const;

export type ReviewSegment = {
  /** 第幾段（從 1 起），對應 splitSegments 切出的順序。 */
  index: number;
  /** 那一段的原文，程式拿來確認標記沒有錯位。 */
  text: string;
  kind: string;
  scope?: string;
  source?: string;
  quote?: string;
};
export type ReviewLineCheck = {
  id: string;
  segments: ReviewSegment[];
  issues: string[];
};
export type ReviewOutput = {
  checks: ReviewLineCheck[];
  selected: string[];
  recommended: string;
};
export type Candidate = { id: string; text: string };

export type LineVerdict = {
  id: string;
  passed: boolean;
  reasons: string[];
};

export type ReviewCheckResult = {
  lines: LineVerdict[];
  selectionOk: boolean;
  selectionReasons: string[];
  /** 選擇核對通過才有：依 ID 從候選原樣複製。 */
  delivered: Array<{ id: string; text: string; recommended: boolean }> | null;
};

/** 依標點、換行與空白切段；只有符號或表情的段併回前一段。 */
export function splitSegments(text: string): string[] {
  const pieces = text
    .split(/(?<=[，,。．！!？?；;…～~])|\n+|\s+/u)
    .map((piece) => piece.trim())
    .filter((piece) => piece.length > 0);
  const segments: string[] = [];
  for (const piece of pieces) {
    if (!/[\p{L}\p{N}]/u.test(piece) && segments.length > 0) {
      segments[segments.length - 1] += piece;
    } else {
      segments.push(piece);
    }
  }
  return segments;
}

/** 比對原文前只留文字與數字：空白、標點、表情和全半形差異都不算。 */
function compactForQuote(text: string): string {
  return text.normalize("NFKC").replace(/[^\p{L}\p{N}]/gu, "");
}

/** 附的原文要跟這一段講同一件事：至少有兩個字連在一起相同。 */
function sharesWords(segment: string, quote: string): boolean {
  const a = compactForQuote(segment);
  const b = compactForQuote(quote);
  if (a.includes(b) || b.includes(a)) return true;
  const pairs = new Set<string>();
  for (let i = 0; i + 1 < b.length; i++) pairs.add(b.slice(i, i + 2));
  for (let i = 0; i + 1 < a.length; i++) {
    if (pairs.has(a.slice(i, i + 2))) return true;
  }
  return false;
}

/** 用戶自己的事件只能來自「用戶最近遇到的事」「看到想到她的東西」。 */
const EVENT_MATERIALS = new Set(["用戶最近遇到的事", "看到想到她的東西"]);
const SAID_MATERIALS = new Set([
  "之前聊過的事（她提過的）",
  "約會時聊到的事",
  "你們之間的梗",
]);
const STATE_MATERIALS = new Set([
  "之前聊過的事（她提過的）",
  "約會時聊到的事",
]);

/**
 * 哪類來源撐得起哪個範圍：習慣撐不起單次事件，日期撐不起天氣或季節；
 * 「她說過」只能來自素材，作戰板不能冒充她說過的話。
 */
function scopeAllows(scope: string, source: SourceItem): boolean {
  const material = source.kind === "素材" ? source.label ?? "" : null;
  switch (scope) {
    case "事件":
      return material !== null && EVENT_MATERIALS.has(material);
    case "習慣":
      return source.kind === "作戰板" || source.kind === "關於我" ||
        material === "你們之間的梗";
    case "擁有":
      return source.kind === "關於我" || material !== null;
    case "說過":
      return material !== null && SAID_MATERIALS.has(material);
    case "狀態":
      return source.kind === "局面" || source.kind === "關於我" ||
        (material !== null && STATE_MATERIALS.has(material));
    case "日期":
      return source.kind === "今天";
    default:
      return false;
  }
}

/**
 * 句子裡有這些字，就是在講一件事實：只能標成事實（範圍要對），或真的在問。
 * 「剛」也抓「剛好」：剛好聽到、剛好路過一樣是事件。
 */
const CLAIM_MARKERS = [
  {
    name: "時間",
    pattern: /今天|今早|今晚|剛|昨天|昨晚|前天|這次|這幾天/gu,
    scopes: ["事件", "日期"],
  },
  {
    name: "習慣",
    pattern: /我[^，,。！!？?、\s]{0,3}(?:每次|總是|固定|一定要|都會|習慣)/gu,
    scopes: ["習慣"],
  },
  { name: "我家", pattern: /我家/gu, scopes: ["擁有", "狀態"] },
] as const;

/** 有問號，或以「嗎」「呢」收尾，才算真的在問。 */
function isQuestion(segment: string): boolean {
  return /[？?]/u.test(segment) || /[嗎呢][^\p{L}\p{N}]*$/u.test(segment);
}

function sectionLines(userPrompt: string): Map<string, string[]> {
  const sections = new Map<string, string[]>();
  let current: string[] | null = null;
  for (const line of userPrompt.split("\n")) {
    const header = /^## (.+)$/.exec(line);
    if (header) {
      current = [];
      sections.set(header[1], current);
    } else if (current !== null) {
      current.push(line);
    }
  }
  return sections;
}

function linesOf(sections: Map<string, string[]>, prefix: string): string[] {
  for (const [title, lines] of sections) {
    if (title.startsWith(prefix)) return lines;
  }
  return [];
}

function bullets(lines: string[]): string[] {
  return lines.filter((line) => line.startsWith("- ")).map((line) =>
    line.slice(2).trim()
  );
}

/** 作戰板：逐行一項，興趣一個一項；節奏分數與最後那行規則不當來源。 */
function boardItems(lines: string[]): string[] {
  const items: string[] = [];
  for (const line of bullets(lines)) {
    if (
      line.startsWith("最近互動投入") || line.includes("只可使用以上明確紀錄")
    ) {
      continue;
    }
    if (line.startsWith("興趣：")) {
      for (const interest of line.slice("興趣：".length).split("、")) {
        if (interest.trim()) items.push(`興趣：${interest.trim()}`);
      }
      continue;
    }
    for (const part of line.split("；")) {
      if (part.trim()) items.push(part.trim());
    }
  }
  return items;
}

/** 局面：「做法：」之前的答案才是用戶說的現況，做法是規則。 */
function situationItems(lines: string[]): string[] {
  const end = lines.findIndex((line) => line.startsWith("做法"));
  return bullets(end === -1 ? lines : lines.slice(0, end));
}

/**
 * A：從正式的使用者提示詞取出原始來源。原型直接讀提示詞，確保審稿看到的
 * 字跟生成看到的一樣；接進正式路徑時改成從請求欄位直接組。
 */
export function buildSourcePack(userPrompt: string): SourceItem[] {
  const sections = sectionLines(userPrompt);
  const items: SourceItem[] = [];
  const push = (prefix: string, kind: SourceKind, texts: string[]) =>
    texts.forEach((text, i) =>
      items.push({ id: `${prefix}${i + 1}`, kind, text })
    );

  push("P", "作戰板", boardItems(linesOf(sections, "對方作戰板")));
  push(
    "U",
    "關於我",
    linesOf(sections, "關於我")
      .map((line) => line.replace(/^- /, "").trim())
      .filter((line) => line.length > 0 && !line.startsWith("（沒有提供")),
  );
  push("S", "局面", situationItems(linesOf(sections, "這次的局面")));

  const material = bullets(linesOf(sections, "用戶手上的素材"));
  const kind = material.find((line) => line.startsWith("類型："));
  const original = material.find((line) => line.startsWith("原文："));
  const quoted = original ? /「(.*)」/u.exec(original) : null;
  if (quoted) {
    items.push({
      id: "M1",
      kind: "素材",
      text: quoted[1],
      label: kind?.slice("類型：".length),
    });
  }

  const today = linesOf(sections, "今天").find((line) => line.trim());
  if (today) {
    items.push({ id: "T1", kind: "今天", text: today.split("。")[0].trim() });
  }
  return items;
}

/** 審稿前就能確定刷掉的：亂碼、控制字元、一句兩問。外洩與「我們」守門接正式檢查。 */
export function preReviewProblems(text: string): string[] {
  const problems: string[] = [];
  if (
    [...text].some((ch) => ch === "�" || (ch !== "\n" && /\p{Cc}/u.test(ch)))
  ) {
    problems.push("garbled");
  }
  if ((text.match(/[？?]/gu) ?? []).length > 1) problems.push("multi_question");
  return problems;
}

/** 一段標記的問題。理由用代碼，「:第幾段」方便評測統計。 */
function segmentProblems(
  label: ReviewSegment,
  segment: string,
  at: number,
  sourceById: Map<string, SourceItem>,
): string[] {
  const kinds: readonly string[] = REVIEW_SEGMENT_KINDS;
  const scopes: readonly string[] = REVIEW_FACT_SCOPES;
  if (!kinds.includes(label.kind)) return [`unknown_kind:${at}`];
  const markers = CLAIM_MARKERS.flatMap((marker) =>
    (segment.match(marker.pattern) ?? []).map((hit) => ({ ...marker, hit }))
  );

  if (label.kind !== "事實") {
    const asked = label.kind === "問題" && isQuestion(segment);
    return markers.length > 0 && !asked
      ? [`claim_not_fact:${at}:${markers[0].name}`]
      : [];
  }

  if (!label.source || !label.quote) return [`fact_without_source:${at}`];
  const source = sourceById.get(label.source);
  if (!source) return [`unknown_source:${at}`];
  const quote = compactForQuote(label.quote);
  if (quote.length < 2 || !compactForQuote(source.text).includes(quote)) {
    return [`quote_not_in_source:${at}`];
  }
  if (!label.scope) return [`fact_without_scope:${at}`];
  if (!scopes.includes(label.scope)) return [`unknown_scope:${at}`];

  const problems = new Set<string>();
  if (!sharesWords(segment, label.quote)) problems.add(`quote_unrelated:${at}`);
  if (!scopeAllows(label.scope, source)) {
    problems.add(`scope_source_mismatch:${at}`);
  }
  for (const marker of markers) {
    const scopesForMarker: readonly string[] = marker.scopes;
    if (!scopesForMarker.includes(label.scope)) {
      problems.add(`marker_scope:${at}:${marker.name}`);
    }
    // 時間詞要出現在附的原文裡；「今天」可由「今天」這個來源撐（範圍是日期）。
    const todayFromDate = marker.hit === "今天" && source.kind === "今天";
    if (
      marker.name === "時間" && !label.quote.includes(marker.hit) &&
      !todayFromDate
    ) {
      problems.add(`time_not_in_quote:${at}`);
    }
  }
  return [...problems];
}

/** D：核對審稿輸出。逐句的理由用代碼，方便評測統計。 */
export function checkReview(input: {
  sources: SourceItem[];
  candidates: Candidate[];
  review: ReviewOutput;
}): ReviewCheckResult {
  const sourceById = new Map(input.sources.map((s) => [s.id, s]));
  const checks = new Map<string, ReviewLineCheck[]>();
  for (const check of input.review.checks) {
    checks.set(check.id, [...(checks.get(check.id) ?? []), check]);
  }
  const issueCodes: readonly string[] = REVIEW_ISSUE_CODES;

  const lines = input.candidates.map((candidate): LineVerdict => {
    const found = checks.get(candidate.id) ?? [];
    if (found.length === 0) {
      return { id: candidate.id, passed: false, reasons: ["no_check"] };
    }
    const reasons: string[] = [];
    if (found.length > 1) reasons.push("duplicate_check");
    const check = found[0];
    const segments = splitSegments(candidate.text);

    // 標記照段號對回程式切出的段，段號重複、超出或原文對不上都算錯位。
    const byIndex = new Map<number, ReviewSegment>();
    for (const label of check.segments) {
      if (
        !Number.isInteger(label.index) || label.index < 1 ||
        label.index > segments.length
      ) {
        reasons.push(`segment_unknown:${label.index}`);
      } else if (byIndex.has(label.index)) {
        reasons.push(`segment_duplicate:${label.index}`);
      } else {
        byIndex.set(label.index, label);
      }
    }
    segments.forEach((segment, i) => {
      const at = i + 1;
      const label = byIndex.get(at);
      if (!label) {
        reasons.push(`segment_missing:${at}`);
      } else if (compactForQuote(label.text) !== compactForQuote(segment)) {
        reasons.push(`segment_mismatch:${at}`);
      } else {
        reasons.push(...segmentProblems(label, segment, at, sourceById));
      }
    });

    for (const issue of check.issues) {
      reasons.push(
        issueCodes.includes(issue)
          ? `issue:${issue}`
          : `unknown_issue:${issue}`,
      );
    }
    return { id: candidate.id, passed: reasons.length === 0, reasons };
  });

  const passed = new Set(lines.filter((l) => l.passed).map((l) => l.id));
  const known = new Set(input.candidates.map((c) => c.id));
  const { selected, recommended } = input.review;
  const selectionReasons: string[] = [];
  if (selected.length !== NEW_TOPIC_TOPIC_COUNT) {
    selectionReasons.push(`selected_count:${selected.length}`);
  }
  if (new Set(selected).size !== selected.length) {
    selectionReasons.push("selected_duplicate");
  }
  for (const id of selected) {
    if (!known.has(id)) selectionReasons.push(`selected_unknown:${id}`);
    else if (!passed.has(id)) {
      selectionReasons.push(`selected_not_passed:${id}`);
    }
  }
  if (!selected.includes(recommended)) {
    selectionReasons.push("recommended_not_selected");
  }
  const selectionOk = selectionReasons.length === 0;
  const textById = new Map(input.candidates.map((c) => [c.id, c.text]));
  return {
    lines,
    selectionOk,
    selectionReasons,
    delivered: selectionOk
      ? selected.map((id) => ({
        id,
        text: textById.get(id) as string,
        recommended: id === recommended,
      }))
      : null,
  };
}
