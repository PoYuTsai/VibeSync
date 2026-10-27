// 每週 cohort 報表（Onboarding 第 8 步）：唯讀查 Supabase，輸出 markdown。
//
// 唯讀保證跟練習室週報同一套：①只組 SELECT（sql.ts）②送出前每條語句再過一次
// `assertReadOnlySql`（沿用 tools/practice-weekly-report 的 `fetchDbRows`，它在
// fetch 之前自己叫）③只呼叫 Management API 的 `/database/query`。腳本絕不寫 DB。
// **第一次真跑要 Eric 另外核准。** 週報只寫到 repo 以外（repo 是公開的，見
// out_path.ts），再由 agent 經 Brain Publisher 收進 Dev Brain。欄位定義、讀法、
// 存檔見 docs/integrations/weekly-cohort-report.md。
//
// 跑法：
//   # 只印 SQL：不打網路、不需要 token、不落檔
//   deno run --allow-env tools/weekly-cohort-report/report.ts --dry-run
//
//   deno run --allow-read --allow-write --allow-env \
//     --allow-net=api.supabase.com tools/weekly-cohort-report/report.ts \
//     --project-ref=<ref> [--week=2026-W43] [--weeks=6] \
//     [--out=<repo 以外的路徑，預設 ~/vibesync-weekly-cohort/<週>.md>]

import { fetchDbRows } from "../practice-weekly-report/report.ts";
import {
  assertOutsideRepo,
  defaultOutContext,
  type OutPathContext,
  resolveOutPath,
  writeOutsideRepo,
} from "./out_path.ts";
import { type CohortResult, parseCohortRow, renderReport } from "./render.ts";
import {
  buildCohortSql,
  type CohortWeek,
  lastCompleteWeek,
  parseIsoWeek,
  weeksEndingAt,
} from "./sql.ts";

/** 預設一次查 6 週：最舊那週的 D30 剛好走完（週報每週跑一次時）。 */
export const DEFAULT_WEEKS = 6;
/** 一週一次查詢；上限擋掉手滑打成幾百週。 */
export const MAX_WEEKS = 12;

export interface CliOptions {
  projectRef: string | undefined;
  /** 報表裡最新的那個註冊週。 */
  latest: CohortWeek;
  weeks: number;
  /** 絕對路徑，一定在 repo 以外。 */
  out: string;
  dryRun: boolean;
}

/** 認得的參數；認不得的、孤立的字串、缺值一律報錯（照練習室週報的教訓）。 */
const VALUE_FLAGS = ["project-ref", "week", "weeks", "out"] as const;
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
    // `--week 2026-W43` 空格式：吃下一個 token。
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      throw new Error(`missing value for --${name}`);
    }
    values.set(name, next);
    index += 1;
  }
  return values;
}

export function parseArgs(
  argv: string[],
  now: Date = new Date(),
  outContext: OutPathContext = defaultOutContext(),
): CliOptions {
  const values = readFlags(argv);
  const week = values.get("week");
  const latest = week === undefined
    ? lastCompleteWeek(now)
    : parseIsoWeek(week);
  // 還沒結束的週，新帳號數本身就不完整；寧可報錯也不要產一份看起來像真的半週報。
  if (Date.parse(`${latest.end}T00:00:00Z`) > now.getTime()) {
    throw new Error(
      `invalid_week: ${latest.label} 還沒結束（${latest.end} 00:00 UTC 之後才完整）`,
    );
  }
  const rawWeeks = values.get("weeks");
  const weeks = rawWeeks === undefined ? DEFAULT_WEEKS : Number(rawWeeks);
  if (!Number.isInteger(weeks) || weeks < 1 || weeks > MAX_WEEKS) {
    throw new Error(`invalid --weeks: ${rawWeeks}（1～${MAX_WEEKS}）`);
  }
  return {
    projectRef: values.get("project-ref") ??
      Deno.env.get("SUPABASE_PROJECT_REF"),
    latest,
    weeks,
    out: resolveOutPath(values.get("out"), latest, outContext),
    dryRun: values.get("dry-run") === "true",
  };
}

/** Bearer token：env 優先，其次 `~/.supabase/access-token`（跟練習室週報一樣）。 */
async function readAccessToken(): Promise<string> {
  const fromEnv = Deno.env.get("SUPABASE_ACCESS_TOKEN")?.trim();
  if (fromEnv) return fromEnv;
  const home = Deno.env.get("HOME") ?? Deno.env.get("USERPROFILE");
  if (home) {
    try {
      const token = (await Deno.readTextFile(`${home}/.supabase/access-token`))
        .trim();
      if (token) return token;
    } catch {
      // 落到下面統一報錯。
    }
  }
  throw new Error(
    "找不到 access token：設 SUPABASE_ACCESS_TOKEN 或放進 ~/.supabase/access-token",
  );
}

/**
 * 一週一條查詢，照週的順序送。每條都剛好回一列（整條 SQL 是一個聚合）；
 * 回零列、多列或欄位壞掉都直接報錯，不要把它印成 0。
 */
export async function fetchCohort(opts: {
  projectRef: string;
  token: string;
  weeks: readonly CohortWeek[];
  fetchImpl?: typeof fetch;
}): Promise<CohortResult[]> {
  const results: CohortResult[] = [];
  for (const week of opts.weeks) {
    const rows = await fetchDbRows<unknown>({
      projectRef: opts.projectRef,
      token: opts.token,
      sql: buildCohortSql(week),
      fetchImpl: opts.fetchImpl,
    });
    if (!Array.isArray(rows) || rows.length !== 1) {
      throw new Error(
        `unexpected_result: ${week.label} 應該剛好一列，拿到 ${
          Array.isArray(rows) ? `${rows.length} 列` : typeof rows
        }`,
      );
    }
    results.push({ week, row: parseCohortRow(rows[0]) });
  }
  return results;
}

/** 真跑的寫檔：寫檔前再用真實路徑確認在 repo 以外（見 out_path.ts）。 */
async function writeReportFile(path: string, text: string): Promise<void> {
  await writeOutsideRepo(path, text);
}

/** 可注入的外部依賴：測試用假的 fetch／token／寫檔，不碰網路也不碰檔案。 */
export interface RunDeps {
  /** 查詢時間：決定每格是「未滿」「紀錄已清」還是數字。 */
  now: Date;
  fetchImpl?: typeof fetch;
  readToken?: () => Promise<string>;
  writeFile?: (path: string, text: string) => Promise<void>;
  log?: (line: string) => void;
}

export async function runReport(
  opts: CliOptions,
  deps: RunDeps,
): Promise<number> {
  const log = deps.log ?? console.log;
  // parseArgs 已經擋過；這裡在讀 token、打網路、寫檔之前再擋一次，
  // 不是從 parseArgs 來的 CliOptions 也繞不過去。之後一律用檢查過的正規化路徑。
  const out = assertOutsideRepo(opts.out, defaultOutContext());
  const weeks = weeksEndingAt(opts.latest, opts.weeks);

  if (opts.dryRun) {
    for (const week of weeks) {
      log(`-- ${week.label}：${week.start} ～ ${week.end}（UTC，含頭不含尾）`);
      log(buildCohortSql(week));
      log("");
    }
    log(
      `-- 真跑會寫到 ${out}（repo 以外；之後由 agent 經 Brain Publisher 收進 Dev Brain）`,
    );
    return 0;
  }

  if (!opts.projectRef) {
    console.error("缺 --project-ref（或 SUPABASE_PROJECT_REF）");
    return 2;
  }
  const token = await (deps.readToken ?? readAccessToken)();
  const results = await fetchCohort({
    projectRef: opts.projectRef,
    token,
    weeks,
    fetchImpl: deps.fetchImpl,
  });
  await (deps.writeFile ?? writeReportFile)(
    out,
    renderReport({ asOf: deps.now, results }),
  );
  log(
    `已輸出 ${out}（不要 commit 進 repo；由 agent 經 Brain Publisher 收進 Dev Brain）`,
  );
  return 0;
}

if (import.meta.main) {
  try {
    const now = new Date();
    Deno.exit(await runReport(parseArgs(Deno.args, now), { now }));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
