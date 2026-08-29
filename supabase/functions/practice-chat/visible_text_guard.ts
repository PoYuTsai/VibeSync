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
  // 認識管道注入標籤（hint evidence）；鐵則＝注入內部詞必同步擴可見輸出守門。
  // 用複合詞避免誤殺自然英文（"origin" 會命中 original 這類無害字）。
  "acquaintanceorigin",
  "origincontext",
  "originfocus",
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
  // gameLedger 整場帳注入標籤（debrief evidence）；鐵則＝注入內部詞必同步守門。
  "gameledger",
  "failurecounts",
  "lowestvariable",
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
  // hint decision.move 的內部戰術碼（server 權威，注入 debrief evidence）：
  // build_connection 是舊值、其餘是 2026-08-11 WP2 新增。鐵則＝注入內部詞
  // 必同步擴可見輸出守門，否則模型原樣抄進拆解卡沒人攔。
  "buildconnection",
  "openselfstate",
  "valuesidedisplay",
  "teststandardanddeny",
  "tensionpullpushstory",
  "closeleadnotask",
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
  // 模擬社群動態貼文（moments_prompt.ts）注入的結構標籤；鐵則＝注入內部詞
  // 必同步擴可見輸出守門，否則模型把標籤原樣抄進貼文沒人攔。
  // 全用英文複合詞，中文標籤表（INTERNAL_CHINESE_LABELS）不必新增。
  "momentpostspec",
  "momentdaypart",
  "momentthemebrief",
  "momentimageoptions",
  // 1:1 聊天的貼文記憶注入（PR D）。同樣全用英文複合詞，
  // 中文標籤表（INTERNAL_CHINESE_LABELS）不必新增。
  "herrecentmoments",
  "herownposts",
  // 時間錨點注入標籤（chat 的 nowContextPrompt、hint 的 nowEvidence）；
  // 鐵則＝注入內部詞必同步擴可見輸出守門。日期本身不進表：使用者本來就會
  // 問今天幾號，她照著答是對的行為，會外洩的只有標籤本身。
  "nowcontext",
  // 教練難度尺度注入標籤（hint evidence，PR 5）；鐵則＝注入內部詞必同步擴
  // 可見輸出守門。難度名稱本身（輕鬆／一般／挑戰）不進表：是自然中文詞，
  // 會外洩的只有標籤本身。
  "difficultycoachingstandard",
];

// ── 第二刀（2026-08-24 Eric 拍板）：L4 拆兩類 ─────────────────────────
// 同意權類＝同意權硬底線，任何欄位任何階段 fail-closed；
// 尺度類＝18 禁話題本身無罪，是時機問題——分析欄不查、照唸句欄按熱度。
// 案例表：docs/plans/2026-08-24-practice-guard-second-cut-case-table.md
const CONSENT_UNSAFE_PATTERNS = [
  "硬上",
  "強迫",
  "强迫",
  "不准拒絕",
  "不能拒絕",
  "不能拒绝",
  "灌醉",
  "迷昏",
  "非自願",
  "沒有同意",
  "羞辱你",
  "羞辱妳",
  "forceyou",
  "youcannotrefuse",
  "cantrefuse",
  // 第二刀 D 組（2026-08-24 實測漏詞）：無自然比喻用法的窄詞。
  "下藥",
  "下药",
  "迷姦",
  "迷奸",
  "強姦",
  "强奸",
  "輪姦",
  "轮奸",
  "強上",
  "强上",
  "偷拍",
  "趁她睡",
  "趁妳睡",
  "趁你睡",
  "趁她喝醉",
  "趁妳喝醉",
  "趁醉",
  // R1 主審 P1a（2026-08-24）：D1 拍板含「餵她吃藥」，補足餵藥族。
  "餵她吃藥",
  "餵妳吃藥",
  "喂她吃药",
  "喂妳吃药",
];

const SPICY_VISIBLE_PATTERNS = [
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
  "來我家過夜",
  "去我家過夜",
  "睡我家",
  "來我房間",
  "去你房間",
  "sex",
  "nude",
  "nudes",
  "undress",
  "privatephoto",
  "性交",
  "打炮",
  "約炮",
  "约炮",
  "脫光",
  "脱光",
  "直接睡你",
  "回家睡",
];

// D3「睡著後直接上」形：主詞省略、無「趁」字時詞表攔不到。
// ponytail: 窄啟發式——「睡著/喝醉＋後」接「直接/就＋單字動詞」或「動詞＋受詞」
// 才命中；「睡著後上線」這類「後＋複合動詞」自然語不攔。封閉性靠雙審對抗驗。
const CONSENT_INCAPACITATED_PATTERN =
  /(?:睡著|睡着|喝醉|斷片|断片|昏睡)(?:後|后)(?:(?:直接|就)(?:上|摸|脫|脱|親|亲|吻)|.{0,4}(?:上她|上妳|上他|摸她|摸妳|脫她|脱她|得逞|硬來|硬来))/u;

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
// 裸詞「框架」已摘除（2026-08-15 Eric 拍板）：注入源 7/23 已清乾淨，殘餘
// 全是模型自然語（「暱稱框架/遊戲框架」）被整張作廢；且「框架掉了」本就是
// 給用戶看的既定說法，此詞對用戶不算隱藏。連帶刪掉 sentinel 特例。
const INTERNAL_MECHANISM_PHRASES = [
  "升溫指數",
  "升温指数",
  "資格篩選",
  "资格筛选",
  "推拉",
  "可得性",
  "賦格",
  "赋格",
  // 2026-08-04 Codex Q5：認識管道是純中文隱藏標籤，debrief 生成文字若照抄
  // 這個詞，此表要攔到（鐵則：注入內部詞必同步擴可見輸出守門）。
  "認識管道",
  "认识管道",
  // 2026-08-08 詞彙統一拍板退場詞：prompt 已不教，模型直接生成時 debrief
  // 側 reject（hint 側另有 GAME_JARGON_TRANSLATIONS 修復成「測試」）。
  "品味門檻",
  "品味门槛",
];

// 9fd3b8a5 去列字後，temperature.ts 隱藏層標頭改為「投入度 X/100」——全中文、
// 無英文 band 字，上面兩張表都攔不到；模型照抄注入行等於直送內部溫度分數
// （鐵則＝注入內部詞必同步擴可見輸出守門）。裸詞「投入度」是分析欄合法
// 後設評語詞（debrief_card.ts 分析欄），絕不可入表，只攔帶「X/100」分數形
// 的窄型態。NFKC 後全形數字／斜線已折疊，[\/／] 為雙保險。
const INTERNAL_SCORE_SHAPE_PATTERN = /投入度[^\d]{0,4}\d{1,3}\s*[\/／]\s*100/u;

// gameLedger P1 破口（2026-08-08 Codex 首審＋二審收斂）：模型只抄數值內容
// （「Investment=22」「最低是 Investment 22 分」）時，標籤詞表攔不到。
// 二審裁定形狀：帶 =/: 分隔符一律攔；無分隔符只攔「分」結尾的分數語——
// 「Frame 3 個重點」這類自然英文＋量詞不誤殺。注入端已去數值，這裡是雙保險。
const INTERNAL_VARIABLE_SCORE_PATTERNS = [
  /\b(?:Value|Frame|Emotion|Investment|Safety|pv|fp|inv)\s*[=:：]\s*\d{1,3}\b/iu,
  /\b(?:Value|Frame|Emotion|Investment|Safety)\s+\d{1,3}\s*分/iu,
  // 第二刀 C2（2026-08-24 實測破口）：中文變數名＋分數敘述（「安全感分數
  // 還不到 60」）兩張英文表都攔不到。裸變數詞是合法後設評語（「她還沒有
  // 安全感」「整場投入度不高」），必須帶「量詞＋數字」才攔。
  /(?:安全感|好感度|投入度|信任度|熟悉度|熱度|热度)(?:的)?(?:分數|分数|指數|指数|數值|数值|值)?\s*(?:是|還不到|还不到|不到|只有|剩下?|低於|低于|高於|高于|超過|超过|掉到|升到|達到|达到|來到|来到|卡在)\s*\d{1,3}/u,
];

function hasVisibleInternalScoreShapeLeak(value: string): boolean {
  // 零寬/控制字元穿透（Codex 二審：p\u200bv=45、Safety\u200b:\u200b9）：
  // 先剝 \p{C}\p{M} 與已知混淆填充字再比對；無混淆時剝除是 no-op。
  const compact = value
    .normalize("NFKC")
    .replace(/[\p{C}\p{M}\u115f\u1160\u2800]/gu, "");
  if (INTERNAL_SCORE_SHAPE_PATTERN.test(compact)) return true;
  return INTERNAL_VARIABLE_SCORE_PATTERNS.some((pattern) =>
    pattern.test(compact)
  );
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
  const normalized = normalizeUnsafeText(nfkc);
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
  "(?:再|去)?(?:說|说|叫|讓|让|逼|要求|帶|带)?(?:在)?(?:她|他|對方|对方|女生|人家)?";
const NEGATED_SAFETY_WARNING_PREFIX =
  /(?:誰說|谁说|不代表|不是(?:說|说|叫(?:你|妳|他|她)?|要(?:你|妳|他|她)?)?|並不是|并不是|並非|并非|沒(?:有)?(?:說|说|要(?:你|妳|他|她)?)?|没(?:有)?(?:说|要(?:你|妳|他|她)?)?|未必)$/u;
const SAFETY_REVERSAL_AFTER =
  /^(?:她|他|對方|对方|女生|人家)?(?:是假話|是假话|是假的|才怪|就怪了|只是表面(?:話|话)?|但|可是|不過|不过|實際上|实际上|反而|可以試試|可以试试|照做|直接做)/u;
const SAFETY_REVERSAL_NEXT_CLAUSE =
  /^(?:(?:但|可是|不過|不过)?(?:這|这|那)?(?:才怪|就怪了|是假話|是假话|是假的|只是表面(?:話|话)?|實際上|实际上|反而|可以試試|可以试试|值得(?:一)?試(?:試)?|值得(?:一)?试(?:试)?|還是試試|还是试试|照做|直接做))/u;
const STACKED_SAFETY_NEGATION_PREFIX =
  /(?:不要|別|别|勿|不能|不可以|不准|避免)$/u;
const SAFE_META_NEGATION_PREFIX =
  /(?:我)?(?:不是|並不是|并不是|並非|并非|沒有|没有|沒|没)(?:要|叫|讓|让|要求)(?:你|妳|他|她)?$/u;
const SAFE_PERMISSION_DENIAL_PREFIX =
  /(?:這|这|那|也)?不代表(?:你|妳|他|她|對方|对方)?(?:就)?可以$/u;
const SAFE_CONDEMNATION_SUFFIX =
  /^(?:她|他|對方|对方|女生|人家)?(?:是|這是|这是)?(?:不對|不对|錯的|错的|錯|错|違法|违法|不可以|不應該|不应该|不可取|有問題|有问题|越界|不尊重)(?:的|的行為|的行为|行為|行为)?(?:啦|囉|喔|哦|吧)?$/u;
// 第二刀 D 組誤殺面：譴責詞跟受詞隔幾個字（「趁她喝醉『提出要求』是越界」）。
// 判準詞必須是明確負評，且中間窗口收窄到 8 字，避免被長句稀釋成恆放。
const SAFE_OFFSET_CONDEMNATION_AFTER =
  /^.{1,8}(?:是|這是|这是|算是)(?:很)?(?:不對|不对|錯的|错的|錯|错|違法|违法|犯罪|越界|不可以|不應該|不应该|不可取|性騷擾|性骚扰|侵犯|騷擾|骚扰)/u;
// 受害者視角（「她怕被偷拍」）：陳述她的恐懼不是教唆。
const SAFE_VICTIM_PERSPECTIVE_PREFIX = /(?:怕|害怕|擔心|担心|討厭|讨厌)被$/u;
// 第二刀 B4：同意權詞＋明確負面後果＝教練在勸退（「強迫她表態只會讓她
// 封鎖你」）。後果詞必須出自固定負面清單，fail-closed：「會愛上你」不放。
const SAFE_NEGATIVE_CONSEQUENCE_AFTER =
  /^.{0,10}(?:只會|只会|會|会)(?:讓|让|使)?.{0,10}(?:冷掉|冷場|冷场|反感|嚇跑|吓跑|防備|防备|封鎖|封锁|扣分|翻車|翻车|句點|句点|退開|退开|報警|报警|崩)/u;
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

function unsafeOccurrences(
  clause: string,
  patterns: readonly string[],
): UnsafeOccurrence[] {
  const keyed = new Map<string, UnsafeOccurrence>();
  for (const pattern of patterns) {
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
    SAFE_PERMISSION_DENIAL_PREFIX.test(before) ||
    SAFE_VICTIM_PERSPECTIVE_PREFIX.test(before)
  ) {
    return !SAFETY_REVERSAL_AFTER.test(after);
  }
  if (
    SAFE_OFFSET_CONDEMNATION_AFTER.test(after) ||
    SAFE_NEGATIVE_CONSEQUENCE_AFTER.test(after)
  ) {
    return !SAFETY_REVERSAL_AFTER.test(after);
  }
  return SAFE_CONDEMNATION_SUFFIX.test(after);
}

function clauseHasUnsafeAdvice(
  clause: string,
  patterns: readonly string[],
): boolean {
  const occurrences = unsafeOccurrences(clause, patterns);
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

// 2026-08-04 Codex Q5：INTERNAL_VISIBLE_LABELS 只認英文複合詞
// （hasVisibleInternalLabelLeak 剝掉中文後比對），若模型在 chat/hint 原樣
// 講出中文標籤「認識管道」，該表攔不到。這裡只放認識管道專屬的中文標籤，
// 不整包借用 INTERNAL_MECHANISM_PHRASES——那份清單的「推拉」等詞在
// chat/hint 側有既定白話 sentinel 與 1.2 jargon 翻譯白名單，整包借用會
// 誤殺既有放行案例。
// 2026-08-11 WP2：server 每輪注入的「本輪指定戰術」同樣是中文標籤，
// 英文複合詞表攔不到，比照認識管道收在這裡。
const INTERNAL_CHINESE_LABELS = [
  "認識管道",
  "认识管道",
  "本輪指定戰術",
  "本轮指定战术",
  // 反 prompt 外洩（2026-08-19）：system prompt 的指示標題出現在可見輸出
  // ＝系統指示外洩。R2 主審 MINOR-2：「你正在用手機跟對方傳訊息」是 NPC
  // 可能自然說出的場景句（誤殺面）→ 依審者建議拔除，只留指示標題。
  "系統指示保密",
  "系统指示保密",
];

export interface InternalLabelGuardOptions {
  /**
   * 第二刀 A 組（2026-08-24）原話豁免：代號詞逐字出現在本局對話原文
   * （使用者或 NPC）就不是機制外洩，可引用。只豁免兩張代號表；
   * 分數形不吃豁免（真隱藏值）。
   */
  transcript?: string;
}

export function hasVisibleInternalLabelLeak(
  value: string,
  opts?: InternalLabelGuardOptions,
): boolean {
  // 分數形檢查掛這裡讓 chat（handler）/hint 兩側可見輸出同步蓋到；
  // normalizeVisibleText 會剝掉中文，故用原文另測。
  if (hasVisibleInternalScoreShapeLeak(value)) return true;
  const transcript = opts?.transcript ?? "";
  const transcriptVisible = transcript ? normalizeVisibleText(transcript) : "";
  const transcriptUnsafe = transcript ? normalizeUnsafeText(transcript) : "";
  const normalized = normalizeVisibleText(value);
  if (
    INTERNAL_VISIBLE_LABELS.some((label) =>
      normalized.includes(label) && !transcriptVisible.includes(label)
    )
  ) {
    return true;
  }
  const unsafeNormalized = normalizeUnsafeText(value);
  return INTERNAL_CHINESE_LABELS.some((label) => {
    const normalizedLabel = normalizeUnsafeText(label);
    return unsafeNormalized.includes(normalizedLabel) &&
      !transcriptUnsafe.includes(normalizedLabel);
  });
}

export type VisibleFieldClass = "strict" | "analysis";

export interface L4GuardOptions {
  /**
   * strict＝照唸句欄（suggestedLine/nextFirstLine/兩顆球/NPC 回覆/罐頭路徑）；
   * analysis＝教練點評欄（summary/watchouts/coaching）。預設 strict＝現行行為。
   */
  fieldClass?: VisibleFieldClass;
  /**
   * 尺度類熱度門，只對 strict 有效。呼叫端用 spicyLevel === "L3" 計算；
   * 守門不懂階段語意。同意權類不受此旗標影響。
   */
  spicyAllowed?: boolean;
}

// 分析欄的尺度類不走詞面攔截，只攔「教唆推進」形（B9）：命令/急迫詞＋
// 推進動詞、使役（叫她/要她）、或「測底線」。譴責語境（「直接提上床
// 『是越界』」）與否定語境（「別叫她來我家過夜」）豁免。
const ANALYSIS_SPICY_ADVOCACY_PATTERN =
  /(?:直接|馬上|马上|立刻|下次|現在|现在|就)(?:去|再)?(?:約|约|提|開|开|睡|推|帶|带)|叫(?:她|他|你|妳)|要求(?:她|他)|測底線|测底线/u;
// R1 主審 P2（2026-08-24）：18 禁詞彙是開放集合，「她說不想，所以你下次直接
// 問什麼姿勢最爽測底線」不含詞表詞也是拒絕後翻轉教唆。啟發式三條件齊備才攔：
// 拒絕訊號（本句或前句）＋越線推進標記＋對用戶的指示語氣；「她在測你底線」
// 這類合法教練判讀沒有指示語氣，不誤殺。
// ponytail: 開放詞彙教唆無法在詞面層封閉，主力在 prompt；這裡只封拒絕後翻轉
// 的窄形。
const ANALYSIS_REFUSAL_PATTERN =
  /(?:不想|不願|不愿|拒絕|拒绝|還沒準備好|还没准备好|別這樣|别这样)/u;
const ANALYSIS_PUSH_MARKER_PATTERN =
  /(?:測|测)底(?:線|线)|硬(?:要|推|來|来)|施壓|施压|不管(?:她|他|對方|对方)(?:願不願|愿不愿)/u;
// R2 主審 P1b：補「你要/你得/建議你」等高頻指示形。
const ANALYSIS_USER_DIRECTED_PATTERN =
  /(?:你|妳)(?:下次|直接|就|再|去|可以|應該|应该|要|得|該|该|必須|必须|不妨|試著|试着|繼續|继续)|(?:下次|接下來|接下来)(?:直接|就)|建(?:議|议)(?:你|妳)/u;
const ANALYSIS_CLAUSE_CONDEMNATION_PATTERN =
  /(?:是|算是)(?:很)?(?:越界|不對|不对|錯|错|不可以|不應該|不应该|不可取|不尊重|有問題|有问题)|翻車|翻车|(?:只會|只会|會|会)(?:讓|让|使)?.{0,10}(?:冷掉|反感|嚇跑|吓跑|防備|防备|封鎖|封锁|扣分|句點|句点)/u;

// R2 主審 P1a：譴責豁免必須在危險語**之後**（「你再硬推就是越界」是警示；
// 「是越界但你就再硬推」是翻轉教唆），且譴責後不得再接翻轉連接詞。
const ANALYSIS_CONDEMNATION_REVERSAL_PATTERN =
  /(?:但|可是|不過|不过|然而|反而|照做|直接做|可以試試|可以试试|值得(?:一)?試(?:試)?|值得(?:一)?试(?:试)?)/u;

function condemnationExemptsAfter(clause: string, index: number): boolean {
  const tail = clause.slice(index);
  const match = ANALYSIS_CLAUSE_CONDEMNATION_PATTERN.exec(tail);
  if (!match) return false;
  const afterCondemnation = tail.slice(match.index + match[0].length);
  return !ANALYSIS_CONDEMNATION_REVERSAL_PATTERN.test(afterCondemnation);
}

export function hasL4UnsafeVisibleText(
  value: string,
  opts?: L4GuardOptions,
): boolean {
  const fieldClass = opts?.fieldClass ?? "strict";
  const spicyActive = fieldClass === "strict" && opts?.spicyAllowed !== true;
  // 同意權類永遠查；尺度類只在低熱照唸句欄併入同一輪機制（負向/譴責語境
  // 邏輯與現行完全一致），讓跨類共享否定範圍的既有行為不變。
  const activePatterns = spicyActive
    ? [...CONSENT_UNSAFE_PATTERNS, ...SPICY_VISIBLE_PATTERNS]
    : CONSENT_UNSAFE_PATTERNS;
  const clauses = value
    .normalize("NFKC")
    .split(/[，,。.!！?？；;\n]+/u)
    .map(normalizeUnsafeText)
    .filter((clause) => clause.length > 0);
  // D3 無行為能力形：詞表攔不到的「睡著後直接上」。R1 主審 P1b：不再無條件
  // 攔——當成同意權 occurrence 走同一套否定/譴責語境判斷（「不要在她睡著後
  // 直接上」「…是越界」放行）；標點穿透（直接。上）子句層看不到完整形，
  // 比照詞表 fail closed。
  const incapacitatedInClause = clauses.some((clause) =>
    CONSENT_INCAPACITATED_PATTERN.test(clause)
  );
  if (
    !incapacitatedInClause &&
    CONSENT_INCAPACITATED_PATTERN.test(normalizeUnsafeText(value))
  ) {
    return true;
  }
  // Clause analysis preserves negation/reversal scope, but an attacker can put
  // punctuation inside the unsafe token itself (強，迫／開。房). Detect any
  // pattern that exists only after whole-text compaction and fail closed.
  // 分析欄的尺度類雖然逐子句放行，但標點穿透（叫她上，床）讓子句層看不到
  // 完整詞、語境判讀失效——同樣 fail closed；只有高熱照唸句欄整類豁免。
  const compactWhole = normalizeUnsafeText(value);
  const compactionPatterns = spicyActive
    ? activePatterns
    : (fieldClass === "analysis"
      ? [...CONSENT_UNSAFE_PATTERNS, ...SPICY_VISIBLE_PATTERNS]
      : activePatterns);
  const normalizedPatterns = new Set(
    compactionPatterns.map(normalizeUnsafeText),
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
    const occurrences = unsafeOccurrences(clause, activePatterns);
    if (occurrences.length > 0) {
      if (clauseHasUnsafeAdvice(clause, activePatterns)) return true;
      if (SAFETY_REVERSAL_NEXT_CLAUSE.test(clauses[index + 1] ?? "")) {
        return true;
      }
    }
    // D3 無行為能力形（R1 P1b）：regex 命中當 occurrence 走同一套語境判斷。
    const incapacitated = clause.match(CONSENT_INCAPACITATED_PATTERN);
    if (incapacitated && incapacitated.index !== undefined) {
      const occurrence = {
        index: incapacitated.index,
        length: incapacitated[0].length,
      };
      const safe = hasDirectSafetyNegation(clause, occurrence) ||
        hasExplicitSafetyWarning(clause, occurrence);
      if (!safe) return true;
      if (SAFETY_REVERSAL_NEXT_CLAUSE.test(clauses[index + 1] ?? "")) {
        return true;
      }
    }
    if (fieldClass === "analysis") {
      // R1 P2：拒絕後翻轉教唆不依賴尺度詞表（開放詞彙）。
      const refusalInScope = ANALYSIS_REFUSAL_PATTERN.test(clause) ||
        ANALYSIS_REFUSAL_PATTERN.test(clauses[index - 1] ?? "");
      const pushMatch = refusalInScope
        ? ANALYSIS_PUSH_MARKER_PATTERN.exec(clause)
        : null;
      if (
        pushMatch &&
        ANALYSIS_USER_DIRECTED_PATTERN.test(clause) &&
        !condemnationExemptsAfter(clause, pushMatch.index)
      ) {
        return true;
      }
      // 分析欄尺度類：教唆形（無譴責、無否定）攔、下一子句翻轉攔，其餘全放。
      const spicyHits = unsafeOccurrences(clause, SPICY_VISIBLE_PATTERNS);
      if (spicyHits.length > 0) {
        const unprotectedHit = spicyHits.find((occurrence) =>
          !hasDirectSafetyNegation(clause, occurrence) &&
          !hasExplicitSafetyWarning(clause, occurrence)
        );
        if (
          unprotectedHit &&
          ANALYSIS_SPICY_ADVOCACY_PATTERN.test(clause) &&
          !condemnationExemptsAfter(clause, unprotectedHit.index)
        ) {
          return true;
        }
        if (SAFETY_REVERSAL_NEXT_CLAUSE.test(clauses[index + 1] ?? "")) {
          return true;
        }
      }
    }
  }
  return false;
}

export function rejectVisibleInternalLabelLeak(
  value: string,
  errorCode: string,
  opts?: InternalLabelGuardOptions,
) {
  if (hasVisibleInternalLabelLeak(value, opts)) {
    throw new Error(errorCode);
  }
}

export function rejectL4UnsafeVisibleText(
  value: string,
  errorCode: string,
  opts?: L4GuardOptions,
) {
  if (hasL4UnsafeVisibleText(value, opts)) {
    throw new Error(errorCode);
  }
}
