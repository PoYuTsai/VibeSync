import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { assertReadOnlySql } from "../practice-weekly-report/sql.ts";
import { COHORT_COLUMNS } from "./render.ts";
import {
  type CliOptions,
  DEFAULT_WEEKS,
  fetchCohort,
  parseArgs,
  runReport,
} from "./report.ts";
import { buildCohortSql, parseIsoWeek, weeksEndingAt } from "./sql.ts";

// 2026-10-27（週二）：上一個完整的週是 2026-W43。
const NOW = new Date("2026-10-27T05:00:00Z");
const FAKE_TOKEN = "fake-token-for-tests";

function row(newAccounts: number): Record<string, number> {
  return Object.fromEntries(
    COHORT_COLUMNS.map((column) => [
      column,
      column === "new_accounts" ? newAccounts : 0,
    ]),
  );
}

interface Captured {
  url: string;
  method: string | undefined;
  authorization: string | null;
  query: string;
}

/** 假的 Management API：照順序回 `bodies`，並記下每一次請求。 */
function fakeFetch(bodies: string[], captured: Captured[], status = 200) {
  return ((input: string | URL, init?: RequestInit) => {
    captured.push({
      url: String(input),
      method: init?.method,
      authorization: new Headers(init?.headers).get("Authorization"),
      query: JSON.parse(String(init?.body)).query,
    });
    const body = bodies[captured.length - 1] ?? "[]";
    return Promise.resolve(new Response(body, { status }));
  }) as unknown as typeof fetch;
}

Deno.test("parseArgs 預設：上一個完整的週、往回 6 週、寫進 docs/reports/weekly-cohort/", () => {
  const opts = parseArgs(["--project-ref=abcdef"], NOW);
  assertEquals(opts.projectRef, "abcdef");
  assertEquals(opts.latest.label, "2026-W43");
  assertEquals(opts.weeks, DEFAULT_WEEKS);
  assertEquals(opts.out, "docs/reports/weekly-cohort/2026-W43.md");
  assertEquals(opts.dryRun, false);
});

Deno.test("parseArgs：--k=v 與 --k v 都收", () => {
  const opts = parseArgs(
    [
      "--week",
      "2026-W40",
      "--weeks=3",
      "--out",
      "docs/reports/weekly-cohort/manual.md",
      "--dry-run",
    ],
    NOW,
  );
  assertEquals(opts.latest.label, "2026-W40");
  assertEquals(opts.weeks, 3);
  assertEquals(opts.out, "docs/reports/weekly-cohort/manual.md");
  assertEquals(opts.dryRun, true);
});

Deno.test("parseArgs：還沒結束的週、不存在的週、--weeks 超出範圍都報錯", () => {
  assertThrows(() => parseArgs(["--week=2026-W44"], NOW), Error, "還沒結束");
  assertThrows(() => parseArgs(["--week=2027-W10"], NOW), Error, "還沒結束");
  assertThrows(
    () => parseArgs(["--week=2027-W53"], NOW),
    Error,
    "invalid_week",
  );
  for (const weeks of ["0", "13", "1.5", "abc", ""]) {
    assertThrows(
      () => parseArgs([`--weeks=${weeks}`], NOW),
      Error,
      "invalid --weeks",
      weeks,
    );
  }
});

Deno.test("parseArgs：未知參數、孤立字串、缺值一律報錯不靜默", () => {
  assertThrows(
    () => parseArgs(["--from=2026-10-19"], NOW),
    Error,
    "unknown flag",
  );
  assertThrows(() => parseArgs(["stray"], NOW), Error, "unexpected argument");
  assertThrows(() => parseArgs(["--week"], NOW), Error, "missing value");
  assertThrows(
    () => parseArgs(["--out", "--dry-run"], NOW),
    Error,
    "missing value",
  );
});

Deno.test("parseArgs：--out 預設只能寫進 docs/reports/，.. 永遠擋", () => {
  assertThrows(
    () => parseArgs(["--out=lib/x.md"], NOW),
    Error,
    "invalid --out",
  );
  assertThrows(
    () => parseArgs(["--out=docs/reports/../../x.md"], NOW),
    Error,
    "路徑穿越",
  );
  assertEquals(
    parseArgs(["--out=/tmp/scratch/x.md", "--allow-out-anywhere"], NOW).out,
    "/tmp/scratch/x.md",
  );
});

Deno.test("fetchCohort：一週一次 POST /database/query，送的就是 buildCohortSql，照週的順序收", async () => {
  const weeks = weeksEndingAt(parseIsoWeek("2026-W43"), 3);
  const captured: Captured[] = [];
  const results = await fetchCohort({
    projectRef: "myref",
    token: FAKE_TOKEN,
    weeks,
    // 第二週的 int8 回成字串也要收。
    fetchImpl: fakeFetch(
      [
        JSON.stringify([row(4)]),
        JSON.stringify([{ ...row(0), new_accounts: "7" }]),
        JSON.stringify([row(9)]),
      ],
      captured,
    ),
  });
  assertEquals(captured.length, 3);
  captured.forEach((call, index) => {
    assertEquals(
      call.url,
      "https://api.supabase.com/v1/projects/myref/database/query",
    );
    assertEquals(call.method, "POST");
    assertEquals(call.authorization, `Bearer ${FAKE_TOKEN}`);
    assertEquals(call.query, buildCohortSql(weeks[index]));
    assertReadOnlySql(call.query);
  });
  assertEquals(
    results.map((result) => [result.week.label, result.row.new_accounts]),
    [["2026-W41", 4], ["2026-W42", 7], ["2026-W43", 9]],
  );
});

Deno.test("fetchCohort：HTTP 錯誤、零列、多列、欄位壞掉都報錯，不印成 0", async () => {
  const weeks = [parseIsoWeek("2026-W43")];
  await assertRejects(
    () =>
      fetchCohort({
        projectRef: "ref",
        token: FAKE_TOKEN,
        weeks,
        fetchImpl: fakeFetch(["boom"], [], 500),
      }),
    Error,
    "Management API 500",
  );
  for (
    const body of ["[]", JSON.stringify([row(1), row(2)]), '{"rows":[]}']
  ) {
    await assertRejects(
      () =>
        fetchCohort({
          projectRef: "ref",
          token: FAKE_TOKEN,
          weeks,
          fetchImpl: fakeFetch([body], []),
        }),
      Error,
      "unexpected_result",
      body,
    );
  }
  await assertRejects(
    () =>
      fetchCohort({
        projectRef: "ref",
        token: FAKE_TOKEN,
        weeks,
        fetchImpl: fakeFetch(
          [JSON.stringify([{ ...row(1), paid_d7: "n/a" }])],
          [],
        ),
      }),
    Error,
    "unexpected_row",
  );
});

function options(overrides: Partial<CliOptions> = {}): CliOptions {
  return {
    ...parseArgs(["--project-ref=myref", "--weeks=2"], NOW),
    ...overrides,
  };
}

Deno.test("runReport：假的 fetch 跑完整條路，寫出報表、token 不進報表", async () => {
  const captured: Captured[] = [];
  const written: Array<{ path: string; text: string }> = [];
  const logs: string[] = [];
  const code = await runReport(options(), {
    now: NOW,
    fetchImpl: fakeFetch(
      [JSON.stringify([row(3)]), JSON.stringify([row(5)])],
      captured,
    ),
    readToken: () => Promise.resolve(FAKE_TOKEN),
    writeFile: (path, text) => {
      written.push({ path, text });
      return Promise.resolve();
    },
    log: (line) => logs.push(line),
  });
  assertEquals(code, 0);
  assertEquals(captured.length, 2);
  assertEquals(written.length, 1);
  assertEquals(written[0].path, "docs/reports/weekly-cohort/2026-W43.md");
  assertStringIncludes(written[0].text, "# 每週 cohort 報表 2026-W43");
  assertStringIncludes(written[0].text, "| 2026-W42（10-12～10-18） | 3 |");
  assertStringIncludes(written[0].text, "| 2026-W43（10-19～10-25） | 5 |");
  assertEquals(written[0].text.includes(FAKE_TOKEN), false);
  assertEquals(logs.join("\n").includes(FAKE_TOKEN), false);
  assertEquals(logs, ["已輸出 docs/reports/weekly-cohort/2026-W43.md"]);
});

Deno.test("runReport --dry-run：只印 SQL，不讀 token、不打網路、不寫檔", async () => {
  const logs: string[] = [];
  const untouchable = () => {
    throw new Error("dry-run 不該碰到這裡");
  };
  const code = await runReport(options({ dryRun: true }), {
    now: NOW,
    fetchImpl: untouchable as unknown as typeof fetch,
    readToken: untouchable,
    writeFile: untouchable,
    log: (line) => logs.push(line),
  });
  assertEquals(code, 0);
  const out = logs.join("\n");
  assertStringIncludes(out, "-- 2026-W42：2026-10-12 ～ 2026-10-19");
  assertStringIncludes(out, buildCohortSql(parseIsoWeek("2026-W43")));
  assertStringIncludes(out, "docs/reports/weekly-cohort/2026-W43.md");
});

Deno.test("runReport：沒有 project ref 就停在送出前（不讀 token、不打網路）", async () => {
  let touched = false;
  const code = await runReport(options({ projectRef: undefined }), {
    now: NOW,
    fetchImpl: (() => {
      touched = true;
      return Promise.reject(new Error("不該打網路"));
    }) as unknown as typeof fetch,
    readToken: () => {
      touched = true;
      return Promise.resolve(FAKE_TOKEN);
    },
    writeFile: () => {
      touched = true;
      return Promise.resolve();
    },
    log: () => {},
  });
  assertEquals(code, 2);
  assertEquals(touched, false);
});

Deno.test("CLI --dry-run：子程序離線跑（--cached-only），只要 env 權限、不需要 token", async () => {
  const command = new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "--cached-only",
      "--allow-env",
      new URL("./report.ts", import.meta.url).pathname,
      "--dry-run",
      "--week=2026-W40",
      "--weeks=2",
    ],
    env: {
      SUPABASE_ACCESS_TOKEN: "",
      SUPABASE_PROJECT_REF: "",
      HOME: "/nonexistent",
    },
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await command.output();
  const out = new TextDecoder().decode(stdout);
  assertEquals(code, 0, new TextDecoder().decode(stderr));
  assertStringIncludes(out, "-- 2026-W39：2026-09-21 ～ 2026-09-28");
  assertStringIncludes(out, "-- 2026-W40：2026-09-28 ～ 2026-10-05");
  assertStringIncludes(out, "SELECT * FROM (\nwith cohort as (");
  assertEquals(out.toLowerCase().includes("bearer"), false);
});
