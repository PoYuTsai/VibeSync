// v3 送給 App 的事件與結果形狀（只給協定版本 3）。v2 的事件型別表
// （stream_events.ts）是模型輸出的解析白名單，v3 事件由伺服器自己產生，不放進去。
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
import type { LIGHTS } from "./read_tags.ts";
import type { CardSpec, HisMethod, Task, Voice } from "./rules.ts";
import type { SafetyKeywordHits } from "./safety.ts";

export const GUIDE_V3_READ_EVENT = "analysis.read";
export const GUIDE_V3_CARD_EVENT = "analysis.card";

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
  /// 預定的卡（照順序）；送出的張數可能比較少（被檢查拿掉）。locked＝這個方案看
  /// 不到（免費方案只送前幾張），伺服器不會寫也不會送那幾張。
  readonly plannedCards: readonly {
    slot: number;
    task: V3CardTaskCode;
    locked: boolean;
  }[];
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
  maxCards: number | null = null,
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
    plannedCards: plan.specs.map((spec, i) => ({
      slot: i + 1,
      task: TASK_CODE[spec.task],
      locked: maxCards !== null && i >= maxCards,
    })),
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
  readonly herLastTurnChars?: number;
  /// 有打對象記憶才有（只有計數，見 memory.ts）。
  readonly memory?: GuideV3MemoryTrace;
  /// care 才有：哪一種固定訊息、誰判出來的；讀局面失敗才靠關鍵字給的，記失敗的錯誤碼。
  readonly care?: {
    readonly kind: GuideV3CareKind;
    readonly trigger: GuideV3CareTrigger;
    readonly readFailedCode?: string;
  };
  /// 程式關鍵字有命中才有（safety.ts；只有真假，不放原句）。
  readonly keywordHits?: SafetyKeywordHits;
  /// 有帶上一輪脈絡才有（只有數量，見 previous_round.ts）。
  readonly previousRound?: GuideV3PreviousRoundTrace;
}

export function finalResult(args: {
  readonly read: GuideV3ReadView;
  readonly cards: readonly GuideV3CardView[];
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
