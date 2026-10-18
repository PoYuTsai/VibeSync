// 程式自己掃的安全訊號（Eric 2026-10-18）：讀局面的模型漏標、讀局面失敗或拒答時的後援。
// 只認明講的說法，寧可漏也不要誤擋：v2 的輸入關鍵字閘門就是因為擋到正常對話，2026-10-12
// 被拆掉的（guardrails.ts 檔尾）。掃 App 送來的原始訊息（不含引用前綴，引用的可能是另一方
// 的話），原文與簡轉繁各掃一次。純函式，不碰模型與資料庫。
import { toTraditionalChinese } from "../../_shared/traditional_chinese.ts";
import type { GuideV3Background } from "./prompts.ts";

export interface SafetyKeywordHits {
  /// 有人明講自己未滿 18 歲、現在讀國中或高中、未成年（雙方的訊息與背景都掃）。
  readonly minor: boolean;
  /// 她明講想死、想自殺、不想活、自殘（只掃她的訊息）。後援層：讀局面失敗或拒答時，
  /// 有這個就給關心訊息（附專線），不給錯誤。
  readonly selfHarm: boolean;
  /// 上面之中最不會是誇張說法的幾種（想自殺、不想活了、割腕、自殘）：讀局面成功但沒標
  /// 自傷，也照樣給關心訊息（plan.ts 的 FORCE_CARE_ON_EXPLICIT_SELF_HARM）。
  readonly selfHarmExplicit: boolean;
}

export const NO_SAFETY_HITS: SafetyKeywordHits = {
  minor: false,
  selfHarm: false,
  selfHarmExplicit: false,
};

export interface SafetyScanMessage {
  readonly isFromMe: boolean;
  readonly content: string;
}

// 講的是以前或別人：「…的時候」「那年」「就…」「畢業」「17 歲的兒子」。
const NOT_NOW = String
  .raw`(?!\s*(?:的|時|那|以前|之前|以後|之後|後來|就|開始|起|畢業|生日|左右))`;
// 10–17 歲，前面不能接別的數字（「28 歲」「三十歲」不算）。個位數不收：「你當我三歲小孩」
// 是常見的說法，交友對話裡也不會真的是個位數。
const AGE = String
  .raw`(?<![0-9一二三四五六七八九十百])(?:1[0-7]|十[一二三四五六七]?)\s*歲${NOT_NOW}`;
// 國一到高三；「高一點」「高三十公分」「國一年」、導師或班級（老師在講學生）、「國一國二都…」
// 「國一到國三」這種回顧都不算。
const GRADE = String
  .raw`(?:國|高)[一二三](?![點些倍度樓層米級年十百千萬班導到]|老師|(?:國|高)[一二三])${NOT_NOW}`;
// 「高中」本身多半是在講以前（「我高中讀女校」），要有「讀、念、上」或「…生」才算現在；
// 「高中生活」「國中生涯」是回顧。
const SCHOOL = String
  .raw`(?:(?:是|還是)?(?:國中|高中)生(?![活涯])|在?(?:讀|念|唸|上)(?:國中|高中))${NOT_NOW}`;
const UNDERAGE = String
  .raw`(?:(?:是|算|還是)?未成年|(?:沒|未)(?:成年|滿\s*(?:18|十八)))${NOT_NOW}`;
const MARKERS = String.raw`(?:現在|目前|今年|也|都|才|只|只有|還在|還|正在)*`;
const BODY = String
  .raw`(?:${AGE}|(?:是|在讀|在念|在唸|讀|念|唸|在|上)?${GRADE}|${SCHOOL}|${UNDERAGE})`;
// 沒寫「歲」的年紀只認「今年 13–17」接句尾或語助詞（「今年 17 號」不算）。
const TEEN_THIS_YEAR = String
  .raw`今年\s*(?:才|只有)?\s*(?:1[3-7]|十[三四五六七])(?=$|[\s，。！？!?,.~～、…]|啦|喔|欸|耶|唷|了|啊|呀|哦|嗎|呢|而已)`;

/// 訊息：只認自稱（我、人家）。「你國中生喔」是常見的虧人說法，不認第二人稱。
const MINOR_IN_MESSAGE = [
  new RegExp(String.raw`(?:我|人家)\s*${MARKERS}\s*${BODY}`, "u"),
  new RegExp(String.raw`(?:我|人家)\s*${TEEN_THIS_YEAR}`, "u"),
  // 整則只有年級或歲數（回答「妳幾年級？」）：「高二啦」「16 歲而已」。
  new RegExp(
    String
      .raw`^\s*(?:現在|目前)?\s*(?:(?:國|高)[一二三]生?|(?:1[0-7]|十[一二三四五六七]?)\s*歲)\s*(?:了|啦|喔|欸|耶|唷|啊|呀|哦|而已|囉)*[\s。！？!?~～…]*$`,
    "u",
  ),
];
/// 背景（作戰板、對象描述、補充、對象背景、更早的摘要）：他寫她多半用「她」或直接寫
/// 「高二學妹」，所以欄位開頭與標點後面也算。
const MINOR_IN_BACKGROUND = [
  new RegExp(
    String
      .raw`(?:^|[\s，,。.、；;：:（(／/|｜]|她|對方|我|人家)\s*${MARKERS}\s*${BODY}`,
    "u",
  ),
  new RegExp(String.raw`(?:她|對方|我|人家)\s*${TEEN_THIS_YEAR}`, "u"),
];

/// 最明確的自傷說法。「不想活在怨恨裡」「熱到不想活了」、「不要自殺」「自殺小隊」、新聞裡別人
/// 輕生、「這樣熬夜根本自殘」都不算。
const SELF_HARM_EXPLICIT = [
  /(?<!不)(?:想|要|去|打算|準備)自殺|想過自殺|自殺的?念頭/u,
  /(?<![到得])不想(?:再)?活(?:了|下去)/u,
  /割腕/u,
  /(?:我|有在|一直|又|會|常常|曾經)在?自殘|想自殘/u,
  /(?<!不)想輕生|輕生的?念頭/u,
];
/// 只在讀局面失敗或拒答時才用：「我好想死」也可能是考試前的誇張說法，模型讀得出來；讀不出來
/// 時寧可附專線。「熱到想死」「笑到想死」「想死你了」不算。
const SELF_HARM_FALLBACK_ONLY = [
  /(?<![到得])(?:我|好|真的|超|很)想去?死(?![你妳他她])/u,
];

function variants(text: string): string[] {
  const halfWidth = text.replace(
    /[０-９]/g,
    (d) => String.fromCharCode(d.charCodeAt(0) - 0xfee0),
  );
  return [...new Set([halfWidth, toTraditionalChinese(halfWidth)])];
}

function anyMatch(texts: readonly string[], patterns: readonly RegExp[]) {
  return texts.some((text) =>
    variants(text).some((v) => patterns.some((p) => p.test(v)))
  );
}

function backgroundTexts(background: GuideV3Background | undefined): string[] {
  if (!background) return [];
  return [
    background.meetingContext,
    background.duration,
    background.goal,
    background.targetDescription,
    background.analysisContextNote,
    background.partnerSummary,
    background.conversationSummary,
  ].filter((v): v is string => typeof v === "string" && v.trim() !== "");
}

export function scanSafetyKeywords(
  messages: readonly SafetyScanMessage[],
  background?: GuideV3Background,
): SafetyKeywordHits {
  const all = messages.map((m) => m.content);
  const hers = messages.filter((m) => !m.isFromMe).map((m) => m.content);
  const selfHarmExplicit = anyMatch(hers, SELF_HARM_EXPLICIT);
  return {
    minor: anyMatch(all, MINOR_IN_MESSAGE) ||
      anyMatch(backgroundTexts(background), MINOR_IN_BACKGROUND),
    selfHarm: selfHarmExplicit || anyMatch(hers, SELF_HARM_FALLBACK_ONLY),
    selfHarmExplicit,
  };
}
