// 測試用：外洩哨兵的各種照抄寫法（主審兩輪 P2，Eric 2026-10-18）。只給測試 import，不進任何 function。
//
// 每句哨兵產生：原樣、每個字後面插空白、簡體、簡體插空白、簡體再轉回繁體（輸出整理就是這樣轉）、
// 轉回繁體再插空白；再夾進幾種一般句子裡。
import OpenCCSimplified from "npm:opencc-js@1.4.1/t2cn";
import OpenCCTraditional from "npm:opencc-js@1.4.1/cn2t";
import { toTraditionalChinese } from "./traditional_chinese.ts";

// 簡體有兩種轉法，模型兩種都可能寫：台灣繁體轉簡體（「留著」→「留着」）、OpenCC 標準繁體轉簡體
// （「著」照留）。
const SIMPLIFIERS: readonly ((text: string) => string)[] = [
  OpenCCSimplified.Converter({ from: "tw", to: "cn" }),
  OpenCCSimplified.Converter({ from: "t", to: "cn" }),
];

// 轉回繁體也有兩種：輸出整理用的那一支（會改詞，「用戶」→「使用者」），和不改詞的 OpenCC 原版。
const TRADITIONALIZERS: readonly ((text: string) => string)[] = [
  toTraditionalChinese,
  OpenCCTraditional.Converter({ from: "cn", to: "tw" }),
];

/// 每個字後面插一個空白。
export function spaced(text: string): string {
  return [...text].map((c) => `${c} `).join("");
}

/// 一句哨兵的所有照抄寫法（去掉重複）。
export function leakVariants(sentinel: string): string[] {
  const simplified = SIMPLIFIERS.map((toSimplified) => toSimplified(sentinel));
  const roundTrip = simplified.flatMap((s) =>
    TRADITIONALIZERS.map((toTraditional) => toTraditional(s))
  );
  return [
    ...new Set(
      [sentinel, ...simplified, ...roundTrip].flatMap((v) => [v, spaced(v)]),
    ),
  ];
}

/// 夾哨兵的一般句子：標點隔開、緊貼中文（繁體與簡體）、單獨一句、前後換行。
export const LEAK_CONTEXTS: readonly ((variant: string) => string)[] = [
  (v) => `好啊，${v}，週六見`,
  (v) => `我覺得${v}這樣比較好`,
  (v) => `我觉得${v}这样比较好`,
  (v) => v,
  (v) => `\n${v}\n`,
];

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
