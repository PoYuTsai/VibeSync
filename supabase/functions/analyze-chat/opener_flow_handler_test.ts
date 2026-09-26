// 兩段式 handler 端到端測試：正式 handler＋正式 RPC SQL（PGlite 真 Postgres）
// ＋正式原料整理／投影／結算；只有模型邊界是替身（附件 §五：不得 override
// 核心方法直接塞成功狀態）。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { parseJsonObjectFromText } from "./json_text.ts";
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handleOpenerAnalyzeRequest,
  handleOpenerGenerateRequest,
  type OpenerFlowHandlerDeps,
  type OpenerFlowModelRequest,
} from "./opener_flow_handler.ts";
import { OPENER_ANALYZE_PROMPT, OPENER_FLOW_REPAIR_PROMPT, OPENER_GENERATE_PROMPT, OPENER_GENERATE_REPAIR_PROMPT } from "./opener_flow_prompt.ts";
import { OPENER_PLAN_PROMPT } from "./opener_plan.ts";
import { buildOpenerWritePrompt } from "./opener_write.ts";
import { computeOpenerGenerationInputHash, parseOpenerGenerateRequest } from "./opener_stage.ts";
import { readPreviousPromptReplay } from "./opener_session.ts";

const MIGRATIONS = [
  "20260702120000_increment_usage_atomic_quota.sql",
  "20260703170000_model_call_rate_limit.sql",
  "20260917120000_opener_two_stage_sessions.sql",
];
const migrationSql = await Promise.all(
  MIGRATIONS.map((name) => Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url))),
);

const USER_ID = "11111111-2222-3333-4444-555555555555";
const OTHER_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const REQ_1 = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f01";
const GEN_1 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e01";
const GEN_2 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e02";
const GEN_3 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e03";
const GEN_4 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e04";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
    CREATE TABLE public.users (id UUID PRIMARY KEY, total_analyses INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE public.subscriptions (user_id UUID PRIMARY KEY, monthly_messages_used INTEGER NOT NULL DEFAULT 0, daily_messages_used INTEGER NOT NULL DEFAULT 0);
    CREATE FUNCTION public.increment_usage(p_user_id UUID, p_messages INTEGER DEFAULT 1) RETURNS void LANGUAGE sql AS $$ SELECT 1; $$;
  `);
  await db.exec("SET app.allow_missing_pg_cron = 'pglite-contract-test'");
  for (const sql of migrationSql) await db.exec(sql);
  for (const id of [USER_ID, OTHER_USER_ID]) {
    await db.query(`INSERT INTO auth.users(id) VALUES ($1)`, [id]);
    await db.query(`INSERT INTO public.users(id) VALUES ($1)`, [id]);
    await db.query(`INSERT INTO public.subscriptions(user_id) VALUES ($1)`, [id]);
  }
  return db;
}

/** supabase.rpc 替身：把 named params 轉成真 SQL 呼叫，錯誤照 PostgREST 形狀回。 */
function supabaseFor(db: PGlite) {
  return {
    from(table: string) {
      if (!["opener_generation_runs", "opener_sessions"].includes(table)) throw new Error("unexpected read table");
      const filters: Array<[string, unknown]> = [];
      let columns = "*";
      const query = {
        select(value: string) { columns = value; return query; },
        eq(key: string, value: unknown) { filters.push([key, value]); return query; },
        async maybeSingle() {
          if (!/^[a-z_, ]+$/.test(columns) || filters.some(([key]) => !/^[a-z_]+$/.test(key))) throw new Error("unsafe query");
          const rows = await db.query(`SELECT ${columns} FROM public.${table} WHERE ${filters.map(([key], i) => `${key} = $${i + 1}`).join(" AND ")}`, filters.map(([, value]) => value));
          return { data: rows.rows[0] ? JSON.parse(JSON.stringify(rows.rows[0])) : null, error: null };
        },
      };
      return query;
    },
    async rpc(fn: string, params: Record<string, unknown>) {
      const keys = Object.keys(params);
      const args = keys.map((key, i) => {
        const value = params[key];
        const cast = typeof value === "object" && value !== null
          ? "::jsonb"
          : typeof value === "number"
          ? "::integer"
          : typeof value === "boolean"
          ? "::boolean"
          : typeof value === "string" && UUID_RE.test(value)
          ? "::uuid"
          : "::text";
        return `${key} => $${i + 1}${cast}`;
      });
      const values = keys.map((key) => {
        const value = params[key];
        return typeof value === "object" && value !== null ? JSON.stringify(value) : value;
      });
      try {
        const rows = await db.query<{ out: unknown }>(`SELECT public.${fn}(${args.join(", ")}) AS out`, values);
        return { data: rows.rows[0]?.out ?? null, error: null };
      } catch (error) {
        const e = error as { message?: string; code?: string };
        return { data: null, error: { message: e.message ?? String(error), code: e.code ?? "P0001" } };
      }
    },
  };
}

const ANALYSIS_JSON = {
  wrongSurface: null,
  profileDigest: "自介：有養一隻狗，假日會去河堤",
  approach: { mode: "anchor_hooks", summary: "可以從她的狗開，但先確認你想聊哪個部分", avoid: [] },
  cues: [
    { id: "cue_1", label: "養狗", source: "profile_text", evidence: { field: "bio", quote: "有養一隻狗" } },
    { id: "cue_2", label: "河堤", source: "profile_text", evidence: { field: "bio", quote: "假日會去河堤" } },
  ],
  question: {
    affects: "sender_fact",
    text: "你跟養狗這件事比較接近哪種？",
    options: [
      { id: "option_1", label: "我自己有養", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我有養狗" },
      { id: "option_2", label: "沒養，但有興趣", meaning: "curious_without_experience", cueId: "cue_1" },
      { id: "option_3", label: "其實想聊別的", meaning: "change_direction" },
    ],
  },
};

function useReading(quote: string, materialId = "material_2") {
  return { materialId, subject: "unknown", kind: "raw_sentence", certainty: "stated", quote, usage: [{ quote, action: "use" }] };
}

const GENERATE_JSON = {
  materialReading: [{ materialId: "material_1", subject: "sender", kind: "interest", certainty: "stated", quote: "有興趣" }, useReading("沒養過，只想知道牠散步會不會自己選路")],
  openers: {
    extend: "牠散步會自己選路嗎",
    resonate: "養這種狗的人假日應該都在外面",
    tease: "妳家狗看起來比妳會安排行程",
    humor: "妳家狗是導航派還是隨機派",
    coldRead: "妳應該是被牠帶著走的那種主人",
  },
  cardReasons: {
    extend: "直接問你想知道的事，也沒有寫成你養過狗",
    resonate: "站在她的處境說話",
    tease: "輕輕戳她的狗",
    humor: "把你好奇的散步習慣變成可愛的問題",
    coldRead: "可被反駁的輕觀察",
  },
  rankedPicks: ["extend", "humor", "tease", "coldRead", "resonate"],
  materialUse: {
    references: [
      { style: "extend", materialId: "material_1", outputSpan: "散步會自己選路" },
      { style: "humor", materialId: "material_1", outputSpan: "導航派" },
    ],
    displayNotes: { extend: "這句接的是你想知道的散步習慣" },
  },
  stretchLevels: { extend: "within", resonate: "within", tease: "within", humor: "within", coldRead: "within" },
  pioneerPlan: { ifCold: "先停一下", handoff: "她回了就貼回分析" },
  profileAnalysis: { positiveHooks: ["養狗"], openingStrategy: "先接狗" },
};

interface ScriptedModel {
  calls: OpenerFlowModelRequest[];
  analyze?: unknown;
  generate?: unknown;
  correction?: unknown;
  repair?: unknown;
  throwOn?: "analyze" | "generate";
}

function omitReading(quote: string, reason = "unsuitable_opener") {
  return { ...useReading(quote, "material_1"), usage: [{ quote, action: "omit", reason }] };
}

for (const [text, reason, tier] of [["腿很長", "unsuitable_opener", "free"], ["幫我算一百乘三十", "irrelevant", "essential"]]) {
  Deno.test(`新素材取捨：${reason}/${tier} 直接交付、單次生成、重播不重扣`, async () => {
    const h = await harness();
    try {
      const analysis = await analyzed(h);
      h.tier = tier;
      h.script.generate = { ...GENERATE_JSON, materialReading: [omitReading(text, reason)], materialUse: { references: [], displayNotes: {} } };
      const request = generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text });
      const response = await handleOpenerGenerateRequest(h.deps(request));
      assertEquals(response.status, 200);
      const body = await json(response);
      assertEquals((body.materialUse as Record<string, unknown>).traceStatus, "uncertain");
      assert((body.materialUse as Record<string, unknown>).handlingNote);
      assertEquals(JSON.stringify(body.openers).includes(text), false);
      assertEquals(h.script.calls.length, 2, "分析一次、生成一次，沒有前置分類或修正呼叫");
      assertEquals(await usage(h.db), { m: 3, d: 3 });
      const replay = await handleOpenerGenerateRequest(h.deps(request));
      assertEquals(replay.status, 200);
      assertEquals((await json(replay)).materialUse, body.materialUse, "新的巢狀提示可以原樣保存回放");
      assertEquals(h.script.calls.length, 2);
      assertEquals(await usage(h.db), { m: 3, d: 3 });
    } finally { await h.db.close(); }
  });
}

Deno.test("取捨契約缺漏：既有一次修復可同步略過與修句；仍缺漏不扣費", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    h.script.generate = { ...GENERATE_JSON, materialReading: [], openers: { ...GENERATE_JSON.openers, extend: "聽說妳腿很長" } };
    h.script.repair = { ...GENERATE_JSON, materialReading: [omitReading("腿很長")], materialUse: { references: [], displayNotes: {} } };
    const request = generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: "腿很長" });
    assertEquals((await handleOpenerGenerateRequest(h.deps(request))).status, 200);
    assertEquals(h.script.calls.length, 3);
    const repair = h.script.calls[2];
    assertEquals(repair.system, OPENER_GENERATE_REPAIR_PROMPT);
    assert(String(repair.messages[0].content).includes("腿很長"));
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    await passOneMinute(h.db);
    h.script.repair = { ...GENERATE_JSON, materialReading: [] };
    const before = h.script.calls.length;
    const failed = await handleOpenerGenerateRequest(h.deps({ ...request, generationId: GEN_2 }));
    assertEquals(failed.status, 502);
    assertEquals(h.script.calls.length - before, 2, "共用修復預算沒有第三次呼叫");
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "失敗不額外扣费");
  } finally { await h.db.close(); }
});

Deno.test("略過後仍帶回原文：一次內容修正保持取捨，說明與引用同步清除", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    h.script.generate = { ...GENERATE_JSON, materialReading: [omitReading("腿很長")], openers: { ...GENERATE_JSON.openers, extend: "聽說妳腿很長" }, cardReasons: { extend: "保留腿很長" }, materialUse: { references: [], displayNotes: {} } };
    h.script.correction = { ...GENERATE_JSON, materialReading: [useReading("腿很長", "material_1")], materialUse: { references: [], displayNotes: {} } };
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: "腿很長" })));
    assertEquals(response.status, 200);
    const body = await json(response);
    assertEquals(JSON.stringify(body).includes("腿很長"), false);
    assertEquals((body.materialUse as Record<string, unknown>).traceStatus, "uncertain");
    assertEquals(h.script.calls.length, 3);
    assert(String(h.script.calls[2].messages[0].content).includes("不可改為採用略過內容"));
  } finally { await h.db.close(); }
});

function invokerFor(script: ScriptedModel) {
  return (req: OpenerFlowModelRequest) => {
    script.calls.push(req);
    const userText = typeof req.messages[0]?.content === "string"
      ? req.messages[0].content
      : JSON.stringify(req.messages[0]?.content);
    let body: unknown;
    if (req.system === OPENER_ANALYZE_PROMPT) {
      if (script.throwOn === "analyze") throw new Error("provider down");
      body = script.analyze ?? ANALYSIS_JSON;
    } else if (req.system === OPENER_FLOW_REPAIR_PROMPT || req.system === OPENER_GENERATE_REPAIR_PROMPT) {
      body = script.repair ?? {};
    } else if (req.system === OPENER_GENERATE_PROMPT && userText.startsWith("以下這組開場白有可確定的錯誤")) {
      body = script.correction ?? GENERATE_JSON;
    } else {
      if (script.throwOn === "generate") throw new Error("provider down");
      body = script.generate ?? GENERATE_JSON;
    }
    const rawText = typeof body === "string" ? body : JSON.stringify(body);
    req.onChunk?.(rawText);
    return Promise.resolve({ rawText, model: "claude-sonnet-5", inputTokens: 100, outputTokens: 50 });
  };
}

interface Harness {
  db: PGlite;
  script: ScriptedModel;
  sub: { monthly_messages_used: number; daily_messages_used: number; tier: string };
  tier: string;
  env: Record<string, string>;
  deps(body: Record<string, unknown>, overrides?: Partial<OpenerFlowHandlerDeps>): OpenerFlowHandlerDeps;
}

async function harness(): Promise<Harness> {
  const db = await createDatabase();
  const script: ScriptedModel = { calls: [] };
  const sub = { monthly_messages_used: 0, daily_messages_used: 0, tier: "free" };
  const env: Record<string, string> = {};
  const h: Harness = {
    db,
    script,
    sub,
    tier: "free",
    env,
    deps(body, overrides = {}) {
      return {
        supabase: supabaseFor(db),
        userId: USER_ID,
        requestBody: body,
        responseMode: "legacy",
        requestStartedAtMs: Date.now(),
        accountIsTest: false,
        claudeApiKey: "test-key",
        refreshTierFromRevenueCat: () => Promise.resolve("not_paid" as const),
        quota: () => ({ sub, monthlyLimit: 30, dailyLimit: 10, effectiveTier: h.tier, allowedFeatures: h.tier === "free" ? ["extend", "humor", "tease"] : ["extend", "resonate", "tease", "humor", "coldRead"] }),
        invokeModel: invokerFor(script),
        env: (name) => env[name],
        ...overrides,
      };
    },
  };
  return h;
}

function analyzeBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    mode: "opener_analyze",
    openerFlowVersion: 1,
    openerContractVersion: 2,
    analysisRequestId: REQ_1,
    profileInfo: { bio: "有養一隻狗，假日會去河堤" },
    ...overrides,
  };
}

function generateBody(sessionId: string, generationId: string, contribution: Record<string, unknown>, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    mode: "opener_generate",
    openerFlowVersion: 1,
    openerContractVersion: 2,
    sessionId,
    analysisRevision: 1,
    generationId,
    userContribution: contribution,
    ...overrides,
  };
}

async function json(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

async function analyzed(h: Harness, overrides: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
  const response = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(overrides)));
  assertEquals(response.status, 200);
  return await json(response);
}

async function usage(db: PGlite, user = USER_ID) {
  const rows = await db.query<{ m: number; d: number }>(`SELECT monthly_messages_used AS m, daily_messages_used AS d FROM public.subscriptions WHERE user_id = $1`, [user]);
  return rows.rows[0];
}

/** 模擬一分鐘過去：opener 限流 3/分由兩階段共用，多步驟情境要重置分鐘窗。 */
async function passOneMinute(db: PGlite) {
  await db.query(`UPDATE public.model_call_rate_limits SET minute_window_start = now() - interval '61 seconds'`);
}

/** 有效作業數：pending／done；R1 後失敗 release 的列以 released 保留輸入身分，不算。 */
async function runCount(db: PGlite) {
  const rows = await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_generation_runs WHERE state <> 'released'`);
  return rows.rows[0].n;
}

const CURIOUS = { state: "answered", questionId: "question_1", selectedOptionId: "option_2", freeText: "沒養過，只想知道牠散步會不會自己選路" };

Deno.test("版本升級：舊 prompt 已完成結果唯讀重播；不同內容、帳號、版本或未完成不復用", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const body = generateBody(String(analysis.sessionId), GEN_1, CURIOUS);
    const first = await handleOpenerGenerateRequest(h.deps(body));
    assertEquals(first.status, 200);
    const saved = await json(first);
    const parsed = parseOpenerGenerateRequest({ rawFlowVersion: body.openerFlowVersion, rawSessionId: body.sessionId, rawAnalysisRevision: body.analysisRevision, rawGenerationId: body.generationId, rawContribution: body.userContribution });
    assert(parsed.ok);
    const oldHash = await computeOpenerGenerationInputHash({ ...parsed.request, contractVersion: 2, promptVersion: "opener-two-stage-prompt-v1" });
    await h.db.query(`UPDATE public.opener_generation_runs SET input_hash = $1 WHERE generation_id = $2`, [oldHash, GEN_1]);
    const before = h.script.calls.length;
    const replay = await handleOpenerGenerateRequest(h.deps(body));
    assertEquals(replay.status, 200);
    const result = await json(replay);
    assertEquals(result.openers, saved.openers);
    assertEquals((result.usage as Record<string, unknown>).replayed, true);
    assertEquals((result.usage as Record<string, unknown>).chargedNow, 0);
    assertEquals(h.script.calls.length, before);
    for (const change of [
      { userContribution: { ...CURIOUS, freeText: "想聊別的" } },
      { openerContractVersion: 1 }, { analysisRevision: 2 }, { sessionId: GEN_4 },
    ]) {
      assert((await handleOpenerGenerateRequest(h.deps({ ...body, ...change }))).status !== 200);
    }
    assert((await handleOpenerGenerateRequest(h.deps(body, { userId: OTHER_USER_ID }))).status !== 200);
    const failedRead = { ...supabaseFor(h.db), from() { throw new Error("read unavailable"); } };
    assert((await handleOpenerGenerateRequest(h.deps(body, { supabase: failedRead }))).status !== 200);
    // A completed, otherwise valid row can expire between claim and the read.
    await h.db.query(`UPDATE public.opener_sessions SET expires_at = now() - interval '1 second' WHERE session_id = $1`, [body.sessionId]);
    assertEquals(await readPreviousPromptReplay({ supabase: supabaseFor(h.db), userId: USER_ID, ...parsed.request, contractVersion: 2 }), null);
    await h.db.query(`UPDATE public.opener_sessions SET expires_at = now() + interval '1 hour' WHERE session_id = $1`, [body.sessionId]);
    const unknownHash = await computeOpenerGenerationInputHash({ ...parsed.request, contractVersion: 2, promptVersion: "unknown-version" });
    await h.db.query(`UPDATE public.opener_generation_runs SET input_hash = $1 WHERE generation_id = $2`, [unknownHash, GEN_1]);
    assert((await handleOpenerGenerateRequest(h.deps(body))).status !== 200);
    await h.db.query(`UPDATE public.opener_generation_runs SET input_hash = $1, result_json = '{}'::jsonb WHERE generation_id = $2`, [oldHash, GEN_1]);
    assert((await handleOpenerGenerateRequest(h.deps(body))).status !== 200);
    for (const state of ["pending", "released"]) {
      await h.db.query(`UPDATE public.opener_generation_runs SET state = $1, result_json = NULL, charged_amount = 0 WHERE generation_id = $2`, [state, GEN_1]);
      assert((await handleOpenerGenerateRequest(h.deps(body))).status !== 200);
    }
    await h.db.query(`UPDATE public.opener_sessions SET expires_at = now() - interval '1 second' WHERE session_id = $1`, [body.sessionId]);
    assert((await handleOpenerGenerateRequest(h.deps(body))).status !== 200);
    assertEquals(h.script.calls.length, before, "相容分支絕不新增模型工作");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally { await h.db.close(); }
});

for (const tier of ["free", "essential"]) {
  Deno.test(`N03/${tier}：來源明確不見面，想約是之後的目標，全 use 的羽球卡直接交付；話題型補充仍不可繞過採用檢查`, async () => {
    const h = await harness();
    try {
      h.tier = tier;
      const bio = "喜歡羽球和科幻片。目前只想線上聊天，不見面、不約。";
      h.script.analyze = { ...ANALYSIS_JSON, profileDigest: bio, cues: [{ id: "cue_1", label: "羽球", source: "profile_text", evidence: { field: "bio", quote: "喜歡羽球" } }], question: null };
      const analysis = await analyzed(h, { profileInfo: { bio } });
      const text = "想約她一起打羽球";
      const safe = { ...GENERATE_JSON,
        openers: { extend: "羽球妳比較喜歡單打還是雙打", resonate: "羽球最近哪一場打得最開心", tease: "羽球最讓妳不想下場的是哪個部分", humor: "羽球場上最常發生什麼小插曲", coldRead: "羽球妳最享受哪種節奏" },
        cardReasons: { extend: "保留打球偏好，不邀約見面" },
        materialReading: [{ ...useReading(text, "material_1"), usage: [{ quote: "想約她一起", action: "omit", reason: "unsuitable_opener" }, { quote: "打羽球", action: "use" }] }],
        materialUse: { references: [], displayNotes: {} },
      };
      h.script.generate = safe;
      const good = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text })));
      assertEquals(good.status, 200);
      assert(((await json(good)).materialUse as Record<string, unknown>).handlingNote);
      assertEquals(h.script.calls.length, 2);
      await passOneMinute(h.db);
      // 2026-09-24 教練型 Opener：想約是之後的目標，這一則只開話題。全 use 也不再要求卡片帶邀約，
      // 只聊羽球的卡直接交付，不送修正。
      h.script.generate = { ...safe, materialReading: [useReading(text, "material_1")] };
      h.script.correction = safe;
      const request = generateBody(String(analysis.sessionId), GEN_2, { state: "answered", freeText: text });
      const direct = await handleOpenerGenerateRequest(h.deps(request));
      assertEquals(direct.status, 200);
      assertEquals(((await json(direct)).openers as Record<string, string>).extend, safe.openers.extend);
      assertEquals(h.script.calls.length, 3, "直接交付，沒有修正呼叫");
      assertEquals((await handleOpenerGenerateRequest(h.deps(request))).status, 200);
      assertEquals(h.script.calls.length, 3, "重播不再生成");
      assertEquals(await usage(h.db), { m: 3, d: 3 }, "同局後續生成與重播不另扣費");
      await passOneMinute(h.db);
      // 話題型補充（想問她科幻片）全 use，卡片卻只聊羽球：仍要一次修正，修不好 502。
      const topic = "想問她都看哪些科幻片";
      h.script.generate = { ...safe, materialReading: [useReading(topic, "material_1")] };
      h.script.correction = h.script.generate;
      const unresolved = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_3, { state: "answered", freeText: topic })));
      assertEquals(unresolved.status, 502, "仍宣告全 use 又沒有採用，不可繞過採用檢查");
      assertEquals((await json(unresolved)).code, "OPENER_CONTENT_CONFLICT");
      assertEquals(h.script.calls.length, 5, "修不好也只有一次修正");
      assert(String(h.script.calls.at(-1)?.messages[0].content).includes(bio), "修正必須仍看得到來源的拒絕，不只看到補充");
      assertEquals(await usage(h.db), { m: 3, d: 3 }, "失敗不另扣費");
    } finally { await h.db.close(); }
  });

  Deno.test(`N03/${tier}：話題型補充初判誤標全 use → 同一次修正可把不適用的補充收窄為 omit，交付羽球卡`, async () => {
    // 原 N03 的收窄路徑（material_unused → reconsiderSelection → 修正改 omit → 200＋handlingNote）改用話題型補充重建。
    const h = await harness();
    try {
      h.tier = tier;
      const bio = "喜歡羽球和科幻片。目前只想線上聊天，不見面、不約。";
      h.script.analyze = { ...ANALYSIS_JSON, profileDigest: bio, cues: [{ id: "cue_1", label: "羽球", source: "profile_text", evidence: { field: "bio", quote: "喜歡羽球" } }], question: null };
      const analysis = await analyzed(h, { profileInfo: { bio } });
      // 她只想線上聊，問住處不適合開場；初判卻全 use，五張只聊羽球 → material_unused。
      const text = "想問她家住哪裡";
      const badminton = { ...GENERATE_JSON,
        openers: { extend: "羽球妳比較喜歡單打還是雙打", resonate: "羽球最近哪一場打得最開心", tease: "羽球最讓妳不想下場的是哪個部分", humor: "羽球場上最常發生什麼小插曲", coldRead: "羽球妳最享受哪種節奏" },
        cardReasons: { extend: "保留打球偏好，不問住處" },
        materialUse: { references: [], displayNotes: {} },
      };
      h.script.generate = { ...badminton, materialReading: [useReading(text, "material_1")] };
      h.script.correction = { ...badminton, materialReading: [{ ...useReading(text, "material_1"), usage: [{ quote: text, action: "omit", reason: "unsuitable_opener" }] }] };
      const res = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text })));
      assertEquals(res.status, 200);
      const result = await json(res);
      assertEquals((result.openers as Record<string, string>).extend, badminton.openers.extend);
      assert((result.materialUse as Record<string, unknown>).handlingNote, "收窄後告知這段補充沒放進開場");
      assertEquals(h.script.calls.length, 3, "分析＋生成＋一次有界修正，不另開分類或生成呼叫");
      const correction = String(h.script.calls.at(-1)?.messages[0].content);
      assert(correction.includes("方案可見的卡尚未找到保留原料"), "這次修正由 material_unused 觸發");
      assert(correction.includes(bio), "修正必須仍看得到來源的拒絕，不只看到補充");
      assertEquals(await usage(h.db), { m: 3, d: 3 }, "只扣一次");
    } finally { await h.db.close(); }
  });
}

Deno.test("採用修正 handler：既有 omit 不能翻回 use；格式修復已用掉就不再補一次", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    // 想約不再要求採用（2026-09-24 教練型 Opener），改用話題型補充觸發 material_unused。
    const text = "腿很長，想問她都去哪裡打羽球";
    const original = { ...GENERATE_JSON, materialReading: [{ ...useReading(text, "material_1"), usage: [
      { quote: "腿很長", action: "omit", reason: "unsuitable_opener" },
      { quote: "想問她都去哪裡打羽球", action: "use" },
    ] }], materialUse: { references: [], displayNotes: {} } };
    h.script.generate = original;
    h.script.correction = { ...original, materialReading: [useReading(text, "material_1")], openers: { ...original.openers, extend: "妳都去哪裡打羽球" } };
    const request = generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text });
    assertEquals((await handleOpenerGenerateRequest(h.deps(request))).status, 502, "即使卡片已符合採用，反轉舊 omit 的整次修正仍拒收");
    assertEquals(h.script.calls.length, 3);
    assertEquals(await usage(h.db), { m: 0, d: 0 });
    await passOneMinute(h.db);
    h.script.generate = { ...original, materialReading: [] };
    h.script.repair = original;
    const before = h.script.calls.length;
    assertEquals((await handleOpenerGenerateRequest(h.deps({ ...request, generationId: GEN_2 }))).status, 502);
    assertEquals(h.script.calls.length - before, 2, "生成與格式修復後沒有額外內容修正");
    assertEquals(await usage(h.db), { m: 0, d: 0 });
  } finally { await h.db.close(); }
});

for (const accountIsTest of [false, true]) {
  Deno.test(`版本升級：${accountIsTest ? "測試帳號" : "無資料零成本"} 已完成結果也可重播且不扣費`, async () => {
    const h = await harness();
    try {
      h.script.analyze = { ...ANALYSIS_JSON, profileDigest: "沒有對方資料", cues: [], question: null };
      const analysis = await analyzed(h, accountIsTest ? {} : { profileInfo: {} });
      const body = generateBody(String(analysis.sessionId), GEN_1, { state: "skipped" });
      h.script.generate = { ...GENERATE_JSON, materialReading: [], materialUse: { references: [], displayNotes: {} } };
      assertEquals((await handleOpenerGenerateRequest(h.deps(body, { accountIsTest }))).status, 200);
      const parsed = parseOpenerGenerateRequest({ rawFlowVersion: body.openerFlowVersion, rawSessionId: body.sessionId, rawAnalysisRevision: body.analysisRevision, rawGenerationId: body.generationId, rawContribution: body.userContribution });
      assert(parsed.ok);
      const hash = await computeOpenerGenerationInputHash({ ...parsed.request, contractVersion: 2, promptVersion: "opener-two-stage-prompt-v1" });
      await h.db.query(`UPDATE public.opener_generation_runs SET input_hash = $1 WHERE generation_id = $2`, [hash, GEN_1]);
      const before = h.script.calls.length;
      const replay = await handleOpenerGenerateRequest(h.deps(body, { accountIsTest }));
      assertEquals(replay.status, 200);
      assertEquals(((await json(replay)).usage as Record<string, unknown>).chargedNow, 0);
      assertEquals(h.script.calls.length, before);
      assertEquals(await usage(h.db), { m: 0, d: 0 });
    } finally { await h.db.close(); }
  });
}

Deno.test("F01／B01：只按分析→只有分析與題目、沒有五句、只打一次模型、不扣額度", async () => {
  const h = await harness();
  try {
    const body = await analyzed(h);
    assertEquals(body.stage, "analyze");
    assert(typeof body.sessionId === "string" && UUID_RE.test(body.sessionId as string));
    assertEquals(body.analysisRevision, 1);
    assertEquals("openers" in body, false);
    assertEquals((body.approach as Record<string, unknown>).mode, "anchor_hooks");
    assertEquals((body.cues as unknown[]).length, 2);
    assertEquals((body.question as Record<string, unknown>).id, "question_1");
    assertEquals(body.usage, { chargedNow: 0, firstGenerationCost: 3, includedGenerationCount: 3, generationsUsed: 0, generationsRemaining: 3, quotaCharged: false });
    assertEquals(h.script.calls.length, 1);
    assertEquals(h.script.calls[0].system, OPENER_ANALYZE_PROMPT);
    assertEquals(await usage(h.db), { m: 0, d: 0 });
    // 回應不含快照內部欄位（App 不能拿它當事實回傳）。
    assertEquals("profileDigest" in body, false);
  } finally {
    await h.db.close();
  }
});

Deno.test("第一段：同 analysisRequestId 重試取回快照（replayed）、不再打模型；旗標關閉／DB 未就緒→503 OPENER_FLOW_UNAVAILABLE", async () => {
  const h = await harness();
  try {
    const first = await analyzed(h);
    const second = await analyzed(h);
    assertEquals(second.sessionId, first.sessionId);
    assertEquals(second.replayed, true);
    assertEquals(h.script.calls.length, 1);

    h.env.OPENER_TWO_STAGE_ENABLED = "false";
    const disabled = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ analysisRequestId: GEN_4 })));
    assertEquals(disabled.status, 503);
    assertEquals((await json(disabled)).code, "OPENER_FLOW_UNAVAILABLE");
    delete h.env.OPENER_TWO_STAGE_ENABLED;

    await h.db.exec(`DROP FUNCTION public.validate_opener_generation_result(jsonb) CASCADE`);
    const notReady = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ analysisRequestId: GEN_4 })));
    assertEquals(notReady.status, 503);
    assertEquals((await json(notReady)).code, "OPENER_FLOW_UNAVAILABLE");
  } finally {
    await h.db.close();
  }
});

Deno.test("第一段：初稿只記「有無」不存原文；零扣費判準只看對方資料（補充不冒充對方資料）", async () => {
  const h = await harness();
  try {
    const body = await analyzed(h, { profileInfo: undefined, initialUserNote: "我超喜歡柴犬，想從狗開" });
    assertEquals((body.usage as Record<string, unknown>).firstGenerationCost, 0, "無圖無對方資料＝零扣費，初稿不算對方資料");
    const rows = await h.db.query<{ analysis_json: Record<string, unknown> }>(`SELECT analysis_json FROM public.opener_sessions`);
    const stored = rows.rows[0].analysis_json;
    assertEquals(stored.initialNoteProvided, true);
    assertEquals(JSON.stringify(stored).includes("我超喜歡柴犬"), false, "快照不得保存初稿原文");
    assert(String(h.script.calls[0].messages[0].content).includes("我超喜歡柴犬"), "第一段模型有看到初稿");
  } finally {
    await h.db.close();
  }
});

Deno.test("第一段：wrongSurface→422 不建立會話；模型失敗→503 且作業釋放", async () => {
  const h = await harness();
  try {
    h.script.analyze = { wrongSurface: "chat_conversation", openers: {} };
    const wrong = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ images: [{ data: "AAAA", mediaType: "image/jpeg", order: 1 }] })));
    assertEquals(wrong.status, 422);
    assertEquals((await json(wrong)).error, "OPENER_WRONG_SURFACE");
    h.script.analyze = undefined;
    h.script.throwOn = "analyze";
    const down = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ analysisRequestId: GEN_4 })));
    assertEquals(down.status, 503);
    const rows = await h.db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_sessions WHERE state <> 'released'`);
    assertEquals(rows.rows[0].n, 0);
  } finally {
    await h.db.close();
  }
});

Deno.test("B02／F13：Free 首次生成→扣 3、可見三卡、推薦在可見卡、來源核對 matched、鎖卡不外流", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, CURIOUS)));
    assertEquals(response.status, 200);
    const body = await json(response);
    assertEquals(body.stage, "generate");
    assertEquals(body.generationId, GEN_1);
    assertEquals(Object.keys(body.openers as Record<string, string>).sort(), ["extend", "humor", "tease"]);
    assertEquals((body.recommendation as Record<string, unknown>).pick, "extend");
    assertEquals((body.materialUse as Record<string, unknown>).traceStatus, "matched");
    assertEquals((body.materialUse as Record<string, unknown>).inputState, "answered");
    assertEquals((body.materialUse as Record<string, unknown>).displayNote, "這句接的是你想知道的散步習慣");
    assertEquals((body.access as Record<string, unknown>).servedTier, "free");
    assertEquals(body.usage, { chargedNow: 3, sessionChargedTotal: 3, generationsUsed: 1, generationsRemaining: 2, replayed: false, cost: 3, includedGenerationCount: 3 });
    assertEquals(JSON.stringify(body).includes("養這種狗的人"), false);
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    // 第二段模型只拿到快照與本次補充，不重傳圖片；補充原文在 user content 裡。
    const generateCall = h.script.calls[1];
    assertEquals(generateCall.system, OPENER_GENERATE_PROMPT);
    assert(String(generateCall.messages[0].content).includes("沒養過，只想知道牠散步會不會自己選路"));
    assert(String(generateCall.messages[0].content).includes("沒有相關經驗"));
  } finally {
    await h.db.close();
  }
});

Deno.test("B06／B09：同 generationId 重試回同組（不重扣、不打模型）；同 ID 改答案→409 輸入不一致", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    const first = await json(await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS))));
    const calls = h.script.calls.length;
    const replay = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)));
    assertEquals(replay.status, 200);
    const replayBody = await json(replay);
    assertEquals(replayBody.openers, first.openers);
    assertEquals((replayBody.usage as Record<string, unknown>).replayed, true);
    assertEquals((replayBody.usage as Record<string, unknown>).chargedNow, 0);
    assertEquals((replayBody.usage as Record<string, unknown>).generationsUsed, 1);
    assertEquals(h.script.calls.length, calls);
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    const edited = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, { ...CURIOUS, freeText: "改聊咖啡" })));
    assertEquals(edited.status, 409);
    assertEquals((await json(edited)).code, "OPENER_OPERATION_INPUT_MISMATCH");
  } finally {
    await h.db.close();
  }
});

Deno.test("F16／回歸：刪掉初稿改聊咖啡→第二段只用目前 freeText，舊初稿不從快照復活", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h, { initialUserNote: "我有養狗，想從狗開" });
    // 第五輪 A：可見卡要在內容上接住「改聊咖啡」，否則會進 material_unused 修正。
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("改聊咖啡", "material_1")], openers: { ...GENERATE_JSON.openers, extend: "改聊咖啡的話 妳平常都喝哪種" } };
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, { state: "answered", freeText: "改聊咖啡" })));
    assertEquals(response.status, 200);
    const generateCall = h.script.calls[1];
    const content = String(generateCall.messages[0].content);
    assert(content.includes("改聊咖啡"));
    assertEquals(content.includes("我有養狗"), false, "被刪掉的初稿不得回到第二段原料");
    const rows = await h.db.query<{ contribution_json: Record<string, unknown> }>(`SELECT contribution_json FROM public.opener_generation_runs`);
    assertEquals(rows.rows[0].contribution_json.freeText, "改聊咖啡");
  } finally {
    await h.db.close();
  }
});

Deno.test("F12：偽造題目／選項在模型工作前拒絕，作業釋放", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    const calls = h.script.calls.length;
    const foreign = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, { state: "answered", questionId: "question_1", selectedOptionId: "option_9" })));
    assertEquals(foreign.status, 400);
    assertEquals((await json(foreign)).code, "OPENER_CONTRIBUTION_INVALID");
    assertEquals(h.script.calls.length, calls);
    assertEquals(await runCount(h.db), 0);
    const skippedWithAnswer = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, { state: "skipped", freeText: "偷夾答案" })));
    assertEquals(skippedWithAnswer.status, 400);
  } finally {
    await h.db.close();
  }
});

Deno.test("B14：另一帳號猜 sessionId→404，拿不到快照與結果", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, CURIOUS), { userId: OTHER_USER_ID }));
    assertEquals(response.status, 404);
    assertEquals((await json(response)).code, "OPENER_SESSION_INVALID");
  } finally {
    await h.db.close();
  }
});

Deno.test("B04／B05：三組不同 generationId 共扣 3；第四組在模型前擋 409", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    for (const [i, gen] of [GEN_1, GEN_2, GEN_3].entries()) {
      await passOneMinute(h.db);
      h.script.generate = { ...GENERATE_JSON, materialReading: [useReading(`第 ${i} 版：只想知道牠散步會不會自己選路`)] };
      const body = await json(await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, gen, { ...CURIOUS, freeText: `第 ${i} 版：只想知道牠散步會不會自己選路` }))));
      assertEquals((body.usage as Record<string, unknown>).generationsUsed, i + 1);
      assertEquals((body.usage as Record<string, unknown>).chargedNow, i === 0 ? 3 : 0);
    }
    const calls = h.script.calls.length;
    const fourth = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_4, CURIOUS)));
    assertEquals(fourth.status, 409);
    const body = await json(fourth);
    assertEquals(body.code, "OPENER_GENERATION_LIMIT_REACHED");
    assertEquals(body.newSessionCost, 3);
    assertEquals(h.script.calls.length, calls);
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally {
    await h.db.close();
  }
});

Deno.test("B08：模型失敗→503 不扣不占次數；沒有來源的「我也養狗」→一次內容修正；修不好→502 不扣", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    h.script.throwOn = "generate";
    const down = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)));
    assertEquals(down.status, 503);
    assertEquals((await json(down)).code, "OPENER_PROVIDER_UNAVAILABLE");
    assertEquals(await runCount(h.db), 0);
    h.script.throwOn = undefined;
    await passOneMinute(h.db);

    // 選「沒養但有興趣」卻寫「我也養狗」：硬錯誤 → 修正 prompt 只改那句。
    h.script.generate = { ...GENERATE_JSON, openers: { ...GENERATE_JSON.openers, resonate: "我也養狗，妳那隻會帶路嗎" } };
    h.script.correction = { openers: { resonate: "養這種狗的人假日應該都在外面" }, cardReasons: { resonate: "改站在她的處境" }, materialUse: { references: [] } };
    h.tier = "essential";
    const corrected = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)));
    assertEquals(corrected.status, 200);
    const body = await json(corrected);
    assertEquals((body.openers as Record<string, string>).resonate, "養這種狗的人假日應該都在外面");
    assertEquals((body.openers as Record<string, string>).extend, "牠散步會自己選路嗎", "沒被標記的句子逐字保留");
    const correctionCall = h.script.calls.find((c) => String(c.messages[0].content).startsWith("以下這組開場白有可確定的錯誤"));
    assert(correctionCall && String(correctionCall.messages[0].content).includes("resonate"));

    // 修正後仍捏造 → 不交付、不扣、作業釋放。
    await passOneMinute(h.db);
    h.script.correction = { openers: { resonate: "我也養狗啦，妳那隻呢" } };
    const still = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, CURIOUS)));
    assertEquals(still.status, 502);
    assertEquals((await json(still)).code, "OPENER_CONTENT_CONFLICT");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions`);
    assertEquals(rows.rows[0].generations_used, 1);
    assertEquals(await runCount(h.db), 1);
  } finally {
    await h.db.close();
  }
});

Deno.test("五句不齊→一次格式修復；仍不齊→502 OPENER_RESPONSE_INCOMPLETE 不扣", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    h.script.generate = { ...GENERATE_JSON, openers: { extend: "只剩一句" } };
    h.script.repair = GENERATE_JSON;
    const repaired = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)));
    assertEquals(repaired.status, 200);
    assert(h.script.calls.some((c) => c.system === OPENER_GENERATE_REPAIR_PROMPT));
    h.script.repair = { openers: { extend: "還是一句" } };
    await passOneMinute(h.db);
    const broken = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, CURIOUS)));
    assertEquals(broken.status, 502);
    assertEquals((await json(broken)).code, "OPENER_RESPONSE_INCOMPLETE");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally {
    await h.db.close();
  }
});

Deno.test("B10：預查通過但結算時額度已被其他功能用掉→429 帶額度鍵、結果不落地、作業釋放", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    await h.db.query(`UPDATE public.subscriptions SET monthly_messages_used = 28 WHERE user_id = $1`, [USER_ID]);
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, CURIOUS)));
    assertEquals(response.status, 429);
    const body = await json(response);
    assert(typeof body.monthlyLimit === "number", "訂閱額度 429 必須帶額度鍵讓 App 顯示方案入口");
    assertEquals(await runCount(h.db), 0);
    const rows = await h.db.query<{ generations_used: number; quota_charged: boolean }>(`SELECT generations_used, quota_charged FROM public.opener_sessions`);
    assertEquals(rows.rows[0], { generations_used: 0, quota_charged: false });
  } finally {
    await h.db.close();
  }
});

Deno.test("B11：已扣費的同局，其他功能把額度用完後剩餘生成仍可用、不再要求付費", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    assertEquals((await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)))).status, 200);
    await passOneMinute(h.db);
    h.sub.monthly_messages_used = 30;
    h.sub.daily_messages_used = 10;
    await h.db.query(`UPDATE public.subscriptions SET monthly_messages_used = 30, daily_messages_used = 10 WHERE user_id = $1`, [USER_ID]);
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("第二版：只想知道牠散步會不會自己選路")] };
    const second = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, { ...CURIOUS, freeText: "第二版：只想知道牠散步會不會自己選路" })));
    assertEquals(second.status, 200);
    assertEquals(((await json(second)).usage as Record<string, unknown>).chargedNow, 0);
    assertEquals(await usage(h.db), { m: 30, d: 10 });
  } finally {
    await h.db.close();
  }
});

Deno.test("B15：模型限流→429 MODEL_RATE_LIMITED 不帶額度鍵、不占成功次數、作業釋放；限流由兩階段共用", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h); // 第 1 次 opener 作業
    const sessionId = analysis.sessionId as string;
    assertEquals((await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)))).status, 200); // 第 2 次
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("二：牠散步會不會自己選路")] };
    assertEquals((await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, { ...CURIOUS, freeText: "二：牠散步會不會自己選路" })))).status, 200); // 第 3 次
    const limited = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_3, { ...CURIOUS, freeText: "三：牠散步會不會自己選路" }))); // 第 4 次／分鐘
    assertEquals(limited.status, 429);
    const body = await json(limited);
    assertEquals(body.code, "MODEL_RATE_LIMITED");
    assertEquals("monthlyLimit" in body, false);
    assertEquals(await runCount(h.db), 2);
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions`);
    assertEquals(rows.rows[0].generations_used, 2);
    // 重播已存結果不計次：GEN_1 仍可取回。
    assertEquals((await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, CURIOUS)))).status, 200);
  } finally {
    await h.db.close();
  }
});

Deno.test("B12／B07：到期→410 不扣；同局另一作業執行中→409 OPENER_GENERATION_PENDING 帶 activeGenerationId", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    await h.db.query(`SELECT public.claim_opener_generation($1::uuid, $2::uuid, $3::uuid, $4::text, $5::uuid, $6::jsonb, 3, 65)`, [
      USER_ID, sessionId, GEN_1, "a".repeat(64), "2b2b2b2b-2b2b-4b2b-8b2b-2b2b2b2b2b2b", JSON.stringify(CURIOUS),
    ]);
    const busy = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, CURIOUS)));
    assertEquals(busy.status, 409);
    const busyBody = await json(busy);
    assertEquals(busyBody.code, "OPENER_GENERATION_PENDING");
    assertEquals(busyBody.activeGenerationId, GEN_1);

    await h.db.query(`UPDATE public.opener_sessions SET expires_at = now() - interval '1 second'`);
    const expired = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_3, CURIOUS)));
    assertEquals(expired.status, 410);
    assertEquals((await json(expired)).code, "OPENER_SESSION_EXPIRED");
    assertEquals(await usage(h.db), { m: 0, d: 0 });
  } finally {
    await h.db.close();
  }
});

Deno.test("串流交付邊界：done 之前只有 started/progress，不外流任何句子；done 帶完整結果", async () => {
  const h = await harness();
  try {
    h.env.OPENER_STREAM_ENABLED = "true";
    const analyzeResponse = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { responseMode: "stream" }));
    assert(analyzeResponse.headers.get("content-type")?.includes("ndjson"));
    const analyzeEvents = (await analyzeResponse.text()).trim().split("\n").map((line) => JSON.parse(line));
    assertEquals(analyzeEvents[0].type, "opener_analyze.started");
    const analyzeDone = analyzeEvents.at(-1);
    assertEquals(analyzeDone.type, "opener_analyze.done");
    assertEquals(analyzeDone.result.stage, "analyze");
    for (const event of analyzeEvents.slice(0, -1)) {
      assertEquals(JSON.stringify(event).includes("養狗"), false, "progress 不帶內容");
    }

    const generateResponse = await handleOpenerGenerateRequest(h.deps(generateBody(analyzeDone.result.sessionId, GEN_1, CURIOUS), { responseMode: "stream" }));
    const events = (await generateResponse.text()).trim().split("\n").map((line) => JSON.parse(line));
    assertEquals(events[0].type, "opener_generate.started");
    assert(events.some((e) => e.type === "opener_generate.progress" && e.phase === "style_extend"));
    assert(events.some((e) => e.type === "opener_generate.progress" && e.phase === "finalizing"));
    for (const event of events.slice(0, -1)) {
      assertEquals(JSON.stringify(event).includes("散步會自己選路"), false, "結算前不得公開可複製的完整回覆");
    }
    const done = events.at(-1);
    assertEquals(done.type, "opener_generate.done");
    assertEquals(done.result.openers.extend, "牠散步會自己選路嗎");
    assertEquals(done.result.usage.chargedNow, 3);
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally {
    await h.db.close();
  }
});

Deno.test("F10／略過：inputState=skipped、traceStatus=no_input、displayNote=null、不宣稱採用", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    h.script.generate = { ...GENERATE_JSON, materialReading: [] };
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, { state: "skipped" })));
    assertEquals(response.status, 200);
    const use = (await json(response)).materialUse as Record<string, unknown>;
    assertEquals(use.inputState, "skipped");
    assertEquals(use.traceStatus, "no_input");
    assertEquals(use.displayNote, null);
    assertEquals(use.references, []);
    assert(String(h.script.calls[1].messages[0].content).includes("不要假裝有取得用戶個人想法"));
  } finally {
    await h.db.close();
  }
});

Deno.test("測試帳號：不扣費、不限流，但仍走 claim／settle 並建立成功次數", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h, {});
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, CURIOUS), { accountIsTest: true }));
    assertEquals(response.status, 200);
    const body = await json(response);
    assertEquals((body.usage as Record<string, unknown>).chargedNow, 0);
    assertEquals((body.usage as Record<string, unknown>).generationsUsed, 1);
    assertEquals(await usage(h.db), { m: 0, d: 0 });
  } finally {
    await h.db.close();
  }
});

// ── 第一輪獨立複核回歸（2026-09-17）

Deno.test("R3b：刪掉初稿改聊咖啡→第一段依初稿寫的方向文字不得回到第二段 prompt", async () => {
  const h = await harness();
  try {
    h.script.analyze = { ...ANALYSIS_JSON, approach: { mode: "anchor_hooks", summary: "你自己有養狗，可以直接從散步習慣開", avoid: ["不用提你妹"] } };
    const analysis = await analyzed(h, { initialUserNote: "我有養狗，想從狗開" });
    assertEquals((analysis.approach as Record<string, unknown>).summary, "你自己有養狗，可以直接從散步習慣開", "第一段當時的判斷照常回給 App 顯示");
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("改聊咖啡，想問照片那家店在哪", "material_1")], openers: { ...GENERATE_JSON.openers, extend: "改聊咖啡 妳照片那家店在哪啊" } };
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, { state: "answered", freeText: "改聊咖啡，想問照片那家店在哪" })));
    assertEquals(response.status, 200);
    const content = String(h.script.calls[1].messages[0].content);
    assertEquals(content.includes("你自己有養狗"), false, "已撤回初稿衍生的方向不得當底稿");
    assertEquals(content.includes("不用提你妹"), false);
    assert(content.includes("改聊咖啡"));
    // 同一份初稿原封送回（等於沒改）：方向文字可沿用。
    await passOneMinute(h.db);
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("我有養狗，想從狗開", "material_1")], openers: { ...GENERATE_JSON.openers, extend: "我有養狗 妳家那隻散步會自己選路嗎" } };
    const same = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_2, { state: "answered", freeText: "我有養狗，想從狗開" })));
    assertEquals(same.status, 200);
    assert(String(h.script.calls[2].messages[0].content).includes("你自己有養狗"));
  } finally {
    await h.db.close();
  }
});

Deno.test("R5：格式修復＋內容修正共用一次額外機會；修好格式後仍有硬錯誤→不發第三次模型請求、502 不扣", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    h.script.generate = "這不是 JSON";
    h.script.repair = { ...GENERATE_JSON, openers: { ...GENERATE_JSON.openers, resonate: "我也養狗，妳那隻會帶路嗎" } };
    h.script.correction = GENERATE_JSON; // 若被呼叫，會把錯誤修好——那就代表預算沒守住
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(analysis.sessionId as string, GEN_1, CURIOUS)));
    assertEquals(response.status, 502);
    assertEquals((await json(response)).code, "OPENER_CONTENT_CONFLICT");
    const generateCalls = h.script.calls.filter((c) => c.system !== OPENER_ANALYZE_PROMPT);
    assertEquals(generateCalls.length, 2, "主呼叫＋一次格式修復；不得再有內容修正");
    assertEquals(await usage(h.db), { m: 0, d: 0 });
    assertEquals(await runCount(h.db), 0);
  } finally {
    await h.db.close();
  }
});

Deno.test("R6b：分析已保存、回應遺失後關閉新局旗標→同 analysisRequestId 重試仍取回快照；新 ID 才被擋", async () => {
  const h = await harness();
  try {
    const first = await analyzed(h);
    h.env.OPENER_TWO_STAGE_ENABLED = "false";
    const replay = await handleOpenerAnalyzeRequest(h.deps(analyzeBody()));
    assertEquals(replay.status, 200);
    const body = await json(replay);
    assertEquals(body.sessionId, first.sessionId);
    assertEquals(body.replayed, true);
    assertEquals(h.script.calls.length, 1, "重播不打模型");
    const fresh = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ analysisRequestId: GEN_4 })));
    assertEquals(fresh.status, 503);
    assertEquals((await json(fresh)).code, "OPENER_FLOW_UNAVAILABLE");
    const rows = await h.db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_sessions WHERE state = 'pending'`);
    assertEquals(rows.rows[0].n, 0, "被擋的新局不得留下 pending 列");
  } finally {
    await h.db.close();
  }
});

// ── 第五輪驗收 A：可見卡沒有一張真的接住用戶原料 → material_unused 一次修正；修不好 502 不扣、不計次。
Deno.test("A（第五輪）：可見推薦沒接原料→一次內容修正改到接住原料才交付；修不好→502 不扣不計次", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    const contribution = { state: "answered", questionId: null, selectedOptionId: null, freeText: "她上次聊天提過想去沖繩，還沒訂" };
    // 模型只聊狗：五張卡都沒有沖繩 → material_unused 標在排序第一的可見卡（extend）→ 修正。
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("她上次聊天提過想去沖繩，還沒訂", "material_1")], materialUse: { references: [], displayNotes: {} } };
    h.script.correction = { openers: { extend: "沖繩機票訂了嗎 還是先顧狗" }, cardReasons: { extend: "接住她提過想去沖繩這件事" }, materialUse: { references: [{ style: "extend", materialId: "material_1", outputSpan: "沖繩" }], displayNotes: { extend: "這句接的是她提過想去沖繩、還沒訂" } } };
    const ok = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, contribution)));
    assertEquals(ok.status, 200);
    const body = await json(ok);
    assertEquals((body.recommendation as Record<string, unknown>).pick, "extend");
    assertEquals((body.openers as Record<string, string>).extend, "沖繩機票訂了嗎 還是先顧狗");
    assertEquals((body.materialUse as Record<string, unknown>).traceStatus, "matched");
    assertEquals((body.usage as Record<string, unknown>).generationsUsed, 1);
    const correctionCall = h.script.calls.find((c) => String(c.messages[0].content).startsWith("以下這組開場白有可確定的錯誤"));
    assert(correctionCall && String(correctionCall.messages[0].content).includes("尚未找到保留原料"), "修正提示要說明未找到原料採用證據");
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    // 修正後仍然沒接住 → 502、不扣、不占次數，且不再發第三次模型請求。
    await passOneMinute(h.db);
    h.script.correction = { openers: { extend: "妳家狗真的很有主見" } };
    const callsBefore = h.script.calls.length;
    const still = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, contribution)));
    assertEquals(still.status, 502);
    assertEquals((await json(still)).code, "OPENER_CONTENT_CONFLICT");
    assertEquals(h.script.calls.length - callsBefore, 2, "生成＋一次修正，沒有第三次");
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "失敗不扣");
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions WHERE session_id = $1`, [sessionId]);
    assertEquals(rows.rows[0].generations_used, 1, "失敗不占次數");
  } finally {
    await h.db.close();
  }
});

// ── 第五輪 G1／G2：正常初次結果直接交付、不額外修正；真正壞結果最多一次修正，仍錯就 502 不扣。
const EXCLUDE_ANALYSIS = { ...ANALYSIS_JSON, question: { ...ANALYSIS_JSON.question, options: [...ANALYSIS_JSON.question.options, { id: "option_4", label: "不想聊狗", meaning: "exclude_cue", cueId: "cue_1" }] } };
const RIVER_OPENERS = { extend: "假日河堤那段妳都從哪裡開始走", resonate: "假日固定去河堤的人通常很需要放空", tease: "河堤是去運動還是去發呆的", humor: "河堤的風跟妳的週末 哪個比較自由", coldRead: "感覺妳週末不太待在室內" };

Deno.test("G1（handler）：選「不想聊狗」→ 改聊河堤的整組直接交付、不發修正、扣 3；仍提到狗才修正", async () => {
  const h = await harness();
  try {
    h.script.analyze = EXCLUDE_ANALYSIS;
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    const exclude = { state: "answered", questionId: "question_1", selectedOptionId: "option_4", freeText: null };
    h.script.generate = { ...GENERATE_JSON, materialReading: [{ materialId: "material_1", subject: "sender", kind: "restriction", certainty: "stated", quote: "不想聊" }], openers: RIVER_OPENERS, materialUse: { references: [], displayNotes: {} } };
    const ok = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, exclude)));
    assertEquals(ok.status, 200);
    const body = await json(ok);
    assertEquals((body.openers as Record<string, string>).extend, RIVER_OPENERS.extend);
    assertEquals((body.recommendation as Record<string, unknown>).pick, "extend");
    assertEquals(h.script.calls.filter((c) => c.system === OPENER_GENERATE_PROMPT).length, 1, "沒有修正呼叫");
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    // 有一張仍聊狗 → excluded_topic_used 一次修正；修好就交付、不再扣。
    await passOneMinute(h.db);
    h.script.generate = { ...GENERATE_JSON, materialReading: [], openers: { ...RIVER_OPENERS, tease: "妳養狗多久了 週末也帶去河堤嗎" }, materialUse: { references: [], displayNotes: {} } };
    h.script.correction = { openers: { tease: "河堤是去運動還是去發呆的" }, cardReasons: { tease: "改成不碰狗" }, materialUse: { references: [] } };
    const fixed = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, exclude)));
    assertEquals(fixed.status, 200);
    assertEquals(((await json(fixed)).openers as Record<string, string>).tease, "河堤是去運動還是去發呆的");
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "同局第二組不再扣");
  } finally {
    await h.db.close();
  }
});

Deno.test("G2（handler）：良性對照（已經訂好了嗎）直接交付不修正；「順帶一提：我也養狗」一次修正、仍錯 502 不扣不計次", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const sessionId = analysis.sessionId as string;
    const sheSaid = { state: "answered", questionId: null, selectedOptionId: null, freeText: "她上次聊天提過想去沖繩，還沒訂" };
    h.script.generate = { ...GENERATE_JSON, materialReading: [useReading("她上次聊天提過想去沖繩，還沒訂", "material_1")], openers: { ...GENERATE_JSON.openers, extend: "沖繩機票已經訂好了嗎？還是先顧狗" }, materialUse: { references: [{ style: "extend", materialId: "material_1", outputSpan: "沖繩" }], displayNotes: { extend: "接的是她提過想去沖繩" } } };
    const ok = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, sheSaid)));
    assertEquals(ok.status, 200);
    const body = await json(ok);
    assertEquals((body.openers as Record<string, string>).extend, "沖繩機票已經訂好了嗎？還是先顧狗");
    assertEquals((body.materialUse as Record<string, unknown>).traceStatus, "matched");
    assertEquals(h.script.calls.filter((c) => c.system === OPENER_GENERATE_PROMPT).length, 1, "良性問句不進修正");
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    // 略過補充卻寫「順帶一提：我也養狗」→ 冒號不放行 → 修正；修正仍自述 → 502 不扣不計次。
    await passOneMinute(h.db);
    h.tier = "essential"; // resonate 是 Free 鎖卡；要看修正結果得用五卡方案
    const skipped = { state: "skipped", questionId: null, selectedOptionId: null, freeText: null };
    h.script.generate = { ...GENERATE_JSON, materialReading: [], openers: { ...GENERATE_JSON.openers, resonate: "順帶一提：我也養狗" }, materialUse: { references: [], displayNotes: {} } };
    h.script.correction = { openers: { resonate: "柴犬：我養妳不是讓妳摸的" } };
    const callsBefore = h.script.calls.length;
    const still = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, skipped)));
    assertEquals(still.status, 200, "代言不是自述，修正後可交付");
    assertEquals(((await json(still)).openers as Record<string, string>).resonate, "柴犬：我養妳不是讓妳摸的");
    assertEquals(h.script.calls.length - callsBefore, 2, "生成＋一次修正");

    await passOneMinute(h.db);
    h.script.correction = { openers: { resonate: "順帶一提：我也養狗啦" } };
    const bad = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_3, skipped)));
    assertEquals(bad.status, 502);
    assertEquals((await json(bad)).code, "OPENER_CONTENT_CONFLICT");
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "失敗不扣");
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions WHERE session_id = $1`, [sessionId]);
    assertEquals(rows.rows[0].generations_used, 2, "失敗不占次數");
  } finally {
    await h.db.close();
  }
});

// ── 第七輪：用真模型確認跑捕獲的 raw（tag g1g2-d4824177-confirm）補驗正式一次內容修正路徑。
//    scripted 模型只驗管線（呼叫數、交付、結算、不扣費），修正後的品質要新模型輸出才算。
interface CapturedFixture { profileInfo: Record<string, unknown>; contribution: Record<string, unknown>; raw: string; analyzeRaw: string }
async function captured(name: string): Promise<CapturedFixture> {
  const fixture = JSON.parse(await Deno.readTextFile(new URL(`../../../tools/opener-content-replay/fixtures/captured-r7-${name}.json`, import.meta.url))) as CapturedFixture;
  // Preserve captured sentences; supply the new internal contract as a scripted
  // fixture. This does not turn historical raw into a live-model usage evaluation.
  const parsed = parseJsonObjectFromText(fixture.raw)!;
  parsed.materialReading = [useReading(String(fixture.contribution.freeText), fixture.contribution.selectedOptionId ? "material_2" : "material_1")];
  return { ...fixture, raw: JSON.stringify(parsed) };
}
function generateCalls(h: Harness): number {
  return h.script.calls.filter((c) => c.system === OPENER_GENERATE_PROMPT).length;
}
async function capturedSession(h: Harness, fx: CapturedFixture): Promise<string> {
  h.script.analyze = fx.analyzeRaw;
  const analysis = await analyzed(h, { profileInfo: fx.profileInfo });
  return analysis.sessionId as string;
}

Deno.test("第七輪 F039：捕獲 raw「家裡保養品多到可以開店」→ relative_fact_extended 一次修正→交付扣 3；修正仍補情境→502 不扣不計次", async () => {
  const h = await harness();
  try {
    const fx = await captured("filter-heavy.A.1");
    const sessionId = await capturedSession(h, fx);
    h.script.generate = fx.raw;
    h.script.correction = { openers: { humor: "我妹也是美容師 妳們平常是不是都站一整天" }, cardReasons: { humor: "只用原句程度" }, materialUse: { references: [{ style: "humor", materialId: "material_1", outputSpan: "我妹也是美容師" }] } };
    const ok = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, fx.contribution)));
    assertEquals(ok.status, 200);
    const body = await json(ok);
    assertEquals((body.openers as Record<string, string>).humor, "我妹也是美容師 妳們平常是不是都站一整天");
    assertEquals((body.openers as Record<string, string>).extend, "我妹也是美容師耶 妳都做哪些項目啊", "沒被標記的句子逐字保留");
    const correctionCall = h.script.calls.find((c) => String(c.messages[0].content).startsWith("以下這組開場白有可確定的錯誤"));
    assert(correctionCall && String(correctionCall.messages[0].content).includes("補上沒說過的情境"), "修正提示要說明是替家人／自家補情境");
    assertEquals(generateCalls(h), 2, "生成＋一次修正");
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    await passOneMinute(h.db);
    h.script.correction = { openers: { humor: "我妹是美容師 家裡都是她帶回來的試用品" } };
    const before = h.script.calls.length;
    const still = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, fx.contribution)));
    assertEquals(still.status, 502);
    assertEquals((await json(still)).code, "OPENER_CONTENT_CONFLICT");
    assertEquals(h.script.calls.length - before, 2, "沒有第三次模型請求");
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "失敗不扣");
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions WHERE session_id = $1`, [sessionId]);
    assertEquals(rows.rows[0].generations_used, 1, "失敗不占次數");
  } finally {
    await h.db.close();
  }
});

Deno.test("第七輪 F051／F040／F058：捕獲 raw 只有 soft 或線索錨字採用 → Free 與 paid 都直接交付、不發修正", async () => {
  const h = await harness();
  try {
    // multi-hook B1：「貓咪比妳早睡…」接住貓的好奇，Free 三卡不再 material_unused。
    const cat = await captured("multi-hook.B.1");
    const catSession = await capturedSession(h, cat);
    h.script.generate = cat.raw;
    const free = await handleOpenerGenerateRequest(h.deps(generateBody(catSession, GEN_1, cat.contribution)));
    assertEquals(free.status, 200);
    const freeBody = await json(free);
    assertEquals((freeBody.recommendation as Record<string, unknown>).pick, "extend");
    assertEquals(generateCalls(h), 1, "Free 沒有修正呼叫");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    await passOneMinute(h.db);
    h.tier = "essential";
    const paid = await handleOpenerGenerateRequest(h.deps(generateBody(catSession, GEN_2, cat.contribution)));
    assertEquals(paid.status, 200);
    assertEquals(Object.keys((await json(paid)).openers as Record<string, string>).length, 5);
    assertEquals(generateCalls(h), 2, "paid 也沒有修正呼叫");
    h.tier = "free";
    await passOneMinute(h.db);

    // multi-hook A3「玩過三年樂團 妳打鼓多久了」與 family-fact A3「我妹聽了應該會說」：soft 不擋。
    for (const [name, style, expected] of [["multi-hook.A.3", "extend", "玩過三年樂團 妳打鼓多久了"], ["family-fact.A.3", "humor", "下班只想睡 我妹聽了應該會說找到同類"]] as const) {
      const h2 = await harness();
      try {
        const fx = await captured(name);
        const sessionId = await capturedSession(h2, fx);
        h2.script.generate = fx.raw;
        const res = await handleOpenerGenerateRequest(h2.deps(generateBody(sessionId, GEN_1, fx.contribution)));
        assertEquals(res.status, 200, name);
        assertEquals(((await json(res)).openers as Record<string, string>)[style], expected, `${name} 逐字交付`);
        assertEquals(generateCalls(h2), 1, `${name} 沒有修正呼叫`);
      } finally {
        await h2.db.close();
      }
    }
  } finally {
    await h.db.close();
  }
});

Deno.test("第七輪 goal A1：捕獲 raw 想約沒邀約 → 想約是之後的目標，Free 與 paid 都直接交付、不送修正", async () => {
  // 2026-09-24 教練型 Opener 反轉原判（原為 Free 修正加邀約、paid 502）：這一則只開話題，想約不要求採用。
  const h = await harness();
  try {
    const fx = await captured("goal-not-consent.A.1");
    const sessionId = await capturedSession(h, fx);
    h.script.generate = fx.raw;
    h.script.correction = { openers: { extend: "一天三杯 找一天一起喝一杯看看？" } };
    const free = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, fx.contribution)));
    assertEquals(free.status, 200);
    const freeBody = await json(free);
    assertEquals((freeBody.openers as Record<string, string>).extend, "一天三杯 是提神還是純粹愛喝", "捕獲 raw 逐字交付");
    assertEquals((freeBody.recommendation as Record<string, unknown>).pick, "extend", "推薦維持模型第一名");
    assertEquals(generateCalls(h), 1, "Free 沒有修正呼叫");
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    await passOneMinute(h.db);
    h.tier = "essential";
    const paid = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, fx.contribution)));
    assertEquals(paid.status, 200);
    const paidOpeners = (await json(paid)).openers as Record<string, string>;
    assertEquals(Object.keys(paidOpeners).length, 5);
    assertEquals(paidOpeners.extend, "一天三杯 是提神還是純粹愛喝");
    assertEquals(generateCalls(h), 2, "paid 也沒有修正呼叫");
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "同局第二組不另扣");
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions WHERE session_id = $1`, [sessionId]);
    assertEquals(rows.rows[0].generations_used, 2);
  } finally {
    await h.db.close();
  }
});

Deno.test("第七輪 goal A1 話題型對照：捕獲 raw 沒接住想問的事 → Free 修正後交付；paid 另算一個情境，修正仍沒接住→502 不扣不計次", async () => {
  // 原測試 paid 分支的保護（修正仍失敗→502、不扣不計次、只一次修正）改用話題型補充重建。
  const h = await harness();
  try {
    const fx = await captured("goal-not-consent.A.1");
    const sessionId = await capturedSession(h, fx);
    const contribution = { ...fx.contribution, freeText: "想問她假日都去哪裡走走" };
    const raw = parseJsonObjectFromText(fx.raw)!;
    raw.materialReading = [useReading(contribution.freeText, "material_1")];
    h.script.generate = JSON.stringify(raw);
    h.script.correction = { openers: { extend: "假日都去哪裡走走？一天三杯應該也要配個好地方" }, cardReasons: { extend: "接住你想問的假日去處" }, materialUse: { references: [{ style: "extend", materialId: "material_1", outputSpan: "假日都去哪裡走走" }] } };
    const free = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, contribution)));
    assertEquals(free.status, 200);
    assertEquals(((await json(free)).openers as Record<string, string>).extend, "假日都去哪裡走走？一天三杯應該也要配個好地方");
    assertEquals(generateCalls(h), 2, "Free：生成＋一次修正");
    assertEquals(await usage(h.db), { m: 3, d: 3 });

    await passOneMinute(h.db);
    h.tier = "essential";
    h.script.correction = { openers: { extend: "一天三杯是咖啡因在續命還是興趣使然" } };
    const before = h.script.calls.length;
    const paid = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, contribution)));
    assertEquals(paid.status, 502, "paid 五卡仍沒接住→不交付");
    assertEquals((await json(paid)).code, "OPENER_CONTENT_CONFLICT");
    assertEquals(h.script.calls.length - before, 2);
    assertEquals(await usage(h.db), { m: 3, d: 3 }, "失敗不扣");
    const rows = await h.db.query<{ generations_used: number }>(`SELECT generations_used FROM public.opener_sessions WHERE session_id = $1`, [sessionId]);
    assertEquals(rows.rows[0].generations_used, 1);
  } finally {
    await h.db.close();
  }
});

Deno.test("C01/C02/C06: limiter infra failure blocks new work but completed replay stays readable", async () => {
  const h = await harness();
  try {
    const first = await analyzed(h);
    const real = supabaseFor(h.db);
    for (const throws of [false, true]) {
      const broken = { async rpc(fn: string, params: Record<string, unknown>) {
        if (fn === "increment_model_usage") {
          if (throws) throw new Error("connection lost");
          return { data: null, error: { message: "database unavailable" } };
        }
        return await real.rpc(fn, params);
      } };
      const before = h.script.calls.length;
      const replay = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { supabase: broken }));
      assertEquals(replay.status, 200);
      const blocked = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ analysisRequestId: GEN_4 }), { supabase: broken }));
      assertEquals(blocked.status, 503);
      assertEquals((await json(blocked)).code, "MODEL_RATE_LIMIT_UNAVAILABLE");
      const gen = await handleOpenerGenerateRequest(h.deps(generateBody(first.sessionId as string, GEN_1, CURIOUS), { supabase: broken }));
      assertEquals(gen.status, 503);
      assertEquals((await json(gen)).code, "MODEL_RATE_LIMIT_UNAVAILABLE");
      assertEquals(h.script.calls.length, before);
      assertEquals(await usage(h.db), { m: 0, d: 0 });
    }
    // Actual production SQL limits; a completed replay bypasses both.
    for (const [column, count] of [["minute_count", 3], ["day_count", 30]] as const) {
      await h.db.exec(`UPDATE public.model_call_rate_limits SET ${column} = ${count}`);
      const before = h.script.calls.length;
      const res = await handleOpenerAnalyzeRequest(h.deps(analyzeBody({ analysisRequestId: GEN_4 })));
      assertEquals(res.status, 429);
      assertEquals((await json(res)).code, "MODEL_RATE_LIMITED");
      assertEquals((await handleOpenerAnalyzeRequest(h.deps(analyzeBody()))).status, 200);
      assertEquals(h.script.calls.length, before);
      await passOneMinute(h.db);
    }
  } finally { await h.db.close(); }
});

Deno.test("C03/C05/C08: production invoker fallback leaves no fourth call for analysis repair", async () => {
  const h = await harness();
  const oldFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => Promise.resolve(++calls < 3
    ? new Response(null, { status: 503 })
    : Response.json({ content: [{ type: "text", text: "{}" }], usage: { input_tokens: 10, output_tokens: 5 } }));
  try {
    const response = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { invokeModel: undefined }));
    assertEquals(response.status, 502);
    assertEquals(calls, 3);
    assertEquals(await usage(h.db), { m: 0, d: 0 });
    const attempts = await h.db.query<{ day_count: number }>("SELECT day_count FROM public.model_call_rate_limits");
    assertEquals(attempts.rows[0].day_count, 1, "failed provider work retains limiter attempt");
  } finally { globalThis.fetch = oldFetch; await h.db.close(); }
});

Deno.test("主審反例：相鄰 use 的不想約她直接交付，不被改成正向邀約要求", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    h.script.generate = { ...GENERATE_JSON, materialReading: [{ ...useReading("我不想約她", "material_1"), usage: [{ quote: "我不想", action: "use" }, { quote: "約她", action: "use" }] }], materialUse: { references: [], displayNotes: {} } };
    h.script.correction = h.script.generate;
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: "我不想約她" })));
    assertEquals(response.status, 200);
    assertEquals(h.script.calls.length, 2, "分析一次、生成一次，不需要內容修正");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally { await h.db.close(); }
});

Deno.test("主審反例：拆單字 omit 的原句回流必須修正，仍未清除則不結算", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const text = "腿很長，想聊她的狗散步";
    const bad = { ...GENERATE_JSON,
      materialReading: [{ ...useReading(text, "material_1"), usage: [
        { quote: "腿", action: "omit", reason: "unsuitable_opener" },
        { quote: "很", action: "omit", reason: "unsuitable_opener" },
        { quote: "長", action: "omit", reason: "unsuitable_opener" },
        { quote: "想聊她的狗散步", action: "use" },
      ] }],
      openers: { ...GENERATE_JSON.openers, extend: "妳腿很長，牠散步會自己選路嗎" },
      materialUse: { references: [{ style: "extend", materialId: "material_1", outputSpan: "散步" }], displayNotes: {} },
    };
    h.script.generate = bad;
    h.script.correction = bad;
    const response = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text })));
    assertEquals(response.status, 502);
    assertEquals((await json(response)).code, "OPENER_CONTENT_CONFLICT");
    assertEquals(h.script.calls.length, 3, "只使用既有的一次內容修正");
    assert(String(h.script.calls[2].messages[0].content).includes("句子或說明帶回已略過的素材"));
    assertEquals(await usage(h.db), { m: 0, d: 0 });
  } finally { await h.db.close(); }
});

for (const surface of ["opener", "reason", "note"] as const) {
  Deno.test(`R3-P2-1：ASCII 分句回流 ${surface} 修正仍失敗時不結算`, async () => {
    const h = await harness();
    try {
      const analysis = await analyzed(h);
      const text = "腿很長. 幫我算一百乘三十";
      const bad = { ...GENERATE_JSON,
        materialReading: [omitReading(text)],
        openers: { ...GENERATE_JSON.openers, ...(surface === "opener" ? { extend: "妳腿很長，牠散步會自己選路嗎" } : {}) },
        cardReasons: { ...GENERATE_JSON.cardReasons, ...(surface === "reason" ? { extend: "直接接住腿很長的觀察" } : {}) },
        materialUse: { references: [], displayNotes: surface === "note" ? { extend: "這句接住你提到的腿很長" } : {} },
      };
      h.script.generate = bad;
      h.script.correction = bad;
      const response = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text })));
      assertEquals(response.status, 502);
      assertEquals((await json(response)).code, "OPENER_CONTENT_CONFLICT");
      assertEquals(h.script.calls.length, 3, "仍只允許既有的一次修正");
      assertEquals(await usage(h.db), { m: 0, d: 0 });
    } finally { await h.db.close(); }
  });
}

Deno.test("R3-P2-1：ASCII 分句回流修正成功後交付，重播不多扣", async () => {
  const h = await harness();
  try {
    const analysis = await analyzed(h);
    const text = "腿很長. 幫我算一百乘三十";
    const good = { ...GENERATE_JSON, materialReading: [omitReading(text)], materialUse: { references: [], displayNotes: {} } };
    h.script.generate = { ...good, openers: { ...good.openers, extend: "妳腿很長，牠散步會自己選路嗎" } };
    h.script.correction = good;
    const body = generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: text });
    const response = await handleOpenerGenerateRequest(h.deps(body));
    assertEquals(response.status, 200);
    assert(!JSON.stringify(await json(response)).includes("妳腿很長"));
    assertEquals(h.script.calls.length, 3, "分析、生成、一次修正");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    const replay = await handleOpenerGenerateRequest(h.deps(body));
    assertEquals(replay.status, 200);
    assertEquals(h.script.calls.length, 3);
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally { await h.db.close(); }
});

for (const secondField of ["reason", "note"] as const) {
  Deno.test(`R3-P2-2：opener 與 ${secondField} 分別合法，不跨欄位拼字誤擋`, async () => {
    const h = await harness();
    try {
      const analysis = await analyzed(h);
      h.script.generate = { ...GENERATE_JSON,
        materialReading: [omitReading("腿很長")],
        openers: { ...GENERATE_JSON.openers, extend: "旅行走久了，妳會不會先放鬆小腿？" },
        cardReasons: secondField === "reason" ? { extend: "很長的路線走完，聊放鬆方式比較好接。" } : {},
        materialUse: { references: [], displayNotes: secondField === "note" ? { extend: "很長的路線走完，聊放鬆方式比較好接。" } : {} },
      };
      h.script.correction = h.script.generate;
      const response = await handleOpenerGenerateRequest(h.deps(generateBody(String(analysis.sessionId), GEN_1, { state: "answered", freeText: "腿很長" })));
      assertEquals(response.status, 200);
      assertEquals(h.script.calls.length, 2, "分析、生成各一次，不增加內容修正");
      assertEquals(await usage(h.db), { m: 3, d: 3 });
    } finally { await h.db.close(); }
  });
}

// ── 結構刀（OPENER_PLAN_WRITE）：規劃→寫手→另外挑，claim／settle／扣費沿用正式路徑 ──

const PLAN_JSON = {
  spans: [{ quote: "想知道牠散步會不會自己選路", role: "question" }],
  anchorCueIds: ["cue_1"],
  herStated: ["有養一隻狗"],
  questionTarget: "牠散步會不會自己選路",
  questionKind: "what",
  intents: { shorter: false, funny: false },
  nominatedStyle: "extend",
};
const WRITE_JSON = {
  openers: {
    extend: "妳家狗散步會自己挑路線嗎？",
    resonate: "帶狗散步應該常被牠拉著走吧？",
    tease: "妳家狗是帶路派還是跟班派？",
    humor: "妳們散步是誰在遛誰？",
    coldRead: "假日去河堤，應該是牠最期待的時間？",
  },
  cardReasons: { extend: "直接問你好奇的散步習慣，她好回答" },
  pioneerPlan: { ifCold: "換問河堤", handoff: "她回兩三句就貼回分析" },
};

function planWriteInvoker(script: { calls: OpenerFlowModelRequest[]; plan?: unknown; write?: unknown; repair?: unknown }) {
  return (req: OpenerFlowModelRequest) => {
    script.calls.push(req);
    const body = req.system === OPENER_ANALYZE_PROMPT
      ? ANALYSIS_JSON
      : req.system === OPENER_PLAN_PROMPT
      ? script.plan ?? PLAN_JSON
      : req.purpose === "repair"
      ? script.repair ?? {}
      : script.write ?? WRITE_JSON;
    const rawText = JSON.stringify(body);
    req.onChunk?.(rawText);
    return Promise.resolve({ rawText, model: "claude-sonnet-5", inputTokens: 100, outputTokens: 50 });
  };
}

Deno.test("結構刀旗標：規劃＋寫手兩次呼叫、首次成功扣一次、重播不重扣也不再呼叫模型", async () => {
  const h = await harness();
  try {
    h.env.OPENER_PLAN_WRITE = "true";
    const script = { calls: [] as OpenerFlowModelRequest[] };
    const analysis = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { invokeModel: planWriteInvoker(script) }));
    const sessionId = String((await json(analysis)).sessionId);
    const request = generateBody(sessionId, GEN_1, { state: "answered", freeText: "沒養過，只想知道牠散步會不會自己選路" }, { openerCardSet: 2 });
    const response = await handleOpenerGenerateRequest(h.deps(request, { invokeModel: planWriteInvoker(script) }));
    assertEquals(response.status, 200);
    const body = await json(response);
    assertEquals(script.calls.map((c) => c.purpose ?? "analyze"), ["analyze", "plan", "write"]);
    assertEquals(Object.keys(body.openers as Record<string, unknown>).sort(), ["extend", "humor", "tease"], "Free 只拿可見卡");
    assertEquals((body.recommendation as Record<string, unknown>).pick, "extend");
    assertEquals((body.materialUse as Record<string, unknown>).traceStatus, "matched");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    const replay = await handleOpenerGenerateRequest(h.deps(request, { invokeModel: planWriteInvoker(script) }));
    assertEquals(replay.status, 200);
    assertEquals((await json(replay)).openers, body.openers);
    assertEquals(script.calls.length, 3);
    assertEquals(await usage(h.db), { m: 3, d: 3 });
    // 旗標關回舊路徑：已完成的結構刀結果仍可用同一筆請求重播（不卡 409、不再呼叫模型）。
    h.env.OPENER_PLAN_WRITE = "false";
    const back = await handleOpenerGenerateRequest(h.deps(request, { invokeModel: planWriteInvoker(script) }));
    assertEquals(back.status, 200);
    assertEquals((await json(back)).openers, body.openers);
    assertEquals(script.calls.length, 3);
  } finally { await h.db.close(); }
});

Deno.test("結構刀旗標：寫手缺卡且唯一修復仍缺 → 502 不扣費，規劃失敗不擋交付", async () => {
  const h = await harness();
  try {
    h.env.OPENER_PLAN_WRITE = "true";
    const partial = { openers: { extend: "妳家狗散步會自己挑路線嗎？" } };
    const script = { calls: [] as OpenerFlowModelRequest[], write: partial, repair: partial };
    const analysis = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { invokeModel: planWriteInvoker(script) }));
    const sessionId = String((await json(analysis)).sessionId);
    const failed = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, { state: "answered", freeText: "想聊牠" }, { openerCardSet: 2 }), { invokeModel: planWriteInvoker(script) }));
    assertEquals(failed.status, 502);
    assertEquals(await usage(h.db), { m: 0, d: 0 });
    assertEquals(script.calls.length, 4, "分析＋規劃＋寫手＋一次修復");
    await passOneMinute(h.db);
    const ok = { calls: [] as OpenerFlowModelRequest[], plan: "不是 JSON" };
    const recovered = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, { state: "answered", freeText: "想聊牠" }, { openerCardSet: 2 }), { invokeModel: planWriteInvoker(ok) }));
    assertEquals(recovered.status, 200);
    assertEquals(((await json(recovered)).materialUse as Record<string, unknown>).handlingNote, "這次沒讀到你的補充，先照她的資料寫。");
    assertEquals(await usage(h.db), { m: 3, d: 3 });
  } finally { await h.db.close(); }
});

Deno.test("結構刀旗標：走 production 預設呼叫器（不注入假模型），規劃與寫手各恰好送出一次請求", async () => {
  const h = await harness();
  const original = globalThis.fetch;
  const sent: Array<Record<string, unknown>> = [];
  try {
    h.env.OPENER_PLAN_WRITE = "true";
    const analysis = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { invokeModel: planWriteInvoker({ calls: [] }) }));
    const sessionId = String((await json(analysis)).sessionId);
    globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body ?? "{}"));
      sent.push(body);
      const system = Array.isArray(body.system) ? body.system.map((b: { text?: string }) => b.text ?? "").join("") : String(body.system ?? "");
      const payload = system === OPENER_PLAN_PROMPT ? PLAN_JSON : WRITE_JSON;
      void input;
      return Promise.resolve(new Response(JSON.stringify({
        id: "msg_test", type: "message", role: "assistant", model: body.model, stop_reason: "end_turn",
        content: [{ type: "text", text: JSON.stringify(payload) }],
        usage: { input_tokens: 100, output_tokens: 50, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
      }), { status: 200, headers: { "content-type": "application/json" } }));
    };
    const started = Date.now();
    const deps = h.deps(generateBody(sessionId, GEN_1, { state: "answered", freeText: "沒養過，只想知道牠散步會不會自己選路" }, { openerCardSet: 2 }));
    delete (deps as Partial<OpenerFlowHandlerDeps>).invokeModel;
    const response = await handleOpenerGenerateRequest(deps);
    assertEquals(response.status, 200);
    assertEquals(sent.length, 2, "規劃一次＋寫手一次");
    assert(Date.now() - started < 5000, "不空轉到規劃截止");
    assertEquals(sent.map((b) => b.model), ["claude-sonnet-5", "claude-sonnet-5"]);
    assertEquals(((await json(response)).materialUse as Record<string, unknown>).traceStatus, "matched", "規劃真的有跑（不是退只用她的資料）");
  } finally {
    globalThis.fetch = original;
    await h.db.close();
  }
});

Deno.test("結構刀旗標：新版 App 帶 openerCardSet=2 拿一句推薦＋四句備選並標 access.cardSet；舊版 App 旗標開了也走舊路徑", async () => {
  const h = await harness();
  try {
    h.env.OPENER_PLAN_WRITE = "true";
    const script = { calls: [] as OpenerFlowModelRequest[] };
    const analysis = await handleOpenerAnalyzeRequest(h.deps(analyzeBody(), { invokeModel: planWriteInvoker(script) }));
    const sessionId = String((await json(analysis)).sessionId);
    const contribution = { state: "answered", freeText: "沒養過，只想知道牠散步會不會自己選路" };
    const newApp = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_1, contribution, { openerCardSet: 2 }), { invokeModel: planWriteInvoker(script) }));
    assertEquals(newApp.status, 200);
    assertEquals(((await json(newApp)).access as Record<string, unknown>).cardSet, 2);
    assertEquals(script.calls.at(-1)?.system, buildOpenerWritePrompt("free"));
    await passOneMinute(h.db);
    // 舊版 App（不帶 openerCardSet）：旗標開了也走舊路徑（上線只影響新版 App），而且照常成功結算。
    const charged = await usage(h.db);
    const before = h.script.calls.length;
    h.script.generate = { ...GENERATE_JSON, materialReading: [] };
    const oldApp = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, { state: "skipped" })));
    assertEquals(oldApp.status, 200);
    const oldBody = await json(oldApp);
    assertEquals((oldBody.access as Record<string, unknown>).cardSet, undefined);
    assertEquals((oldBody.access as Record<string, unknown>).directions, undefined);
    assertEquals(h.script.calls.slice(before).map((c) => c.system), [OPENER_GENERATE_PROMPT], "只有舊路徑生成一次，不呼叫規劃與結構刀寫手");
    assertEquals((oldBody.usage as Record<string, unknown>).chargedNow, 0);
    assertEquals(await usage(h.db), charged, "同局後續生成不另扣費（舊路徑照常結算）");
  } finally { await h.db.close(); }
});
