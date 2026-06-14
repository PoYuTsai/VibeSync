// OCR Golden Set 跑分腳本（黑箱）
//
// 把 golden set 截圖打到 analyze-chat 的 recognizeOnly 端點（不扣 quota），
// 收 recognizedConversation 與 ground truth labels 比對，輸出六指標報告。
// 完全不 import、不複製任何 OCR 程式碼——量到的是用戶真實吃到的全鏈結果。
//
// 用法：
//   deno run --allow-net --allow-read --allow-write --allow-env run_benchmark.ts \
//     [--endpoint <url>] [--only <unit-id>] [--concurrency 2] [--out results/]
//
// 環境變數：
//   OCR_GOLDEN_IMAGES_DIR  真實圖目錄（不入 git；預設見 DEFAULT_IMAGES_DIR）
//   OCR_GOLDEN_TOKEN       Supabase 使用者 JWT（prod 模式必填；local --no-verify-jwt 可免）
//   OCR_GOLDEN_ANON_KEY    Supabase anon/publishable key（prod 模式 apikey header）
//
// 設計文件：docs/plans/2026-06-12-ocr-golden-set-design.md

const DEFAULT_ENDPOINT =
  "https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/analyze-chat";
const DEFAULT_IMAGES_DIR =
  "/mnt/c/Users/eric1/OneDrive/Desktop/VibeSync測試照片/OCR測試圖片";
const SIMILARITY_THRESHOLD = 0.8;

// ---------- 型別 ----------

interface ManifestUnit {
  id: string;
  source: "real" | "real_derived" | "synthetic";
  images: string[]; // 檔名（依 source 決定根目錄），多張 = 一組同請求（重疊情境）
  label: string; // labels/ 下相對路徑
  scenarios: string[];
}

interface LabelMessage {
  side: "left" | "right";
  text: string;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean; // 引用的舊訊息是誰發的（誰引用誰）
  quotedName?: string; // 引用卡內被引用者的顯示名（第③軌 Phase1 名字量測 ground truth）
}

interface GoldenLabel {
  id: string;
  contactName: string | null;
  classification: string;
  importPolicy: string;
  messages: LabelMessage[];
  notes?: string;
}

interface RecognizedMessage {
  side?: string;
  isFromMe?: boolean;
  content?: string;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
}

interface RecognizedConversation {
  contactName?: string | null;
  classification?: string;
  importPolicy?: string;
  confidence?: string;
  sideConfidence?: string;
  uncertainSideCount?: number;
  messageCount?: number;
  messages?: RecognizedMessage[];
  normalizationTelemetry?: Record<string, number>;
  warning?: string | null;
}

// ── 第③軌 Phase 1（量測閘）純觀測 telemetry ────────────────────────────
// server 在 OCR_PHASE1_INSTRUMENT=1 時於回應頂層附 phase1Vision（normalize 折疊前的
// 原始 vision 輸出）。harness 對它算 fill-only 側別、名字召回/正確率，與 position-only 對打。
interface Phase1VisionMessage {
  content: string;
  side: string | null;
  outerColumn: string | null;
  horizontalPosition: number | null;
  blockType: string | null;
  isFromMe: boolean;
  bubbleFillColor: string | null;
  senderNameRaw: string | null;
  senderNameX: number | null;
  quotedName: string | null;
  quotedNamePresent: boolean | null;
}

interface Phase1Vision {
  myBubbleColor: string | null;
  myBubbleColorEvidence: string | null;
  screenSpeakerPattern: string | null;
  messages: Phase1VisionMessage[];
}

// 一則對齊後的側別量測：fill-only 與 position-only 各自對 ground truth 的判斷。
interface Phase1SideRow {
  text: string; // 截斷，audit 用
  gtSide: "left" | "right";
  rawSide: string | null; // 模型自報 side（= position-only 訊號）
  fillSide: "left" | "right" | "unknown"; // (bubbleFillColor==myBubbleColor)?right:left
  bubbleFillColor: string | null;
  senderNameRaw: string | null;
  visionQuotedName: string | null;
}

interface Phase1UnitResult {
  myBubbleColor: string | null;
  myBubbleColorEvidence: string | null;
  alignedRows: number;
  fillKnown: number; // fill-only 能判（myBubbleColor 已知且泡色非空）的列數
  fillCorrect: number; // fill-only 判對數（只計 fillKnown）
  posCorrect: number; // position-only（raw side）判對數（計全部 aligned）
  posKnown: number; // raw side ∈ {left,right} 的列數
  // 名字（以 label 有標 quotedName 的列為 ground truth；set-level 比對避免脆弱逐列歸屬）
  quotedNameExpected: number;
  quotedNameRecalled: number; // vision 任一列吐出可匹配的 quotedName
  rows: Phase1SideRow[]; // 逐列 audit dump（含 senderNameRaw，供「不混欄」目檢）
}

interface UnitResult {
  id: string;
  source: string;
  scenarios: string[];
  httpStatus: number;
  rejected: boolean; // RECOGNITION_UNSUPPORTED（測非聊天圖防護時可能是正確答案）
  error?: string;
  latencyMs?: number;
  expectedCount?: number;
  actualCount?: number;
  alignedCount?: number;
  sideCorrect?: number;
  unknownSides?: number;
  exactTextMatches?: number;
  charErrors?: number;
  charTotal?: number;
  missed?: { side: string; text: string }[];
  hallucinated?: { side: string; text: string }[];
  // 多出來的 actual 列依性質拆桶（皆為真實污染 analyze-chat 的列，不從 precision 抹掉，只標明性質）
  quotedPreviewLeaks?: { side: string; text: string }[]; // 引用預覽被當訊息吐（③ 鬼訊息）
  activityCardNoise?: { side: string; text: string }[]; // 活動卡被拆成日期/時段/按鈕碎片
  sideMismatches?: { expected: string; actual: string; text: string }[];
  classificationMatch?: boolean;
  importPolicyMatch?: boolean;
  uncertainSideCount?: number;
  sideConfidence?: string;
  telemetry?: Record<string, number>;
  quoteAuthorCorrect?: number; // 誰引用誰：isFromMe 判對數（只計 label 有標 quotedReplyPreviewIsFromMe 的 aligned 則）
  quoteAuthorTotal?: number;
  quotePreviewCorrect?: number; // 引用預覽文字判對數（只計 label 有 quotedReplyPreview 的 aligned 則）
  quotePreviewTotal?: number;
  phase1?: Phase1UnitResult; // 第③軌 Phase1 純觀測（server 旗標開時才有）
}

// ---------- 文字比對 ----------

export function normalizeText(s: string): string {
  return s.normalize("NFKC").replace(/\s+/g, "").toLowerCase();
}

// 媒體 token 歸一：把描述型媒體標記（[sticker: 狗]、[photo of x]、sent a photo、
// [貼圖]）收斂成 label 採用的裸 token（[sticker] / [photo] / [video]）。
// 真實 OCR 會吐豐富描述，label 只記 [sticker]/[photo]，不歸一會被當「漏抓+幻覺」雙重扣分。
export function canonicalizeMedia(s: string): string {
  const lower = s.trim().toLowerCase();
  const toToken = (kind: string): string => {
    if (kind === "sticker" || kind === "貼圖") return "[sticker]";
    if (kind === "video" || kind === "影片" || kind === "gif") return "[video]";
    return "[photo]"; // photo/image/picture/照片/圖片 → photo bucket
  };
  const kinds = "sticker|photo|image|picture|video|gif|貼圖|照片|圖片|影片";
  // (?![a-z]) 取代 \b：CJK kind（貼圖/照片）後接 ] 時 ASCII \b 不成立，但仍要擋 photographic
  const bracket = lower.match(new RegExp(`^\\[\\s*(${kinds})(?![a-z])[^\\]]*\\]?$`));
  if (bracket) return toToken(bracket[1]);
  const desc = lower.match(
    new RegExp(`\\b(?:sent|shared|uploaded|attached)\\s+(?:an?\\s+)?(${kinds})\\b`),
  );
  if (desc) return toToken(desc[1]);
  const of = lower.match(/\b(photo|image|picture|video)\s+of\b/);
  if (of) return toToken(of[1]);
  return s;
}

// emoji 容差：去 emoji、膚色修飾（U+1F3FB-1F3FF）、variation selector（U+FE0F）、ZWJ。
// emoji 真值本身常不可靠（label 註記 😯/😲 難辨），不該讓 emoji 差異打斷文字對齊或污染逐字率/CER。
export function stripEmoji(s: string): string {
  // Extended_Pictographic = 多數 emoji；外加膚色修飾、variation selector(FE0F)、ZWJ(200D)。
  const EMOJI = /[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}️‍]/gu;
  return s.replace(EMOJI, "");
}

// 計分用歸一：媒體歸一 + 去 emoji + 文字歸一。對齊、逐字率、CER 都走這條，
// 確保量到的是「文字內容對不對」，而非媒體描述風格或 emoji 變體。
function normalizeForScoring(s: string): string {
  return normalizeText(stripEmoji(canonicalizeMedia(s)));
}

// 活動卡雜訊：LINE 預約/連結卡被 OCR 拆成日期/時段/按鈕碎片列。
// label 只保留卡片標題為一則訊息，碎片列若當一般幻覺會冤枉 precision；獨立歸類才看得出真相。
export function isActivityCardNoise(content: string): boolean {
  const t = content.trim();
  if (!t || t.length > 24) return false;
  if (/^(預約|報名|查看|加入|前往|reserve|book|join)$/i.test(t)) return true;
  // 純日期：06/10 (三) / 2026/06/10 / 6-10
  if (/^\d{1,4}[/-]\d{1,2}(?:[/-]\d{1,2})?\s*(?:[（(][^）)]{1,3}[）)])?$/.test(t)) {
    return true;
  }
  // 純時段：19:00 ~ 20:00 / 19:00-20:00 / 19:00
  if (/^\d{1,2}:\d{2}(?:\s*[~\-－—至]\s*\d{1,2}:\d{2})?$/.test(t)) return true;
  return false;
}

export function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const curr = [i];
    for (let j = 1; j <= b.length; j++) {
      curr[j] = Math.min(
        prev[j] + 1,
        curr[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    prev = curr;
  }
  return prev[b.length];
}

export function similarity(a: string, b: string): number {
  const na = normalizeForScoring(a);
  const nb = normalizeForScoring(b);
  if (!na.length && !nb.length) return 1;
  const maxLen = Math.max(na.length, nb.length);
  return maxLen === 0 ? 1 : 1 - levenshtein(na, nb) / maxLen;
}

// LCS 序列對齊：相似度 ≥ 門檻視為可匹配，保持順序、最大化匹配數。
// 回傳 expected index -> actual index 的配對。
export function alignMessages(
  expected: LabelMessage[],
  actual: RecognizedMessage[],
): Array<[number, number]> {
  const n = expected.length;
  const m = actual.length;
  const sim: number[][] = Array.from(
    { length: n },
    (_, i) =>
      Array.from(
        { length: m },
        (_, j) => similarity(expected[i].text, actual[j].content ?? ""),
      ),
  );
  // dp[i][j] = 前 i 個 expected、前 j 個 actual 的最佳（匹配數, 相似度總和）
  const dp: number[][] = Array.from(
    { length: n + 1 },
    () => new Array(m + 1).fill(0),
  );
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      const match = sim[i - 1][j - 1] >= SIMILARITY_THRESHOLD
        ? dp[i - 1][j - 1] + 1 + sim[i - 1][j - 1] / 1000 // 微權重偏好高相似
        : -Infinity;
      dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1], match);
    }
  }
  // 回溯
  const pairs: Array<[number, number]> = [];
  let i = n, j = m;
  while (i > 0 && j > 0) {
    const match = sim[i - 1][j - 1] >= SIMILARITY_THRESHOLD
      ? dp[i - 1][j - 1] + 1 + sim[i - 1][j - 1] / 1000
      : -Infinity;
    if (dp[i][j] === match) {
      pairs.push([i - 1, j - 1]);
      i--;
      j--;
    } else if (dp[i][j] === dp[i - 1][j]) {
      i--;
    } else {
      j--;
    }
  }
  return pairs.reverse();
}

// ---------- 第③軌 Phase 1 量測 ----------

// 顏色歸一：小寫去空白，grey→gray。fill-only 只需判「此泡色 == 我方色」，
// 故比較歸一字串即可（不做色系模糊歸併，避免把 gray/green 誤併）。
function normalizeColor(c: string | null | undefined): string {
  if (typeof c !== "string") return "";
  return c.trim().toLowerCase().replace(/grey/g, "gray");
}

// fill-only 側別：myBubbleColor 已知且本泡色非空才可判，否則 unknown（不亂猜）。
function deriveFillSide(
  bubbleFillColor: string | null,
  myBubbleColor: string | null,
): "left" | "right" | "unknown" {
  const my = normalizeColor(myBubbleColor);
  const fill = normalizeColor(bubbleFillColor);
  if (!my || my === "unknown" || !fill || fill === "none") return "unknown";
  return fill === my ? "right" : "left";
}

// Wilson 95% 下界：擋小樣本假漂亮（gate 第 2 層）。
export function wilsonLowerBound(correct: number, n: number): number | null {
  if (n <= 0) return null;
  const z = 1.96;
  const p = correct / n;
  const z2 = z * z;
  const denom = 1 + z2 / n;
  const centre = p + z2 / (2 * n);
  const margin = z *
    Math.sqrt((p * (1 - p) + z2 / (4 * n)) / n);
  return (centre - margin) / denom;
}

// 對單一 unit 算 Phase1 純觀測指標。phase1Vision 缺席（旗標關/舊 run）回 undefined。
export function scorePhase1(
  label: GoldenLabel,
  phase1: Phase1Vision | undefined,
): Phase1UnitResult | undefined {
  if (!phase1 || !Array.isArray(phase1.messages)) return undefined;
  const visionMsgs = phase1.messages;
  // 對齊：label 活訊息 ↔ raw vision 列（含 quoted_preview，多半不對齊即略過）。
  const actualForAlign: RecognizedMessage[] = visionMsgs.map((m) => ({
    content: m.content,
    side: m.side ?? undefined,
  }));
  const pairs = alignMessages(label.messages, actualForAlign);

  const rows: Phase1SideRow[] = [];
  let fillKnown = 0, fillCorrect = 0, posCorrect = 0, posKnown = 0;
  for (const [ei, ai] of pairs) {
    const gtSide = label.messages[ei].side;
    const vm = visionMsgs[ai];
    const rawSide = vm.side;
    const fillSide = deriveFillSide(vm.bubbleFillColor, phase1.myBubbleColor);
    if (rawSide === "left" || rawSide === "right") {
      posKnown++;
      if (rawSide === gtSide) posCorrect++;
    }
    if (fillSide !== "unknown") {
      fillKnown++;
      if (fillSide === gtSide) fillCorrect++;
    }
    rows.push({
      text: label.messages[ei].text.slice(0, 24),
      gtSide,
      rawSide,
      fillSide,
      bubbleFillColor: vm.bubbleFillColor,
      senderNameRaw: vm.senderNameRaw,
      visionQuotedName: vm.quotedName,
    });
  }

  // 名字：以 label 標了 quotedName 的列為 ground truth；set-level 召回（避免脆弱逐列歸屬）。
  const expectedNames = label.messages
    .map((m) => m.quotedName)
    .filter((n): n is string => typeof n === "string" && n.trim().length > 0);
  const visionNames = visionMsgs
    .map((m) => m.quotedName)
    .filter((n): n is string => typeof n === "string" && n.trim().length > 0);
  let quotedNameRecalled = 0;
  for (const expName of expectedNames) {
    if (visionNames.some((vn) => similarity(expName, vn) >= SIMILARITY_THRESHOLD)) {
      quotedNameRecalled++;
    }
  }

  return {
    myBubbleColor: phase1.myBubbleColor,
    myBubbleColorEvidence: phase1.myBubbleColorEvidence,
    alignedRows: pairs.length,
    fillKnown,
    fillCorrect,
    posCorrect,
    posKnown,
    quotedNameExpected: expectedNames.length,
    quotedNameRecalled,
    rows,
  };
}

// ---------- HTTP ----------

function detectMediaType(file: string): string {
  if (file.endsWith(".png")) return "image/png";
  if (file.endsWith(".webp")) return "image/webp";
  return "image/jpeg";
}

async function loadImageBase64(path: string): Promise<string> {
  const bytes = await Deno.readFile(path);
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

async function callRecognizeOnly(
  endpoint: string,
  token: string | undefined,
  anonKey: string | undefined,
  imagePaths: string[],
): Promise<{ status: number; body: Record<string, unknown>; latencyMs: number }> {
  const images = [];
  for (let i = 0; i < imagePaths.length; i++) {
    images.push({
      data: await loadImageBase64(imagePaths[i]),
      mediaType: detectMediaType(imagePaths[i]),
      order: i + 1, // server 驗證 1-based（index.ts: img.order < 1 → 400）
    });
  }
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  if (anonKey) headers["apikey"] = anonKey;

  const maxAttempts = 3;
  for (let attempt = 1; ; attempt++) {
    const start = performance.now();
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify({ recognizeOnly: true, images, messages: [] }),
      });
      const latencyMs = Math.round(performance.now() - start);
      const text = await res.text();
      let body: Record<string, unknown> = {};
      try {
        body = JSON.parse(text);
      } catch {
        body = { error: `non-JSON response: ${text.slice(0, 200)}` };
      }
      // 429/5xx 重試；400（reject gate）是合法結果不重試
      if ((res.status === 429 || res.status >= 500) && attempt < maxAttempts) {
        console.error(`  ↻ HTTP ${res.status}，${attempt * 5}s 後重試…`);
        await new Promise((r) => setTimeout(r, attempt * 5000));
        continue;
      }
      return { status: res.status, body, latencyMs };
    } catch (err) {
      if (attempt < maxAttempts) {
        console.error(`  ↻ 網路錯誤（${err}），${attempt * 5}s 後重試…`);
        await new Promise((r) => setTimeout(r, attempt * 5000));
        continue;
      }
      throw err;
    }
  }
}

// ---------- 打分 ----------

export function scoreUnit(
  unit: ManifestUnit,
  label: GoldenLabel,
  status: number,
  body: Record<string, unknown>,
  latencyMs: number,
): UnitResult {
  const base: UnitResult = {
    id: unit.id,
    source: unit.source,
    scenarios: unit.scenarios,
    httpStatus: status,
    rejected: false,
    latencyMs,
  };

  // reject gate（400 RECOGNITION_UNSUPPORTED）：對 importPolicy=reject 的 label 是正確答案
  if (status === 400 && body.code === "RECOGNITION_UNSUPPORTED") {
    base.rejected = true;
    base.importPolicyMatch = label.importPolicy === "reject";
    base.classificationMatch = label.importPolicy === "reject";
    return base;
  }
  if (status !== 200) {
    base.error = String(body.error ?? body.message ?? `HTTP ${status}`);
    return base;
  }

  const rec = body.recognizedConversation as RecognizedConversation | undefined;
  if (!rec || !Array.isArray(rec.messages)) {
    base.error = "回應缺 recognizedConversation.messages";
    return base;
  }

  const expected = label.messages;
  const actual = rec.messages;
  const pairs = alignMessages(expected, actual);

  let sideCorrect = 0;
  let unknownSides = 0;
  let exactTextMatches = 0;
  let charErrors = 0;
  let charTotal = 0;
  let quoteAuthorCorrect = 0;
  let quoteAuthorTotal = 0;
  let quotePreviewCorrect = 0;
  let quotePreviewTotal = 0;
  const sideMismatches: UnitResult["sideMismatches"] = [];

  for (const [ei, ai] of pairs) {
    const exp = expected[ei];
    const act = actual[ai];
    const actSide = act.side ?? (act.isFromMe ? "right" : "left");
    if (actSide === "unknown") unknownSides++;
    if (actSide === exp.side) {
      sideCorrect++;
    } else {
      sideMismatches.push({
        expected: exp.side,
        actual: actSide,
        text: exp.text.slice(0, 30),
      });
    }
    // 誰引用誰：只在 label 標了 quotedReplyPreviewIsFromMe 時計分
    if (typeof exp.quotedReplyPreviewIsFromMe === "boolean") {
      quoteAuthorTotal++;
      if (act.quotedReplyPreviewIsFromMe === exp.quotedReplyPreviewIsFromMe) {
        quoteAuthorCorrect++;
      }
    }
    // 引用預覽文字：只在 label 有 quotedReplyPreview 時計分（抓 dim 灰小字讀錯，如 睏睏→眯眯）
    if (typeof exp.quotedReplyPreview === "string" && exp.quotedReplyPreview.trim()) {
      quotePreviewTotal++;
      if (
        similarity(exp.quotedReplyPreview, act.quotedReplyPreview ?? "") >=
          SIMILARITY_THRESHOLD
      ) {
        quotePreviewCorrect++;
      }
    }
    // 逐字率/CER 走計分歸一（媒體歸一 + 去 emoji），量文字內容而非媒體描述風格/emoji 變體
    const expNorm = normalizeForScoring(exp.text);
    const actNorm = normalizeForScoring(act.content ?? "");
    if (expNorm === actNorm) exactTextMatches++;
    charErrors += levenshtein(expNorm, actNorm);
    charTotal += expNorm.length;
  }

  const alignedExpected = new Set(pairs.map(([e]) => e));
  const alignedActual = new Set(pairs.map(([, a]) => a));

  // 多出來的 actual 列拆桶：引用預覽洩漏（鬼訊息）／活動卡碎片／真幻覺
  const previewTexts = expected
    .map((e) => e.quotedReplyPreview)
    .filter((p): p is string => typeof p === "string" && p.trim().length > 0);
  const hallucinated: { side: string; text: string }[] = [];
  const quotedPreviewLeaks: { side: string; text: string }[] = [];
  const activityCardNoise: { side: string; text: string }[] = [];
  actual.forEach((m, i) => {
    if (alignedActual.has(i)) return;
    const content = m.content ?? "";
    const entry = { side: m.side ?? "?", text: content.slice(0, 40) };
    if (previewTexts.some((p) => similarity(p, content) >= SIMILARITY_THRESHOLD)) {
      quotedPreviewLeaks.push(entry);
    } else if (isActivityCardNoise(content)) {
      activityCardNoise.push(entry);
    } else {
      hallucinated.push(entry);
    }
  });

  return {
    ...base,
    expectedCount: expected.length,
    actualCount: actual.length,
    alignedCount: pairs.length,
    sideCorrect,
    unknownSides,
    exactTextMatches,
    charErrors,
    charTotal,
    missed: expected
      .filter((_, i) => !alignedExpected.has(i))
      .map((mes) => ({ side: mes.side, text: mes.text.slice(0, 40) })),
    hallucinated,
    quotedPreviewLeaks,
    activityCardNoise,
    sideMismatches,
    classificationMatch: rec.classification === label.classification,
    importPolicyMatch: rec.importPolicy === label.importPolicy,
    uncertainSideCount: rec.uncertainSideCount,
    sideConfidence: rec.sideConfidence,
    telemetry: rec.normalizationTelemetry,
    quoteAuthorCorrect,
    quoteAuthorTotal,
    quotePreviewCorrect,
    quotePreviewTotal,
    phase1: scorePhase1(label, body.phase1Vision as Phase1Vision | undefined),
  };
}

// ---------- 彙總 ----------

export function aggregate(results: UnitResult[]) {
  const scored = results.filter((r) => r.alignedCount !== undefined);
  const sum = (f: (r: UnitResult) => number) =>
    scored.reduce((acc, r) => acc + f(r), 0);
  const aligned = sum((r) => r.alignedCount!);
  const expected = sum((r) => r.expectedCount!);
  const actual = sum((r) => r.actualCount!);
  return {
    units: results.length,
    unitsScored: scored.length,
    unitsErrored: results.filter((r) => r.error).length,
    unitsRejected: results.filter((r) => r.rejected).length,
    sideAccuracy: aligned ? sum((r) => r.sideCorrect!) / aligned : null,
    messageRecall: expected ? aligned / expected : null,
    messagePrecision: actual ? aligned / actual : null,
    finalUnknownRate: aligned ? sum((r) => r.unknownSides!) / aligned : null,
    exactTextRate: aligned ? sum((r) => r.exactTextMatches!) / aligned : null,
    cer: sum((r) => r.charTotal!) > 0
      ? sum((r) => r.charErrors!) / sum((r) => r.charTotal!)
      : null,
    classificationMatchRate: scored.length
      ? scored.filter((r) => r.classificationMatch).length / scored.length
      : null,
    quoteAuthorAccuracy: sum((r) => r.quoteAuthorTotal ?? 0) > 0
      ? sum((r) => r.quoteAuthorCorrect ?? 0) / sum((r) => r.quoteAuthorTotal ?? 0)
      : null,
    quoteAuthorTotal: sum((r) => r.quoteAuthorTotal ?? 0),
    quotePreviewAccuracy: sum((r) => r.quotePreviewTotal ?? 0) > 0
      ? sum((r) => r.quotePreviewCorrect ?? 0) /
        sum((r) => r.quotePreviewTotal ?? 0)
      : null,
    quotePreviewTotal: sum((r) => r.quotePreviewTotal ?? 0),
    // 引用預覽洩漏（③ 鬼訊息）與活動卡碎片總數：真實污染 analyze-chat 的列，獨立追蹤
    quotedPreviewLeakTotal: sum((r) => r.quotedPreviewLeaks?.length ?? 0),
    activityCardNoiseTotal: sum((r) => r.activityCardNoise?.length ?? 0),
    totalRepairAdjustments: sum((r) =>
      Object.entries(r.telemetry ?? {})
        .filter(([k]) => k.endsWith("AdjustedCount"))
        .reduce((a, [, v]) => a + v, 0)
    ),
  };
}

// 第③軌 Phase1 彙總：fill-only vs position-only 對打 + 名字召回 + evidence 分佈 + Wilson LB。
export function aggregatePhase1(results: UnitResult[]) {
  const withP1 = results.filter((r) => r.phase1);
  if (!withP1.length) return null;
  const sum = (f: (p: Phase1UnitResult) => number) =>
    withP1.reduce((acc, r) => acc + f(r.phase1!), 0);
  const fillKnown = sum((p) => p.fillKnown);
  const fillCorrect = sum((p) => p.fillCorrect);
  const posKnown = sum((p) => p.posKnown);
  const posCorrect = sum((p) => p.posCorrect);
  const nameExpected = sum((p) => p.quotedNameExpected);
  const nameRecalled = sum((p) => p.quotedNameRecalled);
  const fillOnlyAccuracy = fillKnown ? fillCorrect / fillKnown : null;
  const positionOnlyAccuracy = posKnown ? posCorrect / posKnown : null;
  const evidenceDist: Record<string, number> = {};
  for (const r of withP1) {
    const e = r.phase1!.myBubbleColorEvidence ?? "null";
    evidenceDist[e] = (evidenceDist[e] ?? 0) + 1;
  }
  return {
    units: withP1.length,
    alignedRows: sum((p) => p.alignedRows),
    fillKnown,
    fillCorrect,
    posKnown,
    posCorrect,
    fillOnlyAccuracy,
    positionOnlyAccuracy,
    deltaPp: (fillOnlyAccuracy !== null && positionOnlyAccuracy !== null)
      ? (fillOnlyAccuracy - positionOnlyAccuracy) * 100
      : null,
    fillWilsonLowerBound: wilsonLowerBound(fillCorrect, fillKnown),
    quotedNameRecall: nameExpected ? nameRecalled / nameExpected : null,
    quotedNameExpected: nameExpected,
    evidenceDist,
  };
}

function pct(v: number | null): string {
  return v === null ? "—" : `${(v * 100).toFixed(1)}%`;
}

// ---------- 主流程 ----------

function parseArgs(args: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--")) out[args[i].slice(2)] = args[i + 1] ?? "";
  }
  return out;
}

async function main() {
  const args = parseArgs(Deno.args);
  const scriptDir = new URL(".", import.meta.url).pathname;
  const endpoint = args.endpoint ?? DEFAULT_ENDPOINT;
  const dumpRawDir = args["dump-raw"];
  const gitSha = Deno.env.get("OCR_BENCH_GIT_SHA") ?? null;
  if (dumpRawDir) await Deno.mkdir(dumpRawDir, { recursive: true });
  const imagesDir = Deno.env.get("OCR_GOLDEN_IMAGES_DIR") ?? DEFAULT_IMAGES_DIR;
  const token = Deno.env.get("OCR_GOLDEN_TOKEN");
  const anonKey = Deno.env.get("OCR_GOLDEN_ANON_KEY");
  const isLocal = endpoint.includes("localhost") || endpoint.includes("127.0.0.1");

  if (!token && !isLocal) {
    console.error(
      "缺 OCR_GOLDEN_TOKEN（prod 模式需要使用者 JWT）。local 模式請用 --endpoint http://localhost:54321/functions/v1/analyze-chat",
    );
    Deno.exit(1);
  }

  const manifest: { units: ManifestUnit[] } = JSON.parse(
    await Deno.readTextFile(`${scriptDir}manifest.json`),
  );
  let units = manifest.units;
  if (args.only) units = units.filter((u) => u.id === args.only);
  if (args.scenarios) {
    const want = args.scenarios.split(",").map((s) => s.trim()).filter(Boolean);
    units = units.filter((u) => u.scenarios.some((s) => want.includes(s)));
  }
  if (!units.length) {
    console.error("manifest 無符合的 unit");
    Deno.exit(1);
  }

  const resolveImage = (unit: ManifestUnit, file: string): string => {
    if (unit.source === "synthetic") return `${scriptDir}synthetic/${file}`;
    return `${imagesDir}/${file}`;
  };

  console.log(`端點: ${endpoint}`);
  console.log(`單元數: ${units.length}\n`);

  const results: UnitResult[] = [];
  for (const unit of units) {
    const labelPath = `${scriptDir}labels/${unit.label}`;
    let label: GoldenLabel;
    try {
      label = JSON.parse(await Deno.readTextFile(labelPath));
    } catch {
      console.log(`⏭  ${unit.id}: label 缺檔（${unit.label}），跳過`);
      continue;
    }
    const paths = unit.images.map((f) => resolveImage(unit, f));
    try {
      await Promise.all(paths.map((p) => Deno.stat(p)));
    } catch {
      console.log(`⏭  ${unit.id}: 圖檔缺席（真實圖需 OCR_GOLDEN_IMAGES_DIR），跳過`);
      continue;
    }
    console.log(`▶ ${unit.id}（${unit.images.length} 張, ${unit.scenarios.join("/")}）…`);
    const { status, body, latencyMs } = await callRecognizeOnly(
      endpoint,
      token,
      anonKey,
      paths,
    );
    const r = scoreUnit(unit, label, status, body, latencyMs);
    results.push(r);
    if (dumpRawDir) {
      // 逐訊息原始 vision/parser 輸出（含 outerColumn/side），坐實鎖死推論用。scoring-neutral。
      await Deno.writeTextFile(
        `${dumpRawDir}/${unit.id}.raw.json`,
        JSON.stringify({ unit: unit.id, gitSha, httpStatus: status, latencyMs, body }, null, 2),
      );
    }
    if (r.error) {
      console.log(`  ✗ ${r.error}`);
    } else if (r.rejected) {
      console.log(`  ⛔ reject gate（${r.importPolicyMatch ? "符合預期" : "預期外！"}）`);
    } else {
      console.log(
        `  ✓ side ${r.sideCorrect}/${r.alignedCount} · 對齊 ${r.alignedCount}/${r.expectedCount} · unknown ${r.unknownSides} · ${latencyMs}ms`,
      );
    }
  }

  // 彙總：整體 / 依 source / 依 scenario
  const overall = aggregate(results);
  const bySource: Record<string, ReturnType<typeof aggregate>> = {};
  for (const src of [...new Set(results.map((r) => r.source))]) {
    bySource[src] = aggregate(results.filter((r) => r.source === src));
  }
  const byScenario: Record<string, ReturnType<typeof aggregate>> = {};
  for (const sc of [...new Set(results.flatMap((r) => r.scenarios))]) {
    byScenario[sc] = aggregate(results.filter((r) => r.scenarios.includes(sc)));
  }

  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
  const outDir = args.out ?? `${scriptDir}results`;
  await Deno.mkdir(outDir, { recursive: true });
  const outPath = `${outDir}/${stamp}${isLocal ? "-local" : "-prod"}.json`;
  await Deno.writeTextFile(
    outPath,
    JSON.stringify({ endpoint, gitSha, timestamp: stamp, overall, bySource, byScenario, results }, null, 2),
  );

  console.log(`\n## 彙總（主指標 = real）\n`);
  console.log(
    `| 分層 | side acc | recall | precision | unknown | 逐字率 | CER | 引用誰(n) | 引用文(n) |`,
  );
  console.log(`|---|---|---|---|---|---|---|---|---|`);
  const row = (name: string, a: ReturnType<typeof aggregate>) =>
    console.log(
      `| ${name} | ${pct(a.sideAccuracy)} | ${pct(a.messageRecall)} | ${pct(a.messagePrecision)} | ${pct(a.finalUnknownRate)} | ${pct(a.exactTextRate)} | ${pct(a.cer)} | ${pct(a.quoteAuthorAccuracy)}(${a.quoteAuthorTotal}) | ${pct(a.quotePreviewAccuracy)}(${a.quotePreviewTotal}) |`,
    );
  row("整體", overall);
  for (const [k, v] of Object.entries(bySource)) row(`source:${k}`, v);
  for (const [k, v] of Object.entries(byScenario)) row(`scenario:${k}`, v);
  // 真實污染 analyze-chat 的多出列（不計入 precision 抹除，獨立追蹤，可逐單元下鑽）
  console.log(
    `\n引用預覽洩漏（鬼訊息）總數: ${overall.quotedPreviewLeakTotal} · 活動卡碎片雜訊總數: ${overall.activityCardNoiseTotal}`,
  );

  // ── 第③軌 Phase 1 量測閘報表（server 旗標開時才有 phase1）──────────────
  const darkResults = results.filter((r) => r.scenarios.includes("dark_mode"));
  const p1Dark = aggregatePhase1(darkResults);
  if (p1Dark) {
    console.log(`\n## 第③軌 Phase 1 量測（暗色 gated subset，純觀測）\n`);
    console.log(
      `對齊列 ${p1Dark.alignedRows} · fill 可判 ${p1Dark.fillKnown} · pos 可判 ${p1Dark.posKnown}`,
    );
    console.log(
      `| 訊號 | side accuracy | 判對/可判 |`,
    );
    console.log(`|---|---|---|`);
    console.log(
      `| fill-only | ${pct(p1Dark.fillOnlyAccuracy)} | ${p1Dark.fillCorrect}/${p1Dark.fillKnown} |`,
    );
    console.log(
      `| position-only（模型自報 side） | ${pct(p1Dark.positionOnlyAccuracy)} | ${p1Dark.posCorrect}/${p1Dark.posKnown} |`,
    );
    console.log(
      `\nΔ(fill − position) = ${p1Dark.deltaPp === null ? "—" : p1Dark.deltaPp.toFixed(1) + "pp"} · fill-only Wilson 95% LB = ${pct(p1Dark.fillWilsonLowerBound)}`,
    );
    console.log(
      `名字（quotedName）召回 = ${pct(p1Dark.quotedNameRecall)}（ground truth ${p1Dark.quotedNameExpected} 個）· evidence 分佈 = ${JSON.stringify(p1Dark.evidenceDist)}`,
    );

    // 三層 hard gate 自動判定（設計：fill≥95% 且 +10pp / Wilson LB≥90% / anchor 改善＋零回退）
    const layer1 = p1Dark.fillOnlyAccuracy !== null &&
      p1Dark.fillOnlyAccuracy >= 0.95 &&
      p1Dark.deltaPp !== null && p1Dark.deltaPp >= 10;
    const layer2 = p1Dark.fillWilsonLowerBound !== null &&
      p1Dark.fillWilsonLowerBound >= 0.90;
    console.log(`\n### Phase 1 Hard Gate`);
    console.log(
      `- Layer 1（fill-only ≥95% 且比 position +10pp）: ${layer1 ? "✅ PASS" : "❌ FAIL"}`,
    );
    console.log(
      `- Layer 2（fill-only Wilson LB ≥90%）: ${layer2 ? "✅ PASS" : "❌ FAIL"}`,
    );
    console.log(
      `- Layer 3（anchor 改善＋淺色/交友 app 零回退）: 需與 baseline run 比對，見下方 anchor/淺色 side acc 與 compare_runs.sh`,
    );

    // anchor：S__5480452 的 fill vs position
    const anchor = darkResults.find((r) => r.id === "S__5480452");
    if (anchor?.phase1) {
      const a = anchor.phase1;
      console.log(
        `\nAnchor S__5480452: fill ${a.fillCorrect}/${a.fillKnown}・pos ${a.posCorrect}/${a.posKnown}・myColor=${a.myBubbleColor}(${a.myBubbleColorEvidence})`,
      );
    }

    // 逐列 audit dump（含 senderNameRaw / quotedName，供 Eric 目檢「不混欄」）
    console.log(`\n### 暗色逐列 audit（gt|raw|fill ・色 ・senderName ・quotedName）`);
    for (const r of darkResults) {
      if (!r.phase1) continue;
      console.log(`▶ ${r.id}  myColor=${r.phase1.myBubbleColor}(${r.phase1.myBubbleColorEvidence})`);
      for (const row of r.phase1.rows) {
        const flagFill = row.fillSide !== "unknown" && row.fillSide !== row.gtSide ? "✗fill" : "";
        const flagPos = row.rawSide !== row.gtSide ? "✗pos" : "";
        console.log(
          `   ${row.gtSide.padEnd(5)}|${(row.rawSide ?? "?").padEnd(5)}|${row.fillSide.padEnd(7)} ` +
          `${(row.bubbleFillColor ?? "-").padEnd(10)} name=${row.senderNameRaw ?? "-"} quoted=${row.visionQuotedName ?? "-"} ` +
          `${flagFill}${flagPos}  「${row.text}」`,
        );
      }
    }
  }

  console.log(`\n結果已寫入 ${outPath}`);
}

if (import.meta.main) {
  await main();
}
