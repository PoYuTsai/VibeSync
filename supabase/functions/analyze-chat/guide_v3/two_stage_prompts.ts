// 兩段式「正常回覆」實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19 兩段式實驗）的提示詞：
// 照 Bruce 10/19「先生成回覆，再用說明書的內容來教」。這裡放開關開了才用的字，開關沒開的
// 提示詞（prompts.ts）一字不動。說明書原文仍只在 guide_text.ts、entries.ts。
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { normalizeOutgoingScript } from "../outgoing_message_text.ts";
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
import {
  READ_TAGS_SCHEMA_TWO_STAGE,
  READ_TAGS_SCHEMA_TWO_STAGE_SWEET,
  type ReadTags,
} from "./read_tags.ts";
import { RELATION_FIELD_NOTES, withRelationFields } from "./relation.ts";
import {
  type AnswerLine,
  type CardAnswer,
  type CardSpec,
  herLineText,
  type PraiseStyle,
} from "./rules.ts";
import { latestHerMessages, type Turn } from "./turns.ts";

/// 讀局面多輸出的四欄，以及作戰板標籤靠不住時怎麼判（研究報告 §5.3、§7.2：v3 把 App 預設的
/// 「交友軟體／剛認識」當事實，真的情侶被當成剛認識、親暱稱呼被標成風險）。
export const READ_TWO_STAGE_NOTES = `## 兩段式多輸出的欄位
- establishedCouple：兩人已經在交往。作戰板寫「已是伴侶」，或對話看得很清楚（她叫他男朋友或老公、聊到住在一起、提到交往多久）才算；還在曖昧不算。
- herAffection：她這一輪在撒嬌或示愛，例如說想他、要抱抱、說愛他、傳愛心或親親。
- herHappyShare：她這一輪在分享開心或得意的事，例如好消息、自己做的料理、剛經歷的一個好時刻。
- worthyLines：她最新這一輪值得接的訊息，一則一項。line 填對話稿上那一則前面的編號；label 用幾個字寫那則在講什麼；kind 填「問他」（她直接問他、要他的看法，或想聽他說好不好看、厲不厲害）、「情感」（撒嬌、示愛，或帶著開心、難過、生氣的情緒）、「照片或貼圖」（照片、貼圖或只有表情符號），其他都填「其他」；一則同時算問他和情感時填「問他」。單純附和、語助詞，或跟前一則講同一件事的，可以不列。

## 作戰板標籤跟對話對不上時
- 作戰板上的認識方式、認識多久，有可能只是 App 的預設值，不一定是他自己選的。跟對話內容對不上時，照對話判斷。
- 已經在交往的兩人互用親暱的稱呼、撒嬌，是感情好，不是風險。`;

/// 上面那一段的外洩哨兵（主審第 1 輪 P2，Eric 2026-10-20）：兩段式開時，判讀與要等她做什麼照抄這段就
/// 不給，跟照抄說明書、關係訊號那段一樣。照關係訊號的做法（82d379c2）：每句都照抄自上面那段，而且都帶
/// 只有提示詞才會寫的記號（欄位名、line／label／kind 的填法、種類名後面接它的定義、「兩段式…欄位」
///「作戰板標籤」「App 的預設值」）；一般判讀自己也會講的話（「她在撒嬌或示愛」「是感情好，不是風險」）
/// 不當哨兵，不然好好的判讀會被清掉（測試會檢查）。
export const TWO_STAGE_READ_SENTINELS: readonly string[] = [
  "兩段式多輸出的欄位",
  "establishedCouple：兩人已經在交往",
  "herAffection：她這一輪在撒嬌或示愛",
  "herHappyShare：她這一輪在分享開心或得意的事",
  "worthyLines：她最新這一輪值得接的訊息",
  "line 填對話稿上那一則前面的編號",
  "label 用幾個字寫那則在講什麼",
  "kind 填「問他」（她直接問他、要他的看法",
  "「情感」（撒嬌、示愛，或帶著開心、難過、生氣的情緒）",
  "「照片或貼圖」（照片、貼圖或只有表情符號）",
  "一則同時算問他和情感時填「問他」",
  "作戰板標籤跟對話對不上時",
  "有可能只是 App 的預設值，不一定是他自己選的",
];

/// 跟說明書、關係訊號的哨兵一樣再做一份簡轉繁整理過的（判讀整理後才比的那一次要用）。
export const TWO_STAGE_READ_SENTINELS_NORMALIZED: readonly string[] =
  TWO_STAGE_READ_SENTINELS.map((s) => normalizeOutgoingScript(s) ?? s);

/// 兩段式開時交給 vetPlanText 多比的哨兵（原樣與整理過的，去掉重複）。
export const TWO_STAGE_READ_LEAK_SENTINELS: readonly string[] = [
  ...new Set([
    ...TWO_STAGE_READ_SENTINELS,
    ...TWO_STAGE_READ_SENTINELS_NORMALIZED,
  ]),
];

/// 讀局面兩段式的欄位說明：甜話短回開時 worthyLines 那一條換成多「撒嬌」的寫法、不記帳不承諾開時 herAffection 下面多 herTired
/// 那一行（readTwoStageNotes），都沒開跟今天一字不差。
export function readSystemPromptTwoStage(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
  options: { readonly sweetShort?: boolean; readonly noIou?: boolean } = {},
): string {
  return readSystemPrompt(
    sections,
    entries,
    leakDirective,
    readTwoStageNotes(options),
  );
}

/// 關係訊號（relation.ts，開關 ANALYZE_GUIDE_V3_RELATION）也開時：兩段式的欄位說明之後接關係那段，
/// schema 在兩段式的四欄之後再接關係三欄，關係的欄位照它自己的設計排在最後（Eric 2026-10-20 兩邊都上線）。
export function readSystemPromptTwoStageWithRelation(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
  options: { readonly sweetShort?: boolean; readonly noIou?: boolean } = {},
): string {
  return readSystemPrompt(
    sections,
    entries,
    leakDirective,
    `${readTwoStageNotes(options)}\n\n${RELATION_FIELD_NOTES}`,
  );
}

export const READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION = withRelationFields(
  READ_TAGS_SCHEMA_TWO_STAGE,
);

/// 甜話短回開時（關係訊號也開）：schema 照兩段式甜話短回那一份，關係三欄一樣接在最後。
export const READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION =
  withRelationFields(READ_TAGS_SCHEMA_TWO_STAGE_SWEET);

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
// ── 帶張力改寫法 v2（開關 ANALYZE_GUIDE_V3_TENSION_STYLE，Bruce 2026-10-21「改」）──────────────────────
// 第 4 輪換掉帶張力的定義、材料與手法（玩笑只對事情本身），Bruce 盲選 3:6 輸（PR #97 issuecomment-6295195588）：
// 他留下的舊版是輕輕虧她、拐個彎誇她，那一版連這種也拿掉了。v2 照兩段式原本的寫法，推拉那一條拿掉，換成三條
// 不要：不打分、不說她別有用意、不擺自己比較厲害（Bruce 2026-10-21「改」，issuecomment-6306094638）。開關開時
// 在兩段式的 A5 之上只改這一行；排卡不變。

/// 推拉那一條的位置（虧事不虧人之後、力道看她之前）換成這一行。
export const TENSION_STYLE_LINE =
  "  - 不替她打分、不說她別有用意、不把自己擺得比較厲害。";

export const TENSION_STYLE_A5_EDITS: readonly LineEdit[] = [
  { startsWith: "  - 推拉：", edit: () => TENSION_STYLE_LINE },
];

/// 卡片多比的外洩哨兵（上面那一行裡只有提示詞才寫的說法）：抄進卡片就拿掉那張。
export const TENSION_STYLE_WRITER_SENTINELS: readonly string[] = [
  "不替她打分、不說她別有用意",
  "不把自己擺得比較厲害",
];

// ── 寫卡瘦身（開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Eric 2026-10-27「照預設」）──────────────────────────────────
// Bruce 2026-10-26「看B43-B47感覺可以從寫卡prompt 移除 他們對自然度會有影響」：B43–B47 從寫卡的使用者訊息拿掉（rules.ts
// pickWriterEntries）；同一份規格也拿掉 A5「讓她也投入」那一行裡的一句（WRITER_TRIM_A5_SENTENCE），寫卡不再看到。前後照留：
// 「是邀她參與，不是考她」與「小挑戰」那一句都在。說明書原文（guide_text.ts）與說明步驟（explain.ts）不改。開關開時在兩段式（與
// 帶張力改寫法）的 A5 之上只改這一行；只拿掉字、沒有新加的字，所以不另加外洩哨兵。

/// 寫卡瘦身拿掉的那一句（照抄說明書 A5 原文；原文改了 replaceOnce 就丟錯，測試會先失敗，不會悄悄沒拿掉）。
export const WRITER_TRIM_A5_SENTENCE =
  "她自己多說、解釋自己時一定要接住；她給了沒得到回應，下次就不給了。";

export const WRITER_TRIM_A5_EDITS: readonly LineEdit[] = [
  {
    startsWith: "- 讓她也投入：",
    edit: (l) => replaceOnce(l, WRITER_TRIM_A5_SENTENCE, ""),
  },
];

/// 寫卡瘦身開著、標到 B47（她堅持去她指定的店；排卡是推進換地方、收、推進）時，中間那張收卡的任務字換成這一句（Eric
/// 2026-10-27「照預設，跑」）：「這次先不約」「不出答應去那家的卡」原本只寫在 B47 的條目裡，寫卡看不到條目後，兩張推進卡還有
/// prompts.ts PUSH_NOTE.換地方，收卡只剩「收」（收的寫法是「一句中性收尾，門留著」，可能寫成之後再去那家）。說法照
/// PUSH_NOTE.換地方。沒開、沒標到 B47 時不出現。
export const WRITER_TRIM_VENUE_CLOSE_TASK =
  "收（她堅持要去她指定的店：這次先不約，不答應去那家，也不答應之後再去那家）";

/// 上面那一句的外洩哨兵（排到時只比卡片；說明看不到寫卡的規格，不比）：給她的訊息不會用「不答應…」這樣講。
/// PUSH_NOTE.換地方 也有這一段，抄進卡片一樣拿掉。
export const WRITER_TRIM_VENUE_CLOSE_SENTINELS: readonly string[] = [
  "不答應去那家，也不答應之後再去那家",
];

export function twoStageWriterSections(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  /// 帶張力改寫法開時，A5 在兩段式的改法之上再改帶張力那幾行（TENSION_STYLE_A5_EDITS）；寫卡瘦身開時，最後再拿掉
  /// 「讓她也投入」那一句（WRITER_TRIM_A5_EDITS）。都沒開跟今天一字不差。
  options: {
    readonly tensionStyle?: boolean;
    readonly writerTrim?: boolean;
  } = {},
): { readonly A5: string; readonly A6: string } {
  const a5 = applyLineEdits(sections.A5, TWO_STAGE_A5_EDITS);
  const tensioned = options.tensionStyle
    ? applyLineEdits(a5, TENSION_STYLE_A5_EDITS)
    : a5;
  return {
    A5: options.writerTrim
      ? applyLineEdits(tensioned, WRITER_TRIM_A5_EDITS)
      : tensioned,
    A6: renumber(applyLineEdits(sections.A6, TWO_STAGE_A6_EDITS)),
  };
}

/// 寫卡新加的兩段（我們自己的話；參考 v2 快照 :62-67、:253-257、:553、:566 與 :342-351）。
/// 第 2 輪照 Bruce 10/19 盲選理由補進原本的句子裡，不另開一串「不要」：你我少用、不自己報收到、
/// 不評她的語氣用字、被誇時謙虛（他的例句「還好啦」）、貼圖表情不拿出來講。
export const WRITE_NATURAL_RULES = `## 這一步只寫訊息
- 每則訊息都是他可以原封不動傳出去的自然句子，像他平常跟朋友聊天那樣說話；主詞能省就省，「你」「我」不用每句都帶。
- 直接回她說的事。判斷、策略、招式的名稱、對她的評價（包括評她的語氣和用字），以及替自己說明心態、原則或反應的話（例如「我收到了」「我收下了」「記下了」），都不寫進訊息；為什麼這樣回，下一步會另外說明給用戶。
- 被她誇的時候，謙虛一點帶過，例如「還好啦」，不順勢誇自己。
- 不是每一句都要表態或用上技巧。沒有適合的時機，就像朋友一樣正常聊。`;

export const WRITE_MEDIA_RULES = `## 照片和貼圖
- 她傳照片，是想跟他分享：接她分享的這件事。
- 方括號裡的字是辨識程式寫的照片描述，不是她說的話：不照搬描述裡的用字，也不假裝看到描述以外的東西。
- 貼圖和表情符號是她的語氣：跟旁邊那句話一起讀，用來抓她的心情，不拿出來講。`;

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
  /// 帶張力改寫法開時，A5 的帶張力那幾行換成新的寫法（TENSION_STYLE_A5_EDITS）；寫卡瘦身開時，A5「讓她也投入」少一句
  ///（WRITER_TRIM_A5_EDITS）。
  options: {
    readonly tensionStyle?: boolean;
    readonly writerTrim?: boolean;
  } = {},
): string {
  const writer = twoStageWriterSections(sections, options);
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
/// 第 2 輪改成講那件事本身（Bruce 10/19：「你整個人都亮亮的」不自然；第 1 輪這張常在形容她的樣子）。
export const HAPPY_SHARE_TASK =
  "共鳴（她在分享開心或得意的事：跟她一起為那件事高興，說那件事好在哪）";

const QUOTE_MAX_CHARS = 30;

/// 規格裡引她的那一則：去掉引用前綴與表情、空白收成一格，太長就截短。表情不引（第 2 輪，Bruce
/// 10/19：特別挑她的語氣去評價很不自然）：規格裡少了表情，寫卡就不會把它當成要回的東西；
/// 對話稿裡照樣看得到。跟排卡判斷「有沒有字可以引」用同一份（rules.ts herLineText）。
export function quoteHerLine(content: string): string {
  const text = herLineText(content);
  const chars = [...text];
  return chars.length > QUOTE_MAX_CHARS
    ? `${chars.slice(0, QUOTE_MAX_CHARS - 1).join("")}…`
    : text;
}

/// 規格裡的一則：「她的「…」」；併進來的照片、貼圖（rules.ts assignAnswers 的 with）註明第幾則，
/// 對話稿上她最新這一輪有逐則編號，寫卡看得到那幾則是什麼，規格裡不重抄辨識描述。
function answerQuote(at: AnswerLine, herLatest: readonly string[]): string {
  const folded = at.with.filter((line) =>
    line >= 1 && line <= herLatest.length
  );
  const note = folded.length > 0 ? `（連同第 ${folded.join("、")} 則）` : "";
  return `她的「${quoteHerLine(herLatest[at.line - 1])}」${note}`;
}

/// 第 2 輪（Bruce 10/19 盲選理由）：「這張接」是每張都要先回的那則，「可以順帶」是這張可以多接的
/// 一則。編號不在她最新這一輪、或那一則沒有字可以引，就不寫（不會出現「她的「」」）。說明步驟
///（explain.ts）也用同一份。
export function answerParts(
  answer: CardAnswer | undefined,
  herLatest: readonly string[],
): string[] {
  const inRange = (at: AnswerLine) =>
    at.line >= 1 && at.line <= herLatest.length &&
    quoteHerLine(herLatest[at.line - 1]) !== "";
  if (!answer || !inRange(answer.main)) return [];
  return [
    `這張接：${answerQuote(answer.main, herLatest)}`,
    ...(answer.extra && inRange(answer.extra)
      ? [`可以順帶：${answerQuote(answer.extra, herLatest)}`]
      : []),
  ];
}

/// 規格裡回她哪一則的那幾段（answerParts），抽到短版的那一張在「這張接」後面多寫短版的誇法
///（LIGHT_SHORT_CARD_PART），回她很短甜話的卡在同一個位置多寫短回的指示（SWEET_SHORT_CARD_PART）。寫卡與說明都用這一份。
/// 兩個不會在同一張（她撒嬌時直接誇，不抽短版）；萬一都有，短回在前。
export function specAnswerParts(
  spec: CardSpec,
  herLatest: readonly string[],
): string[] {
  const parts = answerParts(spec.answer, herLatest);
  if (parts.length === 0) return parts;
  const notes = [
    ...(spec.sweetShort ? [SWEET_SHORT_CARD_PART] : []),
    ...(spec.shortPraise ? [LIGHT_SHORT_CARD_PART] : []),
  ];
  return notes.length === 0 ? parts : [parts[0], ...notes, ...parts.slice(1)];
}

/// 兩段式的規格行：任務之後先講這張接她哪一則、可以順帶哪一則，「有他」做法改叫「他的事怎麼寫」。
export function cardSpecLineTwoStage(
  spec: CardSpec,
  n: number,
  herLatest: readonly string[],
  /// 寫卡瘦身開著、標到 B47 時：收卡的任務字換成 WRITER_TRIM_VENUE_CLOSE_TASK。沒給跟今天一樣。
  options: { readonly venueClose?: boolean } = {},
): string {
  const parts = [
    `${n}. 任務：${
      spec.note === "happy_share"
        ? HAPPY_SHARE_TASK
        : options.venueClose === true && spec.task === "收" && !spec.push
        ? WRITER_TRIM_VENUE_CLOSE_TASK
        : cardTaskText(spec)
    }`,
    ...specAnswerParts(spec, herLatest),
    `${TWO_STAGE_METHOD_LABEL}：${cardMethodText(spec)}`,
    `口吻：${spec.voice}`,
    spec.questionBudget === 0 ? "不問問題" : "問句最多 1 個",
  ];
  if (spec.angle > 0) parts.push("切入點要跟前面同規格的卡不同");
  return parts.join("｜");
}

/// 第 2 輪（Bruce 10/19 盲選理由，他的例句照用）：誇她的方式由程式照 praiseStyle 挑一句放進
/// 使用者訊息，不讓寫卡自己判斷兩人到哪一步，也不把兩種寫法同時擺給它挑。
const LIGHT_PRAISE_TEXT =
  "她傳自拍、問他好不好看或討稱讚時：輕輕誇一句、不用給太多，帶點玩笑、留一點讓她猜，像她傳自拍時回「美啊 已戀愛。哈哈哈哈 不錯啦」。";

export const PRAISE_TEXT: Readonly<Record<PraiseStyle, string>> = {
  direct:
    "她傳自拍、問他好不好看或討稱讚時：直接誇、講明白，不賣關子、不吊著她。",
  light: LIGHT_PRAISE_TEXT,
  // 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE）：短版不寫在這一段（第 3 輪真跑寫在這裡時，寫出來還是
  // 一般的回法），改寫在那一張卡的規格（LIGHT_SHORT_CARD_PART）；這一段跟輕輕誇一樣。
  light_short: LIGHT_PRAISE_TEXT,
};

/// 短版稱讚（Bruce 2026-10-20「可以」：還沒交往時偶爾用，要短，太長會油）：抽到短版時，plan.ts 挑的那一張卡
/// 在「這張接」後面多這一段。只講形狀、不放例句（他提醒例句會被照抄）；她沒在討稱讚就照一般寫。
export const LIGHT_SHORT_CARD_PART =
  "誇法（她傳自拍、問好不好看或討稱讚時）：這張只回很短的一句，誇張到一看就知道在開玩笑，用正面的說法，不解釋";

/// 短版稱讚開時，卡片多比的外洩哨兵（上面那段裡只有提示詞才寫的說法）：抄進卡片就拿掉那張。
export const SHORT_PRAISE_WRITER_SENTINELS: readonly string[] = [
  "這張只回很短的一句",
  "誇張到一看就知道在開玩笑",
];

/// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」，指示照他核准的「短短回她一句就好」）：她最新那句
/// 是很短的甜話時，回那句的卡在「這張接」後面多這一段（rules.ts arrangeSweetShort 排）。不放例句（例句會被照抄），也不替她
/// 下標籤（寫「撒嬌」「甜話」，卡片容易變成評她「又在撒嬌」）；她說了什麼，寫卡從「這張接」與對話稿看得到。
export const SWEET_SHORT_CARD_PART = "短短回她一句就好";

/// 甜話短回排到時，卡片多比的外洩哨兵：上面那段整句（8 個字，共用比對最短收 8 個字）。給她的訊息不會用「她」稱呼她，
/// 正常的卡不會有這一句。只比卡片、不比說明：說明講這張「短短回她一句就好」是自然的白話，拿掉反而少了那張的說明；照抄
/// 規格的結構仍由說明自己的哨兵（explain.ts EXPLAIN_SENTINELS）擋。
export const SWEET_SHORT_WRITER_SENTINELS: readonly string[] = [
  SWEET_SHORT_CARD_PART,
];

/// 甜話短回開時讀局面 worthyLines 那一條（Codex 主審第 1 輪 P2：「情感」也包含難過、生氣、痛，「腿好痛」「想你」都標情感時
/// 分不出哪句是甜話）：kind 多一種「撒嬌」，由讀局面逐則標她對他撒嬌或示愛的那一則；情感拿掉撒嬌、示愛，只剩帶著情緒的；一則
/// 算好幾種時照問他、撒嬌、情感的順序。例句是我們寫的類型，不是哪一段真實對話。其他欄位、其他文字照 READ_TWO_STAGE_NOTES。
export const SWEET_WORTHY_LINES_NOTE =
  "- worthyLines：她最新這一輪值得接的訊息，一則一項。line 填對話稿上那一則前面的編號；label 用幾個字寫那則在講什麼；kind 填「問他」（她直接問他、要他的看法，或想聽他說好不好看、厲不厲害）、「撒嬌」（這一則本身在對他撒嬌或示愛，例如說想他、要他抱抱、說愛他或喜歡他、跟他討親親；只是說累、痛或心情不好，填「情感」）、「情感」（帶著開心、難過、生氣的情緒）、「照片或貼圖」（照片、貼圖或只有表情符號），其他都填「其他」；一則同時算好幾種時，照問他、撒嬌、情感的順序填前面那種。單純附和、語助詞，或跟前一則講同一件事的，可以不列。";

/// 不記帳不承諾（開關 ANALYZE_GUIDE_V3_NO_IOU，Bruce 2026-10-22）開時讀局面多的一行，接在 herAffection 那一行下面（readTwoStageNotes）：
/// 排卡在交往中她撒嬌示愛或喊累時不排推進（種子）。例子是我們寫的類型，不是哪一段真實對話。
export const HER_TIRED_NOTE =
  "- herTired：她這一輪在喊累，或說身體痠痛、不舒服，例如說好累、腳很痠、頭痛、沒睡飽。";

/// 上面那一行的外洩哨兵（開關開時，判讀與要等她做什麼照抄就不給，比的位置跟 SWEET_READ_LEAK_SENTINELS 一樣）：照抄自那一行，
/// 而且帶只有提示詞才會寫的記號（欄位名接它的定義、「例如說」接一串例子）；一般判讀自己也會講的話（「她說好累、腳很痠」）不當哨兵。
export const NO_IOU_READ_SENTINELS: readonly string[] = [
  "herTired：她這一輪在喊累",
  "或說身體痠痛、不舒服，例如說好累",
];

/// 不記帳不承諾開時交給 vetPlanText 多比的哨兵（原樣與簡轉繁整理過的，去掉重複）。
export const NO_IOU_READ_LEAK_SENTINELS: readonly string[] = [
  ...new Set([
    ...NO_IOU_READ_SENTINELS,
    ...NO_IOU_READ_SENTINELS.map((s) => normalizeOutgoingScript(s) ?? s),
  ]),
];

/// 讀局面兩段式的欄位說明：甜話短回開時 worthyLines 那一條換成 SWEET_WORTHY_LINES_NOTE、不記帳不承諾開時 herAffection 那一行
/// 下面多 HER_TIRED_NOTE（兩個各自獨立，都開就兩處都改；原文那一行對不上就丟錯，測試會先失敗）；都沒開就是 READ_TWO_STAGE_NOTES
/// 原文。
export function readTwoStageNotes(
  options: { readonly sweetShort?: boolean; readonly noIou?: boolean } = {},
): string {
  const edits: LineEdit[] = [
    // 回兩行＝那一行照留、下面插一行。
    ...(options.noIou
      ? [{
        startsWith: "- herAffection：",
        edit: (line: string) => `${line}\n${HER_TIRED_NOTE}`,
      }]
      : []),
    ...(options.sweetShort
      ? [{ startsWith: "- worthyLines：", edit: () => SWEET_WORTHY_LINES_NOTE }]
      : []),
  ];
  return edits.length > 0
    ? applyLineEdits(READ_TWO_STAGE_NOTES, edits)
    : READ_TWO_STAGE_NOTES;
}

/// 上面那一條新加的說法的外洩哨兵（甜話短回開時，判讀與要等她做什麼照抄就不給，跟 TWO_STAGE_READ_SENTINELS 同一套）：每句都
/// 照抄自 SWEET_WORTHY_LINES_NOTE，而且帶只有提示詞才會寫的記號（種類名接它的定義、「填「情感」」、種類的先後）；一般判讀自己
/// 也會講的話（「她在跟你撒嬌」）不當哨兵。沿用的那幾段已經在 TWO_STAGE_READ_SENTINELS。
export const SWEET_READ_SENTINELS: readonly string[] = [
  "「撒嬌」（這一則本身在對他撒嬌或示愛",
  "只是說累、痛或心情不好，填「情感」",
  "「情感」（帶著開心、難過、生氣的情緒）",
  "一則同時算好幾種時，照問他、撒嬌、情感的順序",
];

/// 甜話短回開時交給 vetPlanText 多比的哨兵（原樣與簡轉繁整理過的，去掉重複）。
export const SWEET_READ_LEAK_SENTINELS: readonly string[] = [
  ...new Set([
    ...SWEET_READ_SENTINELS,
    ...SWEET_READ_SENTINELS.map((s) => normalizeOutgoingScript(s) ?? s),
  ]),
];

export function praiseSection(style: PraiseStyle): string {
  return `## 稱讚\n${PRAISE_TEXT[style]}`;
}

export function writeUserPromptTwoStage(args: {
  readonly turns: readonly Turn[];
  readonly tags: ReadTags;
  readonly entries: readonly GuideV3Entry[];
  readonly cards: readonly CardSpec[];
  readonly background?: GuideV3Background;
  readonly previousRound?: GuideV3PreviousRound;
  /// 出卡、收尾的計畫才有（plan.ts）；沒給就不放稱讚那段。
  readonly praise?: PraiseStyle;
  /// 寫卡瘦身開著、標到 B47 時（stream_flow.ts）：收卡的任務字換成 WRITER_TRIM_VENUE_CLOSE_TASK。沒給跟今天一樣。
  readonly venueClose?: boolean;
}): string {
  const herLatest = latestHerMessages(args.turns);
  const { praise, venueClose, ...rest } = args;
  return writeUserPrompt({
    ...rest,
    variant: {
      numberLatestHerTurn: true,
      entryWriting: twoStageEntryWriting,
      specLine: (spec, n) =>
        cardSpecLineTwoStage(spec, n, herLatest, { venueClose }),
      beforeCards: praise ? [praiseSection(praise)] : [],
    },
  });
}
