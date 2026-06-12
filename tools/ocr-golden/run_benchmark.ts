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
  sideMismatches?: { expected: string; actual: string; text: string }[];
  classificationMatch?: boolean;
  importPolicyMatch?: boolean;
  uncertainSideCount?: number;
  sideConfidence?: string;
  telemetry?: Record<string, number>;
}

// ---------- 文字比對 ----------

export function normalizeText(s: string): string {
  return s.normalize("NFKC").replace(/\s+/g, "").toLowerCase();
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
  const na = normalizeText(a);
  const nb = normalizeText(b);
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
    const expNorm = exp.text.normalize("NFKC").trim();
    const actNorm = (act.content ?? "").normalize("NFKC").trim();
    if (expNorm === actNorm) exactTextMatches++;
    charErrors += levenshtein(expNorm, actNorm);
    charTotal += expNorm.length;
  }

  const alignedExpected = new Set(pairs.map(([e]) => e));
  const alignedActual = new Set(pairs.map(([, a]) => a));

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
    hallucinated: actual
      .filter((_, i) => !alignedActual.has(i))
      .map((mes) => ({
        side: mes.side ?? "?",
        text: (mes.content ?? "").slice(0, 40),
      })),
    sideMismatches,
    classificationMatch: rec.classification === label.classification,
    importPolicyMatch: rec.importPolicy === label.importPolicy,
    uncertainSideCount: rec.uncertainSideCount,
    sideConfidence: rec.sideConfidence,
    telemetry: rec.normalizationTelemetry,
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
    totalRepairAdjustments: sum((r) =>
      Object.entries(r.telemetry ?? {})
        .filter(([k]) => k.endsWith("AdjustedCount"))
        .reduce((a, [, v]) => a + v, 0)
    ),
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
    JSON.stringify({ endpoint, timestamp: stamp, overall, bySource, byScenario, results }, null, 2),
  );

  console.log(`\n## 彙總（主指標 = real）\n`);
  console.log(`| 分層 | side acc | recall | precision | unknown | 逐字率 | CER |`);
  console.log(`|---|---|---|---|---|---|---|`);
  const row = (name: string, a: ReturnType<typeof aggregate>) =>
    console.log(
      `| ${name} | ${pct(a.sideAccuracy)} | ${pct(a.messageRecall)} | ${pct(a.messagePrecision)} | ${pct(a.finalUnknownRate)} | ${pct(a.exactTextRate)} | ${pct(a.cer)} |`,
    );
  row("整體", overall);
  for (const [k, v] of Object.entries(bySource)) row(`source:${k}`, v);
  for (const [k, v] of Object.entries(byScenario)) row(`scenario:${k}`, v);
  console.log(`\n結果已寫入 ${outPath}`);
}

if (import.meta.main) {
  await main();
}
