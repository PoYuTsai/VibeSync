// 卡片的「這題」「滿」交給程式（開關 ANALYZE_GUIDE_V3_PHRASE_TIDY；Bruce 2026-10-20 PR #97：「這題」再處理、
// 先看例子再決定，程度的「滿」要寫「蠻」）：提示詞改了兩次都沒變少——她問是不是最好看，卡常先說「這題我不用想」。
// 每張卡定稿、口吻與斷句改完之後、送出之前，照下面兩條改字；不重新生成、不增減則數。純函式，不碰模型與資料庫。
// 「不怪」那條 Bruce 看過例子後決定不用（Bruce 2026-10-21 PR #97：只用這題和蠻），已經拿掉。
//
// 規則（字表都在下面的常數，Bruce 可以調）：
// - 這題：一則裡用空白或標點隔開的一小段，整段剛好是把她的問題當考題、自己沒有內容的說法（QUIZ_FILLERS，
//   例如「這題不用想」），才拿掉；有別的字的（這題當然第一名啊、這題海邊勝出）不確定答案在不在裡面，照原文
//  （主審第 1 輪 P2）。「這題我選你」這種拿掉考題字也通的說法，只拿掉那兩三個字。她自己的訊息就在講題目
//  （HER_QUIZ_WORDS），這一條整個不做。
// - 滿→蠻：「滿」後面整個接著常數表裡兩個字以上的詞（適合、好看、有勇氣……）、前面那個字也不會跟「滿」
//   連成詞（充滿、裝滿、很滿……），才換成「蠻」；滿意、滿足、滿分、滿會費這些不在表裡，所以不動。
// 拿掉之後這一則還要有字（語助詞、表情、顏文字、網址、標點不算），不然照原文；引號裡、網址、顏文字都不動。
import { withoutEmoji } from "./cards.ts";
import { isMediaLine, QUOTED_REPLY_PREFIX } from "./rules.ts";
import { protectedMap, QUOTE_PAIRS } from "./typing_style.ts";

/// 把她的問題當成考題的字（Bruce 2026-10-20 點名「這題」）。
export const QUIZ_MARKERS: readonly string[] = [
  "這題",
  "這一題",
  "這道題",
  "送分題",
  "這個答案",
];
/// 有考題字、但說的不是考題的詞：題材。
export const NOT_QUIZ_WORDS: readonly string[] = ["這題材"];
/// 她的訊息裡有這些字＝她自己在講真的題目（考試、作業），卡片的「這題」說的就是那一題：整條不做。
export const HER_QUIZ_WORDS: readonly string[] = [...QUIZ_MARKERS, "題目"];
/// 這一小段自己就在回答：這些字後面接著答案（這題我選你、這題我答山上）。
export const ANSWER_VERBS = "選投答挑是說";
/// ……後面接的是這些字就不算答案（答得很快、要選的話、能選吧、答案、投票）。
export const NOT_ANSWER_AFTER = "得的了吧啊啦嗎呢喔欸案票";
/// 答案在這一段裡、拿掉考題字也通的說法：只拿掉考題字（這題我選你→我選你、這題我直接投你一票→我直接投你一票）。
export const QUIZ_REWRITE = /(?:這題|這一題|這道題)(?=我(?:直接|就)?[選投])/u;
/// 會整段拿掉的考題說法：自己沒有內容，答案一定在別段（從之前跑過的卡整理，主審第 1 輪 P2：只認整段剛好
/// 是這些，前面可以有欸、啊，後面可以有語助詞與表情）。開頭的「這題」也可以是這一題、這道題。
export const QUIZ_FILLERS: readonly string[] = [
  "這題不用想",
  "這題我不用想",
  "這題根本不用想",
  "這題連想都不用想",
  "這題沒有懸念",
  "這題沒有第二個答案",
  "這題送分",
  "這題我答得很快",
  "這題我直接答",
  "這題要選的話",
  "這種送分題我秒答",
  "這個答案很穩",
];
/// 考題說法前面可以有的語氣詞。
export const QUIZ_FILLER_LEAD: readonly string[] = ["欸", "啊"];

/// 考題說法後面可以接的語助詞。
export const TRAILING_PARTICLES = "啊啦呀喔哦噢欸耶吧的呢嘛唷咧";

/// 「滿」當「很」用時，後面接的形容詞或動詞（Bruce 2026-10-20：蠻適合的、蠻好看的才對）。只收兩個字以上、
/// 整個詞都在這裡的：Bruce 列的詞，加上之前跑過的卡出現過的加分、有勇氣、有氣質、有精神。一個字的（會、想、
/// 像、有、好、多……）常是下一個詞的開頭（行程很滿會累、繳滿會費），不收（主審第 1 輪 P2）。
export const DEGREE_MAN_NEXT: readonly string[] = [
  "適合",
  "好看",
  "好吃",
  "好玩",
  "有趣",
  "可愛",
  "不錯",
  "喜歡",
  "開心",
  "厲害",
  "特別",
  "漂亮",
  "舒服",
  "舒適",
  "期待",
  "合理",
  "自然",
  "清爽",
  "輕鬆",
  "加分",
  "有勇氣",
  "有氣質",
  "有精神",
];
/// 接在「滿」前面會連成一個詞的字（充滿、裝滿、圓滿、美滿、不滿、客滿、期滿、塞滿、坐滿、加滿、年滿、
/// 繳滿、滿滿、小滿……）：這時的「滿」是填滿的意思，不是「很」，後面就算接著表裡的字（充滿期待、裝滿好吃
/// 的）也不換。前面是很、太、好、超、最、更、蠻、挺的「滿」是形容詞（行程很滿），也不換。
export const MAN_COMPOUND_BEFORE =
  "充裝圓美不客期填塞擠坐住爆額自豐飽布佈寫堆灌加倒斟盛長開掛貼排約訂漲盈溢放種站停圍鋪灑撒蓋擺存集買" +
  "年屆任服做待修拿刷儲蓄沾噴載滿小考選刻畫印繡簽抄吸泡浸染爬躺繳很太好超最更蠻挺";
const DEGREE_MAN_NEXT_MAX = Math.max(
  ...DEGREE_MAN_NEXT.map((w) => [...w].length),
);
/// 語助詞、笑聲：拿掉一段之後只剩這些（加上表情、標點）就算沒有字，照原文。
export const FILLER_CHARS =
  "欸嗯喔哦噢啊啦呀耶哈嘿唉齁吼蛤嘛呢吧哇哎唷呦嘻呵咧";
/// 英文字母拼的表情（XD、QQ、QAQ、TT、orz）：跟顏文字一樣不算字。
export const ASCII_EMOTICONS = /^(?:x+d+|q+a?q+|t+_*t+|orz)$/iu;
/// 一則裡隔開小段的空白與標點（口吻與斷句那一步留下的：空白，加上他用逗號時的逗號、句號）。
const SEPARATOR = /[\s，,。.？?！!～~…⋯、：:；;]/u;
const SEPARATOR_RUN = /[\s，,。.？?！!～~…⋯、：:；;]+/u;
/// 拿掉最後一段後，前面留在結尾的這些標點是用來接下一段的，一起拿掉；問號、驚嘆號、～、…、句號是前一段
/// 自己的語氣，留著。
const JOINERS = /[\s，,、：:；;]+$/u;
const LETTER_OR_DIGIT = /[\p{L}\p{N}]/u;
/// 表情（跟 rules.ts 一樣只用 u 旗標：正式環境的 Edge 解析不了 v 旗標）。
const TRAILING_EMOJI =
  "(?:\\p{Extended_Pictographic}|\\p{Emoji_Modifier}|\\u{FE0F}|\\u{200D})*";
const QUOTE_CHARS = new Set(['"', ...QUOTE_PAIRS.flat()]);

export interface PhraseTidyContext {
  /// 她的訊息裡本來就有考題字（她在講真的題目）：「這題」那一條整個不做。
  readonly herQuizWords: boolean;
}

/// 改了什麼（只有次數，不放字）。
export interface PhraseTidyChanges {
  /// 拿掉的考題小段。
  readonly quiz: number;
  /// 答案在裡面、只拿掉考題字的小段。
  readonly quizRewrite: number;
  /// 換成「蠻」的「滿」。
  readonly degree: number;
  /// 有改到的訊息則數。
  readonly messages: number;
}

export const NO_PHRASE_TIDY_CHANGES: PhraseTidyChanges = {
  quiz: 0,
  quizRewrite: 0,
  degree: 0,
  messages: 0,
};

export function addPhraseTidyChanges(
  a: PhraseTidyChanges,
  b: PhraseTidyChanges,
): PhraseTidyChanges {
  return {
    quiz: a.quiz + b.quiz,
    quizRewrite: a.quizRewrite + b.quizRewrite,
    degree: a.degree + b.degree,
    messages: a.messages + b.messages,
  };
}

/// 她這一則本身（拿掉引用前綴）；照片、貼圖、只有表情的不算她說的話。
function herText(content: string): string | null {
  const text = content.replace(QUOTED_REPLY_PREFIX, "").trim();
  return text && !isMediaLine(text) ? text : null;
}

function mask(text: string, words: readonly string[]): string {
  return words.reduce((t, w) => t.split(w).join("□"), text);
}

/// 從她的訊息看她是不是自己就在講題目（只看她的，不看他的）。
export function phraseTidyContext(args: {
  readonly herMessages: readonly string[];
}): PhraseTidyContext {
  const all = args.herMessages.map(herText).filter((t): t is string =>
    t !== null
  );
  return {
    herQuizWords: all.some((t) =>
      HER_QUIZ_WORDS.some((word) => mask(t, NOT_QUIZ_WORDS).includes(word))
    ),
  };
}

function escape(word: string): string {
  return word.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

function alt(words: readonly string[]): string {
  return words.map(escape).join("|");
}

/// 整段剛好是 QUIZ_FILLERS 的一句（開頭的「這題」可以是這一題、這道題）。
const QUIZ_FILLER_PATTERN = new RegExp(
  `^(?:${alt(QUIZ_FILLER_LEAD)})?(?:${
    QUIZ_FILLERS.map((f) =>
      f.startsWith("這題")
        ? `(?:這題|這一題|這道題)${escape(f.slice("這題".length))}`
        : escape(f)
    ).join("|")
  })[${TRAILING_PARTICLES}]*${TRAILING_EMOJI}$`,
  "u",
);

/// 這一小段自己就在回答：有「你／妳」，或「選、投、答……」後面接著答案。
function carriesAnswer(clause: string): boolean {
  if (/[你妳]/u.test(clause)) return true;
  const chars = [...clause];
  return chars.some((c, i) => {
    const next = chars[i + 1];
    return ANSWER_VERBS.includes(c) && next !== undefined &&
      LETTER_OR_DIGIT.test(next) && !NOT_ANSWER_AFTER.includes(next);
  });
}

function isQuizClause(clause: string): boolean {
  const own = mask(clause, NOT_QUIZ_WORDS);
  return QUIZ_MARKERS.some((m) => own.includes(m));
}

/// 還有字：拿掉顏文字、網址這些受保護的整段，與整個表情（數字鍵帽、國旗也算，cards.ts 的 withoutEmoji）
/// 之後，至少一個不是語助詞、笑聲、英文字母表情的字或數字（主審第 1 輪 P2：「(・ω・)」的 ω、「1️⃣」的 1
/// 原本被當成字，拿掉後只剩表情）。不確定的就算沒字，照原文。
function hasContent(text: string): boolean {
  const chars = [...text];
  const { frozen } = protectedMap(chars);
  const bare = withoutEmoji(chars.filter((_, i) => !frozen[i]).join(""));
  return bare.split(SEPARATOR_RUN).some((token) =>
    !ASCII_EMOTICONS.test(token) &&
    [...token].some((c) => LETTER_OR_DIGIT.test(c) && !FILLER_CHARS.includes(c))
  );
}

interface Piece {
  readonly text: string;
  /// 空白或標點（隔開小段的）。
  readonly sep: boolean;
  /// 有受保護的字（引號裡、網址、顏文字）或引號本身：整段不動。
  readonly locked: boolean;
}

/// 一則切成小段與隔開它們的空白、標點；受保護的字不切、也不算標點。
function piecesOf(message: string): Piece[] {
  const chars = [...message];
  const { inQuote, frozen } = protectedMap(chars);
  const pieces: { text: string; sep: boolean; locked: boolean }[] = [];
  chars.forEach((c, i) => {
    const locked = inQuote[i] || frozen[i] || QUOTE_CHARS.has(c);
    const sep = !locked && SEPARATOR.test(c);
    const last = pieces.at(-1);
    if (last && last.sep === sep) {
      last.text += c;
      last.locked ||= locked;
    } else {
      pieces.push({ text: c, sep, locked });
    }
  });
  return pieces;
}

/// 拿掉標好的小段：連同它後面的空白或標點（那是它自己的語氣）；拿掉的是最後一段，前面留在結尾的接續標點
/// 與空白也拿掉。
function withoutPieces(pieces: readonly Piece[], drop: ReadonlySet<number>) {
  const kept: Piece[] = [];
  pieces.forEach((p, i) => {
    if (drop.has(i)) return;
    if (p.sep && drop.has(i - 1)) return;
    kept.push(p);
  });
  const text = kept.map((p) => p.text).join("");
  const last = kept.at(-1);
  return last?.sep ? text.replace(JOINERS, "") : text;
}

/// 程度的「滿」換成「蠻」（受保護的字不動）；回換好的字與個數。
function degreeMan(text: string): { text: string; count: number } {
  const chars = [...text];
  const { inQuote, frozen } = protectedMap(chars);
  let count = 0;
  const out = chars.map((c, i) => {
    if (c !== "滿" || inQuote[i] || frozen[i]) return c;
    const before = chars[i - 1];
    if (before !== undefined && MAN_COMPOUND_BEFORE.includes(before)) return c;
    if (inQuote[i + 1] || frozen[i + 1]) return c;
    const after = chars.slice(i + 1, i + 1 + DEGREE_MAN_NEXT_MAX).join("");
    if (!DEGREE_MAN_NEXT.some((w) => after.startsWith(w))) return c;
    count++;
    return "蠻";
  });
  return { text: count > 0 ? out.join("") : text, count };
}

/// 一則訊息照兩條改；回改好的字與次數。
export function tidyMessage(
  message: string,
  context: PhraseTidyContext,
): { text: string; changes: PhraseTidyChanges } {
  const pieces = piecesOf(message);
  const quizDrops = new Set<number>();
  const rewrites = new Map<number, string>();
  pieces.forEach((p, i) => {
    if (p.sep || p.locked) return;
    if (!context.herQuizWords && isQuizClause(p.text)) {
      // 只拿掉整段剛好是考題空話的；其他有考題字的，只有「這題我選你」這種只拿掉考題字，不然照原文。
      if (QUIZ_FILLER_PATTERN.test(p.text)) quizDrops.add(i);
      else if (carriesAnswer(p.text) && QUIZ_REWRITE.test(p.text)) {
        rewrites.set(i, p.text.replace(QUIZ_REWRITE, ""));
      }
    }
  });
  const rewritten = pieces.map((p, i) =>
    rewrites.has(i) ? { ...p, text: rewrites.get(i)! } : p
  );
  const drop = quizDrops;
  let text = rewritten.map((p) => p.text).join("");
  let dropped = false;
  if (drop.size > 0) {
    const rest = withoutPieces(rewritten, drop);
    // 拿掉之後還要有字；沒有就整則照原文（則數不能少，也不能變成只剩語助詞）。
    if (hasContent(rest)) {
      text = rest;
      dropped = true;
    }
  }
  const man = degreeMan(text);
  text = man.text;
  if (text === "" || text === message) {
    return { text: message, changes: NO_PHRASE_TIDY_CHANGES };
  }
  return {
    text,
    changes: {
      quiz: dropped ? quizDrops.size : 0,
      quizRewrite: rewrites.size,
      degree: man.count,
      messages: 1,
    },
  };
}

/// 一張卡的每一則都照兩條改（則數不變）。
export function tidyCard(
  messages: readonly string[],
  context: PhraseTidyContext,
): { messages: string[]; changes: PhraseTidyChanges } {
  let changes = NO_PHRASE_TIDY_CHANGES;
  const out = messages.map((m) => {
    const tidied = tidyMessage(m, context);
    changes = addPhraseTidyChanges(changes, tidied.changes);
    return tidied.text;
  });
  return { messages: out, changes };
}
