// 讀局面之後、寫卡之前：把標記交給 rules.ts，得出這一輪要做什麼（回、先別回、
// 收尾、停、關心），以及每張卡的規格與要帶的情境條目。純函式，不碰模型與資料庫。
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import type { INVITE_READINESS, ReadTags, TwoStageTags } from "./read_tags.ts";
import {
  arrangeCards,
  arrangeSweetShort,
  assignAnswers,
  type CardSpec,
  decidePush,
  decideReply,
  herPerfunctoryStreak,
  judgmentFor,
  PERFUNCTORY_HOLD_REASON,
  pickEntries,
  pickWriterEntries,
  type PraiseStyle,
  praiseStyle,
  type PushAction,
  withoutCoupleSeed,
} from "./rules.ts";
import { NO_SAFETY_HITS, type SafetyKeywordHits } from "./safety.ts";
import { latestHerMessages, type Turn } from "./turns.ts";

/// send＝出卡；close＝她婉拒或說了界線，一張收尾卡；hold＝先別回；stop＝停；
/// care＝不出卡、不扣，改顯示固定訊息（自傷關心，或涉及未成年）。
export type GuideV3Decision = "send" | "close" | "hold" | "stop" | "care";

/// care 的兩種固定訊息（Eric 2026-10-18 加未成年）。送給 App 的決定一樣是 care：舊版 App
/// 照樣只顯示固定文案、不出卡，新版看這一欄換標題；分析看 reason 與這一欄分得開。
export type GuideV3CareKind = "self_harm" | "minor";
/// 誰判出來的：讀局面的模型標記、程式關鍵字（safety.ts），或兩者都有。只進伺服器紀錄，
/// 用來看是哪一層判出來的。
export type GuideV3CareTrigger = "model" | "keyword" | "both";

/// 讀局面成功、不是 care 才有：邀約進度，以及給新話題的冷訊號（Eric 2026-10-18；不分方案）。
/// c1＝這一輪是 C1「他連續主動兩次、她都只回敷衍的字」判的先別回（被停、B47 蓋過就不算）；
/// herPerfunctoryStreak＝她最近連續幾輪只回敷衍的字。
export interface GuideV3Signals {
  readonly inviteReadiness: typeof INVITE_READINESS[number];
  readonly cold: {
    readonly c1: boolean;
    readonly herPerfunctoryStreak: number;
  };
}

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
  /// 寫卡瘦身（開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Eric 2026-10-27「照預設」）開著、出卡或收尾才有：只給寫卡用的條目（排除
  /// B43、B45、B46、B47，rules.ts pickWriterEntries）。B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」）。
  /// 說明步驟與 trace 照舊用 entries；沒開時沒有這個欄位。
  readonly writerEntries?: readonly GuideV3Entry[];
  /// care 才有。
  readonly careKind?: GuideV3CareKind;
  readonly careTrigger?: GuideV3CareTrigger;
  /// care 沒有。
  readonly signals?: GuideV3Signals;
  /// 兩段式實驗開著、出卡或收尾才有：誇她的方式（rules.ts praiseStyle）。
  readonly praise?: PraiseStyle;
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

/// 兩段式實驗：每張卡記下要回她最新這一輪的哪幾則（rules.ts assignAnswers）；沒有可指定的
///（她值得接的只有照片、貼圖或表情）就不加欄位。
function withAnswers(
  specs: CardSpec[],
  turns: readonly Turn[],
  twoStage: TwoStageTags | undefined,
  /// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT）：她最新那句是很短的甜話時改排（rules.ts arrangeSweetShort）。
  sweetShort = false,
): CardSpec[] {
  if (!twoStage || specs.length === 0) return specs;
  const herLatest = latestHerMessages(turns);
  const answers = assignAnswers(
    specs.length,
    twoStage.worthyLines,
    herLatest,
  );
  const answered = specs.map((spec, i) => {
    const answer = answers[i];
    return answer ? { ...spec, answer } : spec;
  });
  return sweetShort
    ? arrangeSweetShort(answered, twoStage, herLatest)
    : answered;
}

/// 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE）：抽到輕輕誇的短版時，挑一張卡寫短版的誇法——有回她
/// 最想聽那則的接住先，其次共鳴，再其次其他有指定那則的卡（推進、收不放）；都沒有就不放。
function withShortPraise(specs: CardSpec[]): CardSpec[] {
  const eligible = (task: CardSpec["task"]) =>
    specs.findIndex((s) => s.answer !== undefined && s.task === task);
  let at = eligible("接住");
  if (at === -1) at = eligible("共鳴");
  if (at === -1) {
    at = specs.findIndex((s) =>
      s.answer !== undefined && s.task !== "推進" && s.task !== "收"
    );
  }
  return at === -1
    ? specs
    : specs.map((s, i) => i === at ? { ...s, shortPraise: true as const } : s);
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

/// 額度不夠時（Eric 2026-10-18）：她的訊息有自殺、自殘、割腕、輕生、不想活任一個字，就不讀
/// 局面、直接給自傷關心訊息（附專線）。「想死」與未成年不算，照額度不足處理（null）。
export function planCareFromQuota(hits: SafetyKeywordHits): GuideV3Plan | null {
  return hits.selfHarmWords ? carePlan("self_harm", false, true) : null;
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
  /// 兩段式實驗的讀局面四欄（開關 ANALYZE_GUIDE_V3_TWO_STAGE）；沒給就跟今天一樣。
  twoStage?: TwoStageTags,
  /// 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE）：這次分析抽到輕輕誇的短版（rules.ts lightShortRun）。
  /// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）：她最新那句是很短的甜話時，只有一張卡回那句、
  /// 其他卡回她別的話，沒有別的話就少出幾張（rules.ts arrangeSweetShort）。
  /// 不記帳不承諾（開關 ANALYZE_GUIDE_V3_NO_IOU，Bruce 2026-10-22「不要」）：已經在交往、她撒嬌或喊累時不排推進（種子）
  ///（rules.ts withoutCoupleSeed）；只在有兩段式的讀局面欄位時有作用。
  /// 寫卡瘦身（開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Bruce 2026-10-26；Eric 2026-10-27「照預設」）：出卡、收尾的計畫多一欄
  /// writerEntries（寫卡看不到 B43、B45、B46、B47）；B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」）。
  /// 決定、排卡、判讀與 entries 都不變。只在兩段式開時才會給（stream_flow.ts 把關）。
  options: {
    readonly lightShortPraise?: boolean;
    readonly sweetShort?: boolean;
    readonly noIou?: boolean;
    readonly writerTrim?: boolean;
  } = {},
): GuideV3Plan {
  if (tags.selfHarmSignal || hits.selfHarmWords) {
    return carePlan("self_harm", tags.selfHarmSignal, hits.selfHarmWords);
  }
  if (tags.minorSignal) return carePlan("minor", true, false);
  const reply = decideReply(turns, tags);
  const decided = reply.kind === "send" ? decidePush(turns, tags) : null;
  // 在排卡之前換：張數、任務、問句、甜話短回那張排在哪，以及計畫、trace 裡的 push，都照沒有推進的排法走。
  const push = options.noIou === true && twoStage
    ? withoutCoupleSeed(decided, twoStage)
    : decided;
  const answeredSpecs = withAnswers(
    arrangeCards(reply, push, tags, twoStage),
    turns,
    twoStage,
    // 只在照常出卡時排：婉拒收尾那一張要回她的婉拒；詐騙換地方的三張固定排法不動。
    options.sweetShort === true && reply.kind === "send" && push !== "換地方",
  );
  const judgment = judgmentFor(tags);
  const praiseValue = twoStage
    ? praiseStyle(twoStage, options.lightShortPraise === true)
    : undefined;
  const praise = praiseValue ? { praise: praiseValue } : {};
  // 寫卡瘦身：沒開時計畫一個 key 都不多（trace 與既有雜湊不變）。
  const writerEntries = options.writerTrim === true
    ? { writerEntries: pickWriterEntries(tags.matchedEntries, entries) }
    : {};
  // 短版只放在一張卡、接在她最想聽的那則後面（第 3 輪真跑：只寫在稱讚那段時，寫出來還是一般的回法）。
  const specs = praiseValue === "light_short"
    ? withShortPraise(answeredSpecs)
    : answeredSpecs;
  const signals: GuideV3Signals = {
    inviteReadiness: tags.inviteReadiness,
    cold: {
      c1: reply.kind === "hold" && reply.reason === PERFUNCTORY_HOLD_REASON,
      herPerfunctoryStreak: herPerfunctoryStreak(turns, tags),
    },
  };
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
        signals,
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
        signals,
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
        signals,
        ...praise,
        ...writerEntries,
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
        signals,
        ...praise,
        ...writerEntries,
      };
  }
}
