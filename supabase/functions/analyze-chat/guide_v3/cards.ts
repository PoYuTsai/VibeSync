// 第二段（寫卡）的輸出：一行一張卡的解析、預設口吻把「妳」換成「你」，以及說明書 C5
// 只記錄、不擋卡的字眼檢查（每張卡的，和整組的開頭重複）。
import type { CardSpec } from "./rules.ts";

export interface WrittenCard {
  readonly card: number;
  readonly messages: readonly string[];
  readonly hasInventedDetail: boolean;
  readonly expectedReaction: string;
}

/// 一行一張卡的 JSON；不是合法的卡回 null。
export function parseWrittenCardLine(raw: string): WrittenCard | null {
  const line = raw.trim();
  if (!line) return null;
  try {
    // deno-lint-ignore no-explicit-any
    const v: any = JSON.parse(line);
    const messages = Array.isArray(v?.messages)
      ? v.messages.filter((m: unknown) =>
        typeof m === "string" && m.trim() !== ""
      )
      : [];
    if (!Number.isInteger(v?.card) || messages.length === 0) return null;
    return {
      card: v.card,
      messages,
      hasInventedDetail: v.hasInventedDetail === true,
      expectedReaction: typeof v.expectedReaction === "string"
        ? v.expectedReaction
        : "",
    };
  } catch {
    return null;
  }
}

/// 一行一張卡的 JSON；壞掉的行略過（記在 invalidLines）。
export function parseWrittenCards(
  text: string,
): { cards: WrittenCard[]; invalidLines: number } {
  const cards: WrittenCard[] = [];
  let invalidLines = 0;
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim()) continue;
    const card = parseWrittenCardLine(raw);
    if (card) cards.push(card);
    else invalidLines++;
  }
  cards.sort((a, b) => a.card - b.card);
  return { cards, invalidLines };
}

/// 串流用：把文字片段切成完整的行；最後沒換行的那段由 flush 交出。
export function createLineSplitter(): {
  push(chunk: string): string[];
  flush(): string[];
} {
  let buffer = "";
  return {
    push(chunk) {
      buffer += chunk;
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() ?? "";
      return lines.filter((line) => line.trim() !== "");
    },
    flush() {
      const rest = buffer;
      buffer = "";
      return rest.trim() ? [rest] : [];
    },
  };
}

/// v3 A5：預設口吻的稱呼一律用「你」。模型常照對話寫成「妳」（10/14 第一輪 41/108 張），
/// 由程式換掉；照他的卡跟他，不動。原文另存在 rawMessages。
export function applyVoice(
  card: WrittenCard,
  spec: Pick<CardSpec, "voice"> | undefined,
): WrittenCard & { rawMessages?: readonly string[] } {
  if (spec?.voice !== "預設" || !card.messages.some((m) => m.includes("妳"))) {
    return card;
  }
  return {
    ...card,
    messages: card.messages.map((m) => m.replaceAll("妳", "你")),
    rawMessages: card.messages,
  };
}

/// v3.2 C5（Bruce 10/14）：打分或考題字眼，只記錄、不擋。照他口吻的卡可能用「妳」，比對前換成「你」。
/// 過關、這關、再考慮看看、再考慮帶你是 10/18 盤點補的（Eric 2026-10-18）：黑箱裡「先給妳過關」
///「咖啡這關過了再說」「聊得不錯再考慮帶你去」舊清單抓不到。要改成擋，先要 Bruce 同意。
export const SCORING_WORDS = [
  "加分",
  "扣分",
  "及格",
  "跳級",
  "舉證",
  "證明給我看",
  "重答",
  "給你一次機會",
  "看表現",
  "過關",
  "這關",
  "再考慮看看",
  "再考慮帶你",
] as const;

/// 「這關」只算關卡、考驗的意思：後面接係、於、鍵、心、東時，「關」是另一個詞的開頭
///（關係、關於、關鍵、關心、關東煮），比對前先拿掉。
const ZHE_GUAN_COMPOUND = /這關(?=[係於鍵心東])/gu;

export function scoringWords(text: string): string[] {
  const t = text.replaceAll("妳", "你").replace(ZHE_GUAN_COMPOUND, "");
  return SCORING_WORDS.filter((w) => t.includes(w));
}

/// C5 的「欠」組（Bruce 第 6 節不收「欠我」「欠著」；Eric 2026-10-18 決定這組改成不送）：
/// 卡片讓她欠他一杯、先欠著，就拿掉那一張，其他卡照送。黑箱量過：舊版 1,799 張與 v3 1,401 張
/// 裡擋對 11 張、誤擋 0。「欠缺」「欠自己的覺」不算。照他口吻的「妳」比對前換成「你」。
export const DEBT_FRAME_WORDS = ["欠我", "欠著", "你欠"] as const;

export function debtFrameHits(text: string): string[] {
  const t = text.replaceAll("妳", "你").replaceAll("你欠缺", "");
  return DEBT_FRAME_WORDS.filter((w) => t.includes(w));
}

/// C5 只記錄、不擋的卡片檢查（Eric 2026-10-18 補齊 C5 要記的項目）：只有數字與真假，不放
/// 文字，存進 trace 與 outcome log。
export interface CardChecks {
  readonly slot: number;
  /// 問句數（連在一起的問號算一個）。
  readonly questions: number;
  /// 最後一則用「你呢」收尾。
  readonly endsWithNiNe: boolean;
  readonly emoji: number;
  /// 字數（各則加總，不算空白）；跟她最後一輪的字數比，看份量相不相當。
  readonly chars: number;
  /// 照他口吻的卡有沒有照抄他說過的話（連續 8 字以上）；預設口吻的卡不檢查，是 null。
  readonly copiesHim: boolean | null;
  /// 推進卡的最後一則用請求句收尾（REQUEST_ENDINGS）；不是推進卡是 null。
  readonly endsWithRequest: boolean | null;
  /// 推進卡裡任何一句用請求句收尾，例如「週六兩點可以嗎？我來訂位」：盤點的 4/58 是這樣算的，
  /// 其中 3 張的請求句不在最後。不是推進卡是 null。
  readonly hasRequest: boolean | null;
  /// 像說明書條目編號（B44）的字串出現幾次。「B12 維他命」也會算到，所以只記錄、不拿掉卡。
  readonly internalIds: number;
}

const EMOJI = /\p{Extended_Pictographic}/gu;
/// 比對前把一整個表情換成空白（主審 r1 P3）：數字鍵帽是「1」加 U+FE0F、U+20E3，只拿掉表情字會
/// 留下數字；旗幟的標籤字元、變體選擇符、ZWJ、膚色也要一起拿掉。換成空白，表情夾在兩句中間時
/// 還是斷句的位置。表情個數（emoji）照舊只數表情字。
const EMOJI_SEQUENCE =
  /[0-9#*]\u{FE0F}?\u{20E3}|\p{Extended_Pictographic}|\p{Regional_Indicator}|\p{Emoji_Modifier}|[\u{FE0E}\u{FE0F}\u{200D}\u{20E3}\u{E0020}-\u{E007F}]/gu;

function withoutEmoji(text: string): string {
  return text.replace(EMOJI_SEQUENCE, " ");
}
const ENDS_WITH_NI_NE = /[你妳]呢[？?！!～~。…\s]*$/u;
const COPY_RUN = 8;

/// 推進卡的請求句（說明書 A5 不用請求句收尾；Eric 2026-10-18 先記錄、不擋）：一句話以這些說法
/// 收尾就算。只給次數用，清單刻意精簡：盤點列的六個、其中幾個的「A 不 A」問法，加上 A5 自己
/// 舉的「會不會太突然」。「要不要一起去」這種請求放在開頭的問句不算。
export const REQUEST_ENDINGS = [
  "可以嗎",
  "可不可以",
  "好嗎",
  "好不好",
  "行嗎",
  "方便嗎",
  "方不方便",
  "怎麼樣",
  "要不要",
  "會不會太突然",
] as const;

/// 標點、符號（大部分表情屬於這類）、表情的變體選擇符與連接符、空白。
const NON_TEXT_CLASS = String.raw`[\p{P}\p{S}\p{M}\s\u200d]`;
const TRAILING_NON_TEXT = new RegExp(`${NON_TEXT_CLASS}+$`, "u");
const NON_TEXT = new RegExp(NON_TEXT_CLASS, "gu");
/// 請求句：清單裡的說法後面接標點、表情、空白，或在一則的結尾。
const REQUEST_CLAUSE = new RegExp(
  `(?:${REQUEST_ENDINGS.join("|")})(?=${NON_TEXT_CLASS}|$)`,
  "u",
);

/// 說明書條目編號的形狀：B 加兩位數字，前後不接英文字母或數字（B612、AB12 不算）。
const INTERNAL_ID = /(?<![A-Za-z0-9])B\d{2}(?![A-Za-z0-9])/g;

/// 同一組卡開頭重複只比第一則的前幾個字。
export const OPENING_CHARS = 4;

/// 字數：不算空白。
export function charCount(text: string): number {
  return [...text.replace(/\s+/gu, "")].length;
}

function copiesAny(
  messages: readonly string[],
  source: readonly string[],
): boolean {
  const pool = source.map((m) => m.replace(/\s+/gu, "")).filter((m) =>
    [...m].length >= COPY_RUN
  );
  if (pool.length === 0) return false;
  return messages.some((message) => {
    const chars = [...message.replace(/\s+/gu, "")];
    for (let i = 0; i + COPY_RUN <= chars.length; i++) {
      const run = chars.slice(i, i + COPY_RUN).join("");
      if (pool.some((m) => m.includes(run))) return true;
    }
    return false;
  });
}

/// hisMessages：他在對話裡傳過的原始訊息（不含引用前綴）。
export function cardChecks(
  slot: number,
  messages: readonly string[],
  spec: Pick<CardSpec, "voice" | "task">,
  hisMessages: readonly string[],
): CardChecks {
  const last = withoutEmoji(messages.at(-1) ?? "").trim();
  const lastCore = last.replace(TRAILING_NON_TEXT, "");
  return {
    slot,
    questions: messages.reduce(
      (n, m) => n + (m.match(/[？?]+/g)?.length ?? 0),
      0,
    ),
    endsWithNiNe: ENDS_WITH_NI_NE.test(last),
    emoji: messages.reduce((n, m) => n + (m.match(EMOJI)?.length ?? 0), 0),
    chars: messages.reduce((n, m) => n + charCount(m), 0),
    copiesHim: spec.voice === "照他" ? copiesAny(messages, hisMessages) : null,
    endsWithRequest: spec.task === "推進"
      ? REQUEST_ENDINGS.some((w) => lastCore.endsWith(w))
      : null,
    hasRequest: spec.task === "推進"
      ? messages.some((m) => REQUEST_CLAUSE.test(withoutEmoji(m)))
      : null,
    internalIds: messages.reduce(
      (n, m) => n + (m.normalize("NFKC").match(INTERNAL_ID)?.length ?? 0),
      0,
    ),
  };
}

/// 同一組卡開頭重複（說明書 C4 不允許；Eric 2026-10-18 先記錄、不擋）：每張送出的卡取第一則，
/// 去掉表情、標點與空白（「妳」當成「你」）後的前 4 個字，跟前面某一張一樣就算一張。第一則
/// 沒有字可比（只有表情或標點）的卡不算。cards：送出的卡依送出順序，各自的訊息。
export function sameOpeningCount(
  cards: readonly (readonly string[])[],
): number {
  const seen = new Set<string>();
  let same = 0;
  for (const messages of cards) {
    const text = withoutEmoji(messages[0] ?? "").replaceAll("妳", "你")
      .replace(NON_TEXT, "");
    const opening = [...text].slice(0, OPENING_CHARS).join("");
    if (!opening) continue;
    if (seen.has(opening)) same++;
    else seen.add(opening);
  }
  return same;
}
