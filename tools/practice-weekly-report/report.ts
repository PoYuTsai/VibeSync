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
  assertRange,
  assertReadOnlySql,
  buildAiLogsSql,
  buildLogsSql,
  buildSessionsSql,
  type DateRange,
  type DayWindow,
  dayWindows,
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

/**
 * 認得的參數。分開列是為了「未知參數直接報錯」——第一次實跑就是把
 * `--out path`（空格式）打進只認 `--k=v` 的解析器，被靜默忽略後寫到預設路徑。
 * 現在兩種寫法都收，認不得的一律炸掉，不再有安靜的誤跑。
 */
const VALUE_FLAGS = [
  "project-ref",
  "from",
  "to",
  "out",
  "payers-starter",
  "payers-essential",
  "logs-limit",
] as const;
const BOOL_FLAGS = ["dry-run"] as const;

function readFlags(argv: string[]): Map<string, string> {
  const values = new Map<string, string>();
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      throw new Error(`unexpected argument: ${arg}`);
    }
    const eq = arg.indexOf("=");
    const name = eq === -1 ? arg.slice(2) : arg.slice(2, eq);
    if ((BOOL_FLAGS as readonly string[]).includes(name)) {
      values.set(name, eq === -1 ? "true" : arg.slice(eq + 1));
      continue;
    }
    if (!(VALUE_FLAGS as readonly string[]).includes(name)) {
      throw new Error(`unknown flag: --${name}`);
    }
    if (eq !== -1) {
      values.set(name, arg.slice(eq + 1));
      continue;
    }
    // `--out path` 空格式：吃下一個 token。
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      throw new Error(`missing value for --${name}`);
    }
    values.set(name, next);
    index += 1;
  }
  return values;
}

function count(values: Map<string, string>, name: string): number | undefined {
  const raw = values.get(name);
  if (raw === undefined) return undefined;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`invalid --${name}: ${raw}`);
  }
  return value;
}

export function parseArgs(argv: string[], now: Date = new Date()): CliOptions {
  const values = readFlags(argv);
  const fallback = defaultRange(now);
  const range: DateRange = {
    from: values.get("from") ?? fallback.from,
    to: values.get("to") ?? fallback.to,
  };
  assertRange(range);
  const starter = count(values, "payers-starter");
  const essential = count(values, "payers-essential");
  return {
    projectRef: values.get("project-ref") ??
      Deno.env.get("SUPABASE_PROJECT_REF"),
    range,
    out: values.get("out") ?? `docs/reports/${range.to}-practice-weekly.md`,
    dryRun: values.get("dry-run") === "true",
    logsLimit: count(values, "logs-limit") ?? DEFAULT_LOGS_LIMIT,
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

/**
 * Postgres 唯讀查詢。守門在**這裡**再叫一次（不是只靠 main）：任何呼叫端拿到
 * 這支函式都不可能繞過 `assertReadOnlySql`，而且是在 `fetch` 之前就丟錯——
 * 被擋下的語句一個位元組都不會離開這台機器。
 */
export async function fetchDbRows<T>(opts: {
  projectRef: string;
  token: string;
  sql: string;
  fetchImpl?: typeof fetch;
}): Promise<T[]> {
  assertReadOnlySql(opts.sql);
  const fetchImpl = opts.fetchImpl ?? fetch;
  const response = await fetchImpl(
    `https://api.supabase.com/v1/projects/${opts.projectRef}/database/query`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${opts.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query: opts.sql }),
    },
  );
  if (!response.ok) {
    throw new Error(
      `Management API ${response.status}: ${await response.text()}`,
    );
  }
  return await response.json() as T[];
}

/** 限流退避間隔（ms）：1s、2s、4s，共 3 次重試。 */
export const LOGS_BACKOFF_MS = [1000, 2000, 4000] as const;

/** 逐日呼叫之間的間隔（ms）。 */
export const LOGS_DAY_GAP_MS = 500;

export interface LogFetchResult {
  rows: LogRow[];
  /** 退避用完仍被限流的日子，報告會逐日印「未取得」。 */
  missingDays: string[];
}

function isThrottled(status: number, body: string): boolean {
  return status === 429 || body.includes("ThrottlerException");
}

/**
 * 逐日拉 function logs。
 *
 * 為什麼逐日：實跑證實同一條 SQL 帶 2 天窗回 11 筆、帶 7 天窗回 0 筆，範圍
 * 太大時端點直接回空而不報錯。時間窗只能走 query string，寫進 SQL 的 WHERE
 * 會讓結果變空。
 *
 * 限流（HTTP 429 或 body 帶 `ThrottlerException`）退避重試 1s／2s／4s；三次
 * 都不過就把那一天記進 `missingDays`——少一天資料要看得見，但不該讓整份報告
 * 失敗。其他 HTTP 錯誤照樣往上丟（那是真的壞了）。
 */
export async function fetchLogRows(opts: {
  projectRef: string;
  token: string;
  sql: string;
  windows: readonly DayWindow[];
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}): Promise<LogFetchResult> {
  assertReadOnlySql(opts.sql);
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ??
    ((ms: number) => new Promise<void>((done) => setTimeout(done, ms)));
  const rows: LogRow[] = [];
  const missingDays: string[] = [];

  for (const [index, window] of opts.windows.entries()) {
    if (index > 0) await sleep(LOGS_DAY_GAP_MS);
    for (let attempt = 0;; attempt += 1) {
      const response = await fetchImpl(
        logsEndpoint(opts.projectRef, opts.sql, window),
        { method: "GET", headers: { "Authorization": `Bearer ${opts.token}` } },
      );
      const body = await response.text();
      if (isThrottled(response.status, body)) {
        if (attempt < LOGS_BACKOFF_MS.length) {
          await sleep(LOGS_BACKOFF_MS[attempt]);
          continue;
        }
        missingDays.push(window.day);
        break;
      }
      if (!response.ok) {
        throw new Error(`Logs API ${response.status}: ${body}`);
      }
      const parsed = JSON.parse(body) as { result?: LogRow[] } | LogRow[];
      rows.push(...(Array.isArray(parsed) ? parsed : parsed.result ?? []));
      break;
    }
  }
  return { rows, missingDays };
}

async function main(): Promise<number> {
  const opts = parseArgs(Deno.args);
  const sessionsSql = buildSessionsSql(opts.range);
  const aiLogsSql = buildAiLogsSql(opts.range);
  const logsSql = buildLogsSql(opts.logsLimit);
  const windows = dayWindows(opts.range);

  if (opts.dryRun) {
    console.log(`-- sessions (${opts.range.from} ~ ${opts.range.to})`);
    console.log(sessionsSql);
    console.log("");
    console.log(`-- ai_logs (${opts.range.from} ~ ${opts.range.to})`);
    console.log(aiLogsSql);
    console.log("");
    console.log(
      `-- function logs：逐日 ${windows.length} 段，每段一次 GET，間隔 ${LOGS_DAY_GAP_MS}ms`,
    );
    console.log(
      "-- 時間窗走 query string，不寫進 SQL（寫進 WHERE 會回 0 筆）",
    );
    console.log(logsSql);
    for (const window of windows) {
      console.log(
        `-- ${window.day}: iso_timestamp_start=${window.isoStart}&iso_timestamp_end=${window.isoEnd}`,
      );
    }
    return 0;
  }

  if (!opts.projectRef) {
    console.error("缺 --project-ref（或 SUPABASE_PROJECT_REF）");
    return 2;
  }
  const token = await readAccessToken();
  const sessions = await fetchDbRows<SessionRow>({
    projectRef: opts.projectRef,
    token,
    sql: sessionsSql,
  });
  const aiLogs = await fetchDbRows<AiLogRow>({
    projectRef: opts.projectRef,
    token,
    sql: aiLogsSql,
  });
  const logs = await fetchLogRows({
    projectRef: opts.projectRef,
    token,
    sql: logsSql,
    windows,
  });
  if (logs.rows.length >= opts.logsLimit) {
    console.warn(
      `logs 回了 ${logs.rows.length} 列（撞到 --logs-limit），聊天那段可能被截斷`,
    );
  }
  if (logs.missingDays.length > 0) {
    console.warn(
      `logs 有 ${logs.missingDays.length} 天被限流擋掉，見報告涵蓋範圍`,
    );
  }

  const markdown = renderReport(
    aggregate({
      range: opts.range,
      sessions,
      aiLogs,
      payers: opts.payers,
      logs: aggregateLogs(logs.rows, logs.missingDays),
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
