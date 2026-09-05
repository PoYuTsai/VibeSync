// 練習室週報（Phase 5 WP1）：唯讀拉 Supabase telemetry，輸出 markdown。
//
// 唯讀保證有三層：①只組 SELECT（sql.ts）②送出前每條語句過 `assertReadOnlySql`
// ③Management API 只呼叫 `/database/query`，不碰任何寫入端點。腳本絕不寫 DB。
//
// 跑法（詳見 README.md）：
//   deno run --allow-read --allow-write --allow-env \
//     --allow-net=api.supabase.com tools/practice-weekly-report/report.ts \
//     --project-ref=<ref> [--from=YYYY-MM-DD] [--to=YYYY-MM-DD] \
//     [--out=docs/reports/<to>-practice-weekly.md] \
//     [--payers-starter=N --payers-essential=N] [--dry-run]

import {
  aggregate,
  aggregateLogs,
  type AiLogRow,
  type LogRow,
  type SessionRow,
} from "./aggregate.ts";
import { renderReport } from "./render.ts";
import {
  assertReadOnlySql,
  buildAiLogsSql,
  buildLogsSql,
  buildSessionsSql,
  type DateRange,
  defaultRange,
  logsEndpoint,
} from "./sql.ts";

/** Logs Explorer 單次查詢的列數上限。 */
export const DEFAULT_LOGS_LIMIT = 10000;

export interface CliOptions {
  projectRef: string | undefined;
  range: DateRange;
  out: string;
  dryRun: boolean;
  payers?: { starter: number; essential: number };
  /** function logs 一次最多抓幾列（撞到就代表被截斷，報告會印出來）。 */
  logsLimit: number;
}

function flag(argv: string[], name: string): string | undefined {
  return argv.find((arg) => arg.startsWith(`--${name}=`))?.slice(
    name.length + 3,
  );
}

function count(argv: string[], name: string): number | undefined {
  const raw = flag(argv, name);
  if (raw === undefined) return undefined;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`invalid --${name}: ${raw}`);
  }
  return Math.floor(value);
}

export function parseArgs(argv: string[], now: Date = new Date()): CliOptions {
  const fallback = defaultRange(now);
  const range: DateRange = {
    from: flag(argv, "from") ?? fallback.from,
    to: flag(argv, "to") ?? fallback.to,
  };
  const starter = count(argv, "payers-starter");
  const essential = count(argv, "payers-essential");
  return {
    projectRef: flag(argv, "project-ref") ??
      Deno.env.get("SUPABASE_PROJECT_REF"),
    range,
    out: flag(argv, "out") ??
      `docs/reports/${range.to}-practice-weekly.md`,
    dryRun: argv.includes("--dry-run"),
    logsLimit: count(argv, "logs-limit") ?? DEFAULT_LOGS_LIMIT,
    payers: starter === undefined && essential === undefined
      ? undefined
      : { starter: starter ?? 0, essential: essential ?? 0 },
  };
}

/** Bearer token：env 優先，其次 `~/.supabase/access-token`。 */
async function readAccessToken(): Promise<string> {
  const fromEnv = Deno.env.get("SUPABASE_ACCESS_TOKEN")?.trim();
  if (fromEnv) return fromEnv;
  const home = Deno.env.get("HOME") ?? Deno.env.get("USERPROFILE");
  if (home) {
    try {
      const file = await Deno.readTextFile(`${home}/.supabase/access-token`);
      const token = file.trim();
      if (token) return token;
    } catch {
      // 落到下面統一報錯，不洩漏路徑以外的資訊。
    }
  }
  throw new Error(
    "找不到 access token：設 SUPABASE_ACCESS_TOKEN 或放進 ~/.supabase/access-token",
  );
}

async function runQuery<T>(
  projectRef: string,
  token: string,
  sql: string,
): Promise<T[]> {
  assertReadOnlySql(sql);
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${projectRef}/database/query`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query: sql }),
    },
  );
  if (!response.ok) {
    throw new Error(
      `Management API ${response.status}: ${await response.text()}`,
    );
  }
  return await response.json() as T[];
}

/**
 * Logs Explorer 是 GET＋query string（跟 `/database/query` 不同端點），回傳
 * `{ result: [...] }`。查不到列不是錯誤——保留期把時間窗吃掉時就是 0 筆，
 * 報告會用涵蓋範圍把這件事印出來。
 */
async function runLogsQuery(
  projectRef: string,
  token: string,
  sql: string,
): Promise<LogRow[]> {
  assertReadOnlySql(sql);
  const response = await fetch(logsEndpoint(projectRef, sql), {
    method: "GET",
    headers: { "Authorization": `Bearer ${token}` },
  });
  if (!response.ok) {
    throw new Error(
      `Logs API ${response.status}: ${await response.text()}`,
    );
  }
  const body = await response.json() as { result?: LogRow[] } | LogRow[];
  return Array.isArray(body) ? body : body.result ?? [];
}

async function main(): Promise<number> {
  const opts = parseArgs(Deno.args);
  const sessionsSql = buildSessionsSql(opts.range);
  const aiLogsSql = buildAiLogsSql(opts.range);
  const logsSql = buildLogsSql(opts.range, opts.logsLimit);

  if (opts.dryRun) {
    console.log(`-- sessions (${opts.range.from} ~ ${opts.range.to})`);
    console.log(sessionsSql);
    console.log("");
    console.log(`-- ai_logs (${opts.range.from} ~ ${opts.range.to})`);
    console.log(aiLogsSql);
    console.log("");
    console.log(`-- function logs (${opts.range.from} ~ ${opts.range.to})`);
    console.log(logsSql);
    return 0;
  }

  if (!opts.projectRef) {
    console.error("缺 --project-ref（或 SUPABASE_PROJECT_REF）");
    return 2;
  }
  const token = await readAccessToken();
  const sessions = await runQuery<SessionRow>(
    opts.projectRef,
    token,
    sessionsSql,
  );
  const aiLogs = await runQuery<AiLogRow>(opts.projectRef, token, aiLogsSql);
  const logRows = await runLogsQuery(opts.projectRef, token, logsSql);
  if (logRows.length >= opts.logsLimit) {
    console.warn(
      `logs 回了 ${logRows.length} 列（撞到 --logs-limit），聊天那段可能被截斷`,
    );
  }

  const markdown = renderReport(
    aggregate({
      range: opts.range,
      sessions,
      aiLogs,
      payers: opts.payers,
      logs: aggregateLogs(logRows),
    }),
  );
  await Deno.writeTextFile(opts.out, markdown);
  console.log(`已輸出 ${opts.out}`);
  return 0;
}

if (import.meta.main) {
  try {
    Deno.exit(await main());
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
