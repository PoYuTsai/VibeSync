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
