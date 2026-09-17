// 兩段式 handler 端到端測試：正式 handler＋正式 RPC SQL（PGlite 真 Postgres）
// ＋正式原料整理／投影／結算；只有模型邊界是替身（附件 §五：不得 override
// 核心方法直接塞成功狀態）。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handleOpenerAnalyzeRequest,
  handleOpenerGenerateRequest,
  type OpenerFlowHandlerDeps,
  type OpenerFlowModelRequest,
} from "./opener_flow_handler.ts";
import { OPENER_ANALYZE_PROMPT, OPENER_FLOW_REPAIR_PROMPT, OPENER_GENERATE_PROMPT } from "./opener_flow_prompt.ts";

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

const GENERATE_JSON = {
  materialReading: [{ materialId: "material_1", subject: "sender", kind: "interest", certainty: "stated", quote: "有興趣" }],
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
    displayNote: "這句接的是你想知道的散步習慣",
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
    } else if (req.system === OPENER_FLOW_REPAIR_PROMPT) {
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

async function runCount(db: PGlite) {
  const rows = await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_generation_runs`);
  return rows.rows[0].n;
}

const CURIOUS = { state: "answered", questionId: "question_1", selectedOptionId: "option_2", freeText: "沒養過，只想知道牠散步會不會自己選路" };

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
    const rows = await h.db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_sessions`);
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
      const body = await json(await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, gen, { ...CURIOUS, freeText: `第 ${i} 版回答` }))));
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
    assert(h.script.calls.some((c) => c.system === OPENER_FLOW_REPAIR_PROMPT));
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
    const second = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, { ...CURIOUS, freeText: "第二版" })));
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
    assertEquals((await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_2, { ...CURIOUS, freeText: "二" })))).status, 200); // 第 3 次
    const limited = await handleOpenerGenerateRequest(h.deps(generateBody(sessionId, GEN_3, { ...CURIOUS, freeText: "三" }))); // 第 4 次／分鐘
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
