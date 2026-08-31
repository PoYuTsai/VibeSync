// 台灣繁中可見文字的英文守門（2026-08-31，「欸你today過得怎樣」案）。
//
// 為什麼是來源支持制而不是黑名單或「禁所有英文」：同一種病已發作四次
// （простее→long→safe→today），一次補一個字治不了；全禁 A–Z 又會誤殺
// LINE、Netflix、英文名字與使用者自己寫的英文。規則收斂成：
// 建議句裡的英文詞必須「使用者親手寫過」或在小白名單裡，其餘判 language_drift
// 交給既有重試機制在扣費前重生。教練自己的舊輸出不算來源（記憶回注會讓
// 第一次漏出的英文替下一次背書）。
//
// 這裡刻意只做偵測不做改寫：英文詞常是謂語，摳掉會留殘句（08-17 教訓）；
// 正確順序是拒絕→讓模型依脈絡重寫。

// 小白名單（Eric 2026-08-31 拍板選項 A）：只收品牌/服務名與 OK 這類極少數
// 詞，一律小寫比對。自然外來語（chill、+1…）刻意不收——教練「教你怎麼寫」
// 的句子要乾淨；要夾雜必須有使用者來源。
const ALLOWED_LATIN_TOKENS = new Set([
  "ai",
  "android",
  "app",
  "emoji",
  "facebook",
  "fb",
  "gif",
  "google",
  "ig",
  "instagram",
  "ios",
  "iphone",
  "ktv",
  "line",
  "netflix",
  "ok",
  "okay",
  "spotify",
  "threads",
  "uber",
  "youtube",
]);

// 網址、Email、@帳號、Hashtag 整段先摘掉，不逐 token 判。
const IGNORED_SEGMENT_PATTERN =
  /https?:\/\/\S+|www\.\S+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+|[@#][A-Za-z0-9_.]+/g;

const LATIN_TOKEN_PATTERN = /[A-Za-z]+(?:['’][A-Za-z]+)*/g;

// 使用者明確要英文時，建議句放行（教練解釋欄位仍守繁中）。
// 否定句（「不要用英文回」「不是要你用英文寫」）不算要求——否則一句普通
// 否定就整段解除守門（R1 審查 P1-4）。
const EXPLICIT_ENGLISH_REQUEST_PATTERN =
  /用英[文語]|英文回|英文訊息|英文寫|全英文|in english/i;
const NEGATED_ENGLISH_REQUEST_PATTERN =
  /(?:不要|不用|不必|不想|不是|別|沒有)[^，。！？]{0,4}(?:用英[文語]|英文回|英文訊息|英文寫)/;

export function isExplicitEnglishRequest(userQuestion: string): boolean {
  return EXPLICIT_ENGLISH_REQUEST_PATTERN.test(userQuestion) &&
    !NEGATED_ENGLISH_REQUEST_PATTERN.test(userQuestion);
}

/**
 * 回傳 text 裡「沒有來源支持、也不在白名單」的英文詞（去重、保留原大小寫）。
 * source 只能餵使用者親手寫的文字；空陣列＝全部合法。
 * 來源比對用整詞集合，不用子字串——來源寫 busywork 不能替 busy 背書
 * （R1 審查 P2-6）。
 * 單一字母 token（A咖、B型、P.S.）放行——中文語境常見且無混語觀感。
 */
export function findUnsupportedLatinTokens(
  text: string,
  sourceText: string,
): string[] {
  const cleaned = text.replace(IGNORED_SEGMENT_PATTERN, " ");
  const sourceTokens = new Set(
    [...sourceText.matchAll(LATIN_TOKEN_PATTERN)].map((m) =>
      m[0].toLowerCase()
    ),
  );
  const seen = new Set<string>();
  const offenders: string[] = [];
  for (const match of cleaned.matchAll(LATIN_TOKEN_PATTERN)) {
    const token = match[0];
    if (token.length <= 1) continue;
    const lower = token.toLowerCase();
    if (seen.has(lower)) continue;
    seen.add(lower);
    if (ALLOWED_LATIN_TOKENS.has(lower)) continue;
    if (sourceTokens.has(lower)) continue;
    offenders.push(token);
  }
  return offenders;
}
