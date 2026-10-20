// 口吻與斷句交給程式（開關 ANALYZE_GUIDE_V3_TYPING_STYLE，Bruce 2026-10-20 改法 3）：卡片打字像寫作文
//（九成用逗號、句尾有句號），稱呼也跟他平常打的不一樣。從他自己傳過的訊息看兩件事——稱呼打「你」
// 還是「妳」、斷句用逗號還是空白（句尾有沒有句號）——再把同一組每張卡的每一則照他的習慣統一。
// 只換稱呼與標點，不重新生成、不增減則數。純函式，不碰模型與資料庫。
//
// 規則（數字與字表都在下面的常數，Bruce 可以調）：
// - 稱呼：他打過「你」或「妳」就照他（多數；一樣多當沒有）；沒有就用「你」（說明書預設口吻的稱呼；
//   卡是一張一張串流送出的，第一張送出時還看不到整組，Eric 2026-10-20 定）。引號裡的字、迷你這類
//   不是稱呼的詞不動；你們、妳們跟著換。
// - 斷句：他不是明顯用逗號斷句的人，句子中間的逗號換成一個空白、一則中間的句號也換成空白；他不是明顯
//   會在句尾打句號的人，一則最後的句號拿掉。頓號、問號、驚嘆號、～、…、表情、1,000、3.5、網址都不動；
//   連打的句號（。。。）當刪節號不動；引號裡的字不動。換完之後，引號外連在一起的空白併成一個、
//   頭尾修掉（引號裡的空白照原樣）；一則換完變空的就照原文。
import { isMediaLine, QUOTED_REPLY_PREFIX } from "./rules.ts";

export type Address = "你" | "妳";

/// 他沒有稱呼習慣時用的稱呼（說明書預設口吻：稱呼一律用「你」）。
export const DEFAULT_ADDRESS: Address = "你";
/// 「明顯的習慣」：他至少有這麼多則這樣打……
export const HIS_HABIT_MIN_MESSAGES = 2;
/// ……而且至少佔這個比例（逗號：佔他「句子中間有斷開」的訊息；句號：佔他全部有字的訊息）。
export const HIS_HABIT_MIN_SHARE = 1 / 3;
/// 裡面有「你」但不是稱呼的詞：不換。
export const NOT_PRONOUN_WORDS: readonly string[] = ["迷你"];
/// 引號（開、關）；半形的 " 開關是同一個字，另外處理。
export const QUOTE_PAIRS: readonly (readonly [string, string])[] = [
  ["「", "」"],
  ["『", "』"],
  ["“", "”"],
];

export interface TypingHabits {
  /// 他自己打的稱呼（多數）；沒打過或一樣多是 null。
  readonly address: Address | null;
  /// 他明顯用逗號斷句：逗號與一則中間的句號都照留。
  readonly usesCommas: boolean;
  /// 他明顯會在一則最後打句號：句尾的句號照留。
  readonly endsWithPeriod: boolean;
  /// 拿來判斷的他的訊息則數（去掉照片、貼圖、空白）。
  readonly messages: number;
}

/// 改了什麼（只有次數，不放字）。
export interface TypingChanges {
  /// 換掉的稱呼個數。
  readonly address: number;
  /// 換成空白的逗號個數。
  readonly commas: number;
  /// 換成空白的一則中間的句號個數。
  readonly innerPeriods: number;
  /// 拿掉的句尾句號個數。
  readonly finalPeriods: number;
  /// 有改到的訊息則數。
  readonly messages: number;
}

export const NO_TYPING_CHANGES: TypingChanges = {
  address: 0,
  commas: 0,
  innerPeriods: 0,
  finalPeriods: 0,
  messages: 0,
};

export function addTypingChanges(
  a: TypingChanges,
  b: TypingChanges,
): TypingChanges {
  return {
    address: a.address + b.address,
    commas: a.commas + b.commas,
    innerPeriods: a.innerPeriods + b.innerPeriods,
    finalPeriods: a.finalPeriods + b.finalPeriods,
    messages: a.messages + b.messages,
  };
}

const HAN = /\p{Script=Han}/u;
const DIGIT = /\p{Nd}/u;
/// 網址與 email 整段不動：http(s)://（大小寫都算）、www. 開頭的、email（主審第 1 輪 P2：原本只認小寫的
/// http(s)://，HTTPS://…/你好、www.…/你好 的「你」會被換掉）。
const URL = /(?:https?:\/\/|www\.)\S+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+/giu;
const SPACE_BREAK = /\p{Script=Han}[ \u3000]+\S|\S[ \u3000]+\p{Script=Han}/u;

/// 每個字是不是在引號裡（引號本身不算在裡面）、是不是在網址或「不是稱呼的詞」裡（都不動）。
function protectedMap(chars: readonly string[]): {
  inQuote: boolean[];
  frozen: boolean[];
} {
  const text = chars.join("");
  const inQuote: boolean[] = [];
  const frozen: boolean[] = Array(chars.length).fill(false);
  const closers = new Map(QUOTE_PAIRS.map(([open, close]) => [close, open]));
  const openers = new Set(QUOTE_PAIRS.map(([open]) => open));
  const stack: string[] = [];
  let ascii = false;
  for (const c of chars) {
    if (openers.has(c)) {
      inQuote.push(stack.length > 0 || ascii);
      stack.push(c);
    } else if (closers.has(c) && stack.at(-1) === closers.get(c)) {
      stack.pop();
      inQuote.push(stack.length > 0 || ascii);
    } else if (c === '"') {
      inQuote.push(stack.length > 0);
      ascii = !ascii;
    } else {
      inQuote.push(stack.length > 0 || ascii);
    }
  }
  // 網址與 email、不是稱呼的詞：以字（code point）為單位標記。
  const marks: [number, number][] = [];
  for (const m of text.matchAll(URL)) marks.push([m.index!, m[0].length]);
  for (const word of NOT_PRONOUN_WORDS) {
    let at = text.indexOf(word);
    while (at !== -1) {
      marks.push([at, word.length]);
      at = text.indexOf(word, at + word.length);
    }
  }
  if (marks.length > 0) {
    // 字串位置（UTF-16）換成字的位置。
    const startOf: number[] = [];
    let offset = 0;
    for (const c of chars) {
      startOf.push(offset);
      offset += c.length;
    }
    for (const [start, length] of marks) {
      chars.forEach((_, i) => {
        if (startOf[i] >= start && startOf[i] < start + length) {
          frozen[i] = true;
        }
      });
    }
  }
  return { inQuote, frozen };
}

/// i 前面（往前跳過空白）第一個字；沒有是 ""。
function prevNonSpace(chars: readonly string[], i: number): string {
  for (let j = i - 1; j >= 0; j--) if (chars[j].trim()) return chars[j];
  return "";
}

function nextNonSpace(chars: readonly string[], i: number): string {
  for (let j = i + 1; j < chars.length; j++) {
    if (chars[j].trim()) return chars[j];
  }
  return "";
}

/// 句子中間的逗號：全形「，」（不在兩個數字中間），或半形「,」旁邊是漢字（1,000 不算）。
function isClauseComma(chars: readonly string[], i: number): boolean {
  const c = chars[i];
  if (c !== "，" && c !== ",") return false;
  const prev = prevNonSpace(chars, i);
  const next = nextNonSpace(chars, i);
  if (DIGIT.test(prev) && DIGIT.test(next)) return false;
  return c === "，" || HAN.test(prev) || HAN.test(next);
}

function isFinal(chars: readonly string[], i: number): boolean {
  for (let j = i + 1; j < chars.length; j++) if (chars[j].trim()) return false;
  return true;
}

/// 連打的句號（。。、。。。）：當刪節號，不動。
function inPeriodRun(chars: readonly string[], i: number): boolean {
  return chars[i - 1] === "。" || chars[i + 1] === "。";
}

/// 他這一則本身（拿掉引用前綴）；照片、貼圖、只有表情的不算。
function hisText(content: string): string | null {
  const text = content.replace(QUOTED_REPLY_PREFIX, "").trim();
  return text && !isMediaLine(text) ? text : null;
}

/// 從他傳過的訊息看習慣（只看他的，不看她的）。
export function detectTypingHabits(
  hisMessages: readonly string[],
): TypingHabits {
  const texts = hisMessages.map(hisText).filter((t): t is string => t !== null);
  let you = 0;
  let youF = 0;
  let commaMessages = 0;
  let multiClause = 0;
  let periodEnds = 0;
  for (const text of texts) {
    const chars = [...text];
    const { inQuote, frozen } = protectedMap(chars);
    let hasComma = false;
    let hasInnerPeriod = false;
    chars.forEach((c, i) => {
      if (inQuote[i] || frozen[i]) return;
      if (c === "你") you++;
      else if (c === "妳") youF++;
      else if (isClauseComma(chars, i)) hasComma = true;
      else if (c === "。" && !isFinal(chars, i) && !inPeriodRun(chars, i)) {
        hasInnerPeriod = true;
      }
    });
    if (hasComma) commaMessages++;
    // 空白斷句與句尾句號也只看他自己打的字：引號裡（沒關上的引號算到這一則結尾）、網址換成一個
    // 不是空白也不是漢字的記號再比（主審第 1 輪 P3：「她說「明天 見」」不算他用空白斷句，
    //「她說「好。」不算他習慣句尾打句號）。
    const own = chars.map((c, i) => inQuote[i] || frozen[i] ? "□" : c).join("");
    if (hasComma || hasInnerPeriod || SPACE_BREAK.test(own)) multiClause++;
    const last = chars.length - 1;
    const lastIsHis = !inQuote[last] && !frozen[last];
    if (
      lastIsHis &&
      ((chars[last] === "。" && !inPeriodRun(chars, last)) ||
        (chars[last] === "." && HAN.test(chars[last - 1] ?? "")))
    ) periodEnds++;
  }
  const habit = (count: number, total: number) =>
    count >= HIS_HABIT_MIN_MESSAGES && count >= total * HIS_HABIT_MIN_SHARE;
  return {
    address: you > youF ? "你" : youF > you ? "妳" : null,
    usesCommas: habit(commaMessages, multiClause),
    endsWithPeriod: habit(periodEnds, texts.length),
    messages: texts.length,
  };
}

/// 這一組卡要用的稱呼：他的習慣，沒有就用預設的「你」。
export function addressFor(habits: TypingHabits): Address {
  return habits.address ?? DEFAULT_ADDRESS;
}

/// 改好的一個字，記著它是不是受保護（引號裡、網址等）。
interface OutChar {
  readonly c: string;
  readonly locked: boolean;
}

/// 換完之後整理空白：只整理沒受保護的字——連在一起的空白併成一個、頭尾的空白修掉；引號裡、網址
/// 這些受保護的字照原樣（主審第 1 輪 P2：原本整則一起併，會把引號裡的「A  B」改成「A B」）。
function tidy(out: readonly OutChar[]): string {
  const kept: OutChar[] = [];
  for (const x of out) {
    const prev = kept.at(-1);
    if (
      !x.locked && x.c === " " && prev && !prev.locked && prev.c === " "
    ) continue;
    kept.push(x);
  }
  const loose = (x: OutChar) => !x.locked && /\s/u.test(x.c);
  let start = 0;
  let end = kept.length;
  while (start < end && loose(kept[start])) start++;
  while (end > start && loose(kept[end - 1])) end--;
  return kept.slice(start, end).map((x) => x.c).join("");
}

/// 一則訊息照他的習慣改；回改好的字與次數。
export function styleMessage(
  message: string,
  habits: TypingHabits,
): { text: string; changes: TypingChanges } {
  const target = addressFor(habits);
  const other: Address = target === "你" ? "妳" : "你";
  const chars = [...message];
  const { inQuote, frozen } = protectedMap(chars);
  let address = 0;
  let commas = 0;
  let innerPeriods = 0;
  let finalPeriods = 0;
  const out: OutChar[] = [];
  const keep = (c: string, locked = false) => out.push({ c, locked });
  chars.forEach((c, i) => {
    if (inQuote[i] || frozen[i]) {
      keep(c, true);
      return;
    }
    if (c === other) {
      keep(target);
      address++;
      return;
    }
    if (!habits.usesCommas && isClauseComma(chars, i)) {
      keep(" ");
      commas++;
      return;
    }
    const final = isFinal(chars, i);
    if (c === "。" && !inPeriodRun(chars, i)) {
      if (!final && !habits.usesCommas) {
        keep(" ");
        innerPeriods++;
        return;
      }
      if (final && !habits.endsWithPeriod) {
        finalPeriods++;
        return;
      }
    }
    if (
      c === "." && final && !habits.endsWithPeriod &&
      HAN.test(chars[i - 1] ?? "")
    ) {
      finalPeriods++;
      return;
    }
    keep(c);
  });
  const changed = address + commas + innerPeriods + finalPeriods > 0;
  const text = changed ? tidy(out) : message;
  // 換完變空的（例如整則只有一個句號）就照原文：則數不能少。
  if (!changed || text === "") {
    return { text: message, changes: NO_TYPING_CHANGES };
  }
  return {
    text,
    changes: {
      address,
      commas,
      innerPeriods,
      finalPeriods,
      messages: text === message ? 0 : 1,
    },
  };
}

/// 一張卡的每一則都照他的習慣改（則數不變）。
export function styleCard(
  messages: readonly string[],
  habits: TypingHabits,
): { messages: string[]; changes: TypingChanges } {
  let changes = NO_TYPING_CHANGES;
  const out = messages.map((m) => {
    const styled = styleMessage(m, habits);
    changes = addTypingChanges(changes, styled.changes);
    return styled.text;
  });
  return { messages: out, changes };
}
