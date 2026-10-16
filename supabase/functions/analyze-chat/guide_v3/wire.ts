// v3 送給 App 的事件與結果形狀（只給協定版本 3）。v2 的事件型別表
// （stream_events.ts）是模型輸出的解析白名單，v3 事件由伺服器自己產生，不放進去。
import type { V3CardTaskCode } from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import type { GuideV3Decision, GuideV3Plan } from "./plan.ts";
import type { LIGHTS } from "./read_tags.ts";
import type { CardSpec, HisMethod, Task, Voice } from "./rules.ts";

export const GUIDE_V3_READ_EVENT = "analysis.read";
export const GUIDE_V3_CARD_EVENT = "analysis.card";

/// 卡片任務 → 扣費紀錄與 App 用的代碼（migration 20261016120000 的 card_task）。
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

/// 需要他填的空格（提示詞要求寫成「＿＿」）。
const BLANK_PATTERN = /＿/;

export interface GuideV3ReadView {
  readonly guideVersion: string;
  readonly decision: GuideV3Decision;
  readonly light: typeof LIGHTS[number];
  readonly judgment: string;
  readonly waitFor?: string;
  readonly careMessage?: string;
  /// 預定的卡（照順序）；送出的張數可能比較少（被檢查拿掉）。
  readonly plannedCards: readonly { slot: number; task: V3CardTaskCode }[];
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
  light: typeof LIGHTS[number],
): GuideV3ReadView {
  return {
    guideVersion: GUIDE_V3_VERSION,
    decision: plan.decision,
    light,
    judgment: plan.judgment,
    ...(plan.decision === "hold" ? { waitFor: plan.waitFor } : {}),
    ...(plan.decision === "care" ? { careMessage: CARE_MESSAGE } : {}),
    plannedCards: plan.specs.map((spec, i) => ({
      slot: i + 1,
      task: TASK_CODE[spec.task],
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
  readonly removed: readonly { slot: number; reason: string }[];
  readonly invalidLines: number;
  readonly scoringWords: readonly { slot: number; words: readonly string[] }[];
  readonly rawMessages: readonly {
    slot: number;
    messages: readonly string[];
  }[];
  readonly models: { read?: string; write?: string };
  readonly firstCardMs: number | null;
}

export function finalResult(args: {
  readonly read: GuideV3ReadView;
  readonly cards: readonly GuideV3CardView[];
  readonly partial: boolean;
  readonly usage: Record<string, unknown>;
  readonly telemetry: Record<string, unknown>;
  readonly trace: GuideV3Trace;
  readonly recovered?: boolean;
}): Record<string, unknown> {
  return {
    guideVersion: GUIDE_V3_VERSION,
    read: args.read,
    cards: args.cards,
    partial: args.partial,
    ...(args.recovered ? { recovered: true } : {}),
    usage: args.usage,
    telemetry: args.telemetry,
    guideV3Trace: args.trace,
  };
}

export function isGuideV3FinalResult(value: unknown): boolean {
  return typeof value === "object" && value !== null &&
    typeof (value as { guideVersion?: unknown }).guideVersion === "string" &&
    Array.isArray((value as { cards?: unknown }).cards);
}
