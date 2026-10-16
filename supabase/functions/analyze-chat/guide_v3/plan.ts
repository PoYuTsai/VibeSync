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
import type { Turn } from "./turns.ts";

/// send＝出卡；close＝她婉拒或說了界線，一張收尾卡；hold＝先別回；stop＝停；
/// care＝自傷訊號，不出卡，改顯示固定的關心訊息。
export type GuideV3Decision = "send" | "close" | "hold" | "stop" | "care";

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
}

/// 模型沒寫要等什麼時的預設（依先別回的理由）。
export const HOLD_WAIT_FALLBACK = "等她回你，再看她怎麼接";
export const STOP_REASON_CARE = "對話裡有自傷訊號";

export function planTurn(
  turns: readonly Turn[],
  tags: ReadTags,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
): GuideV3Plan {
  if (tags.selfHarmSignal) {
    return {
      decision: "care",
      judgment: "",
      reason: STOP_REASON_CARE,
      waitFor: "",
      push: null,
      specs: [],
      entries: [],
    };
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
