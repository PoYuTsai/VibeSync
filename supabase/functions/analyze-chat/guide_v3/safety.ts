// 程式自己掃的安全訊號（Eric 2026-10-18）。讀局面的模型是可靠的那一層（10/18 付費黑箱：
// 未成年、自傷、詐騙的標記 17/17 都對），關鍵字只在模型讀不到時當後援，或用在 Eric 決定
// 寧可多關心的自傷字眼；主審第 1 輪找到的誤判都出在句型比對，所以改成只看有沒有這些字，
// 不再猜句型。掃 App 送來的原始訊息（不含引用前綴，引用的可能是另一方的話），原文與簡轉繁
// 各掃一次。純函式，不碰模型與資料庫。
import { toTraditionalChinese } from "../../_shared/traditional_chinese.ts";
import type { GuideV3Background } from "./prompts.ts";

export interface SafetyKeywordHits {
  /// 雙方訊息或背景裡有 10–17 歲、國中、高中、國一到高三、未成年這些字。只在讀局面失敗、
  /// 拒答或逾時時用（plan.ts 的 planWithoutRead）：那時本來就不出卡，誤判只是把錯誤換成
  /// 固定說明；讀局面成功時只看模型的 minorSignal。
  readonly minorWords: boolean;
  /// 她明講想死、想自殺、不想活、自殘（只掃她的訊息）。後援層：讀局面失敗或拒答時，
  /// 有這個就給關心訊息（附專線），不給錯誤。
  readonly selfHarm: boolean;
  /// 上面之中最不會是誇張說法的幾種（想自殺、不想活了、割腕、自殘）：讀局面成功但沒標
  /// 自傷，也照樣給關心訊息（plan.ts 的 FORCE_CARE_ON_EXPLICIT_SELF_HARM）。
  readonly selfHarmExplicit: boolean;
  /// 她要他借錢、轉帳、代付，或拉他投資、叫他下載 App 或換地方聊又講到錢（只掃她的訊息）。
  /// 跟讀局面的風險標記同樣處理：不排推進、判讀換成固定提醒（plan.ts）。
  readonly money: boolean;
}

export const NO_SAFETY_HITS: SafetyKeywordHits = {
  minorWords: false,
  selfHarm: false,
  selfHarmExplicit: false,
  money: false,
};

export interface SafetyScanMessage {
  readonly isFromMe: boolean;
  readonly content: string;
}

/// 只看有沒有這些字：「我高中的時候」「高中老師」也算（後援才用，誤判無害）。
const MINOR_WORDS =
  /1[0-7]\s*歲|十[一二三四五六七]\s*歲|國中|高中|國[一二三]|高[一二三]|未成年/u;

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

/// 跟他借錢、拉他投資。「借我看一下」「跟你借個充電器」、她自己做投資或在券商上班、聊她的工作
/// （入金、下單、跟單都是常見的工作用語）都不算。
const MONEY_ASK = [
  /(?:跟你|向你|找你)借(?:錢|點錢|一點錢|一些錢|[0-9]|[一二兩三四五六七八九十幾]+[百千萬塊])|借我(?:錢|點錢|一點錢|一些錢|[0-9]|[一二兩三四五六七八九十幾]+[百千萬塊])/u,
  /帶你(?:一起)?(?:投資|賺錢|賺|操作|下單|進場|翻身)|穩賺|保證(?:獲利|賺|回本)|穩定獲利|零風險|躺著賺|(?:幫你|你先|你可以|你要|你就)(?:入金|儲值)|USDT|泰達幣/iu,
];
/// 要他轉帳、匯款或代付；同一則講到分帳、AA、他那份就不算（吃完飯叫他轉他的那份）。
const MONEY_TRANSFER =
  /(?:匯(?:款|錢)?|轉(?:帳|賬|账|錢))給我|幫我(?:匯款|轉帳|付款|儲值|繳)/u;
const BILL_SPLIT =
  /AA|ＡＡ|分帳|平分|一人一半|各付|各出|拆帳|你那份|你的那份|你的部分/iu;
/// 叫他下載 App、加群組或換到別的聊天軟體，同一則又講到錢；單純「換 LINE 聊」不算。
const MOVE_PLATFORM =
  /(?:下載|換到|換去|改用|加入|加我|加一下)[^。！？!?\n]{0,12}(?:APP|App|app|ＡＰＰ|軟體|群組|群|LINE|Line|line|賴|TG|Telegram|telegram|微信|WhatsApp|whatsapp)/u;
const MONEY_WORDS =
  /投資|賺錢|獲利|收益|儲值|入金|出金|下單|報酬|回報|利潤|翻倍/u;

function asksForMoney(text: string): boolean {
  return MONEY_ASK.some((p) => p.test(text)) ||
    (MONEY_TRANSFER.test(text) && !BILL_SPLIT.test(text)) ||
    (MOVE_PLATFORM.test(text) && MONEY_WORDS.test(text));
}

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
    minorWords: anyMatch(
      [...all, ...backgroundTexts(background)],
      [MINOR_WORDS],
    ),
    selfHarm: selfHarmExplicit || anyMatch(hers, SELF_HARM_FALLBACK_ONLY),
    selfHarmExplicit,
    money: hers.some((text) => variants(text).some(asksForMoney)),
  };
}
