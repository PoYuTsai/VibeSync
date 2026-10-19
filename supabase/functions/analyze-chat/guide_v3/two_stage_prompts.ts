// 兩段式「正常回覆」實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19 兩段式實驗）的提示詞：
// 照 Bruce 10/19「先生成回覆，再用說明書的內容來教」。這裡放開關開了才用的字，開關沒開的
// 提示詞（prompts.ts）一字不動。說明書原文仍只在 guide_text.ts、entries.ts。
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import { GUIDE_V3_SECTIONS, type GuideV3SectionId } from "./guide_text.ts";
import type { GuideV3PreviousRound } from "./previous_round.ts";
import {
  cardMethodText,
  cardTaskText,
  type GuideV3Background,
  readSystemPrompt,
  readUserPrompt,
  WRITE_OUTPUT_FORMAT,
  WRITE_SAFETY_FLOOR,
  writeUserPrompt,
} from "./prompts.ts";
import type { ReadTags } from "./read_tags.ts";
import type { CardSpec } from "./rules.ts";
import { latestHerMessages, type Turn } from "./turns.ts";

/// 讀局面多輸出的四欄，以及作戰板標籤靠不住時怎麼判（研究報告 §5.3、§7.2：v3 把 App 預設的
/// 「交友軟體／剛認識」當事實，真的情侶被當成剛認識、親暱稱呼被標成風險）。
export const READ_TWO_STAGE_NOTES = `## 兩段式多輸出的欄位
- establishedCouple：兩人已經在交往。作戰板寫「已是伴侶」，或對話看得很清楚（她叫他男朋友或老公、聊到住在一起、提到交往多久）才算；還在曖昧不算。
- herAffection：她這一輪在撒嬌或示愛，例如說想他、要抱抱、說愛他、傳愛心或親親。
- herHappyShare：她這一輪在分享開心或得意的事，例如好消息、自己做的料理、剛經歷的一個好時刻。
- worthyLines：她最新這一輪值得接的訊息，一則一項。line 填對話稿上那一則前面的編號；label 用幾個字寫那則在講什麼；kind 填「情感」（撒嬌、示愛，或帶著開心、難過、生氣的情緒）、「照片或貼圖」（照片、貼圖或只有表情符號），其他都填「其他」。單純附和、語助詞，或跟前一則講同一件事的，可以不列。

## 作戰板標籤跟對話對不上時
- 作戰板上的認識方式、認識多久，有可能只是 App 的預設值，不一定是他自己選的。跟對話內容對不上時，照對話判斷。
- 已經在交往的兩人互用親暱的稱呼、撒嬌，是感情好，不是風險。`;

export function readSystemPromptTwoStage(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  return readSystemPrompt(
    sections,
    entries,
    leakDirective,
    READ_TWO_STAGE_NOTES,
  );
}

/// 她最新這一輪逐則編號，worthyLines 才填得出編號。
export function readUserPromptTwoStage(
  turns: readonly Turn[],
  background?: GuideV3Background,
  previousRound?: GuideV3PreviousRound,
): string {
  return readUserPrompt(turns, background, previousRound, true);
}

// ── 寫卡（第 1 段）：只寫正常的回覆 ──────────────────────────────────────────
// 研究 §7.1 的結構刀：寫卡不帶 A1、不帶「每張卡都要有他的態度」與快檢「有他」，帶張力不講「先繃緊
// 再鬆開」、不取封號，推拉不講「推在前、拉收尾」，「「有他」做法」改叫「他的事怎麼寫」。拿掉的段落
// 移到說明步驟（explain.ts）。
// A2、A3、A5 其餘、A6 其餘、條目、安全底線、輸出格式照舊。

/// 寫卡看到的「他的事」標籤（Bruce 原文叫「「有他」做法」，名稱本身會讓模型每張都表態）。
export const TWO_STAGE_METHOD_LABEL = "他的事怎麼寫";

/// 一行一行改說明書原文：startsWith 要在那一節剛好對上一行，edit 回新的一行（null＝刪掉）。
/// 只寫每行開頭幾個字，不在這裡另抄一份原文；對不上就丟錯：Bruce 改了說明書、這裡沒跟著改時，
/// 測試會先失敗，不會悄悄沒拿掉。
export interface LineEdit {
  readonly startsWith: string;
  readonly edit: (line: string) => string | null;
}

export function applyLineEdits(
  section: string,
  edits: readonly LineEdit[],
): string {
  let lines = section.split("\n");
  for (const { startsWith, edit } of edits) {
    const at = lines.flatMap((l, i) => (l.startsWith(startsWith) ? [i] : []));
    if (at.length !== 1) {
      throw new Error(
        `two_stage_prompts: expected one line, found ${at.length}: ${startsWith}`,
      );
    }
    const next = edit(lines[at[0]]);
    lines = next === null
      ? lines.filter((_, i) => i !== at[0])
      : lines.map((l, i) => (i === at[0] ? next : l));
  }
  return lines.join("\n");
}

/// 那一行裡的 from 要剛好出現一次，換成 to。
function replaceOnce(line: string, from: string, to: string): string {
  if (line.split(from).length !== 2) {
    throw new Error(`two_stage_prompts: expected one "${from}" in: ${line}`);
  }
  return line.replace(from, to);
}

/// 只留第一個「；」之前的那半句（後半句要拿掉）。
function keepBeforeSemicolon(line: string): string {
  const cut = line.indexOf("；");
  if (cut === -1) throw new Error(`two_stage_prompts: no "；" in: ${line}`);
  return `${line.slice(0, cut)}。`;
}

/// 項目符號後只留最後一句（前面幾句要拿掉）。
function keepLastSentence(line: string): string {
  const bullet = line.match(/^(\s*- )/)?.[1] ?? "";
  const sentences = line.slice(bullet.length).split("。").filter((x) => x);
  if (sentences.length < 2) {
    throw new Error(`two_stage_prompts: need two sentences in: ${line}`);
  }
  return `${bullet}${sentences.at(-1)}。`;
}

/// 拿掉一條之後，編號重排成 1、2、3…（A6 只有一組編號）。
function renumber(section: string): string {
  let n = 0;
  return section.split("\n").map((l) =>
    /^\d+\. /.test(l) ? l.replace(/^\d+/, String(++n)) : l
  ).join("\n");
}

/// 帶張力的新說法（照 v2「安全的誤讀、反差或輕推拉，保留退路」的精神）：手法與界線沿用 A5
/// 下面原本的幾條（誇張解讀、反差、好笑的類比…；虧事不虧人；她越喜歡他，玩笑越少）。
export const TWO_STAGE_TENSION_LINE =
  "- **帶張力**：開一個輕的玩笑，讓聊天多一點來回；用下面的手法，留好退路，她接了就一起玩，沒接也不尷尬。";

export const TWO_STAGE_A5_EDITS: readonly LineEdit[] = [
  {
    startsWith: "程式會指定每張卡的",
    edit: (l) => replaceOnce(l, "「有他」做法", TWO_STAGE_METHOD_LABEL),
  },
  // 「先繃緊再鬆開」的定義換成上面的新說法；底下的手法與界線照留。
  { startsWith: "- **帶張力**：", edit: () => TWO_STAGE_TENSION_LINE },
  // 取封號那半句拿掉（研究 §3.3：替她定性的來源）。
  { startsWith: "  - 材料從她話裡", edit: keepBeforeSemicolon },
  // 推拉那一條拿掉「用來製造張力」和「推在前、拉收尾…」那一句：跟先繃緊再鬆開是同一個形狀
  //（研究 §3.3、§7.1；Eric 2026-10-19 兩段式實驗），具體手法與界線照留。說明步驟照原文。
  // 兩段字都要剛好出現一次，原文改了就丟錯。
  {
    startsWith: "  - 推拉用來製造張力：",
    edit: (l) =>
      replaceOnce(
        replaceOnce(l, "推拉用來製造張力：", "推拉："),
        "推在前、拉收尾，最後一句決定她讀到的是好感。",
        "",
      ),
  },
  {
    startsWith: "**「有他」做法**",
    edit: () => `**${TWO_STAGE_METHOD_LABEL}**`,
  },
  // 「每張卡都要有他的態度…換誰講都成立」拿掉；最後一句講具體、不講類別，跟表態無關，留著。
  { startsWith: "- 每張卡都要有他的態度", edit: keepLastSentence },
];

export const TWO_STAGE_A6_EDITS: readonly LineEdit[] = [
  {
    startsWith: "2. **照規格**",
    edit: (l) => replaceOnce(l, "「有他」做法", TWO_STAGE_METHOD_LABEL),
  },
  // 快檢「有他：換誰講都成立嗎？」拿掉，後面的編號往前補。
  { startsWith: "3. **有他**", edit: () => null },
];

/// 寫卡看到的 A5、A6（從說明書原文改出來）。
export function twoStageWriterSections(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
): { readonly A5: string; readonly A6: string } {
  return {
    A5: applyLineEdits(sections.A5, TWO_STAGE_A5_EDITS),
    A6: renumber(applyLineEdits(sections.A6, TWO_STAGE_A6_EDITS)),
  };
}

/// 寫卡新加的兩段（我們自己的話；參考 v2 快照 :62-67、:253-257、:553、:566 與 :342-351）。
export const WRITE_NATURAL_RULES = `## 這一步只寫訊息
- 每則訊息都是他可以原封不動傳出去的自然句子，像他平常跟朋友聊天那樣說話。
- 判斷、策略、招式的名稱、對她的評價，以及替自己說明心態或原則的話，都不寫進訊息；為什麼這樣回，下一步會另外說明給用戶。
- 不是每一句都要表態或用上技巧。沒有適合的時機，就像朋友一樣正常聊。`;

export const WRITE_MEDIA_RULES = `## 照片和貼圖
- 她傳照片，是想跟他分享：接她分享的這件事。
- 方括號裡的字是辨識程式寫的照片描述，不是她說的話：不照搬描述裡的用字，也不假裝看到描述以外的東西。
- 貼圖或只有一個表情符號，是她的語氣：跟旁邊那句話一起讀。`;

/// 新加段落的外洩哨兵（只在兩段式寫出來的卡上檢查）：正常的回覆不會出現這些說法。
export const TWO_STAGE_WRITER_SENTINELS: readonly string[] = [
  "原封不動傳出去的自然句子",
  "下一步會另外說明給用戶",
  "辨識程式寫的照片描述",
];

export function writeSystemPromptTwoStage(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  safetyRules: string = WRITE_SAFETY_FLOOR,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  const writer = twoStageWriterSections(sections);
  return [
    "你是 VibeSync 對話分析的「寫句子」步驟：照使用者訊息裡每張卡的規格，寫他可以直接傳給她的訊息。",
    WRITE_NATURAL_RULES,
    sections.A2,
    sections.A3,
    WRITE_MEDIA_RULES,
    writer.A5,
    writer.A6,
    WRITE_OUTPUT_FORMAT,
    safetyRules.trim(),
    leakDirective.trim(),
  ].join("\n\n");
}

/// 條目寫法裡提到「「有他」做法」的（B23），寫卡看到的也換成新名稱。
export function twoStageEntryWriting(entry: GuideV3Entry): string {
  return entry.writing.replaceAll(
    "「有他」做法",
    `「${TWO_STAGE_METHOD_LABEL}」`,
  );
}

/// 她開心分享時換上的那張共鳴：說明書的共鳴是寫她氣頭上或難過時，這張另外講清楚是陪她開心。
export const HAPPY_SHARE_TASK =
  "共鳴（她在分享開心或得意的事：跟她一起高興，具體說出他替她開心的地方）";

const QUOTE_MAX_CHARS = 30;
const QUOTED_REPLY_PREFIX = /^（引用：「[^」]*」）/;

/// 規格裡引她的那一則：去掉引用前綴、空白收成一格，太長就截短。
export function quoteHerLine(content: string): string {
  const text = content.replace(QUOTED_REPLY_PREFIX, "").replace(/\s+/g, " ")
    .trim();
  const chars = [...text];
  return chars.length > QUOTE_MAX_CHARS
    ? `${chars.slice(0, QUOTE_MAX_CHARS - 1).join("")}…`
    : text;
}

/// 兩段式的規格行：任務之後先講這張接她哪一句，「有他」做法改叫「他的事怎麼寫」。
export function cardSpecLineTwoStage(
  spec: CardSpec,
  n: number,
  herLatest: readonly string[],
): string {
  const answers = (spec.lines ?? [])
    .filter((line) => line >= 1 && line <= herLatest.length)
    .map((line) => `「${quoteHerLine(herLatest[line - 1])}」`);
  const parts = [
    `${n}. 任務：${
      spec.note === "happy_share" ? HAPPY_SHARE_TASK : cardTaskText(spec)
    }`,
    ...(answers.length > 0 ? [`這張接：她的${answers.join("和")}`] : []),
    `${TWO_STAGE_METHOD_LABEL}：${cardMethodText(spec)}`,
    `口吻：${spec.voice}`,
    spec.questionBudget === 0 ? "不問問題" : "問句最多 1 個",
  ];
  if (spec.angle > 0) parts.push("切入點要跟前面同規格的卡不同");
  return parts.join("｜");
}

export function writeUserPromptTwoStage(args: {
  readonly turns: readonly Turn[];
  readonly tags: ReadTags;
  readonly entries: readonly GuideV3Entry[];
  readonly cards: readonly CardSpec[];
  readonly background?: GuideV3Background;
  readonly previousRound?: GuideV3PreviousRound;
}): string {
  const herLatest = latestHerMessages(args.turns);
  return writeUserPrompt({
    ...args,
    variant: {
      numberLatestHerTurn: true,
      entryWriting: twoStageEntryWriting,
      specLine: (spec, n) => cardSpecLineTwoStage(spec, n, herLatest),
    },
  });
}
