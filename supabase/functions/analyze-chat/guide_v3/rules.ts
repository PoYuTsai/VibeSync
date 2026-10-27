// 程式規則（說明書 C 段，含 Bruce 10/14、10/15 的決定）：要不要回、推進動作、每張卡的規格、
// 挑情境條目，以及給用戶看的判斷。函式不用 C1–C4 命名（測試裡的「C1–C4」已被畫面重構用掉）。
//
// 規則先後（前面的蓋過後面的；rules_prompts_test.ts「規則先後」逐組釘住）：
// 1. 自傷訊號、涉及未成年：固定訊息，不出卡（plan.ts，比這裡所有規則都先；自傷再先於未成年）。
// 2. 明確拒絕或封鎖：停（被封鎖時最常是他最後一則，要先判，不能落到先別回；Eric 2026-10-18）。
// 3. 他是最後一則：先別回。
// 4. B47（指定店家、換地方不肯）：照常出卡，只排「推進（換地方）、收、推進」，判斷換成固定提醒；
//    不受 B46 不排推進、她直接問他時第一張排接住、婉拒收尾影響。沒有 B47 時，讀局面標到風險就
//    不排推進，判斷換成金錢、詐騙的固定提醒。
// 5. 他連續主動兩次、她都只回敷衍的字：先別回。
// 6. 她取消約會：照常出卡（推進：改天或說定）；她說太快了（B34）：照常出卡、不當收尾；
//    婉拒或界線：一張收尾。
// 7. 排卡：B34、B46 不排推進，蓋過「她給了機會至少一張推進」；B43–B46 帶張力改排接住，
//    蓋過「綠燈至少一張帶張力」；最後她直接問他時，第一張排接住。
// 8. 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19；沒開時這條不存在）：綠燈帶張力
//    最多一張，已在交往或她撒嬌示愛時不排；她分享開心的事（她情緒差時不算）第二張改成共鳴；
//    最後每張卡都指定先回她最想聽的那則、可以順帶一則（第 2 輪，Bruce 10/19 盲選理由）。
//    上面 1–7 都照舊先算。
// 9. 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」；沒開時這條不存在）：她撒嬌、這一輪有讀局面標成
//    撒嬌的很短的一則時（不一定是本來先回的那則；她問了他什麼就不算），只有一張卡回那句（短短回一句），其他卡改回她別的話、
//    不提任何一句很短的甜話；她沒有別的話就少出幾張、至少 3 張（arrangeSweetShort）。上面 1–8 都照舊先算；婉拒收尾、詐騙
//    換地方的固定排法不動（plan.ts 把關）。
// 10. 不記帳不承諾（開關 ANALYZE_GUIDE_V3_NO_IOU，Bruce 2026-10-22「不要」；沒開時這條不存在）：decidePush 算出種子、已經在
//    交往、她這一輪撒嬌示愛或喊累時，這次不推進（withoutCoupleSeed，plan.ts 在排卡之前換）；張數、任務照沒有推進的排法走，
//    9 也照這個排。其他推進（具體邀約、說定、改天、換地方）、還沒交往都照舊。跟 9 各自獨立。
// （寫卡瘦身，開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Bruce 2026-10-26；不是排卡的規則：上面 1–10 都不動，只是寫卡拿到的條目先排除
//  B43、B45、B46、B47，見 pickWriterEntries。B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」）。）
import { withoutEmoji } from "./cards.ts";
import type { GuideV3Entry } from "./entries.ts";
import {
  type ReadTags,
  SWEET_LINE_KIND,
  type TwoStageTags,
  type WorthyLine,
  type WorthyLineKind,
} from "./read_tags.ts";
import type { Turn } from "./turns.ts";

export type ReplyDecision =
  | { readonly kind: "send" }
  | { readonly kind: "hold"; readonly reason: string }
  | { readonly kind: "close"; readonly reason: string }
  | { readonly kind: "stop"; readonly reason: string };

/// 從最後往前數「他一輪、她敷衍一輪」連續幾組；最後一輪不是她就是 0。
export function perfunctoryStreak(
  turns: readonly Turn[],
  tags: Pick<ReadTags, "herTurnsPerfunctory">,
): number {
  const flags = new Map(
    tags.herTurnsPerfunctory.map((t) => [t.turn, t.perfunctory]),
  );
  let count = 0;
  for (let i = turns.length - 1; i >= 1; i -= 2) {
    const her = turns[i];
    const him = turns[i - 1];
    if (her.fromMe || !him.fromMe || flags.get(her.index) !== true) break;
    count++;
  }
  return count;
}

/// 她最近連續幾輪只回敷衍的字：從她最新的一輪往前數，碰到沒標敷衍的就停；最後一則是他
/// 也照數。給新話題的冷訊號（Eric 2026-10-18）；C1 要不要回仍只看 perfunctoryStreak。
export function herPerfunctoryStreak(
  turns: readonly Turn[],
  tags: Pick<ReadTags, "herTurnsPerfunctory">,
): number {
  const flags = new Map(
    tags.herTurnsPerfunctory.map((t) => [t.turn, t.perfunctory]),
  );
  let count = 0;
  for (let i = turns.length - 1; i >= 0; i--) {
    if (turns[i].fromMe) continue;
    if (flags.get(turns[i].index) !== true) break;
    count++;
  }
  return count;
}

/// C1「他連續主動兩次、她都只回敷衍的字」判的先別回。plan.ts 認這個理由給冷訊號的 c1，
/// 不另寫一份判斷。
export const PERFUNCTORY_HOLD_REASON = "他連續主動兩次，她都只回敷衍的字";

/// C1 要不要回。v3 的順序：明確拒絕或封鎖就停（她拒絕後他又追問、或被封鎖時他是最後
/// 一則，也是停）；他是最後一則先別回；他連續主動兩次、她都只回敷衍的字就先別回（不附
/// 備用句）；她取消約會不是只回收尾（交給推進）；她說太快了（B34）照常回；她婉拒或說了
/// 界線就一句中性收尾；其他照常回（她只冷一次也照常回）。
export function decideReply(
  turns: readonly Turn[],
  tags: ReadTags,
): ReplyDecision {
  if (tags.blocked || tags.explicitRejection) {
    return { kind: "stop", reason: "明確拒絕或封鎖" };
  }
  if (turns.length === 0 || turns.at(-1)!.fromMe) {
    return { kind: "hold", reason: "他的訊息是最後一則" };
  }
  // B47（v3.3 第一輪：讀局面會把「她不肯換地方」也標成婉拒，結果只剩一張收尾）：
  // 不當婉拒收尾，照 Bruce 出「堅持換地方」和「這次先不約」兩種卡。
  if (matchedSet(tags).has(SCAM_VENUE_ENTRY)) return { kind: "send" };
  if (perfunctoryStreak(turns, tags) >= 2) {
    return { kind: "hold", reason: PERFUNCTORY_HOLD_REASON };
  }
  if (tags.inviteReadiness === "她取消了") return { kind: "send" };
  // B34：照常聊、不當收尾（Bruce 10/18）。讀局面可能把「我想慢一點」標成界線，那樣會只剩
  // 一張收尾。
  if (matchedSet(tags).has(SLOW_DOWN_ENTRY)) return { kind: "send" };
  if (tags.declinedOrBoundary) {
    return { kind: "close", reason: "她婉拒或說了界線" };
  }
  return { kind: "send" };
}

export type PushAction = "種子" | "具體邀約" | "說定" | "改天" | "換地方";

/// v3.3 C4（Bruce 10/15）：標到這些條目時，帶張力改排接住（她解釋自己、討他的看法、
/// 問他喜歡怎樣的人、對自己的投入不好意思）。
export const NO_TENSION_ENTRIES: readonly string[] = [
  "B43",
  "B44",
  "B45",
  "B46",
];
/// B34（她說太快了、想慢一點）：照常聊、不推進，也不當收尾（Bruce 10/18，Eric 2026-10-19）。
export const SLOW_DOWN_ENTRY = "B34";
/// 標到 B34、B46（她對自己的投入不好意思）時不排推進：不靠讀局面有沒有標 retreating。
export const NO_PUSH_ENTRIES: readonly string[] = [SLOW_DOWN_ENTRY, "B46"];
/// B33（兩次提案都被帶過）：不再排推進，照常聊（Bruce 已定的規格，Eric 2026-10-18 要程式照做）。
/// 她自己提見面或明確答應時照常推進：B33 的寫法本來就是等她自己開口。
export const BRUSHED_OFF_TWICE_ENTRY = "B33";
/// B47：她約第一次見面指定某家酒吧或餐廳，他提議換地方她不肯。
export const SCAM_VENUE_ENTRY = "B47";
export const SCAM_VENUE_WARNING =
  "她堅持約在她指定的店、換地方也不肯，小心可能是酒托或飯托。可以堅持換你找的地方，或這次先不約。";
/// 她直接問他：第一張排接住，推進放後面（Bruce 10/15）。
const DIRECT_QUESTION_MOVES: readonly string[] = [
  "問他的事",
  "問他意見",
  "認真問",
];

function matchedSet(tags: Pick<ReadTags, "matchedEntries">): Set<string> {
  return new Set(tags.matchedEntries.map((m) => m.trim()));
}

/// C3 邀約動作（簡化）。C2 的天數與次數要等紀錄接進分析，在那之前照預設：婉拒過、猶豫都先不推進。
export function decidePush(
  turns: readonly Turn[],
  tags: ReadTags,
): PushAction | null {
  const matched = matchedSet(tags);
  // B47：只出「堅持換地方」或「這次先不約」；風險標記也照出換地方的推進卡。
  if (matched.has(SCAM_VENUE_ENTRY)) return "換地方";
  if (NO_PUSH_ENTRIES.some((id) => matched.has(id))) return null;
  if (
    tags.herMoodBad || tags.drunkOrLateNight || tags.retreating || tags.risk ||
    tags.light === "red"
  ) return null;
  if (
    matched.has(BRUSHED_OFF_TWICE_ENTRY) &&
    tags.inviteReadiness !== "她自己提見面" &&
    tags.inviteReadiness !== "明確答應"
  ) return null;
  switch (tags.inviteReadiness) {
    case "明確答應":
      return "說定";
    case "她自己提見面":
    case "含糊答應":
      return "具體邀約";
    case "她取消了":
      return tags.cancelHasAlternative ? "說定" : "改天";
    case "婉拒過":
    case "猶豫":
      return null;
  }
  if (tags.herMove === "開窗") return "具體邀約";
  const hisTurns = turns.filter((t) => t.fromMe).length;
  const herTurns = turns.length - hisTurns;
  // 種子不用等綠燈（Bruce 10/13）：黃燈聊開了也種；紅燈上面已經擋掉。
  if (hisTurns >= 2 && herTurns >= 2) return "種子";
  return null;
}

/// 不記帳不承諾（開關 ANALYZE_GUIDE_V3_NO_IOU；Bruce 2026-10-22 PR #97 盲選回覆：「已經在交往、她撒嬌或喊累時，排一張「下次約」
/// 的卡：不要」）：decidePush 給種子、讀局面標已經在交往、而且她這一輪撒嬌示愛或喊累（herTired，開關開時讀局面才標）時，這次
/// 不推進（回 null）；其他情況原樣回。只拿掉種子：具體邀約、說定、改天、換地方是她自己給的機會或固定排法，照舊；還沒交往照舊。
export function withoutCoupleSeed(
  push: PushAction | null,
  twoStage: Pick<
    TwoStageTags,
    "establishedCouple" | "herAffection" | "herTired"
  >,
): PushAction | null {
  return push === "種子" && twoStage.establishedCouple &&
      (twoStage.herAffection || twoStage.herTired === true)
    ? null
    : push;
}

export type Task = "接住" | "共鳴" | "帶張力" | "推進" | "收";
export type HisMethod = "只用反應" | "用他說過的" | "留空格" | "照樣寫＋標示";
export type Voice = "照他" | "預設";

export interface CardSpec {
  readonly task: Task;
  readonly method: HisMethod;
  readonly voice: Voice;
  readonly questionBudget: 0 | 1;
  readonly push: PushAction | null;
  /// 同規格的第幾張（0 起算）；大於 0 時要換切入點。
  readonly angle: number;
  /// 兩段式實驗才有（沒開時沒有這兩個欄位）：這張要回她最新這一輪的哪幾則（assignAnswers），
  /// 以及她分享開心的事時換上的那張共鳴。
  readonly answer?: CardAnswer;
  readonly note?: "happy_share";
  /// 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE，Bruce 2026-10-20「可以」）：這次抽到短版時，只有這一張的
  /// 規格在「這張接」後面寫短版的誇法（plan.ts 挑第一張回她那則的接住）；其他時候沒有這個欄位。
  readonly shortPraise?: true;
  /// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）：回她那句很短甜話的卡，規格在「這張接」
  /// 後面多寫短回的指示（arrangeSweetShort 排）；其他時候沒有這個欄位。
  readonly sweetShort?: true;
}

/// 兩段式實驗：她最新這一輪的第幾則（1 起算）。with＝併進這一則一起看的照片、貼圖或只有表情的
/// 那幾則：它們不單獨當一張卡要回的對象（第 2 輪，Bruce 10/19：不用特別去評價她的貼圖）。
export interface AnswerLine {
  readonly line: number;
  readonly with: readonly number[];
}

/// main＝她最想聽他回的那則，每張卡都一樣；extra＝這張可以順帶的一則（可以沒有）。
export interface CardAnswer {
  readonly main: AnswerLine;
  readonly extra?: AnswerLine;
}

/// C4 每次幾張：情緒差、黃燈、紅燈、問他的事但缺他的資料是 3；綠燈而且她給了機會、
/// 或一輪丟了好幾顆值得接的球是 5；一般綠燈 4。
export function cardCount(tags: ReadTags, push: PushAction | null): number {
  if (push === "換地方") return 3;
  const asksHimWithoutFacts =
    (tags.herMove === "問他的事" || tags.identityQuestion) &&
    tags.hisStatedFacts.length === 0;
  if (tags.herMoodBad || tags.light !== "green" || asksHimWithoutFacts) {
    return 3;
  }
  if (
    push === "具體邀約" || push === "說定" || push === "改天" ||
    tags.herMove === "開窗" || tags.worthyBallCount >= 2
  ) return 5;
  return 4;
}

function tasksFor(
  tags: ReadTags,
  push: PushAction | null,
  n: number,
  twoStage?: TwoStageTags,
): Task[] {
  // B47：推進（換地方）、收（這次先不約）、推進（換個切入點）。
  if (push === "換地方") return ["推進", "收", "推進"];
  if (tags.herMoodBad) return Array(n).fill("共鳴");
  if (tags.drunkOrLateNight) {
    return Array.from({ length: n }, (_, i) => i % 2 === 0 ? "共鳴" : "接住");
  }
  // 預設：紅燈只用接住和收（她大笑收尾也是這樣排）。
  if (tags.light === "red") {
    return [...Array(n - 1).fill("接住"), "收"];
  }
  // 她大笑收尾：一張收。綠燈照 C4 原樣，另外還是要一張帶張力，讓他也可以選擇繼續玩
  //（Bruce 10/14）。帶張力是綠燈的規則：黃燈的收之外照下面一般的排法，不排帶張力，聊開了
  // 選的種子照樣排進來（Bruce 10/18 黃燈維持現在；主審第 1 輪 P2）。
  const laughClose = tags.herMove === "大笑收尾";
  // 她大笑收尾但已經答應邀約（Bruce 10/19）：第一張排那張推進（明確答應就說定時間地點，含糊
  // 答應由他講具體），這張本身就是收尾，不另排收；其餘照原本的排法。標到 B34 時 decidePush
  // 不推進，照舊排收；聊開了的種子不在這條裡，照舊。
  const acceptedInvite = laughClose && (
    (tags.inviteReadiness === "含糊答應" && push === "具體邀約") ||
    (tags.inviteReadiness === "明確答應" && push === "說定")
  );
  if (laughClose && tags.light === "green") {
    return [
      acceptedInvite ? "推進" : "收",
      "帶張力",
      ...Array(n - 2).fill("接住"),
    ];
  }
  const tasks: Task[] = laughClose && !acceptedInvite ? ["收"] : [];
  if (push) {
    tasks.push(...Array(n >= 5 && push === "具體邀約" ? 2 : 1).fill("推進"));
  }
  // 兩段式實驗：綠燈最多一張（研究 §2.2：刻意句 76%、擺姿態 9/10 都在帶張力；Eric 2026-10-19）。
  const tension = tags.light === "green" ? (n >= 4 && !twoStage ? 2 : 1) : 0;
  const rest = n - tasks.length;
  // 接住、帶張力交錯；放不下就從後面補滿帶張力的張數。
  const fill: Task[] = Array(rest).fill("接住");
  let placed = 0;
  for (let i = 1; i < rest && placed < tension; i += 2) {
    fill[i] = "帶張力";
    placed++;
  }
  for (let i = rest - 1; i >= 0 && placed < tension; i--) {
    if (fill[i] === "接住") {
      fill[i] = "帶張力";
      placed++;
    }
  }
  return [...tasks, ...fill];
}

/// C4「有他」：身分題只能留空格（他說過的可以用）；缺他的事實時至少一張留空格；
/// 照樣寫＋標示最多一張，只用在接住或帶張力，她情緒差、推進、她問他的事時都不用
/// （後者是預設）；有他說過的素材時優先用。
function methodsFor(tags: ReadTags, tasks: readonly Task[]): HisMethod[] {
  const hasFacts = tags.hisStatedFacts.length > 0;
  if (tags.identityQuestion) {
    return tasks.map((_, i) => hasFacts && i === 0 ? "用他說過的" : "留空格");
  }
  let invented = false;
  let slotted = false;
  let used = false;
  return tasks.map((task) => {
    if (task === "收") return "只用反應";
    if (task === "推進") {
      if (hasFacts && !used) {
        used = true;
        return "用他說過的";
      }
      return tags.needsHisFacts ? "留空格" : "只用反應";
    }
    if (tags.needsHisFacts && !hasFacts && !slotted && task === "接住") {
      slotted = true;
      return "留空格";
    }
    if (hasFacts && !used && task !== "共鳴") {
      used = true;
      return "用他說過的";
    }
    if (
      tags.needsHisFacts && !invented && !tags.herMoodBad &&
      (task === "帶張力" || task === "接住")
    ) {
      invented = true;
      return "照樣寫＋標示";
    }
    return "只用反應";
  });
}

export function arrangeCards(
  decision: ReplyDecision,
  push: PushAction | null,
  tags: ReadTags,
  /// 兩段式實驗的讀局面四欄；沒給（開關沒開）就跟今天一樣。
  twoStage?: TwoStageTags,
): CardSpec[] {
  const voiceOnly: Voice = tags.hasHisVoiceSample ? "照他" : "預設";
  if (decision.kind === "close") {
    return [{
      task: "收",
      method: "只用反應",
      voice: voiceOnly,
      questionBudget: 0,
      push: null,
      angle: 0,
    }];
  }
  if (decision.kind !== "send") return [];
  const n = cardCount(tags, push);
  const matched = matchedSet(tags);
  // v3.3：B43–B46 不排帶張力（10/15 實驗：明顯考她或打分的卡 13→0）。兩段式實驗另外在已經
  // 交往、或她這一輪撒嬌示愛時不排（她越喜歡他，玩笑越少；Eric 2026-10-19 兩段式實驗）。
  const noTension = NO_TENSION_ENTRIES.some((id) => matched.has(id)) ||
    (twoStage !== undefined &&
      (twoStage.establishedCouple || twoStage.herAffection));
  const tasks = tasksFor(tags, push, n, twoStage).map((t): Task =>
    noTension && t === "帶張力" ? "接住" : t
  );
  // v3.3：她直接問他（問他的事、問他意見、認真問，或標到她直接問的條目）時，第一張排接住。
  const directQuestion = DIRECT_QUESTION_MOVES.includes(tags.herMove) ||
    ENTRY_PRIORITY[1].some((id) => matched.has(id));
  if (directQuestion && push !== "換地方" && tasks[0] === "推進") {
    const firstAccept = tasks.indexOf("接住");
    if (firstAccept > 0) {
      tasks.splice(firstAccept, 1);
      tasks.unshift("接住");
    }
  }
  // 兩段式實驗：她分享開心或得意的事（情緒差時不算），第二張換成一張共鳴，第一張照原本的順序
  //（Bruce 10/19 PR #97 計畫第 4 點）。B47 的三張固定排法不動。
  const warmAt = twoStage?.herHappyShare && !tags.herMoodBad &&
      push !== "換地方"
    ? placeWarmCard(tasks)
    : null;
  const methods = methodsFor(tags, tasks);
  // 口吻：有他的訊息時照他、預設交錯（第一張照他）；沒有就全部預設。
  const voices: Voice[] = tasks.map((_, i) =>
    tags.hasHisVoiceSample && i % 2 === 0 ? "照他" : "預設"
  );
  const seen = new Map<string, number>();
  const cards: CardSpec[] = tasks.map((task, i) => {
    const key = `${task}|${methods[i]}|${voices[i]}`;
    const angle = seen.get(key) ?? 0;
    seen.set(key, angle + 1);
    const isSeed = task === "推進" && push === "種子";
    return {
      task,
      method: methods[i],
      voice: voices[i],
      // 每張最多 1 個問句，不分卡種；種子照 v3 不加問號（Bruce 10/14）。
      questionBudget: isSeed ? 0 : 1,
      push: task === "推進" ? push : null,
      angle,
      ...(i === warmAt ? { note: "happy_share" as const } : {}),
    };
  });
  // 第一張照 C4 的自然順序：她給了機會時是推進，否則是接住或共鳴（可以有空格）。
  // 10/14 第一輪原型曾把「不用改就能送」的卡挪到第一，結果需要他填資料時，帶張力的卡
  // 變成推薦（9/48 次），已拿掉。
  return cards;
}

/// 兩段式實驗：把一張接住（沒有就一張帶張力）換成共鳴、放到第二張；第一張不動。已經有共鳴
///（她喝醉或深夜）、或第一張之外沒有可換的卡，就不換。回換上的位置。
function placeWarmCard(tasks: Task[]): number | null {
  if (tasks.length < 2 || tasks.includes("共鳴")) return null;
  let from = tasks.indexOf("接住", 1);
  if (from === -1) from = tasks.indexOf("帶張力", 1);
  if (from === -1) return null;
  tasks.splice(from, 1);
  tasks.splice(1, 0, "共鳴");
  return 1;
}

/// 兩段式實驗第 2 輪（Bruce 10/19 盲選理由：在一起後稱讚不用迂迴、一直吊著；曖昧期委婉一點、留
/// 一點讓她猜）：誇她的方式由程式挑，寫卡只看到其中一句。已經在交往、或她這一輪撒嬌示愛，直接誇；
/// 其他時候輕輕誇。她示愛也算：第 1 輪讀局面把用 App 預設標籤的情侶都判成還沒交往，她都示愛了
/// 還讓她猜，就是在吊著她。
/// light_short（Bruce 2026-10-20「可以」，開關 ANALYZE_GUIDE_V3_SHORT_PRAISE）：還沒交往時偶爾用的輕輕誇，
/// 很短、一看就是故意誇張的那種；多久用一次由程式決定（lightShortRun），不讓寫卡自己挑。
export type PraiseStyle = "direct" | "light" | "light_short";

export function praiseStyle(
  twoStage: Pick<TwoStageTags, "establishedCouple" | "herAffection">,
  /// 這次分析抽到輕輕誇的短版（開關開才會是 true）。
  lightShort = false,
): PraiseStyle {
  if (twoStage.establishedCouple || twoStage.herAffection) return "direct";
  return lightShort ? "light_short" : "light";
}

/// 輕輕誇的短版每幾次分析用一次（Bruce「偶爾用」；我們的預設）。
export const LIGHT_SHORT_EVERY = 4;

/// 這次分析要不要用輕輕誇的短版：照 runId 算 FNV-1a 雜湊，同一個 runId 永遠一樣（重播、測試對得上）。
export function lightShortRun(runId: string): boolean {
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(runId)) {
    hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  }
  return hash % LIGHT_SHORT_EVERY === 0;
}

/// 照片、貼圖的辨識標記（方括號開頭；外面可能再包一層「」，10/19 正式環境的案例就是這樣）。
const MEDIA_PLACEHOLDER = /^[「『"]?[\[［【]/u;
/// 一整個表情拆成這幾種片段一起拿掉：數字鍵帽（1️⃣、#️⃣，連前面的數字一起，所以放第一個）、表情字、
/// 膚色、區域指示字（國旗）、變體選擇符、ZWJ、標籤字（英格蘭這類旗）。只認 Extended_Pictographic 會把
/// 🇹🇼、1️⃣ 當成文字（主審第 1 輪 P2）。只用 u 旗標：正式環境的 Edge 還沒有函式用過 v 旗標，模組層級的
/// 正規式解析不了，整個 analyze-chat 都開不起來（Eric 2026-10-20 送主審第 2 輪前改）。
const EMOJI_PIECES =
  /[0-9#*]\u{FE0F}?\u{20E3}|\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Regional_Indicator}|\p{Variation_Selector}|\p{Join_Control}|[\u{E0020}-\u{E007F}]/gu;
const LETTER_OR_DIGIT = /[\p{L}\p{N}]/u;

/// 正式流程在引用回覆前面加的「（引用：「…」）」（stream_flow.ts guideMessagesFrom）：那是被引用的
/// 那句，不是她這一則說的話；分類與引她的話都先拿掉（主審第 1 輪 P2）。
export const QUOTED_REPLY_PREFIX = /^（引用：「[\s\S]*?」）/u;

/// 她這一則本身：拿掉引用前綴、前後空白。
function herLineBody(content: string): string {
  return content.replace(QUOTED_REPLY_PREFIX, "").trim();
}

/// 規格引她的話用的字：她這一則本身去掉表情、空白收成一格。空字串＝這一則沒有字可以引。
export function herLineText(content: string): string {
  return withoutEmoji(content.replace(QUOTED_REPLY_PREFIX, ""))
    .replace(/\s+/g, " ")
    .trim();
}

/// 照片或貼圖的標記，或整則只有表情（可以夾標點，例如「😂～」）；都看她這一則本身，不看引用的那句。
/// 單獨的數字、有字又有表情的，算文字。
export function isMediaLine(content: string): boolean {
  const body = herLineBody(content);
  if (MEDIA_PLACEHOLDER.test(body)) return true;
  const rest = body.replace(EMOJI_PIECES, "");
  return rest !== body && !LETTER_OR_DIGIT.test(rest);
}

/// 誰先被當成「她最想聽他回的那則」：問他最先、情感其次、其他再來。有字的那則被標成照片或貼圖時
/// 當其他（照片、貼圖本身由 isMediaLine 認，不靠這個標記）。撒嬌只有甜話短回開時讀局面才會標，跟情感同一級。
const ANSWER_RANK: Readonly<Record<WorthyLineKind, number>> = {
  問他: 0,
  撒嬌: 1,
  情感: 1,
  其他: 2,
  照片或貼圖: 2,
};

/// 離 line 最近的那一則；一樣近時取後面那則（她常先傳照片，再講照片裡的事）。
function nearestLine(line: number, candidates: readonly number[]): number {
  return candidates.reduce((best, c) => {
    const d = Math.abs(c - line);
    const bestD = Math.abs(best - line);
    return d < bestD || (d === bestD && c > best) ? c : best;
  });
}

/// 兩段式實驗第 2 輪（Bruce 10/19 盲選理由）：每張卡都先回她最想聽他回的那則（問他 → 情感 →
/// 其他，同一級取她最後傳的），每張最多再順帶一則（其餘值得接的照同樣的先後、同一級照她傳的順序
/// 輪流分；比卡多的不排）。第 1 輪把句子輪流分給各張，結果有幾張只回了照片、貼圖或肉盤，沒回她
/// 問的那句（代審「沒對準她要的」15%→34%）。照片、貼圖、只有表情的那則不單獨當對象，併進最近
/// 一則有字的（with）。編號不在她最新這一輪、或重複的略過；沒有一則有字的就不指定（null）。
export function assignAnswers(
  cardCount: number,
  worthy: readonly WorthyLine[],
  herLatest: readonly string[],
): (CardAnswer | null)[] {
  const seen = new Set<number>();
  const valid = worthy.filter((w) => {
    if (w.line < 1 || w.line > herLatest.length || seen.has(w.line)) {
      return false;
    }
    seen.add(w.line);
    return true;
  });
  // 引她的話會是空的那則（只有引用、或去掉表情後沒有字）也不當對象，跟照片貼圖一樣併進旁邊那則：
  // 規格不會出現「她的「」」（主審第 1 輪 P2）。
  const notTarget = (line: number) =>
    isMediaLine(herLatest[line - 1]) || herLineText(herLatest[line - 1]) === "";
  const media = valid.filter((w) => notTarget(w.line));
  const text = valid.filter((w) => !notTarget(w.line));
  if (text.length === 0) return Array.from({ length: cardCount }, () => null);
  const rank = (w: WorthyLine) => ANSWER_RANK[w.kind];
  const main = text.reduce((best, w) =>
    rank(w) < rank(best) || (rank(w) === rank(best) && w.line > best.line)
      ? w
      : best
  );
  const extras = text.filter((w) => w !== main)
    .sort((a, b) => rank(a) - rank(b) || a.line - b.line)
    .slice(0, cardCount);
  const folded = new Map<number, number[]>();
  for (const m of media) {
    const to = nearestLine(m.line, text.map((w) => w.line));
    folded.set(to, [...(folded.get(to) ?? []), m.line]);
  }
  const answerLine = (w: WorthyLine): AnswerLine => ({
    line: w.line,
    with: [...(folded.get(w.line) ?? [])].sort((a, b) => a - b),
  });
  return Array.from({ length: cardCount }, (_, i) =>
    extras.length > 0
      ? {
        main: answerLine(main),
        extra: answerLine(extras[i % extras.length]),
      }
      : { main: answerLine(main) });
}

// ── 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）──────────────────────────────────
// Bruce 2026-10-22 iPhone 試兩段式：已經在交往，她撒嬌說了很短的甜話、又說腿很累，5 張卡都回那三個字，還要換切入點，只能
// 評論那兩個字（「專屬的我收到了」「專屬這兩個字聽起來就很有分量」）；他說這種甜話短短回就好。讀局面把腿那則也標情感時，
// 每張卡改成先回腿、甜話當順帶，一樣每張都提那兩個字，所以候選不限先回的那則。「情感」也包含難過、生氣、痛，「腿好痛」
// 「想你」都標情感時分不出哪句是甜話（Codex 主審第 1 輪 P2），所以開關開時讀局面逐則多標一種「撒嬌」，只有標成撒嬌的才算。
// 只看讀局面的標記與字數，不比對內容。

/// 她那則去掉引用前綴、表情、標點與空白後，幾個字以內算「很短」：先訂 6 個字（我們的預設，Bruce 可以調）。
export const SWEET_SHORT_MAX_CHARS = 6;
/// 她沒有其他有字、值得回的句子時，張數改成這麼多（原本就不到這麼多張就不動）；付費頁寫的「每次 3–5 張」不變。
export const SWEET_SHORT_CARD_COUNT = 3;

/// 她那則本身有幾個字：去掉引用前綴與表情（herLineText）之後，只數字母與數字，標點、空白不算。
export function herLineChars(content: string): number {
  return [...herLineText(content)].filter((ch) => LETTER_OR_DIGIT.test(ch))
    .length;
}

/// 她最新這一輪每一則有字、值得接的句子在 assignAnswers 裡的樣子（連同併進來的照片、貼圖），照編號查：卡給到跟條目一樣多張，
/// 第一順位那則是每張的 main，其他則輪流當順帶，每一則都會出現。
function answerLinesOf(
  worthy: readonly WorthyLine[],
  herLatest: readonly string[],
): Map<number, AnswerLine> {
  const out = new Map<number, AnswerLine>();
  for (
    const a of assignAnswers(Math.max(1, worthy.length), worthy, herLatest)
  ) {
    if (!a) continue;
    out.set(a.main.line, a.main);
    if (a.extra) out.set(a.extra.line, a.extra);
  }
  return out;
}

/// 甜話短回的候選與選中的那則：讀局面標她這一輪撒嬌或示愛時，有字（不是照片、貼圖、只有表情或只有引用）、標成撒嬌（甜話短回
/// 開時讀局面才會標的那一種）、而且不超過 SWEET_SHORT_MAX_CHARS 個字的每一則都是候選（連同併進來的照片、貼圖）；標成情感的
/// 一律不算，再短也不算（「腿好痛」是情感，不是甜話）。不一定是本來每張卡都要先回的那則：Bruce 2026-10-22 那次她先撒嬌、後說
/// 腿很累，腿那則排第一時甜話只當順帶。本來先回的那則是問他（她問了他什麼）就不算，照今天每張卡都先回她問的那句。選中的是
/// assignAnswers 在候選裡排第一的那則（都是撒嬌，同一級取她後傳的）。
function pickSweetShort(
  twoStage: TwoStageTags,
  herLatest: readonly string[],
): { readonly sweet: AnswerLine; readonly candidates: AnswerLine[] } | null {
  if (!twoStage.herAffection) return null;
  const main = assignAnswers(1, twoStage.worthyLines, herLatest)[0]?.main;
  if (!main) return null;
  // 同一則標了兩次時跟 assignAnswers 一樣看第一次的標記。
  const kindOf = (line: number) =>
    twoStage.worthyLines.find((w) => w.line === line)?.kind;
  if (kindOf(main.line) === "問他") return null;
  const all = answerLinesOf(twoStage.worthyLines, herLatest);
  const candidates = [...all.values()].filter((a) =>
    kindOf(a.line) === SWEET_LINE_KIND &&
    herLineChars(herLatest[a.line - 1]) <= SWEET_SHORT_MAX_CHARS
  ).sort((a, b) => a.line - b.line);
  if (candidates.length === 0) return null;
  const lines = new Set(candidates.map((c) => c.line));
  const first = assignAnswers(
    1,
    twoStage.worthyLines.filter((w) => lines.has(w.line)),
    herLatest,
  )[0]?.main.line;
  const sweet = candidates.find((c) => c.line === first);
  return sweet ? { sweet, candidates } : null;
}

/// 她最新這一輪有沒有很短的甜話（見 pickSweetShort）：有就回選中的那則（連同併進來的照片、貼圖），沒有就 null。
export function sweetShortLine(
  twoStage: TwoStageTags,
  herLatest: readonly string[],
): AnswerLine | null {
  return pickSweetShort(twoStage, herLatest)?.sweet ?? null;
}

/// 回甜話的那一張：第一張不是推進、也不是收的卡；她開心分享時換上的那張共鳴留給她分享的那件事，也先跳過。都沒有就放寬
/// 開心分享那張，再沒有就第一張。
function sweetCardAt(specs: readonly CardSpec[]): number {
  const free = (s: CardSpec) => s.task !== "推進" && s.task !== "收";
  const at = specs.findIndex((s) => free(s) && s.note !== "happy_share");
  if (at !== -1) return at;
  const loose = specs.findIndex(free);
  return loose === -1 ? 0 : loose;
}

/// 換切入點照「同任務、同做法、同口吻、回同一則」重算：甜話短回把各張卡回的那則分開了，前面同規格的卡回的是別則時
/// 不用換（沒開時每張都回同一則，跟 arrangeCards 算的一樣）。
function withAngles(specs: readonly CardSpec[]): CardSpec[] {
  const seen = new Map<string, number>();
  return specs.map((spec) => {
    const key = `${spec.task}|${spec.method}|${spec.voice}|${
      spec.answer?.main.line ?? 0
    }`;
    const angle = seen.get(key) ?? 0;
    seen.set(key, angle + 1);
    return { ...spec, angle };
  });
}

/// 甜話短回的排法（Eric 2026-10-22「照預設」）。specs 是 withAnswers 排好、每張都先回同一則的卡；她這一輪沒有很短的甜話
///（pickSweetShort）就原樣回。有的話：
/// - 只有一張卡回選中的那句、不帶順帶（sweetCardAt 挑），規格多短回的指示（sweetShort）。
/// - 其他卡改回她其他有字、值得回的句子：每一句很短的甜話（候選，不只選中的那句）與併進它們的照片、貼圖都拿掉，其餘照
///   assignAnswers 同一套先後與輪流重排，所以這些卡的規格完全不會出現任何一句很短的甜話（main、順帶都不是）；換切入點跟著
///   重算（withAngles）。
/// - 她沒有其他有字的句子：張數改成 SWEET_SHORT_CARD_COUNT（前幾張，原本就不到就不動），每張都回選中的那句、都帶短回的指示，
///   不要求換切入點，靠口吻（照他、預設交錯）區分。
export function arrangeSweetShort(
  specs: readonly CardSpec[],
  twoStage: TwoStageTags,
  herLatest: readonly string[],
): CardSpec[] {
  const picked = pickSweetShort(twoStage, herLatest);
  if (!picked || specs.length === 0) return [...specs];
  const { sweet, candidates } = picked;
  const left = new Set(candidates.flatMap((c) => [c.line, ...c.with]));
  const others = twoStage.worthyLines.filter((w) => !left.has(w.line));
  const sweetCard = (spec: CardSpec): CardSpec => ({
    ...spec,
    answer: { main: sweet },
    sweetShort: true,
  });
  if (assignAnswers(1, others, herLatest)[0] === null) {
    return specs.slice(0, SWEET_SHORT_CARD_COUNT).map((spec) => ({
      ...sweetCard(spec),
      angle: 0,
    }));
  }
  const at = sweetCardAt(specs);
  // 有其他有字的句子時，assignAnswers 每一項都有指定（全是 null 只會發生在一則有字的都沒有）。
  const rest = assignAnswers(specs.length - 1, others, herLatest);
  let next = 0;
  return withAngles(
    specs.map((spec, i) =>
      i === at ? sweetCard(spec) : { ...spec, answer: rest[next++]! }
    ),
  );
}

const ENTRY_PRIORITY: readonly (readonly string[])[] = [
  ["B11", "B10", "B36", "B12", "B32", "B33", "B47"],
  // B44、B45 是她直接問他（v3.2，Bruce 10/14）。
  ["B02", "B19", "B24", "B25", "B26", "B27", "B28", "B29", "B30", "B44", "B45"],
];

/// C5：只從啟用的挑，最多三條；先挑停、拒絕、安全，再挑她直接問的，最後其他（預設）。
export function pickEntries(
  matched: readonly string[],
  entries: readonly GuideV3Entry[],
): GuideV3Entry[] {
  const enabled = new Map(
    entries.filter((e) => e.enabled).map((e) => [e.id, e]),
  );
  const ids = [...new Set(matched.map((m) => m.trim()))].filter((id) =>
    enabled.has(id)
  );
  const rank = (id: string) => {
    const g = ENTRY_PRIORITY.findIndex((group) => group.includes(id));
    return g === -1 ? ENTRY_PRIORITY.length : g;
  };
  return ids
    .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
    .slice(0, 3)
    .map((id) => enabled.get(id)!);
}

// ── 寫卡瘦身（開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Eric 2026-10-27「照預設」）──────────────────────────────────
// Bruce 2026-10-26「看B43-B47感覺可以從寫卡prompt 移除 他們對自然度會有影響」：寫卡的使用者訊息「## 這一輪的情境做法」不再帶
// B43、B45、B46、B47 的觸發與寫法。B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」）。讀局面照舊標
// 這幾條，程式的保護照舊：B43–B46 不排帶張力、B46 不推進、B44／B45（她直接問他）第一張排接住；B47 照樣辨認，固定的酒托提醒
// （SCAM_VENUE_WARNING）、三張固定排法、換地方的卡片規格（prompts.ts PUSH_NOTE.換地方）都不動。B47 不照 Bruce 規格整條拿掉
// （Eric 2026-10-27「照預設」），只是寫卡看不到它的條目。說明步驟與 trace 的 entries 照舊用 pickEntries 那一份。

/// 寫卡看不到的條目：B43、B45、B46 與 B47（SCAM_VENUE_ENTRY）。B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日
/// 「照預設」）。
export const WRITER_TRIM_ENTRY_IDS: readonly string[] = [
  "B43",
  "B45",
  "B46",
  SCAM_VENUE_ENTRY,
];

/// 寫卡拿到的條目：先排除 WRITER_TRIM_ENTRY_IDS，再照 pickEntries 的規則挑（只從啟用的挑、最多三條、同一套先後），空出來的
/// 名額由其他標到的條目補上。沒標到這幾條時跟 pickEntries 一樣；只標到這幾條時是空的。
export function pickWriterEntries(
  matched: readonly string[],
  entries: readonly GuideV3Entry[],
): GuideV3Entry[] {
  return pickEntries(
    matched,
    entries.filter((e) => !WRITER_TRIM_ENTRY_IDS.includes(e.id)),
  );
}

/// 金錢、詐騙的固定提醒（Eric 2026-10-18 盤點預設）：讀局面標到風險（剛認識就熱得不合理，
/// 或只在要他花錢、送禮、幫忙時才熱）時顯示，所以用「例如」列常見的訊號；推進卡由
/// decidePush 拿掉。只看模型的標記：關鍵字會把「借我 5 分鐘」「理專講投資」誤判（主審第 1 輪），
/// 10/18 黑箱裡模型的 risk 5/5 都判對。
export const MONEY_RISK_WARNING =
  "這段對話有感情詐騙常見的訊號，例如剛認識就很熱絡，或聊到借錢、匯款、投資、下載 App。先不要轉帳或儲值，也別照她給的連結或 App 操作。";

/// 給用戶看的局面判讀；標到 B47 時整段換成固定的酒托、飯托提醒，不用模型寫的
/// （v3.3 第一輪：模型的判讀兩次寫「順著她的選擇比較穩」，跟提醒互相矛盾）。標到風險時
/// 同樣整段換成金錢、詐騙的固定提醒（B47 優先，它有自己的提醒與換地方的卡）。
export function judgmentFor(
  tags: Pick<ReadTags, "readForUser" | "matchedEntries" | "risk">,
): string {
  if (matchedSet(tags).has(SCAM_VENUE_ENTRY)) return SCAM_VENUE_WARNING;
  if (tags.risk) return MONEY_RISK_WARNING;
  return tags.readForUser.trim();
}
