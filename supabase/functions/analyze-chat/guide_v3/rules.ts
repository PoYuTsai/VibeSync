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
import type { GuideV3Entry } from "./entries.ts";
import type { ReadTags } from "./read_tags.ts";
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

function tasksFor(tags: ReadTags, push: PushAction | null, n: number): Task[] {
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
  const tension = tags.light === "green" ? (n >= 4 ? 2 : 1) : 0;
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
  // v3.3：B43–B46 不排帶張力（10/15 實驗：明顯考她或打分的卡 13→0）。
  const noTension = NO_TENSION_ENTRIES.some((id) => matched.has(id));
  const tasks = tasksFor(tags, push, n).map((t): Task =>
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
    };
  });
  // 第一張照 C4 的自然順序：她給了機會時是推進，否則是接住或共鳴（可以有空格）。
  // 10/14 第一輪原型曾把「不用改就能送」的卡挪到第一，結果需要他填資料時，帶張力的卡
  // 變成推薦（9/48 次），已拿掉。
  return cards;
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
