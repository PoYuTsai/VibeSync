import type { PracticeTurn } from "./validate.ts";

const KNOWN_CANNED_SIGNATURES = [
  "妳剛說的那個點",
  "你剛說的那個點",
  "妳剛剛說的那個點",
  "你剛剛說的那個點",
  "我先分享我的版本再聽妳的",
  "我先分享我的版本再聽你的",
  "我先說我的版本再聽妳的",
  "我先說我的版本再聽你的",
  "目前比較像穩住話題",
  "還沒看到足夠投入或明確窗口",
  "先補感受與投入再接低壓邀約窗口",
  "提示偏保守",
];

const GENERIC_META_SIGNATURES = [
  "先接住她",
  "先接住對方",
  "分享你的版本",
  "分享自己的版本",
  "再聽她的",
  "再聽對方的",
];

// These are semantic skeletons rather than exact canned sentences. Providers
// often hide the same empty acknowledgement behind a topic slot, a discourse
// particle (「啦／耶」), or a near-synonym (「也常這樣／跟妳一樣」).
// A concrete continuation does not match because every skeleton is anchored at
// the end of the visible line.
const SLOT_PREFIX = ".*";
const GENERIC_PARTICLE = "(?:啦|耶|啊|喔|哦|欸|齁)?";
const GENERIC_ACK =
  `(?:我)?(?:(?:懂|了解|明白|知道)(?:了)?${GENERIC_PARTICLE}|(?:有)?(?:收到|接到|接住)(?:了)?${GENERIC_PARTICLE}|(?:能理解|有共鳴|有感|get到(?:了)?)${GENERIC_PARTICLE})`;
const GENERIC_SELF_LEAD =
  "(?:(?:其實|大概|好像)?我|我(?:其實|大概|好像)?|(?:其實|大概|好像))?";
const GENERIC_SELF_SIMILARITY =
  `${GENERIC_SELF_LEAD}(?:也(?:是(?:這樣)?|有過|遇(?:過|到過)|常(?:常)?(?:會)?(?:這樣|遇到|碰到)|會(?:這樣)?|差不多|一樣)|跟[妳你她他](?:一樣|差不多))${GENERIC_PARTICLE}`;
const GENERIC_RETURN_PROMPT =
  "(?:再聊聊[妳你]的|(?:那)?[妳你](?:呢|勒|咧)|換[妳你](?:呢|勒|咧)?|[妳你]也(?:是|會)嗎)?";
const GENERIC_HANDOFF =
  "(?:換我(?:來)?(?:說說|講講|聊聊|說一點|講一點|分享|分享一下|(?:說|講|聊)我的)|我(?:來|也來)(?:說說|講講|聊聊|分享|分享一下|(?:說|講|聊)我的)|再(?:換|讓)我(?:說說|講講|聊聊|分享|分享一下)|(?:輪到|該)我(?:說|講|聊)(?:了)?|輪我(?:了|(?:說|講|聊)(?:了)?))";
const GENERIC_HANDOFF_TAIL = "(?:再聽[妳你]的|再聊聊[妳你]的|[妳你]呢)?";

const SLOT_FILLED_CANNED_PATTERNS = [
  new RegExp(
    `^${SLOT_PREFIX}${GENERIC_SELF_SIMILARITY}${GENERIC_RETURN_PROMPT}$`,
    "u",
  ),
  new RegExp(
    `^${SLOT_PREFIX}(?:這個點|這件事|這句|這段)(?:${GENERIC_ACK}|(?:我)?(?:先記住|記住了))(?:${GENERIC_RETURN_PROMPT}|${GENERIC_HANDOFF}${GENERIC_HANDOFF_TAIL})$`,
    "u",
  ),
  new RegExp(
    `^${SLOT_PREFIX}${GENERIC_ACK}${GENERIC_HANDOFF}${GENERIC_HANDOFF_TAIL}$`,
    "u",
  ),
];

const GENERIC_PRAISE_TAIL =
  /(?:聽起來|感覺|看起來)?(?:很|蠻|滿|挺|有點)?(?:舒服|真實|有意思|有趣|有生活感|有感覺|特別|不錯|很好|很棒|很讚|可以)(?:耶|啦|啊|喔|哦|欸|齁)?$/u;
const GENERIC_PRAISE_HANDOFF =
  /(?:聽起來|感覺|看起來)?(?:很|蠻|滿|挺|有點)?(?:舒服|真實|有意思|有趣|有生活感|有感覺|特別|不錯|很好|很棒|很讚|可以)(?:[妳你])?(?:可以|願意|想|要不要)?(?:再|繼續)?(?:多)?(?:說|分享|聊|講)(?:一點|一些|一下|更多|下去)?(?:嗎|呢|嘛)?$/u;
// A negated acknowledgement ("沒記住"／"不懂") is a substantive admission, not a
// generic "收到／了解了" echo, so the tail must not fire when negated.
const GENERIC_ECHO_TAIL =
  /(?<![沒不未別])(?:收到|記住(?:了)?|聽到(?:了)?|懂(?:了)?|了解(?:了)?|明白(?:了)?|有接到(?:了)?|有接住(?:了)?)(?:耶|啦|啊|喔|哦|欸|齁)?$/u;
// The negation may sit further left than one char ("沒有記住"、"不太懂"、"沒聽懂"),
// which a single-char lookbehind cannot see, so this guard runs before the echo
// tail. The gap stays a bounded whitelist（有／程度副詞／複合動詞首字）— an
// arbitrary-char gap would let real echoes masquerade as negated admissions.
const NEGATED_ACK_TAIL =
  /[沒不未別](?:是)?(?:有)?(?:太|大|很|真的|完全|怎麼)?[聽記看搞弄]?(?:收到|記住|聽到|聽懂|懂|了解|明白|接到|接住)(?:了)?(?:耶|啦|啊|喔|哦|欸|齁)?$/u;

const COMMON_EVIDENCE_FRAGMENTS = new Set([
  "妳好",
  "你好",
  "我很",
  "你很",
  "妳很",
  "她很",
  "這個",
  "那個",
  "可以",
  "就是",
  "因為",
  "所以",
  "但是",
  "今天",
  "現在",
  "剛剛",
  "真的",
  "有點",
  "感覺",
  "想要",
  "什麼",
  "怎麼",
  "為什",
  "妳說",
  "你說",
  "我說",
  "她說",
  "這句",
  "那句",
  "妳的",
  "你的",
  "我的",
  "她的",
  "我還",
  "還在",
  "我在",
  "你在",
  "妳在",
  "她在",
  "我有",
  "你有",
  "妳有",
  "她有",
  "也有",
  "不會",
  "不是",
  "不要",
  "先不",
  "一下",
  "一點",
  "一個",
  "這樣",
  "那樣",
  "這麼",
  "那麼",
  // round15 Codex P2-2：約會聊天語境的超高頻詞——模板句寫「把聊天帶下去」
  // 撞上她隨口說的「聊天不用像面試」就洗白 grounding，2-gram 證據力為零。
  "聊天",
]);

function compact(value: string): string {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}]/gu, "");
}

/**
 * Detects a grounded topic slot wrapped in praise or acknowledgement but with
 * no stance, scene, choice, or concrete next move. Grounding is deliberately
 * checked elsewhere; repeating one transcript noun must not make this useful.
 */
export function isGenericPracticeComplimentOrEcho(value: string): boolean {
  const normalized = compact(value);
  return GENERIC_PRAISE_TAIL.test(normalized) ||
    GENERIC_PRAISE_HANDOFF.test(normalized) ||
    (!NEGATED_ACK_TAIL.test(normalized) && GENERIC_ECHO_TAIL.test(normalized));
}

function groundingCompact(value: string): string {
  return compact(value)
    .replace(/(?:發|送|寄|丟|轉)(?=給)/gu, "傳")
    .replace(/那家店/gu, "那間店")
    .replace(/這家店/gu, "這間店");
}

export function rejectKnownCannedPracticeText(
  value: string,
  errorCode: string,
): void {
  const normalized = compact(value);
  if (
    KNOWN_CANNED_SIGNATURES.some((signature) =>
      normalized.includes(compact(signature))
    )
  ) {
    throw new Error(errorCode);
  }
}

export function rejectGenericPasteablePracticeText(
  value: string,
  errorCode: string,
): void {
  rejectKnownCannedPracticeText(value, errorCode);
  const normalized = compact(value);
  if (
    normalized.length < 6 ||
    SLOT_FILLED_CANNED_PATTERNS.some((pattern) => pattern.test(normalized)) ||
    GENERIC_META_SIGNATURES.some((signature) =>
      normalized === compact(signature) ||
      normalized === `${compact(signature)}。`
    )
  ) {
    throw new Error(errorCode);
  }
}

function evidenceFragments(value: string): Set<string> {
  const normalized = groundingCompact(value);
  const result = new Set<string>();
  // Very short replies are common in real chats. Their whole token is the only
  // honest lexical anchor; treating them as "no evidence" would let generic
  // canned copy pass. Emoji/punctuation-only turns remain ungroundable and are
  // failed closed by assertPracticeTextGroundedInTurns.
  if (normalized.length > 0 && normalized.length < 4) {
    result.add(normalized);
    return result;
  }
  // English replies are valid conversation evidence too. Keeping their word
  // tokens closes the old fail-open where Okay/Thanks/haha produced no
  // fragments and let generic Chinese copy pass automatically.
  if (!/\p{Script=Han}/u.test(normalized)) {
    for (
      const token of value.normalize("NFKC").toLowerCase().match(
        /[a-z0-9]{2,}/gu,
      ) ?? []
    ) {
      result.add(token);
    }
    return result;
  }
  if (normalized.length < 4) {
    return result;
  }
  for (const width of [4, 3, 2]) {
    if (normalized.length < width) continue;
    for (let index = 0; index <= normalized.length - width; index++) {
      const fragment = normalized.slice(index, index + width);
      if (COMMON_EVIDENCE_FRAGMENTS.has(fragment)) continue;
      if (/^[我你妳她他它這那的是了嗎呢吧啊喔哦欸啦]+$/u.test(fragment)) {
        continue;
      }
      result.add(fragment);
    }
  }
  return result;
}

// ── 裁決 (a) 2026-07-23（round6 判定表 §5 根因 2）：詞面 n-gram 對「回應句」
// 有結構性盲區——這些句子的功能是「回應」而非「複讀」，天然零詞面重疊。
// Eric 裁決四型分治：誠實迴避／提案時間／收尾允諾三型給窄豁免；「回應質問型」
// 不豁免（gate 保留＝把模型推向引用她原話的幽默反打/曲解技巧，刻意設計）。
// 鐵則：豁免只跳過本詞面比對；fact-ledger 捏造檢查、洩漏詞表、invite_route
// 等其他 gate 一律照走。

// 誠實迴避：第一人稱＋否定/未然承認（還沒去過、不知道、想不起來…）。
// 沒去過就說沒去過＋轉話題/反問/邀約皆合法解（判定表 #11 gh5）。
const HONEST_AVOIDANCE_ADMISSION_PATTERN =
  /(?:還沒(?:有)?(?:實際)?(?:去|吃|看|聽|玩|試)過|沒(?:有)?(?:去|吃|看|聽|玩|試)過|沒聽過|不知道|不清楚|不確定|想不起來|記不(?:得|起來)|答不上來|沒背下來|不太熟)/u;

// 提案時間：日級/鐘點級時間錨＋第一人稱＋要求對方配合的動作（妳留/妳排/
// 妳有空…）。練習室教的是「提案時間、尋求共識」的形狀，用戶貼出前自己換
// 真時間（判定表 #15/#16 gd2）。刻意不收「下個月/最近」等自陳近況時間詞，
// 也不把句尾問號當提案訊號——否則「我最近也在計畫下個月去日本…妳有推薦
// 嗎？」型捏造近況句（判定表 #22）會被誤放。
const PROPOSAL_TIME_ANCHOR_PATTERN =
  /(?:[週周][一二三四五六日天末]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|這[週周]|下[週周]|今晚|明晚|明天|後天|[0-9０-９一二三四五六七八九十]+點(?:半)?)/u;
const PROPOSAL_SECOND_PERSON_COOP_PATTERN =
  /[你妳][^，。！？!?,;；]{0,4}(?:留|排|挑|選|看看|方便|有空|可以|能不能|要不要|決定)/u;

// 收尾允諾：簡短允諾/確認開頭（好啊/沒問題/一言為定…）＋碰面或時間詞，
// 且全句短（判定表 #26 gd5「好，週六見」形）。長度上限擋住把允諾當前綴
// 夾帶長段新敘事的句子。
const CLOSING_ASSENT_LEAD_PATTERN =
  /^(?:好(?:啊|呀|哇|喔|哦|的)?|沒問題|成交|說定(?:了)?|一言為定|就這麼(?:說定|辦)|ok)/u;
const CLOSING_MEET_ANCHOR_PATTERN =
  /(?:見面|碰面|見|約|時間|[0-9０-９一二三四五六七八九十幾]+點)/u;
const CLOSING_PROMISE_MAX_COMPACT_LENGTH = 30;

function isHonestAvoidanceResponse(value: string): boolean {
  return /我/u.test(value) && HONEST_AVOIDANCE_ADMISSION_PATTERN.test(value);
}

function isTimeProposalResponse(value: string): boolean {
  return /我/u.test(value) && PROPOSAL_TIME_ANCHOR_PATTERN.test(value) &&
    PROPOSAL_SECOND_PERSON_COOP_PATTERN.test(value);
}

function isClosingPromiseResponse(value: string): boolean {
  const normalized = compact(value);
  return normalized.length > 0 &&
    normalized.length <= CLOSING_PROMISE_MAX_COMPACT_LENGTH &&
    CLOSING_ASSENT_LEAD_PATTERN.test(normalized) &&
    CLOSING_MEET_ANCHOR_PATTERN.test(normalized);
}

/** 三型窄豁免的唯一入口；質問型與其他回應句不在此列，照走詞面比對。 */
function isGroundingExemptResponseShape(value: string): boolean {
  return isHonestAvoidanceResponse(value) || isTimeProposalResponse(value) ||
    isClosingPromiseResponse(value);
}

// round14/15 曾在此加「賭局衍生」「自我揭露邀請」兩型 fragment 豁免；
// Codex 三輪對抗審（session 019f904b）以短子句切割洗白、分隔符繞過與
// base grounding any-fragment 快速路徑證明詞面豁免不可行，主線停損裁決
// 全數撤除、回歸 fail-closed。gh3 賭約句/gd3 自介句被攔＝已知接受的 FP，
// 留待「非可貼上欄位 repair/strip」架構案處理。

/**
 * Generated coaching must visibly touch the supplied conversation rather than
 * pass a generic relationship template. This is deliberately lexical and
 * conservative: the prompt already asks the model to reuse a concrete detail,
 * and a failed check simply moves to the generated Claude repair path.
 */
export function assertPracticeTextGroundedInTurns(opts: {
  visibleText: string;
  turns?: PracticeTurn[];
  latestOnly?: boolean;
  errorCode: string;
}): void {
  if (!opts.turns || opts.turns.length === 0) return;
  // 非 latestOnly 的證據窗＝整份逐字稿：這個 gate 擋的是「完全沒碰到這場
  // 對話」的萬用模板，引用較早輪次一樣是有憑有據（舊的 slice(-8) 會把
  // 10-16 句 fixture 的前段引用整批誤殺——2026-07-23 判定表）。
  const evidenceTurns = opts.latestOnly
    ? [...opts.turns].reverse().filter((turn) => turn.role === "ai").slice(0, 1)
    : opts.turns;
  const fragments = new Set<string>();
  for (const turn of evidenceTurns) {
    for (const fragment of evidenceFragments(turn.text)) {
      fragments.add(fragment);
    }
  }
  if (fragments.size === 0) {
    // 對話存在但全是 emoji/標點＝無從驗證，寧可 fail-closed 也不放行
    // 萬用模板（不限 latestOnly：全窗版一樣適用）。
    if (
      evidenceTurns.some((turn) => turn.text.trim().length > 0) &&
      evidenceTurns.every((turn) => compact(turn.text).length === 0)
    ) {
      throw new Error(opts.errorCode);
    }
    return;
  }
  const visible = groundingCompact(opts.visibleText);
  if (![...fragments].some((fragment) => visible.includes(fragment))) {
    if (isGroundingExemptResponseShape(opts.visibleText)) return;
    throw new Error(opts.errorCode);
  }
}

export function normalizedPracticeText(value: string): string {
  return compact(value);
}

const GAME_BREAKDOWN_ECHO_FRAGMENT_WIDTH = 6;
const GAME_BREAKDOWN_ECHO_MIN_FIELD_COUNT = 3;

/**
 * 2026-08-06 真機案例：Game 拆盤五欄中至少 4 欄字面複製同一句籠統描述
 * （「她剛丟回來的話題」），這種 case 之所以漏得出去，是因為 salvage 只擋
 * 罐頭句簽名，不查「內容是不是空話」；而正常兩發也從沒檢查過
 * phaseReached/missedVariable/failureState/inviteDirection 這四欄的實質內容
 * （唯一被查的可貼句是 nextFirstLine）。
 *
 * 這裡不判斷「像不像空話」（regex 對句型窮舉不完），改用更可靠的訊號：
 * 五個分析不同面向（進度/缺口/卡點/下句/邀約）的欄位，如果有同一段 6 字
 * 以上的字面原文同時出現在 3 欄以上，且這段原文**不是**逐字出現在對話逐字稿
 * 裡，就判斷是模型偷懶把同一句籠統話貼滿多欄。
 *
 * GLM 對抗審查（2026-08-06）當面反例證實原始版本（純字面重複、無逐字稿豁免、
 * width=8）誤殺合法內容：教練分析五欄真的引用她原話（"我最近工作壓力很大"）
 * 或同一個具體提案（"週末一起去那家新開的咖啡廳"）時，本來就該在多欄重複出
 * 現——這是 grounding 要的行為，不是空話。逐字稿豁免直接解掉這個誤殺，因為
 * 「是不是模型自己發明的籠統描述」跟「是不是真的在對話裡」剛好是同一條線。
 * 豁免後才敢把 width 從 8 降到 6，抓住同一位模型審查抓到的短版填充變體
 * （例如「延續剛剛話題」6 字），而不會反過來吃進更多合法短引句。
 *
 * 殘留已知漏洞（GLM 同一輪指出，刻意接受）：模型如果每欄換一種近義說法
 * （「她剛丟回來的話題」／「她剛拋出的話題」／「她丟過來的話題」……）逐字
 * 零重疊，或把同一句籠統話只塞進 2 欄而非 3 欄，這裡抓不到。這跟本檔其他
 * 詞面守門（如 rejectGenericPasteablePracticeText）同樣的取捨：擋住已觀測
 * 到的失敗模式，不承諾窮舉所有可能措辭。
 */
function gameBreakdownFieldFragments(compacted: string): Set<string> {
  const result = new Set<string>();
  for (
    let index = 0;
    index <= compacted.length - GAME_BREAKDOWN_ECHO_FRAGMENT_WIDTH;
    index++
  ) {
    result.add(
      compacted.slice(index, index + GAME_BREAKDOWN_ECHO_FRAGMENT_WIDTH),
    );
  }
  return result;
}

export function rejectGameBreakdownFieldEcho(
  fields: Readonly<Record<string, string>>,
  turns: readonly PracticeTurn[] | undefined,
  errorCode: string,
): void {
  const values = Object.values(fields)
    .map((value) => compact(value))
    .filter((value) => value.length > 0);
  if (values.length < GAME_BREAKDOWN_ECHO_MIN_FIELD_COUNT) return;
  const transcript = compact((turns ?? []).map((turn) => turn.text).join(""));
  const fieldCountByFragment = new Map<string, number>();
  for (const value of values) {
    for (const fragment of gameBreakdownFieldFragments(value)) {
      // 逐字出現在對話裡＝合法引用/callback，不算空話回聲。
      if (transcript.length > 0 && transcript.includes(fragment)) continue;
      fieldCountByFragment.set(
        fragment,
        (fieldCountByFragment.get(fragment) ?? 0) + 1,
      );
    }
  }
  for (const count of fieldCountByFragment.values()) {
    if (count >= GAME_BREAKDOWN_ECHO_MIN_FIELD_COUNT) {
      throw new Error(errorCode);
    }
  }
}

/**
 * salvage 的**唯一**否決名單（2026-08-06 Eric 拍板，把白名單翻成黑名單）。
 *
 * 為什麼翻：白名單（列出「哪些失敗可以放行」）本質上要一條一條吵，守門碼有
 * 五十幾個，每審一輪就冒出新的邊界要討論，而使用者拿到的還是 503。Eric 的要求
 * 很明確——我們自己的守門不准造成 503。對應的做法就是反過來：**只有紅線可以
 * 殺，其他一律端出去**。
 *
 * 紅線只有三類，刻意講得完：
 * 1. `_l4_unsafe`——露骨性內容。
 * 2. `_internal_label_leak` / `_temperature_leak`——洩漏我們的內部機制。
 * 3. `_canned_visible_text`——我們自己寫死的罐頭句混進模型輸出。
 *
 * Game 拆盤多欄字面複製同一句籠統話（`rejectGameBreakdownFieldEcho`，
 * 2026-08-06 真機加）刻意**不進**這份名單：GLM 對抗審查指出，若把它當紅線
 * 會在 salvage 兩發都失敗的情境下把它變成新的不可救、直接 503——跟其他三類
 * 「使用者絕不能看到」的紅線不同，這只是 Game 拆盤這個**可選**子區塊的內部
 * 空洞偵測，成本不對等。改走既有的「拆盤缺欄」同一套降級路徑（parser 內
 * throw／salvage 內 return null 丟掉這個可選區塊），不用整張卡陪葬。
 *
 * **捏造事實（unsupported_detail）刻意不在紅線內**：Eric 2026-08-06 拍板拿掉。
 * 我提過代價——模型編造時，AI 可能跟使用者說她沒說過的事，使用者照著聊會被
 * 拆穿——他選擇字面上的零 503。守門嚴重度分級後它在正式發也只記 finding
 * （debrief_card.ts assertGeneratedDebriefQuality），靠 telemetry 盯著。
 * 要推翻這條＝重新對齊 Eric，別自己改回來。
 *
 * 注意這是**敗因碼**的名單，不是 gate 的名單：salvage 重解時還要靠
 * `salvagePass` 讓非紅線的 gate 自己讓路，兩邊要一起看。
 */
const NEVER_SALVAGEABLE_FAILURE_CODE_PARTS = [
  "_l4_unsafe",
  "_internal_label_leak",
  "_temperature_leak",
  "_canned_visible_text",
] as const;

export function isSalvageableFailureCode(code?: string): boolean {
  if (typeof code !== "string" || code.length === 0) return false;
  return !NEVER_SALVAGEABLE_FAILURE_CODE_PARTS.some((part) =>
    code.includes(part)
  );
}
