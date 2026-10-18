// 上一輪脈絡（previousRound）：分析完的片段就封存，她回了之後他只能另開新片段，
// 模型原本看不到上一輪。App 在新片段帶一份精簡的上一輪：上次的燈號、決定與判讀，
// 加上一段最後幾則（Eric 2026-10-18 拍板「新片段要帶」）。不帶「他複製的那張」：
// 手機上的複製紀錄記不準最後複製的是哪張、也不反映他改過的字（主審第 1 輪 P2），
// 舊版 App 送來也不收。
//
// - 開關 ANALYZE_GUIDE_V3_PREV_ROUND（off／test／on，見 routing.ts）開著才讀；沒開
//   就當沒送，兩段提示詞一字不變。
// - 不算計費字數（獨立欄位，計費只看 messages），也不進對話雜湊：v3 續看只重播、
//   不重寫，上一輪脈絡不影響續看的結果。
// - 格式不對或超過上限就整份不用，不擋分析；log 與 trace 只記數量和原因代碼。
import { LIGHTS } from "./read_tags.ts";

/// 上限（App 端照同一組數字裁好再送）：每段文字 120、最多 4 則、全部合計 600。
/// 字數照現有驗證的算法：trim 之後的字串長度。
export const PREVIOUS_ROUND_MAX_CHARS = 600;
export const PREVIOUS_ROUND_MAX_TEXT_CHARS = 120;
export const PREVIOUS_ROUND_MAX_MESSAGES = 4;

/// 自傷關心不帶：那一輪只有固定文案，沒有判讀可以接。
export const PREVIOUS_ROUND_DECISIONS = [
  "send",
  "close",
  "hold",
  "stop",
] as const;
export type PreviousRoundDecision = typeof PREVIOUS_ROUND_DECISIONS[number];

export interface GuideV3PreviousRound {
  readonly decision: PreviousRoundDecision;
  readonly light?: typeof LIGHTS[number];
  /// 上次給用戶看的判讀；沒有就不放。
  readonly judgment?: string;
  /// 上一段最後幾則（舊到新）。
  readonly messages: readonly {
    readonly isFromMe: boolean;
    readonly content: string;
  }[];
}

export type PreviousRoundIgnoredReason =
  | "not_object"
  | "decision"
  | "light"
  | "judgment"
  | "messages"
  | "message"
  | "too_long"
  | "empty";

export type PreviousRoundParse =
  | { readonly kind: "absent" }
  | { readonly kind: "ok"; readonly round: GuideV3PreviousRound }
  | { readonly kind: "ignored"; readonly reason: PreviousRoundIgnoredReason };

/// 存進 guideV3Trace 與 guide_v3_outcome 的只有數量，不放任何字。
export interface GuideV3PreviousRoundTrace {
  readonly messages: number;
  readonly chars: number;
  readonly judgment: boolean;
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

/// 選填文字：沒給或空白回 ""；不是字串或超過上限回 null。
function optionalText(value: unknown): string | null {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text.length <= PREVIOUS_ROUND_MAX_TEXT_CHARS ? text : null;
}

export function parsePreviousRound(raw: unknown): PreviousRoundParse {
  if (raw === undefined || raw === null) return { kind: "absent" };
  const ignored = (reason: PreviousRoundIgnoredReason): PreviousRoundParse => ({
    kind: "ignored",
    reason,
  });
  const input = record(raw);
  if (!input) return ignored("not_object");
  const decision = PREVIOUS_ROUND_DECISIONS.find((d) => d === input.decision);
  if (!decision) return ignored("decision");
  let light: typeof LIGHTS[number] | undefined;
  if (input.light !== undefined && input.light !== null) {
    light = LIGHTS.find((l) => l === input.light);
    if (!light) return ignored("light");
  }
  const judgment = optionalText(input.judgment);
  if (judgment === null) return ignored("judgment");
  const rawMessages = input.messages ?? [];
  if (
    !Array.isArray(rawMessages) ||
    rawMessages.length > PREVIOUS_ROUND_MAX_MESSAGES
  ) return ignored("messages");
  const messages: { isFromMe: boolean; content: string }[] = [];
  for (const item of rawMessages) {
    const message = record(item);
    const content = typeof message?.content === "string"
      ? message.content.trim()
      : "";
    if (
      !message || typeof message.isFromMe !== "boolean" || !content ||
      content.length > PREVIOUS_ROUND_MAX_TEXT_CHARS
    ) return ignored("message");
    messages.push({ isFromMe: message.isFromMe, content });
  }
  // 每段上限加起來剛好 600（判讀＋4 則）；這條是之後改上限時的保險。
  const chars = judgment.length +
    messages.reduce((total, m) => total + m.content.length, 0);
  if (chars > PREVIOUS_ROUND_MAX_CHARS) return ignored("too_long");
  if (chars === 0) return ignored("empty");
  return {
    kind: "ok",
    round: {
      decision,
      ...(light ? { light } : {}),
      ...(judgment ? { judgment } : {}),
      messages,
    },
  };
}

/// handler 在開關允許時才呼叫：格式不對整份不用，原因代碼交給 onIgnored 記 log。
export function acceptedPreviousRound(
  raw: unknown,
  onIgnored: (reason: PreviousRoundIgnoredReason) => void,
): GuideV3PreviousRound | undefined {
  const parsed = parsePreviousRound(raw);
  if (parsed.kind === "ignored") onIgnored(parsed.reason);
  return parsed.kind === "ok" ? parsed.round : undefined;
}

export function previousRoundTrace(
  round: GuideV3PreviousRound,
): GuideV3PreviousRoundTrace {
  return {
    messages: round.messages.length,
    chars: (round.judgment?.length ?? 0) +
      round.messages.reduce((total, m) => total + m.content.length, 0),
    judgment: Boolean(round.judgment),
  };
}

const LIGHT_LABEL: Readonly<Record<typeof LIGHTS[number], string>> = {
  green: "綠燈",
  yellow: "黃燈",
  red: "紅燈",
};

const DECISION_LABEL: Readonly<Record<PreviousRoundDecision, string>> = {
  send: "回她",
  close: "收尾",
  hold: "先別回",
  stop: "停，不再主動傳",
};

function oneLine(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

/// 上一輪的訊息不編輪次：讀局面的輪次編號只屬於這次的對話。
function lastMessagesLines(round: GuideV3PreviousRound): string[] {
  if (round.messages.length === 0) return [];
  return [
    "- 上一段最後幾則：",
    ...round.messages.map((m) =>
      `  - ${m.isFromMe ? "他" : "她"}：${oneLine(m.content)}`
    ),
  ];
}

const SECTION_TITLE = "## 上一輪（比下面的對話早）";

/// 讀局面：上次的判讀＋最後幾則。燈號只反映那一輪，這一輪照這次的
/// 對話重判（把上次的分數餵回去會錨定，見 App 的 PartnerSummaryBuilder）。
export function previousRoundReadSection(
  round: GuideV3PreviousRound | undefined,
): string[] {
  if (!round) return [];
  const labels = [
    ...(round.light ? [LIGHT_LABEL[round.light]] : []),
    DECISION_LABEL[round.decision],
  ].join("，");
  const judgment = round.judgment ? oneLine(round.judgment) : "";
  return [
    [
      SECTION_TITLE,
      "上一段分析留下的紀錄，只當背景：不是她這次說的話，跟這次的對話對不上時以這次為準，燈號也照這次的對話重新判斷。",
      `- 上次的判讀：${labels}。${judgment}`,
      ...lastMessagesLines(round),
    ].join("\n"),
  ];
}

/// 寫卡：只放最後幾則（判讀對寫句子是雜訊）；沒有就不放。
export function previousRoundWriteSection(
  round: GuideV3PreviousRound | undefined,
): string[] {
  if (!round) return [];
  const lines = lastMessagesLines(round);
  if (lines.length === 0) return [];
  return [
    [
      SECTION_TITLE,
      "上一段的紀錄，只當背景，不是這次要接的球。",
      ...lines,
    ].join("\n"),
  ];
}
