/**
 * 新話題結構方案（PR #93）的「原始來源＋程式核對」原型。
 *
 * Eric 2026-10-08 要求先交免費驗證：這個檔案只在評測工具裡，沒有接進
 * handler，不影響正式路徑。對應方案的兩步：
 * - A（buildSourcePack）：從正式的使用者提示詞取出原始來源，原文照抄、編 ID；
 *   缺的就是缺。
 * - D（checkReview）：核對審稿輸出。每段都要有標記；標成事實的段要附來源 ID
 *   與原文，原文要逐字出現在那個來源裡；有問題代碼就剔除；選的 5 句都要通過、
 *   ★ 在其中；交付的句子依 ID 從候選原樣複製，審稿改不到。
 *
 * 程式擋不住兩種錯：審稿把事件標成看法，或拿「每次」的習慣當「今天」的證據
 * （原文逐字存在，但撐不起這句）。這兩種要靠付費的審稿回測量。
 */
import { NEW_TOPIC_TOPIC_COUNT } from "../../supabase/functions/analyze-chat/new_topic_payload.ts";

export type SourceItem = {
  id: string;
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

export type ReviewSegment = { kind: string; source?: string; quote?: string };
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
  const push = (prefix: string, texts: string[]) =>
    texts.forEach((text, i) => items.push({ id: `${prefix}${i + 1}`, text }));

  push("P", boardItems(linesOf(sections, "對方作戰板")));
  push(
    "U",
    linesOf(sections, "關於我")
      .map((line) => line.replace(/^- /, "").trim())
      .filter((line) => line.length > 0 && !line.startsWith("（沒有提供")),
  );
  push("S", situationItems(linesOf(sections, "這次的局面")));

  const material = bullets(linesOf(sections, "用戶手上的素材"));
  const kind = material.find((line) => line.startsWith("類型："));
  const original = material.find((line) => line.startsWith("原文："));
  const quoted = original ? /「(.*)」/u.exec(original) : null;
  if (quoted) {
    items.push({
      id: "M1",
      text: quoted[1],
      label: kind?.slice("類型：".length),
    });
  }

  const today = linesOf(sections, "今天").find((line) => line.trim());
  if (today) items.push({ id: "T1", text: today.split("。")[0].trim() });
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
  const kinds: readonly string[] = REVIEW_SEGMENT_KINDS;
  const issueCodes: readonly string[] = REVIEW_ISSUE_CODES;

  const lines = input.candidates.map((candidate): LineVerdict => {
    const found = checks.get(candidate.id) ?? [];
    if (found.length === 0) {
      return { id: candidate.id, passed: false, reasons: ["no_check"] };
    }
    const reasons: string[] = [];
    if (found.length > 1) reasons.push("duplicate_check");
    const check = found[0];
    if (check.segments.length !== splitSegments(candidate.text).length) {
      reasons.push("segment_count_mismatch");
    }
    check.segments.forEach((segment, i) => {
      const at = i + 1;
      if (!kinds.includes(segment.kind)) {
        reasons.push(`unknown_kind:${at}`);
        return;
      }
      if (segment.kind !== "事實") return;
      if (!segment.source || !segment.quote) {
        reasons.push(`fact_without_source:${at}`);
        return;
      }
      const source = sourceById.get(segment.source);
      if (!source) {
        reasons.push(`unknown_source:${at}`);
        return;
      }
      const quote = compactForQuote(segment.quote);
      if (quote.length < 2 || !compactForQuote(source.text).includes(quote)) {
        reasons.push(`quote_not_in_source:${at}`);
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
