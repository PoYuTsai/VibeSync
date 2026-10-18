// 讀局面之後、寫卡之前：把標記交給 rules.ts，得出這一輪要做什麼（回、先別回、
// 收尾、停、關心），以及每張卡的規格與要帶的情境條目。純函式，不碰模型與資料庫。
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import type { ReadTags } from "./read_tags.ts";
import {
  arrangeCards,
  type CardSpec,
  decidePush,
  decideReply,
  judgmentFor,
  pickEntries,
  type PushAction,
} from "./rules.ts";
import { NO_SAFETY_HITS, type SafetyKeywordHits } from "./safety.ts";
import type { Turn } from "./turns.ts";

/// send＝出卡；close＝她婉拒或說了界線，一張收尾卡；hold＝先別回；stop＝停；
/// care＝不出卡、不扣，改顯示固定訊息（自傷關心，或涉及未成年）。
export type GuideV3Decision = "send" | "close" | "hold" | "stop" | "care";

/// care 的兩種固定訊息（Eric 2026-10-18 加未成年）。送給 App 的決定一樣是 care：舊版 App
/// 照樣只顯示固定文案、不出卡，新版看這一欄換標題；分析看 reason 與這一欄分得開。
export type GuideV3CareKind = "self_harm" | "minor";
/// 誰判出來的：讀局面的模型標記、程式關鍵字（safety.ts），或兩者都有。只進伺服器紀錄，
/// 用來量關鍵字的誤判。
export type GuideV3CareTrigger = "model" | "keyword" | "both";

export interface GuideV3Plan {
  readonly decision: GuideV3Decision;
  /// 給用戶看的局面判讀（B47 換成固定提醒）；care 時是空字串。
  readonly judgment: string;
  /// 程式規則的理由（存進扣費紀錄，不顯示）。
  readonly reason: string;
  /// 先別回時要等她做什麼；其他決定是空字串。
  readonly waitFor: string;
  readonly push: PushAction | null;
  readonly specs: readonly CardSpec[];
  readonly entries: readonly GuideV3Entry[];
  /// care 才有。
  readonly careKind?: GuideV3CareKind;
  readonly careTrigger?: GuideV3CareTrigger;
}

/// 模型沒寫要等什麼時的預設（依先別回的理由）。
export const HOLD_WAIT_FALLBACK = "等她回你，再看她怎麼接";
export const STOP_REASON_CARE = "對話裡有自傷訊號";
export const STOP_REASON_MINOR = "對話涉及未成年";

function carePlan(
  kind: GuideV3CareKind,
  model: boolean,
  keyword: boolean,
): GuideV3Plan {
  return {
    decision: "care",
    judgment: "",
    reason: kind === "minor" ? STOP_REASON_MINOR : STOP_REASON_CARE,
    waitFor: "",
    push: null,
    specs: [],
    entries: [],
    careKind: kind,
    careTrigger: model && keyword ? "both" : model ? "model" : "keyword",
  };
}

/// 讀局面失敗或拒答時，程式關鍵字仍看得出的固定訊息（不給錯誤、不扣）；看不出就 null，
/// 照原本的錯誤處理。
export function planWithoutRead(hits: SafetyKeywordHits): GuideV3Plan | null {
  if (hits.minor) return carePlan("minor", false, true);
  return null;
}

/// 規則先後：自傷關心 → 未成年 → rules.ts 的 C 段規則。自傷排在未成年前面：兩個都有時，
/// 專線比「不提供建議」重要。
export function planTurn(
  turns: readonly Turn[],
  tags: ReadTags,
  hits: SafetyKeywordHits = NO_SAFETY_HITS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
): GuideV3Plan {
  if (tags.selfHarmSignal) return carePlan("self_harm", true, false);
  if (tags.minorSignal || hits.minor) {
    return carePlan("minor", tags.minorSignal, hits.minor);
  }
  const reply = decideReply(turns, tags);
  const push = reply.kind === "send" ? decidePush(turns, tags) : null;
  const specs = arrangeCards(reply, push, tags);
  const judgment = judgmentFor(tags);
  switch (reply.kind) {
    case "hold":
      return {
        decision: "hold",
        judgment,
        reason: reply.reason,
        waitFor: tags.waitFor.trim() || HOLD_WAIT_FALLBACK,
        push: null,
        specs: [],
        entries: [],
      };
    case "stop":
      return {
        decision: "stop",
        judgment,
        reason: reply.reason,
        waitFor: "",
        push: null,
        specs: [],
        entries: [],
      };
    case "close":
      return {
        decision: "close",
        judgment,
        reason: reply.reason,
        waitFor: "",
        push: null,
        specs,
        entries: pickEntries(tags.matchedEntries, entries),
      };
    case "send":
      return {
        decision: "send",
        judgment,
        reason: "照常回",
        waitFor: "",
        push,
        specs,
        entries: pickEntries(tags.matchedEntries, entries),
      };
  }
}
