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
/// 用來看是哪一層判出來的。
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

/// 讀局面失敗、拒答或逾時時，程式關鍵字仍看得出的固定訊息（不給錯誤、不扣）：自傷給關心
/// 訊息（附專線），其次未成年；都看不出就 null，照原本的錯誤處理。
export function planWithoutRead(hits: SafetyKeywordHits): GuideV3Plan | null {
  if (hits.selfHarmWords || hits.wantsToDie) {
    return carePlan("self_harm", false, true);
  }
  if (hits.minorWords) return carePlan("minor", false, true);
  return null;
}

/// 規則先後：自傷關心 → 未成年 → rules.ts 的 C 段規則。自傷排在未成年前面：兩個都有時，
/// 專線比「不提供建議」重要。自傷：模型標了，或她的訊息有自殺、自殘、割腕、輕生、不想活
/// 這些字，一律關心（Eric 2026-10-18）。讀局面成功時，未成年只看模型的 minorSignal（主審
/// 第 1 輪：句型關鍵字會把老師、講以前的事誤擋，模型在黑箱 6/6 都判對）。
export function planTurn(
  turns: readonly Turn[],
  tags: ReadTags,
  hits: SafetyKeywordHits = NO_SAFETY_HITS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
): GuideV3Plan {
  if (tags.selfHarmSignal || hits.selfHarmWords) {
    return carePlan("self_harm", tags.selfHarmSignal, hits.selfHarmWords);
  }
  if (tags.minorSignal) return carePlan("minor", true, false);
  // 她要他借錢、轉帳、投資或下載 App（程式關鍵字）跟讀局面的風險標記同樣處理：不排推進、
  // 判讀換成固定提醒（B47 的做法；Eric 2026-10-18）。trace 另記模型原本的標記與關鍵字命中。
  const ruled = hits.money && !tags.risk ? { ...tags, risk: true } : tags;
  const reply = decideReply(turns, ruled);
  const push = reply.kind === "send" ? decidePush(turns, ruled) : null;
  const specs = arrangeCards(reply, push, ruled);
  const judgment = judgmentFor(ruled);
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
