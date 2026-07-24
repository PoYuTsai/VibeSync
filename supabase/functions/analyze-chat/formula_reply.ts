// 公式回覆共用 normalizer（2026-07-24 公式回覆計畫 §4）。
//
// Opener 的 formulaOpeners 與 New Topic 的 formulaTopics 共用同一 item
// shape：{ openingLine, whyItWorks }。這裡是 server canonical 的唯一入口：
// best-effort 收 0–2 則合法公式，任何壞項只丟該則、絕不觸發 repair、
// 絕不影響 base 成敗。
//
// 純 helper：不 import Edge server、不碰 DB，可純 unit test。

export type FormulaReply = {
  openingLine: string;
  whyItWorks: string;
};

export const FORMULA_REPLY_MAX_COUNT = 2;

// hard cap 以 Unicode code points 計：TS [...text].length＝
// PostgreSQL char_length()＝Dart runes.length。prompt soft target 是
// 45–80／60–100 繁中字，cap 只擋失控輸出，不是正常長度。
export const FORMULA_REPLY_CAPS = {
  openingLine: 180,
  whyItWorks: 300,
} as const;

/**
 * Prompt 內示範句＋schema placeholder（§4-10；Codex 首審 P2 擴充）：模型
 * 逐字照抄範例或 JSON schema 佔位文字時整則丟棄，不得把與本次素材無關
 * 的示範／模板內容送給使用者。normalizer 永遠內建排除這組，呼叫端另外
 * 傳本次 base opener/topic 五句。
 */
export const FORMULA_PROMPT_EXAMPLE_LINES: readonly string[] = [
  "妳那張山頂照讓我有點想把週末從沙發救回來。那條是新手也能活著下山的路線嗎？",
  "妳看起來很有趣，平常喜歡做什麼？",
  "公式開場第一則：具體線索＋我的當下反應＋好接的開口，可直接送出",
  "公式開場第二則（與第一則抓不同線索或不同開口）",
  "公式新話題第一則：具體線索＋一小段我＋好接的開口，可直接送出",
  "公式新話題第二則（與第一則抓不同線索或不同開口）",
];

/**
 * whyItWorks 的 schema placeholder：dedupe key 完全相同才丟（教練註解是
 * 自然語句，只擋逐字照抄，不做模糊比對）。
 */
export const FORMULA_PROMPT_PLACEHOLDER_NOTES: readonly string[] = [
  "一句教練註解",
  "一句教練註解：這句接了哪個細節、為什麼好回；若自然可補她回後怎麼接",
  "一句教練註解：為什麼這句現在好接",
];

/**
 * 明顯內部來源標籤（§4-8）：可見文字出現任一標籤＝把系統如何記錄對方
 * 洩漏給對方，整則丟棄。只擋這組明確標籤，不做廣泛禁詞掃描（§4-9）。
 */
export const FORMULA_INTERNAL_LABELS: readonly string[] = [
  "對象作戰板",
  "對方作戰板",
  "最近熱度",
  "累計對話",
  "你的備註",
  "過往備註",
  "性格分析",
  "資料顯示",
  "系統判斷",
];

export type FormulaNormalizeOptions = {
  /** base opener/topic 的 openingLine（cross-field dedupe；§4-6）。 */
  excludeOpeningLines?: readonly string[];
  /** true 時任一可見欄位含內部標籤即丟整則（§4-8）。 */
  rejectInternalLabels?: boolean;
};

export type FormulaNormalizeOutcome = {
  replies: FormulaReply[];
  /**
   * 本次模型 formula array 中被檢查、但未進 canonical 0–2 結果的項目數
   *（malformed、over-cap、schema leak、internal label、duplicate、超過
   * 兩則都算；§8 telemetry 定義）。非 array 輸入＝0。只記總數不記內容。
   */
  droppedCount: number;
};

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Dedupe key（§4-6）：NFKC → 小寫 → 移除一般與全形空白。標點保留、
 * 不做模糊語意比對，避免誤殺。
 */
export function formulaDedupeKey(value: string): string {
  return value.normalize("NFKC").toLowerCase().replace(/[\s　]+/g, "");
}

/** visible-text markers（§4-5）：trim 後檢查 code fence／raw JSON／schema 洩漏。 */
function hasVisibleTextLeak(trimmed: string): boolean {
  if (trimmed.includes("```")) return true;
  if (/^[{[]/.test(trimmed)) return true;
  const lower = trimmed.toLowerCase();
  return lower.includes('"formulaopeners"') ||
    lower.includes('"formulatopics"') ||
    lower.includes('"openingline"') ||
    lower.includes('"whyitworks"') ||
    lower.includes('"openers"') ||
    lower.includes('"topics"');
}

function sanitizeFormulaField(
  value: unknown,
  maxCodePoints: number,
): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  // 超長一律丟整則、不截斷（§3）。
  if ([...trimmed].length > maxCodePoints) return null;
  if (hasVisibleTextLeak(trimmed)) return null;
  return trimmed;
}

function containsInternalLabel(text: string): boolean {
  return FORMULA_INTERNAL_LABELS.some((label) => text.includes(label));
}

/**
 * Best-effort canonicalize（§4）：依原始順序掃描直到收滿兩則合法公式；
 * 壞項丟該則不失敗。輸出只含兩個白名單 key（模型多吐的 key 不外傳）。
 */
export function normalizeFormulaRepliesDetailed(
  value: unknown,
  options?: FormulaNormalizeOptions,
): FormulaNormalizeOutcome {
  if (!Array.isArray(value)) {
    return { replies: [], droppedCount: 0 };
  }

  const excludeKeys = new Set<string>();
  for (const line of FORMULA_PROMPT_EXAMPLE_LINES) {
    excludeKeys.add(formulaDedupeKey(line));
  }
  for (const line of options?.excludeOpeningLines ?? []) {
    if (typeof line === "string" && line.trim().length > 0) {
      excludeKeys.add(formulaDedupeKey(line));
    }
  }
  const placeholderNoteKeys = new Set(
    FORMULA_PROMPT_PLACEHOLDER_NOTES.map(formulaDedupeKey),
  );

  const replies: FormulaReply[] = [];
  const seenKeys = new Set<string>();
  for (const item of value) {
    if (replies.length >= FORMULA_REPLY_MAX_COUNT) break;
    if (!isPlainObject(item)) continue;

    const openingLine = sanitizeFormulaField(
      item.openingLine,
      FORMULA_REPLY_CAPS.openingLine,
    );
    const whyItWorks = sanitizeFormulaField(
      item.whyItWorks,
      FORMULA_REPLY_CAPS.whyItWorks,
    );
    if (openingLine === null || whyItWorks === null) continue;

    if (
      options?.rejectInternalLabels === true &&
      (containsInternalLabel(openingLine) || containsInternalLabel(whyItWorks))
    ) {
      continue;
    }

    // whyItWorks 逐字照抄 schema placeholder＝模板洩漏，整則丟。
    if (placeholderNoteKeys.has(formulaDedupeKey(whyItWorks))) continue;

    const key = formulaDedupeKey(openingLine);
    // 與示範句／schema placeholder／base opener/topic 重複＝丟公式、
    // 原內容不動；兩則公式彼此重複只留第一則（§4-6）。
    if (excludeKeys.has(key) || seenKeys.has(key)) continue;
    seenKeys.add(key);

    replies.push({ openingLine, whyItWorks });
  }

  return { replies, droppedCount: value.length - replies.length };
}

export function normalizeFormulaReplies(
  value: unknown,
  options?: FormulaNormalizeOptions,
): FormulaReply[] {
  return normalizeFormulaRepliesDetailed(value, options).replies;
}
