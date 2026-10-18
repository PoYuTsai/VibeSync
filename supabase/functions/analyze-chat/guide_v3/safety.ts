// 程式自己掃的安全訊號（Eric 2026-10-18）。讀局面的模型是可靠的那一層（10/18 付費黑箱：
// 未成年、自傷、詐騙的標記 17/17 都對），關鍵字只在模型讀不到時當後援，或用在 Eric 決定
// 寧可多關心的自傷字眼；主審第 1 輪找到的誤判都出在句型比對，所以改成只看有沒有這些字，
// 不再猜句型。金錢、詐騙不掃關鍵字，只看讀局面的風險標記（借東西、理專講投資都會誤判）。
// 掃 App 送來的原始訊息（不含引用前綴，引用的可能是另一方的話），原文與簡轉繁各掃一次。
// 純函式，不碰模型與資料庫。
import { toTraditionalChinese } from "../../_shared/traditional_chinese.ts";
import type { GuideV3Background } from "./prompts.ts";

export interface SafetyKeywordHits {
  /// 雙方訊息或背景裡有 10–17 歲、國中、高中、國一到高三、未成年這些字。只在讀局面失敗、
  /// 拒答或逾時時用（plan.ts 的 planWithoutRead）：那時本來就不出卡，誤判只是把錯誤換成
  /// 固定說明；讀局面成功時只看模型的 minorSignal。
  readonly minorWords: boolean;
  /// 她的訊息裡有自殺、自殘、割腕、輕生、不想活任一個字：就算讀局面成功、模型沒標，也一律
  /// 改顯示關心訊息（Eric 2026-10-18：「代價是她在開玩笑或談別人的事時也會先關心」）。
  readonly selfHarmWords: boolean;
  /// 她的訊息裡有「想死」：只在讀局面失敗、拒答或逾時時算（跟上面一起），給關心訊息不給
  /// 錯誤；讀局面成功時「熱到想死」「想死你了」交給模型判斷。
  readonly wantsToDie: boolean;
}

export const NO_SAFETY_HITS: SafetyKeywordHits = {
  minorWords: false,
  selfHarmWords: false,
  wantsToDie: false,
};

export interface SafetyScanMessage {
  readonly isFromMe: boolean;
  readonly content: string;
}

/// 只看有沒有這些字：「我高中的時候」「高中老師」也算（後援才用，誤判無害）。
const MINOR_WORDS =
  /1[0-7]\s*歲|十[一二三四五六七]\s*歲|國中|高中|國[一二三]|高[一二三]|未成年/u;

/// 只看有沒有這些字（主審第 1 輪：句型比對漏掉「我要自殘了」、又把「我沒有自殺的念頭」算進來）。
/// 否定、轉述、開玩笑也算，是 Eric 接受的代價。
const SELF_HARM_WORDS = /自殺|自殘|割腕|輕生|不想活/u;
const WANTS_TO_DIE = /想死/u;

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
  return {
    minorWords: anyMatch(
      [...all, ...backgroundTexts(background)],
      [MINOR_WORDS],
    ),
    selfHarmWords: anyMatch(hers, [SELF_HARM_WORDS]),
    wantsToDie: anyMatch(hers, [WANTS_TO_DIE]),
  };
}
