// 結構刀評測共用：固定案例、語料用的四份她的資料、PGlite 會話資料庫、
// 攔截 fetch 記錄每一次 provider 請求與回應、成本計算。
//
// 原則（Dev Brain 坑：評測跑在非生產設定會讓結論作廢）：生成走真的 handler 與
// production 預設呼叫器（ModelCallBudget、fallback、thinking 契約都一樣），只把第一段
// 分析換成固定快照（不花錢、不引入分析變異）。評測只讀產品程式，不改。

import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { calculateCost } from "../../supabase/functions/analyze-chat/logger.ts";
import type { OpenerAnalysisSnapshot } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import { buildOpenerAnalysisSnapshot } from "../../supabase/functions/analyze-chat/opener_stage.ts";

export const EVAL_DIR = new URL(".", import.meta.url).pathname;
export const USER_ID = "11111111-2222-3333-4444-555555555555";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MIGRATIONS = [
  "20260702120000_increment_usage_atomic_quota.sql",
  "20260703170000_model_call_rate_limit.sql",
  "20260917120000_opener_two_stage_sessions.sql",
];

export interface EvalCase {
  id: string;
  domain: string | null;
  group: string | null;
  intentNote: string | null;
  profileInfo: Record<string, string>;
  initialUserNote?: string | null;
  contribution: { state: string; freeText: string | null; questionId?: string | null; selectedOptionId?: string | null };
  snapshot: { imageCount: number; profileDigest: string; cues: Array<Record<string, unknown>> };
}

export async function loadCases(): Promise<EvalCase[]> {
  return JSON.parse(await Deno.readTextFile(`${EVAL_DIR}cases.json`)).cases;
}

/** 語料配對的四份她的資料（corpus.json profileId）。 */
export const CORPUS_PROFILES: Record<string, { bio: string; cues: string[] }> = {
  P1: { bio: "平日做行銷，下班常去岩館抱石，最近卡在一條紫色路線好幾週。假日喜歡找巷子裡的滷味攤。", cues: ["抱石", "紫色路線", "滷味攤"] },
  P2: { bio: "在咖啡店上班，家裡有一隻橘貓叫胖丁，週末喜歡看恐怖片。", cues: ["咖啡店", "橘貓", "恐怖片"] },
  P3: { bio: "每週三次沿河夜跑，最近在準備第一場半馬。不聊工作。", cues: ["夜跑", "半馬"] },
  P4: { bio: "喜歡旅行 🌏", cues: ["旅行"] },
};

/** 第一段分析的固定輸出（與自然度評測 syntheticSnapshot 同一組法）。 */
export function analysisJsonFor(profileBio: string, snapshot: { profileDigest: string; cues: Array<Record<string, unknown>> }) {
  return {
    wrongSurface: null,
    profileDigest: snapshot.profileDigest ?? profileBio,
    approach: { mode: snapshot.cues.length ? "anchor_hooks" : "low_info", summary: "依可核對的資料與本次補充選題", avoid: [] },
    cues: snapshot.cues,
    question: null,
  };
}

export function corpusSnapshot(profileId: string): OpenerAnalysisSnapshot {
  const p = CORPUS_PROFILES[profileId];
  const cues = p.cues.map((quote, i) => ({ id: `cue_${i + 1}`, label: quote, source: "profile_text", evidence: { field: "bio", quote } }));
  const snapshot = buildOpenerAnalysisSnapshot({
    parsed: analysisJsonFor(p.bio, { profileDigest: p.bio, cues }),
    rawProfileInfo: { bio: p.bio },
    imageCount: 0,
    initialUserNote: null,
  });
  if (!snapshot) throw new Error(`invalid corpus snapshot ${profileId}`);
  return snapshot;
}

export async function createDatabase(): Promise<PGlite> {
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
  for (const name of MIGRATIONS) {
    await db.exec(await Deno.readTextFile(new URL(`../../supabase/migrations/${name}`, import.meta.url)));
  }
  await db.query(`INSERT INTO auth.users(id) VALUES ($1)`, [USER_ID]);
  await db.query(`INSERT INTO public.users(id) VALUES ($1)`, [USER_ID]);
  await db.query(`INSERT INTO public.subscriptions(user_id) VALUES ($1)`, [USER_ID]);
  return db;
}

/** supabase 替身（與 handler 測試同一份）：rpc 轉真 SQL，只讀兩張 opener 表。 */
export function supabaseFor(db: PGlite) {
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
        const cast = typeof value === "object" && value !== null ? "::jsonb"
          : typeof value === "number" ? "::integer"
          : typeof value === "boolean" ? "::boolean"
          : typeof value === "string" && UUID_RE.test(value) ? "::uuid"
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

export interface CapturedCall {
  model: string | null;
  maxTokens: number | null;
  thinking: unknown;
  temperature: unknown;
  system: string;
  user: string;
  status: number;
  rawText: string | null;
  stopReason: string | null;
  usage: Record<string, number> | null;
  costUsd: number | null;
  elapsedMs: number;
}

/**
 * 攔截送往 Anthropic 的 fetch：記下真正送出的請求（model、max_tokens、thinking、有沒有
 * temperature）與回應原文、usage、成本。不改請求內容。
 */
export function installFetchCapture(sink: CapturedCall[]): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = async (input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    if (!url.includes("api.anthropic.com")) return await original(input, init);
    const started = Date.now();
    let req: Record<string, unknown> = {};
    try { req = JSON.parse(String(init?.body ?? "{}")); } catch { /* 非 JSON 請求照原樣送 */ }
    const response = await original(input, init);
    const clone = response.clone();
    let body: Record<string, unknown> | null = null;
    try { body = await clone.json(); } catch { body = null; }
    const usage = (body?.usage ?? null) as Record<string, number> | null;
    const content = Array.isArray(body?.content) ? body!.content as Array<{ type?: string; text?: string }> : [];
    const model = typeof req.model === "string" ? req.model : null;
    const system = Array.isArray(req.system)
      ? (req.system as Array<{ text?: string }>).map((b) => b.text ?? "").join("")
      : String(req.system ?? "");
    const messages = Array.isArray(req.messages) ? req.messages as Array<{ content: unknown }> : [];
    sink.push({
      model,
      maxTokens: typeof req.max_tokens === "number" ? req.max_tokens : null,
      thinking: req.thinking ?? null,
      temperature: req.temperature ?? null,
      system,
      user: typeof messages[0]?.content === "string" ? messages[0].content as string : JSON.stringify(messages[0]?.content ?? ""),
      status: response.status,
      rawText: content.filter((b) => b.type === "text").map((b) => b.text ?? "").join("") || null,
      stopReason: typeof body?.stop_reason === "string" ? body.stop_reason as string : null,
      usage,
      costUsd: usage && model
        ? calculateCost(model, usage.input_tokens ?? 0, usage.output_tokens ?? 0, usage.cache_creation_input_tokens ?? 0, usage.cache_read_input_tokens ?? 0)
        : null,
      elapsedMs: Date.now() - started,
    });
    return response;
  };
  return () => { globalThis.fetch = original; };
}

export async function readApiKey(): Promise<string> {
  const key = (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`)).trim();
  if (!key.startsWith("sk-")) throw new Error("~/.config/anthropic/key does not look like an Anthropic key");
  return key;
}

export function uuidFor(prefix: string, n: number): string {
  const hex = (n >>> 0).toString(16).padStart(12, "0");
  return `${prefix}-0000-4000-8000-${hex}`;
}

export function parseArgs(args: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (const arg of args) {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(arg);
    if (m) out[m[1]] = m[2] ?? true;
  }
  return out;
}
