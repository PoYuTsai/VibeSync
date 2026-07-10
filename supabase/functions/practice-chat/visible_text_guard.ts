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
const INTERNAL_TEMPERATURE_LABELS_LATIN_PATTERN =
  /\b(?:frozen|cold|neutral|warm|hot|band|score|temperature|dhv)\b/i;

const INTERNAL_MECHANISM_PHRASES = [
  "升溫指數",
  "升温指数",
  "篩選",
  "筛选",
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

export function hasVisibleTemperatureMechanismLeak(value: string): boolean {
  const nfkc = value.normalize("NFKC");
  if (INTERNAL_TEMPERATURE_LABELS_LATIN_PATTERN.test(nfkc)) return true;
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
    .replace(/[\s\p{P}\p{S}_]+/gu, "");
}

export function hasVisibleInternalLabelLeak(value: string): boolean {
  const normalized = normalizeVisibleText(value);
  return INTERNAL_VISIBLE_LABELS.some((label) => normalized.includes(label));
}

export function hasL4UnsafeVisibleText(value: string): boolean {
  const normalized = normalizeUnsafeText(value);
  return L4_UNSAFE_VISIBLE_PATTERNS.some((pattern) =>
    normalized.includes(normalizeUnsafeText(pattern))
  );
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
