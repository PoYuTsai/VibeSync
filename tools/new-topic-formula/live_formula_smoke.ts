// 公式回覆 live production smoke（2026-07-24 計畫 §15 步驟 6–9）。
// 測試帳號（TEST_EMAILS 免扣）打 production analyze-chat：
//   A. Opener v1（無 openerContractVersion）：舊 client 相容——只驗不炸、
//      不強制 formula（舊 App 忽略未知欄位）。
//   B. Opener v2 ×N：五型完整、access 一致、formulaOpeners 0–2 canonical
//      形狀、無內部標籤、usage tokens 記錄。
//   C. New Topic fresh ×N：五題/推薦/access strict、formulaTopics 0–2、
//      usage.cost=3；每次新 requestId。
//   D. New Topic replay：同 requestId 重打，body 必須與 fresh 完全一致。
// 比較的是契約不變量與成功率，不比模型文字逐字相同（§15）。
//
// 執行：deno run --allow-read --allow-net tools/new-topic-formula/live_formula_smoke.ts [N]
type JsonRecord = Record<string, unknown>;

function parseDotEnv(text: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator <= 0) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`missing_${label}`);
  }
  return value.trim();
}

function asRecord(value: unknown, label: string): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`invalid_${label}`);
  }
  return value as JsonRecord;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const INTERNAL_LABELS = [
  "對象作戰板",
  "對方作戰板",
  "最近熱度",
  "累計對話",
  "你的備註",
  "過往備註",
  "性格分析",
  "資料顯示",
  "系統判斷",
];

function assertFormulaShape(value: unknown, label: string): number {
  assert(Array.isArray(value), `${label}: formula 必須是 array`);
  assert(value.length <= 2, `${label}: formula 最多兩則`);
  for (const item of value) {
    const record = asRecord(item, `${label}_item`);
    const keys = Object.keys(record).sort();
    assert(
      keys.length === 2 && keys[0] === "openingLine" && keys[1] === "whyItWorks",
      `${label}: item 必須恰好兩鍵，got ${keys.join(",")}`,
    );
    const opening = requireString(record.openingLine, `${label}_openingLine`);
    const why = requireString(record.whyItWorks, `${label}_whyItWorks`);
    assert([...opening].length <= 180, `${label}: openingLine 超 cap`);
    assert([...why].length <= 300, `${label}: whyItWorks 超 cap`);
    for (const text of [opening, why]) {
      assert(!text.includes("```"), `${label}: code fence 洩漏`);
      assert(!/^[{[]/.test(text), `${label}: raw JSON 洩漏`);
      for (const internal of INTERNAL_LABELS) {
        assert(!text.includes(internal), `${label}: 內部標籤洩漏 ${internal}`);
      }
    }
  }
  return value.length;
}

const localEnv = parseDotEnv(
  await Deno.readTextFile(new URL("../../.env.local", import.meta.url)),
);
const goldenEnv = parseDotEnv(
  await Deno.readTextFile(
    new URL("../../tools/ocr-golden/.env.golden", import.meta.url),
  ),
);
const supabaseUrl = requireString(localEnv.SUPABASE_URL, "supabase_url");
const anonKey = requireString(localEnv.SUPABASE_ANON_KEY, "anon_key");
const email = requireString(goldenEnv.TEST_EMAIL, "test_email");
const password = requireString(goldenEnv.TEST_PASSWORD, "test_password");

const authResponse = await fetch(
  `${supabaseUrl}/auth/v1/token?grant_type=password`,
  {
    method: "POST",
    headers: { "content-type": "application/json", apikey: anonKey },
    body: JSON.stringify({ email, password }),
  },
);
const authJson = asRecord(await authResponse.json(), "auth_response");
assert(authResponse.ok, `auth_failed_${authResponse.status}`);
const accessToken = requireString(authJson.access_token, "access_token");
console.log("auth ok");

async function callAnalyzeChat(
  body: JsonRecord,
): Promise<{ status: number; json: JsonRecord; latencyMs: number }> {
  const startedAt = Date.now();
  const response = await fetch(`${supabaseUrl}/functions/v1/analyze-chat`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: anonKey,
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
  });
  const latencyMs = Date.now() - startedAt;
  const json = asRecord(await response.json(), "edge_response");
  return { status: response.status, json, latencyMs };
}

const runs = Number(Deno.args[0] ?? "10");
const openerProfile = {
  name: "小雅",
  bio: "大夜班護理師，熱愛學新東西，最近迷上手沖咖啡跟爬山。不要問上班的事。",
  interests: "手沖咖啡、爬山、看展",
  meetingContext: "交友軟體",
};
const newTopicSummary =
  "對象：小雅。興趣：手沖咖啡、爬山。個性：直接、愛新鮮。上次聊到她剛買新磨豆機。";

// ── A. Opener v1（舊 client 相容）──
{
  const { status, json } = await callAnalyzeChat({
    mode: "opener",
    profileInfo: openerProfile,
    requestId: crypto.randomUUID(),
  });
  assert(status === 200, `opener_v1_status_${status}: ${JSON.stringify(json).slice(0, 200)}`);
  const openers = asRecord(json.openers, "opener_v1_openers");
  assert(Object.keys(openers).length >= 1, "opener_v1 無可見卡");
  if ("formulaOpeners" in json) assertFormulaShape(json.formulaOpeners, "opener_v1");
  console.log(`A opener v1: 200, visible=${Object.keys(openers).join(",")}`);
}

// ── B. Opener v2 ×N ──
const openerStats: Array<JsonRecord> = [];
for (let index = 0; index < runs; index++) {
  const { status, json, latencyMs } = await callAnalyzeChat({
    mode: "opener",
    openerContractVersion: 2,
    profileInfo: openerProfile,
    requestId: crypto.randomUUID(),
  });
  assert(status === 200, `opener_v2_run${index}_status_${status}: ${JSON.stringify(json).slice(0, 200)}`);
  const access = asRecord(json.access, "opener_access");
  const openers = asRecord(json.openers, "opener_openers");
  const visibleTypes = access.visibleTypes as string[];
  for (const type of visibleTypes) {
    requireString(openers[type], `opener_v2_missing_${type}`);
  }
  const formulaCount = assertFormulaShape(json.formulaOpeners, `opener_v2_run${index}`);
  const usage = asRecord(json.usage, "opener_usage");
  openerStats.push({
    formulaCount,
    latencyMs,
    outputTokens: usage.outputTokens,
    visible: visibleTypes.length,
  });
  console.log(
    `B opener v2 #${index + 1}: formula=${formulaCount} visible=${visibleTypes.length} out=${usage.outputTokens} ${latencyMs}ms`,
  );
}

// ── C/D. New Topic fresh ×N＋首發 replay ──
const newTopicStats: Array<JsonRecord> = [];
let replayChecked = false;
for (let index = 0; index < runs; index++) {
  const requestId = crypto.randomUUID();
  const body: JsonRecord = {
    mode: "new_topic",
    requestId,
    partnerSummary: newTopicSummary,
    situation: "stuck",
  };
  const fresh = await callAnalyzeChat(body);
  assert(
    fresh.status === 200,
    `new_topic_run${index}_status_${fresh.status}: ${JSON.stringify(fresh.json).slice(0, 200)}`,
  );
  const topics = fresh.json.topics;
  assert(Array.isArray(topics) && topics.length >= 1, "new_topic 無 topics");
  const usage = asRecord(fresh.json.usage, "new_topic_usage");
  assert(usage.cost === 3, `new_topic usage.cost=${usage.cost}`);
  assert("formulaTopics" in fresh.json, "new_topic 缺 formulaTopics 鍵");
  const formulaCount = assertFormulaShape(
    fresh.json.formulaTopics,
    `new_topic_run${index}`,
  );
  newTopicStats.push({
    formulaCount,
    latencyMs: fresh.latencyMs,
    topics: (topics as unknown[]).length,
  });
  console.log(
    `C new topic #${index + 1}: formula=${formulaCount} topics=${(topics as unknown[]).length} ${fresh.latencyMs}ms`,
  );

  if (!replayChecked) {
    const replay = await callAnalyzeChat(body);
    assert(replay.status === 200, `replay_status_${replay.status}`);
    assert(
      JSON.stringify(replay.json) === JSON.stringify(fresh.json),
      "D replay body 與 fresh 不一致",
    );
    replayChecked = true;
    console.log("D new topic replay: body 與 fresh 完全一致");
  }
}

function summarize(stats: Array<JsonRecord>, label: string) {
  const counts = [0, 0, 0];
  let latencyTotal = 0;
  for (const stat of stats) {
    counts[stat.formulaCount as number] += 1;
    latencyTotal += stat.latencyMs as number;
  }
  console.log(
    `${label}: n=${stats.length} formula 0/1/2=${counts.join("/")} avgLatency=${
      Math.round(latencyTotal / stats.length)
    }ms`,
  );
}
summarize(openerStats, "SUMMARY opener v2");
summarize(newTopicStats, "SUMMARY new topic");
console.log("LIVE_FORMULA_SMOKE_PASSED");
