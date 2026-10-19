// 測試用：外洩哨兵的各種照抄寫法（主審兩輪 P2，Eric 2026-10-18）。只給測試 import，不進任何 function。
//
// 每句哨兵產生：原樣、每個字後面插空白、簡體、簡體插空白、簡體再轉回繁體（輸出整理就是這樣轉）、
// 轉回繁體再插空白；再夾進幾種一般句子裡，或接上剛好跟頭尾的字湊成詞的字（主審 r2 P2）。
import OpenCCSimplified from "npm:opencc-js@1.4.1/t2cn";
import OpenCCTraditional from "npm:opencc-js@1.4.1/cn2t";
import {
  GUIDE_V3_SENTINELS,
  GUIDE_V3_SENTINELS_NORMALIZED,
} from "../analyze-chat/guide_v3/finalize.ts";
import {
  GUIDE_V3_REFINE_SENTINELS,
  GUIDE_V3_REFINE_SENTINELS_NORMALIZED,
} from "../analyze-chat/guide_v3/refine_card.ts";
import {
  RELATION_SENTINELS,
  RELATION_SENTINELS_NORMALIZED,
} from "../analyze-chat/guide_v3/relation.ts";
import { OPENER_FLOW_PROMPT_SENTINELS } from "../analyze-chat/opener_flow_prompt.ts";
import {
  ANALYZE_CHAT_PROMPT_SENTINELS,
  NEW_TOPIC_SLOTS_PROMPT_SENTINELS,
} from "../analyze-chat/prompt_leak.ts";
import { COACH_PROMPT_LEAK_SENTINELS } from "../coach-chat/validate.ts";
import { MOMENT_PROMPT_SENTINELS } from "../practice-chat/moments_prompt.ts";
import { compactForLeakScan, DIRECTIVE_SENTINEL } from "./prompt_leak_guard.ts";
import { toTraditionalChinese } from "./traditional_chinese.ts";

/// 每一份外洩哨兵清單。
export const SENTINEL_LISTS: Readonly<Record<string, readonly string[]>> = {
  // 對話分析（含 v3 讀局面、寫卡）
  ANALYZE_CHAT_PROMPT_SENTINELS,
  NEW_TOPIC_SLOTS_PROMPT_SENTINELS,
  OPENER_FLOW_PROMPT_SENTINELS,
  // v3 說明書每一節的第一行，和它整理（簡轉繁）過的那一份
  GUIDE_V3_SENTINELS,
  GUIDE_V3_SENTINELS_NORMALIZED,
  // v3 讀局面多的關係狀態那一段（開關開才比），和它整理過的那一份
  RELATION_SENTINELS,
  RELATION_SENTINELS_NORMALIZED,
  // 再調一下，和它整理過的那一份
  GUIDE_V3_REFINE_SENTINELS,
  GUIDE_V3_REFINE_SENTINELS_NORMALIZED,
  COACH_PROMPT_LEAK_SENTINELS,
  // 練習室動態
  MOMENT_PROMPT_SENTINELS,
  // 保密指示的片段：每次都會比
  DIRECTIVE: [DIRECTIVE_SENTINEL],
};

type Convert = (text: string) => string;

// 簡體有兩種轉法，模型兩種都可能寫：台灣繁體轉簡體（「留著」→「留着」）、OpenCC 標準繁體轉簡體
// （「著」照留）。
const SIMPLIFIERS: readonly Convert[] = [
  OpenCCSimplified.Converter({ from: "tw", to: "cn" }),
  OpenCCSimplified.Converter({ from: "t", to: "cn" }),
];

// 轉回繁體也有兩種：輸出整理用的那一支（會改詞，「用戶」→「使用者」），和不改詞的 OpenCC 原版。
const TRADITIONALIZERS: readonly Convert[] = [
  toTraditionalChinese,
  OpenCCTraditional.Converter({ from: "cn", to: "tw" }),
];

// 原樣、簡體、簡體再轉回繁體。
const COPY_CONVERSIONS: readonly Convert[] = [
  (text) => text,
  ...SIMPLIFIERS,
  ...SIMPLIFIERS.flatMap((toSimplified) =>
    TRADITIONALIZERS.map((toTraditional) => (text: string) =>
      toTraditional(toSimplified(text))
    )
  ),
];

/// 每個字後面插一個空白。
export function spaced(text: string): string {
  return [...text].map((c) => `${c} `).join("");
}

function withSpaced(copies: readonly string[]): string[] {
  return [...new Set(copies.flatMap((v) => [v, spaced(v)]))];
}

/// 一句哨兵沒插空白的照抄寫法（去掉重複）。
export function copyForms(sentinel: string): string[] {
  return [...new Set(COPY_CONVERSIONS.map((convert) => convert(sentinel)))];
}

/// 一句哨兵的所有照抄寫法（去掉重複）。
export function leakVariants(sentinel: string): string[] {
  return withSpaced(copyForms(sentinel));
}

/// 逐字轉換得到的照抄寫法：整句轉的結果跟一個字一個字轉再接起來一樣，沒有用到詞組規則
/// （「回覆」→「回复」）或產品用詞（「用戶」→「使用者」）。只差在每個字的寫法。
export function charByCharVariants(sentinel: string): string[] {
  return withSpaced(
    COPY_CONVERSIONS
      .filter((convert) =>
        convert(sentinel) === [...sentinel].map(convert).join("")
      )
      .map((convert) => convert(sentinel)),
  );
}

/// 夾哨兵的一般句子：標點隔開、緊貼中文（繁體與簡體）、單獨一句、前後換行。
export const LEAK_CONTEXTS: readonly ((variant: string) => string)[] = [
  (v) => `好啊，${v}，週六見`,
  (v) => `我覺得${v}這樣比較好`,
  (v) => `我觉得${v}这样比较好`,
  (v) => v,
  (v) => `\n${v}\n`,
];

interface PhraseHalves {
  /// 詞的後半 → 可以接在前面的前半
  readonly headsByTail: ReadonlyMap<string, readonly string[]>;
  /// 詞的前半 → 可以接在後面的後半
  readonly tailsByHead: ReadonlyMap<string, readonly string[]>;
  readonly maxLength: number;
}

let phraseHalves: PhraseHalves | null = null;

// 轉換路徑上的每一本詞組字典：簡轉繁（含台灣異體）、台灣繁體轉簡體，加上產品用詞
// （_shared/traditional_chinese.ts 的 PRODUCT_TERMS）。每個詞從每個位置切成前後兩半。
function halves(): PhraseHalves {
  if (phraseHalves) return phraseHalves;
  const dictionaries = [
    ...OpenCCTraditional.Locale.from.cn,
    ...OpenCCTraditional.Locale.to.tw,
    ...OpenCCSimplified.Locale.from.tw,
    ...OpenCCSimplified.Locale.to.cn,
  ].flat().filter((d): d is string => typeof d === "string");
  const phrases = new Set(["用戶", "軟件", "信息", "神秘"]);
  for (const dictionary of dictionaries) {
    for (const entry of dictionary.split("|")) {
      const phrase = entry.split(" ")[0];
      if ([...phrase].length >= 2) phrases.add(phrase);
    }
  }
  const headsByTail = new Map<string, string[]>();
  const tailsByHead = new Map<string, string[]>();
  const add = (map: Map<string, string[]>, key: string, value: string) => {
    const list = map.get(key);
    if (list) list.push(value);
    else map.set(key, [value]);
  };
  let maxLength = 0;
  for (const phrase of phrases) {
    const chars = [...phrase];
    maxLength = Math.max(maxLength, chars.length);
    for (let i = 1; i < chars.length; i++) {
      const head = chars.slice(0, i).join("");
      const tail = chars.slice(i).join("");
      add(headsByTail, tail, head);
      add(tailsByHead, head, tail);
    }
  }
  phraseHalves = { headsByTail, tailsByHead, maxLength };
  return phraseHalves;
}

/// 詞組跨過哨兵頭尾的句子：詞的前半接在照抄寫法前面、後半接在後面，剛好跟頭尾的字湊成一個詞。
export function phraseStraddles(variant: string): string[] {
  const { headsByTail, tailsByHead, maxLength } = halves();
  const chars = [...compactForLeakScan(variant)];
  const texts: string[] = [];
  for (let n = 1; n < Math.min(maxLength, chars.length); n++) {
    const first = chars.slice(0, n).join("");
    const last = chars.slice(chars.length - n).join("");
    for (const head of headsByTail.get(first) ?? []) texts.push(head + variant);
    for (const tail of tailsByHead.get(last) ?? []) texts.push(variant + tail);
  }
  return texts;
}

/// 緊接在照抄寫法後面、能跟它最後一個字湊成詞的字（最後一個字不在任何詞開頭就沒有）。
export function phraseTails(variant: string): readonly string[] {
  const chars = [...compactForLeakScan(variant)];
  return halves().tailsByHead.get(chars[chars.length - 1] ?? "") ?? [];
}

/// 固定種子的亂數漢字串（每次跑都一樣），給逐字比對的性質測試當前後文。
export function seededHanRuns(seed: number): (maxLength: number) => string {
  let state = seed >>> 0;
  const next = () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  // 中日韓統一表意文字基本區 U+4E00–U+9FFF。
  const hanChar = () =>
    String.fromCodePoint(0x4e00 + Math.floor(next() * 0x5200));
  return (maxLength) => {
    const length = 1 + Math.floor(next() * maxLength);
    return Array.from({ length }, hanChar).join("");
  };
}

/// 一般聊天（繁體與簡體）：有些跟哨兵共用詞（資料、順序、用戶、分段、合併、留著），但都不是整句照抄。
export const ORDINARY_CHAT: readonly string[] = [
  "妳感覺是那種下班還很有精神的人？",
  "这个周末一起去看展吗？",
  "我覺得資料整理的順序可以再調一下",
  "我觉得资料整理的顺序可以再调一下",
  "用戶說分段有點亂，我再看看怎麼排",
  "用户说分段有点乱，我再看看怎么排",
  "兩張照片不要合併，分開傳比較自然",
  "两张照片不要合并，分开发比较自然",
  "她這一輪回得很快，訊息也比上次長",
  "她这一轮回得很快，信息也比上次长",
  "這是你發的動態嗎？背景好好看",
  "这是你发的动态吗？背景好好看",
  "可以留著當紀念，下次再一起去",
  "可以留着当纪念，下次再一起去",
  "先回應她剛說的事，再講你自己的想法",
  "先回应她刚说的事，再讲你自己的想法",
  "你是我見過最會聊天的人",
  "只輸出一個想法：週六見面吧",
];
