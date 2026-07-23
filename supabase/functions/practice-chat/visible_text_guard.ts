const INTERNAL_VISIBLE_LABELS = [
  "notready",
  "softinviteready",
  "directinviteready",
  "partnerwindow",
  "highintimacy",
  "relationshipscore",
  "invitestage",
  "currenttemperaturescore",
  "memorysummary",
  "scenestatus",
  "datechance",
  "nextinvitemove",
  "partnerstate",
  "partnermood",
  "innerthought",
  "sceneprompt",
  "replytempo",
  "inviteguidance",
  "softinvite",
  "directinvite",
  "gamemode",
  "spicygamemode",
  "gamehint",
  "targetvariable",
  "speedinvitedirection",
  "allowspicylevel",
  "socialgamefsm",
  "hiddenvariables",
  "failurestates",
  "realityflags",
  "deltaclamp",
  "srstrategy",
  "gamestrategy",
  "valuehooks",
  "teststyle",
  "tensionstyle",
  "closehooks",
  "punishments",
  "heatbias",
  "p1open",
  "p2value",
  "p3test",
  "p4tension",
  "p5close",
  "p1",
  "p2",
  "p3",
  "p4",
  "p5",
  "l0",
  "l1",
  "l2",
  "l3",
  "l4",
  "boring",
  "toolguy",
  "greasy",
  "framecollapse",
  "enginestall",
  "ghostrisk",
  "obvioustrap",
  "frameoverreach",
  "fakefamiliarity",
  "socialproofattempt",
];

const L4_UNSAFE_VISIBLE_PATTERNS = [
  "做愛",
  "做爱",
  "上床",
  "開房",
  "开房",
  "脫衣",
  "脱衣",
  "裸體",
  "裸照",
  "私密照",
  "摸你",
  "摸妳",
  "胸部",
  "硬上",
  "強迫",
  "强迫",
  "不准拒絕",
  "不能拒絕",
  "灌醉",
  "迷昏",
  "非自願",
  "沒有同意",
  "羞辱你",
  "羞辱妳",
  "來我家過夜",
  "去我家過夜",
  "睡我家",
  "來我房間",
  "去你房間",
  "sex",
  "nude",
  "nudes",
  "undress",
  "forceyou",
  "youcannotrefuse",
  "cantrefuse",
  "privatephoto",
  "上床",
  "做愛",
  "做爱",
  "性交",
  "打炮",
  "約炮",
  "约炮",
  "裸照",
  "脫光",
  "脱光",
  "硬上",
  "不准拒絕",
  "不能拒絕",
  "不能拒绝",
  "直接睡你",
  "回家睡",
];

// ── debrief 可見欄位的溫度/內部機制詞守門（批3）─────────────────────────
// debrief prompt 會注入 band 詞（frozen/cold/.../hot、升溫指數），模型可能
// 抄進可見欄位。英文內部詞用 Latin word-boundary 比對，避免誤傷組合詞
// （photo/husband/scoreboard）；中文詞去空白標點後 substring。
// 只給 debrief 生成路徑用；chat/hint 既有詞表與放行語意不動。
const INTERNAL_TEMPERATURE_LABELS_LATIN = [
  "frozen",
  "cold",
  "neutral",
  "warm",
  "hot",
  "band",
  "score",
  "temperature",
  "dhv",
] as const;
const LATIN_OBFUSCATION_SEPARATOR =
  "[\\s\\p{P}\\p{S}\\p{C}\\p{M}\\u115f\\u1160\\u2800]*";

// 裸詞「篩選/筛选」已摘除（round7 bd4）：9fd3b8a5 去列字後 debrief 全路徑
// 注入已不含此詞（probe 實測 0 hit），守門只剩誤殺自然語（「導演+預告的
// 篩選法」）；hint 路另有 repairChineseJargon 轉譯，不經此表。複合內部詞
// 「資格篩選」是 1.2 原詞、無自然語用法，保留。若日後任何 debrief 注入
// 重新引入「篩選」原詞，必須同步回列（鐵則：注入內部詞必同步守門）。
const INTERNAL_MECHANISM_PHRASES = [
  "升溫指數",
  "升温指数",
  "資格篩選",
  "资格筛选",
  "推拉",
  "可得性",
  "賦格",
  "赋格",
  "框架",
];

/**
 * 批2 拍板的唯一白話 sentinel：「框架掉了」是 debrief 既定失敗狀態說法，
 * 檢查前先剝除＝維持放行；其他「框架」語境仍拒。
 */
const DEBRIEF_ALLOWED_SENTINELS = ["框架掉了"];

// 9fd3b8a5 去列字後，temperature.ts 隱藏層標頭改為「投入度 X/100」——全中文、
// 無英文 band 字，上面兩張表都攔不到；模型照抄注入行等於直送內部溫度分數
// （鐵則＝注入內部詞必同步擴可見輸出守門）。裸詞「投入度」是分析欄合法
// 後設評語詞（debrief_card.ts 分析欄），絕不可入表，只攔帶「X/100」分數形
// 的窄型態。NFKC 後全形數字／斜線已折疊，[\/／] 為雙保險。
const INTERNAL_SCORE_SHAPE_PATTERN = /投入度[^\d]{0,4}\d{1,3}\s*[\/／]\s*100/u;

function hasVisibleInternalScoreShapeLeak(value: string): boolean {
  return INTERNAL_SCORE_SHAPE_PATTERN.test(value.normalize("NFKC"));
}

export function hasVisibleTemperatureMechanismLeak(value: string): boolean {
  if (hasVisibleInternalScoreShapeLeak(value)) return true;
  const nfkc = value.normalize("NFKC");
  for (const label of INTERNAL_TEMPERATURE_LABELS_LATIN) {
    const obfuscatedLabel = [...label].join(LATIN_OBFUSCATION_SEPARATOR);
    const pattern = new RegExp(
      `(?:^|[^a-z0-9])${obfuscatedLabel}(?:$|[^a-z0-9])`,
      "iu",
    );
    if (pattern.test(nfkc)) return true;
  }
  let normalized = normalizeUnsafeText(nfkc);
  for (const sentinel of DEBRIEF_ALLOWED_SENTINELS) {
    normalized = normalized.replaceAll(normalizeUnsafeText(sentinel), "");
  }
  return INTERNAL_MECHANISM_PHRASES.some((phrase) =>
    normalized.includes(normalizeUnsafeText(phrase))
  );
}

export function rejectVisibleTemperatureMechanismLeak(
  value: string,
  errorCode: string,
) {
  if (hasVisibleTemperatureMechanismLeak(value)) {
    throw new Error(errorCode);
  }
}

function normalizeVisibleText(value: string): string {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function normalizeUnsafeText(value: string): string {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}\p{C}\p{M}_\u115f\u1160\u2800]+/gu, "");
}

const CLEAR_SAFETY_NEGATION_PREFIX =
  "(?:千萬不要|千万不要|不可以|不能|不准|不必|不用|不要|別|别|不可|不該|不该|不應|不应|避免|勿)";
const CLEAR_SAFETY_NEGATION_BRIDGE =
  "(?:再|去)?(?:說|说|叫|讓|让|逼|要求|帶|带)?(?:她|他|對方|对方|女生|人家)?";
const NEGATED_SAFETY_WARNING_PREFIX =
  /(?:誰說|谁说|不代表|不是(?:說|说|叫(?:你|妳|他|她)?|要(?:你|妳|他|她)?)?|並不是|并不是|並非|并非|沒(?:有)?(?:說|说|要(?:你|妳|他|她)?)?|没(?:有)?(?:说|要(?:你|妳|他|她)?)?|未必)$/u;
const SAFETY_REVERSAL_AFTER =
  /^(?:她|他|對方|对方|女生|人家)?(?:是假話|是假话|是假的|才怪|就怪了|只是表面(?:話|话)?|但|可是|不過|不过|實際上|实际上|反而|可以試試|可以试试|照做|直接做)/u;
const SAFETY_REVERSAL_NEXT_CLAUSE =
  /^(?:(?:但|可是|不過|不过)?(?:這|这|那)?(?:才怪|就怪了|是假話|是假话|是假的|只是表面(?:話|话)?|實際上|实际上|反而|可以試試|可以试试|照做|直接做))/u;
const STACKED_SAFETY_NEGATION_PREFIX =
  /(?:不要|別|别|勿|不能|不可以|不准|避免)$/u;
const SAFE_META_NEGATION_PREFIX =
  /(?:我)?(?:不是|並不是|并不是|並非|并非|沒有|没有|沒|没)(?:要|叫|讓|让|要求)(?:你|妳|他|她)?$/u;
const SAFE_PERMISSION_DENIAL_PREFIX =
  /(?:這|这|那|也)?不代表(?:你|妳|他|她|對方|对方)?(?:就)?可以$/u;
const SAFE_CONDEMNATION_SUFFIX =
  /^(?:她|他|對方|对方|女生|人家)?(?:是|這是|这是)?(?:不對|不对|錯的|错的|錯|错|違法|违法|不可以|不應該|不应该|不可取|有問題|有问题|越界|不尊重)(?:的|的行為|的行为|行為|行为)?(?:啦|囉|喔|哦|吧)?$/u;
const DIRECT_SAFETY_NEGATION_SUFFIX = new RegExp(
  `${CLEAR_SAFETY_NEGATION_PREFIX}${CLEAR_SAFETY_NEGATION_BRIDGE}$`,
  "u",
);

interface UnsafeOccurrence {
  index: number;
  length: number;
}

// round13 曾對「加重量還不能拒絕」健身吐槽做過 L4 詞面豁免；Codex 兩輪
// 對抗審（round14/15 P1）以命令前綴（我要求妳/我會逼妳＋加重量）與跨子句
// 組合（…拒絕吧，現在跟我回家）證明詞面層無法封閉，裁決撤除豁免、回歸
// fail-closed。bh5 良性句被攔＝已知且接受的 FP（首發打回，重試可救）。

function unsafeOccurrences(clause: string): UnsafeOccurrence[] {
  const keyed = new Map<string, UnsafeOccurrence>();
  for (const pattern of L4_UNSAFE_VISIBLE_PATTERNS) {
    const normalizedPattern = normalizeUnsafeText(pattern);
    let index = clause.indexOf(normalizedPattern);
    while (index >= 0) {
      keyed.set(`${index}:${normalizedPattern.length}`, {
        index,
        length: normalizedPattern.length,
      });
      index = clause.indexOf(normalizedPattern, index + 1);
    }
  }
  return [...keyed.values()].sort((a, b) =>
    a.index - b.index || b.length - a.length
  );
}

function hasDirectSafetyNegation(
  clause: string,
  occurrence: UnsafeOccurrence,
): boolean {
  const before = clause.slice(0, occurrence.index);
  const direct = before.match(DIRECT_SAFETY_NEGATION_SUFFIX)?.[0];
  if (!direct) return false;
  const beforeNegation = before.slice(0, -direct.length);
  if (NEGATED_SAFETY_WARNING_PREFIX.test(beforeNegation)) return false;
  if (STACKED_SAFETY_NEGATION_PREFIX.test(beforeNegation)) return false;
  const after = clause.slice(occurrence.index + occurrence.length);
  return !SAFETY_REVERSAL_AFTER.test(after);
}

function hasExplicitSafetyWarning(
  clause: string,
  occurrence: UnsafeOccurrence,
): boolean {
  const before = clause.slice(0, occurrence.index);
  const after = clause.slice(occurrence.index + occurrence.length);
  if (
    SAFE_META_NEGATION_PREFIX.test(before) ||
    SAFE_PERMISSION_DENIAL_PREFIX.test(before)
  ) {
    return !SAFETY_REVERSAL_AFTER.test(after);
  }
  return SAFE_CONDEMNATION_SUFFIX.test(after);
}

function clauseHasUnsafeAdvice(clause: string): boolean {
  const occurrences = unsafeOccurrences(clause);
  let previousSafe: UnsafeOccurrence | null = null;
  for (const occurrence of occurrences) {
    let safe = hasDirectSafetyNegation(clause, occurrence) ||
      hasExplicitSafetyWarning(clause, occurrence);
    if (!safe && previousSafe) {
      const between = clause.slice(
        previousSafe.index + previousSafe.length,
        occurrence.index,
      );
      const sharesNegationScope = between.length === 0 ||
        /^(?:她|他|對方|对方|女生|人家)?(?:或|和|以及|及)$/u.test(between);
      const after = clause.slice(occurrence.index + occurrence.length);
      safe = sharesNegationScope && !SAFETY_REVERSAL_AFTER.test(after);
    }
    if (!safe) return true;
    previousSafe = occurrence;
  }
  return false;
}

export function hasVisibleInternalLabelLeak(value: string): boolean {
  // 分數形檢查掛這裡讓 chat（handler）/hint 兩側可見輸出同步蓋到；
  // normalizeVisibleText 會剝掉中文，故用原文另測。
  if (hasVisibleInternalScoreShapeLeak(value)) return true;
  const normalized = normalizeVisibleText(value);
  return INTERNAL_VISIBLE_LABELS.some((label) => normalized.includes(label));
}

export function hasL4UnsafeVisibleText(value: string): boolean {
  const clauses = value
    .normalize("NFKC")
    .split(/[，,。.!！?？；;\n]+/u)
    .map(normalizeUnsafeText)
    .filter((clause) => clause.length > 0);
  // Clause analysis preserves negation/reversal scope, but an attacker can put
  // punctuation inside the unsafe token itself (強，迫／開。房). Detect any
  // pattern that exists only after whole-text compaction and fail closed.
  const compactWhole = normalizeUnsafeText(value);
  const normalizedPatterns = new Set(
    L4_UNSAFE_VISIBLE_PATTERNS.map(normalizeUnsafeText),
  );
  for (const pattern of normalizedPatterns) {
    if (
      compactWhole.includes(pattern) &&
      !clauses.some((clause) => clause.includes(pattern))
    ) {
      return true;
    }
  }
  for (let index = 0; index < clauses.length; index++) {
    const clause = clauses[index];
    const occurrences = unsafeOccurrences(clause);
    if (occurrences.length === 0) continue;
    if (clauseHasUnsafeAdvice(clause)) return true;
    if (SAFETY_REVERSAL_NEXT_CLAUSE.test(clauses[index + 1] ?? "")) {
      return true;
    }
  }
  return false;
}

export function rejectVisibleInternalLabelLeak(
  value: string,
  errorCode: string,
) {
  if (hasVisibleInternalLabelLeak(value)) {
    throw new Error(errorCode);
  }
}

export function rejectL4UnsafeVisibleText(value: string, errorCode: string) {
  if (hasL4UnsafeVisibleText(value)) {
    throw new Error(errorCode);
  }
}
