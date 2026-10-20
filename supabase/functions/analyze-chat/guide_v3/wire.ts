// v3 送給 App 的事件與結果形狀（只給協定版本 3）。v2 的事件型別表
// （stream_events.ts）是模型輸出的解析白名單，v3 事件由伺服器自己產生，不放進去。
import type { TypingChanges, TypingHabits } from "./typing_style.ts";
import type { PhraseTidyChanges } from "./phrase_tidy.ts";
import type { V3CardTaskCode } from "../stream_run_store.ts";
import type { CardChecks } from "./cards.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import type { GuideV3MemoryTrace } from "./memory.ts";
import type {
  GuideV3CareKind,
  GuideV3CareTrigger,
  GuideV3Decision,
  GuideV3Plan,
} from "./plan.ts";
import type { GuideV3PreviousRoundTrace } from "./previous_round.ts";
import type {
  HER_MOVES,
  INVITE_READINESS,
  LIGHTS,
  ReadTags,
} from "./read_tags.ts";
import type {
  GameStage,
  GuideV3RelationTrace,
  RelationRead,
} from "./relation.ts";
import type { CardSpec, HisMethod, Task, Voice } from "./rules.ts";
import type { SafetyKeywordHits } from "./safety.ts";

export const GUIDE_V3_READ_EVENT = "analysis.read";
export const GUIDE_V3_CARD_EVENT = "analysis.card";
/// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）：卡都送完、done 之前，每張卡
/// 一則「為什麼這樣回」。舊版 App 不認得的事件型別一律略過。
export const GUIDE_V3_CARD_EXPLAIN_EVENT = "analysis.card_explain";

/// 卡片任務 → 扣費紀錄與 App 用的代碼（migration 20261016171939 的 card_task）。
export const TASK_CODE: Readonly<Record<Task, V3CardTaskCode>> = {
  接住: "accept",
  共鳴: "resonate",
  帶張力: "tension",
  推進: "push",
  收: "close",
};

export type MethodCode = "reaction" | "his_facts" | "blank" | "invented";
export const METHOD_CODE: Readonly<Record<HisMethod, MethodCode>> = {
  只用反應: "reaction",
  用他說過的: "his_facts",
  留空格: "blank",
  "照樣寫＋標示": "invented",
};

export type VoiceCode = "his" | "default";
export const VOICE_CODE: Readonly<Record<Voice, VoiceCode>> = {
  照他: "his",
  預設: "default",
};

/// 邀約進度 → App 用的代碼（Eric 2026-10-18 燈號紀錄＋邀約進度）。中文類別名之後可能改，
/// App 只認代碼、不認得的當沒有。
export type InviteReadinessCode =
  | "none"
  | "declined"
  | "vague_yes"
  | "clear_yes"
  | "she_proposed"
  | "she_cancelled"
  | "hesitant";
export const INVITE_READINESS_CODE: Readonly<
  Record<typeof INVITE_READINESS[number], InviteReadinessCode>
> = {
  沒機會: "none",
  婉拒過: "declined",
  含糊答應: "vague_yes",
  明確答應: "clear_yes",
  她自己提見面: "she_proposed",
  她取消了: "she_cancelled",
  猶豫: "hesitant",
};

/// 她這一輪在做什麼 → App 用的代碼（「關係狀態」卡，Bruce 2026-10-19 路線二）。中文類別名之後
/// 可能改，App 只認代碼、不認得的當沒有。
export type HerMoveCode =
  | "daily_life"
  | "emotion"
  | "high_point"
  | "laugh_ending"
  | "teasing"
  | "testing"
  | "serious_question"
  | "asks_about_him"
  | "asks_his_opinion"
  | "open_window"
  | "braking";
export const HER_MOVE_CODE: Readonly<
  Record<typeof HER_MOVES[number], HerMoveCode>
> = {
  生活: "daily_life",
  情緒: "emotion",
  高點: "high_point",
  大笑收尾: "laugh_ending",
  調侃: "teasing",
  試探: "testing",
  認真問: "serious_question",
  問他的事: "asks_about_him",
  問他意見: "asks_his_opinion",
  開窗: "open_window",
  煞車: "braking",
};

/// 自傷訊號時顯示的固定關心訊息（Eric 10/16 同意的文案，之後給 Bruce 看）。
export const CARE_MESSAGE = [
  "對話裡出現了可能有人有危險的訊號。先把安全放在第一位，不用想怎麼回得漂亮。",
  "如果你擔心她的安全：直接問她現在還好嗎、陪她聯絡安心專線 1925（24 小時）或生命線 1995。",
  "如果你自己也很難受，這兩支電話也可以打給你自己。情況緊急，打 110 或 119。",
  "這次不提供回覆建議。",
].join("\n");

/// 涉及未成年時的固定說明（Eric 2026-10-18 盤點預設：一兩句、平靜、不說教，只講這類對話
/// 不給建議）。
export const MINOR_MESSAGE =
  "看起來對話裡有人未滿 18 歲或還在讀國中、高中，這類對話我們不提供回覆建議。這次不扣額度。";

/// 需要他填的空格（提示詞要求寫成「＿＿」）。
const BLANK_PATTERN = /＿/;

export interface GuideV3ReadView {
  readonly guideVersion: string;
  readonly decision: GuideV3Decision;
  /// 讀局面失敗、只靠程式關鍵字給固定訊息時沒有燈號（App 本來就不給 care 顯示燈號）。
  readonly light: typeof LIGHTS[number] | null;
  readonly judgment: string;
  readonly waitFor?: string;
  readonly careMessage?: string;
  /// care 才有：self_harm（自傷關心）或 minor（涉及未成年）。舊版 App 不看這欄。
  readonly careKind?: GuideV3CareKind;
  /// care 以外才有（plan.signals）：邀約進度，以及給新話題的冷訊號。跟判讀一起在扣費之後
  /// 才送；舊版 App 不看這兩欄。
  readonly inviteReadiness?: InviteReadinessCode;
  readonly cold?: {
    readonly c1: boolean;
    readonly herPerfunctoryStreak: number;
  };
  /// 預定的卡（照順序）；送出的張數可能比較少（被檢查拿掉）。免費也看全部卡（Bruce
  /// 10/18，Eric 2026-10-19），沒有鎖住的卡：locked 一律 false，欄位留著給舊版 App
  ///（它看到 true 才顯示升級區塊）。
  readonly plannedCards: readonly {
    slot: number;
    task: V3CardTaskCode;
    locked: false;
  }[];
  /// 關係訊號開關開才有，排在最後（舊版 App 不看這欄）；自傷關心、未成年不帶。
  readonly relation?: GuideV3RelationView;
}

/// 判讀裡的關係狀態（Bruce 2026-10-19 路線二：結果頁的「關係狀態」卡、作戰板的階段、熱度與雷達）。
/// stage、heat、dimensions 來自讀局面多要的三欄，沒通過檢查的不放；dimensions 要熱度與四個維度
/// 都在才放（App 的雷達是五個角，heat 就是熱度）。herMove、willingness 是本來就有的標記，一定有。
export interface GuideV3RelationView {
  readonly stage?: GameStage;
  readonly heat?: number;
  readonly dimensions?: {
    readonly heat: number;
    readonly engagement: number;
    readonly topicDepth: number;
    readonly replyWillingness: number;
    readonly emotionalConnection: number;
  };
  readonly herMove: HerMoveCode;
  readonly willingness: ReadTags["replyWillingness"];
}

/// 三欄都沒通過檢查就沒有 relation（判讀跟開關沒開一樣）。
export function relationView(
  read: RelationRead,
  tags: Pick<ReadTags, "herMove" | "replyWillingness">,
): GuideV3RelationView | undefined {
  const dimensions = read.heat !== undefined && read.dimensions
    ? { heat: read.heat, ...read.dimensions }
    : undefined;
  if (!read.stage && read.heat === undefined && !dimensions) return undefined;
  return {
    ...(read.stage ? { stage: read.stage } : {}),
    ...(read.heat !== undefined ? { heat: read.heat } : {}),
    ...(dimensions ? { dimensions } : {}),
    herMove: HER_MOVE_CODE[tags.herMove],
    willingness: tags.replyWillingness,
  };
}

export interface GuideV3CardView {
  /// 預定的第幾張（1 起算）。
  readonly slot: number;
  readonly task: V3CardTaskCode;
  readonly method: MethodCode;
  readonly voice: VoiceCode;
  readonly messages: readonly string[];
  readonly hasInventedDetail: boolean;
  readonly hasBlank: boolean;
}

export function readView(
  plan: GuideV3Plan,
  light: typeof LIGHTS[number] | null,
  relation?: GuideV3RelationView,
): GuideV3ReadView {
  const careKind = plan.careKind ?? "self_harm";
  return {
    guideVersion: GUIDE_V3_VERSION,
    decision: plan.decision,
    light,
    judgment: plan.judgment,
    ...(plan.decision === "hold" ? { waitFor: plan.waitFor } : {}),
    ...(plan.decision === "care"
      ? {
        careMessage: careKind === "minor" ? MINOR_MESSAGE : CARE_MESSAGE,
        careKind,
      }
      : {}),
    ...(plan.decision !== "care" && plan.signals
      ? {
        inviteReadiness: INVITE_READINESS_CODE[plan.signals.inviteReadiness],
        cold: { ...plan.signals.cold },
      }
      : {}),
    plannedCards: plan.specs.map((spec, i) => ({
      slot: i + 1,
      task: TASK_CODE[spec.task],
      locked: false,
    })),
    // 自傷關心、未成年只顯示固定訊息，關係狀態沒有意義，不帶（Bruce 2026-10-19 路線二）。
    ...(plan.decision !== "care" && relation ? { relation } : {}),
  };
}

export function cardView(
  slot: number,
  spec: CardSpec,
  messages: readonly string[],
  hasInventedDetail: boolean,
): GuideV3CardView {
  return {
    slot,
    task: TASK_CODE[spec.task],
    method: METHOD_CODE[spec.method],
    voice: VOICE_CODE[spec.voice],
    messages,
    hasInventedDetail,
    hasBlank: messages.some((m) => BLANK_PATTERN.test(m)),
  };
}

export function readEvent(view: GuideV3ReadView): Record<string, unknown> {
  return { type: GUIDE_V3_READ_EVENT, ...view };
}

export function cardEvent(view: GuideV3CardView): Record<string, unknown> {
  return { type: GUIDE_V3_CARD_EVENT, ...view };
}

/// card＝那張卡 analysis.card 事件的 slot。
export function cardExplainEvent(
  card: number,
  text: string,
): Record<string, unknown> {
  return { type: GUIDE_V3_CARD_EXPLAIN_EVENT, card, text };
}

/// 兩段式實驗的說明步驟紀錄（只進伺服器的 trace）。status：ok＝有回（送出的在 delivered，
/// 沒過檢查或沒寫到的在 removed）；failed＝呼叫失敗或逾時（code）；invalid＝回的格式壞了；
/// skipped＝沒打（沒有呼叫、或 App 已斷線）。texts 是送出的說明原文（跟卡同一類產品輸出）。
export interface GuideV3ExplainTrace {
  readonly status: "ok" | "failed" | "invalid" | "skipped";
  readonly code?: string;
  readonly model?: string;
  readonly latencyMs: number | null;
  readonly delivered: readonly number[];
  readonly removed: readonly { card: number; reason: string }[];
  readonly texts?: readonly { card: number; text: string }[];
}

/// 伺服器專用：讀局面標記、卡片規格、條目與被拿掉的卡。存進 final_result_json，
/// 送 App 前由 stripClientHiddenFinalResult 剝掉。
export interface GuideV3Trace {
  readonly tags: unknown;
  readonly push: string | null;
  readonly specs: readonly CardSpec[];
  readonly entries: readonly string[];
  /// 被定稿檢查拿掉的卡：原因，加上模型寫的原文（跟送出的卡同一類資料、同樣保存 30 天，
  /// 誤擋時才查得到；Eric 2026-10-18）。
  readonly removed: readonly {
    slot: number;
    reason: string;
    messages?: readonly string[];
    detail?: readonly string[];
  }[];
  readonly invalidLines: number;
  readonly scoringWords: readonly { slot: number; words: readonly string[] }[];
  /// 預設口吻的「妳」被換掉時留的原文；帶了上一輪的那次只留第幾張與則數
  ///（previous_round.ts 的 traceWithoutText）。
  readonly rawMessages: readonly (
    | { slot: number; messages: readonly string[] }
    | { slot: number; messageCount: number }
  )[];
  readonly models: { read?: string; write?: string };
  readonly firstCardMs: number | null;
  /// 有寫卡才有：送出的每張卡的 C5 檢查（cards.ts，只有數字與真假），以及她最後一輪的字數。
  readonly checks?: readonly CardChecks[];
  /// 有寫卡才有：送出的卡裡，開頭跟前面某一張一樣的張數（cards.ts sameOpeningCount）。
  readonly sameOpening?: number;
  readonly herLastTurnChars?: number;
  /// 有打對象記憶才有（只有計數，見 memory.ts）。
  readonly memory?: GuideV3MemoryTrace;
  /// 關係訊號開關開、讀局面成功才有：通過檢查的階段、熱度與四個維度，加上拿掉的欄位（只有代碼
  /// 與數字，見 relation.ts）。
  readonly relation?: GuideV3RelationTrace;
  /// care 才有：哪一種固定訊息、誰判出來的；讀局面失敗才靠關鍵字給的，記失敗的錯誤碼；
  /// 額度不夠、沒讀局面就直接給的，標 insufficientQuota（Eric 2026-10-18）。
  readonly care?: {
    readonly kind: GuideV3CareKind;
    readonly trigger: GuideV3CareTrigger;
    readonly readFailedCode?: string;
    readonly insufficientQuota?: boolean;
  };
  /// 程式關鍵字有命中才有（safety.ts；只有真假，不放原句）。
  readonly keywordHits?: SafetyKeywordHits;
  /// 有帶上一輪脈絡才有（只有數量，見 previous_round.ts）。
  readonly previousRound?: GuideV3PreviousRoundTrace;
  /// 兩段式實驗開了、有出卡才有：說明步驟的結果。
  readonly twoStage?: { readonly explain: GuideV3ExplainTrace };
  /// 口吻與斷句交給程式開著、有出卡才有：他的打字習慣與整組改了幾處（只有次數，不放字）。
  readonly typingStyle?: {
    readonly habits: TypingHabits;
    readonly changes: TypingChanges;
  };
  /// 「這題」「不怪」「滿→蠻」開著、有出卡才有：她最新這一輪提到幾種擔心、是不是自己在講題目，與整組
  /// 改了幾處（只有次數與真假，不放字；phrase_tidy.ts）。
  readonly phraseTidy?: {
    readonly herWorries: number;
    readonly herQuizWords: boolean;
    readonly changes: PhraseTidyChanges;
  };
}

/// 兩段式實驗的「為什麼這樣回」放進結果的 key（App 573b71ee 的 guide_v3_result.dart 讀這個）：
/// 續看只重播結果、不重播 analysis.card_explain，說明要跟卡一起存，才取得回來（主審第 1 輪 P2）。
export const GUIDE_V3_CARD_EXPLAINS_KEY = "cardExplains";

export interface GuideV3CardExplain {
  /// 那張卡的 slot（analysis.card 的 slot）。
  readonly card: number;
  readonly text: string;
}

export function finalResult(args: {
  readonly read: GuideV3ReadView;
  readonly cards: readonly GuideV3CardView[];
  /// 兩段式實驗才有：通過檢查、送出的說明（照卡號排）；沒有就不放這個 key。
  readonly cardExplains?: readonly GuideV3CardExplain[];
  readonly partial: boolean;
  readonly usage: Record<string, unknown>;
  readonly telemetry: Record<string, unknown>;
  readonly trace: GuideV3Trace;
  readonly recovered?: boolean;
  /// 對象記憶（形狀同 v2，provenanceVersion 1）；沒有就不放，App 沿用上一份。
  readonly targetProfile?: Record<string, unknown>;
}): Record<string, unknown> {
  return {
    guideVersion: GUIDE_V3_VERSION,
    read: args.read,
    cards: args.cards,
    ...(args.cardExplains && args.cardExplains.length > 0
      ? { [GUIDE_V3_CARD_EXPLAINS_KEY]: args.cardExplains }
      : {}),
    partial: args.partial,
    ...(args.recovered ? { recovered: true } : {}),
    usage: args.usage,
    telemetry: args.telemetry,
    ...(args.targetProfile ? { targetProfile: args.targetProfile } : {}),
    guideV3Trace: args.trace,
  };
}

export function isGuideV3FinalResult(value: unknown): boolean {
  return typeof value === "object" && value !== null &&
    typeof (value as { guideVersion?: unknown }).guideVersion === "string" &&
    Array.isArray((value as { cards?: unknown }).cards);
}
