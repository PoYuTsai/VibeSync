import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { assertReadOnlySql } from "../practice-weekly-report/sql.ts";
import { type OutPathContext, REPO_ROOT } from "./out_path.ts";
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
// 假的路徑：repo 在 /work/VibeSync、家目錄在 /home/tester、目前目錄是 repo 根。
const OUT_CTX: OutPathContext = {
  repoRoot: "/work/VibeSync",
  home: "/home/tester",
  cwd: () => "/work/VibeSync",
};
const DEFAULT_OUT = "/home/tester/vibesync-weekly-cohort/2026-W43.md";

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

Deno.test("parseArgs 預設：上一個完整的週、往回 6 週、寫到家目錄底下（repo 以外）", () => {
  const opts = parseArgs(["--project-ref=abcdef"], NOW, OUT_CTX);
  assertEquals(opts.projectRef, "abcdef");
  assertEquals(opts.latest.label, "2026-W43");
  assertEquals(opts.weeks, DEFAULT_WEEKS);
  assertEquals(opts.out, DEFAULT_OUT);
  assertEquals(opts.dryRun, false);
});

Deno.test("parseArgs：--k=v 與 --k v 都收", () => {
  const opts = parseArgs(
    [
      "--week",
      "2026-W40",
      "--weeks=3",
      "--out",
      "/home/tester/notes/manual.md",
      "--dry-run",
    ],
    NOW,
    OUT_CTX,
  );
  assertEquals(opts.latest.label, "2026-W40");
  assertEquals(opts.weeks, 3);
  assertEquals(opts.out, "/home/tester/notes/manual.md");
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

Deno.test("parseArgs：--out 指到 repo 裡面（含 docs/）就拒絕並說明原因；沒有逃生口", () => {
  for (
    const out of [
      "docs/reports/weekly-cohort/2026-W43.md",
      "docs/integrations/x.md",
      "/work/VibeSync/docs/x.md",
    ]
  ) {
    const error = assertThrows(
      () => parseArgs([`--out=${out}`], NOW, OUT_CTX),
      Error,
      "在 repo 裡面",
      out,
    );
    assertStringIncludes(error.message, "repo 是公開的");
  }
  // 舊的 --allow-out-anywhere 拿掉了：週報沒有任何寫進 repo 的路。
  assertThrows(
    () => parseArgs(["--allow-out-anywhere"], NOW, OUT_CTX),
    Error,
    "unknown flag",
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
    ...parseArgs(["--project-ref=myref", "--weeks=2"], NOW, OUT_CTX),
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
  assertEquals(written[0].path, DEFAULT_OUT);
  assertStringIncludes(written[0].text, "# 每週 cohort 報表 2026-W43");
  assertStringIncludes(written[0].text, "| 2026-W42（10-12～10-18） | 3 |");
  assertStringIncludes(written[0].text, "| 2026-W43（10-19～10-25） | 5 |");
  assertEquals(written[0].text.includes(FAKE_TOKEN), false);
  assertEquals(logs.join("\n").includes(FAKE_TOKEN), false);
  assertEquals(logs.length, 1);
  assertStringIncludes(logs[0], `已輸出 ${DEFAULT_OUT}`);
  assertStringIncludes(logs[0], "不要 commit 進 repo");
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
  assertStringIncludes(out, `-- 真跑會寫到 ${DEFAULT_OUT}（repo 以外`);
});

Deno.test("runReport 再擋一次：out 指到這個 repo 裡面就停，不讀 token、不打網路、不寫檔", async () => {
  let touched = false;
  const touch = () => {
    touched = true;
    return Promise.resolve(FAKE_TOKEN);
  };
  const touchWrite = (_path: string, _text: string) => {
    touched = true;
    return Promise.resolve();
  };
  for (const dryRun of [false, true]) {
    await assertRejects(
      () =>
        runReport(options({ out: `${REPO_ROOT}docs/reports/x.md`, dryRun }), {
          now: NOW,
          fetchImpl: touch as unknown as typeof fetch,
          readToken: touch,
          writeFile: touchWrite,
          log: () => {},
        }),
      Error,
      "在 repo 裡面",
    );
  }
  assertEquals(touched, false);
});

Deno.test({
  name:
    "runReport 再擋一次：Linux 上 out 是 C:\\temp\\cohort.md 這種 Windows 路徑就停（Codex 主審第 1 輪 P2）",
  ignore: Deno.build.os === "windows", // Windows 上這是合法的絕對路徑
  fn: async () => {
    let touched = false;
    const touch = () => {
      touched = true;
      return Promise.resolve(FAKE_TOKEN);
    };
    const touchWrite = (_path: string, _text: string) => {
      touched = true;
      return Promise.resolve();
    };
    for (const out of ["C:\\temp\\cohort.md", "\\\\server\\share\\x.md"]) {
      await assertRejects(
        () =>
          runReport(options({ out }), {
            now: NOW,
            fetchImpl: touch as unknown as typeof fetch,
            readToken: touch,
            writeFile: touchWrite,
            log: () => {},
          }),
        Error,
        "看起來是 Windows 路徑",
        out,
      );
    }
    assertEquals(touched, false);
  },
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
  // 預設路徑在家目錄底下，不在 repo 裡。
  assertStringIncludes(
    out,
    "-- 真跑會寫到 /nonexistent/vibesync-weekly-cohort/2026-W40.md",
  );
  assertEquals(out.toLowerCase().includes("bearer"), false);
});

Deno.test("CLI：在 repo 根目錄下指定 --out=docs/... 會被拒絕（exit 1），說明 repo 是公開的", async () => {
  const command = new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "--cached-only",
      "--allow-env",
      new URL("./report.ts", import.meta.url).pathname,
      "--dry-run",
      "--week=2026-W40",
      "--weeks=1",
      "--out=docs/reports/weekly-cohort/2026-W40.md",
    ],
    cwd: REPO_ROOT,
    env: { SUPABASE_ACCESS_TOKEN: "", HOME: "/nonexistent" },
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await command.output();
  const err = new TextDecoder().decode(stderr);
  assertEquals(code, 1);
  assertStringIncludes(err, "在 repo 裡面");
  assertStringIncludes(err, "repo 是公開的");
  assertEquals(new TextDecoder().decode(stdout), "");
});

Deno.test({
  name:
    "CLI：在 repo 根目錄真跑、--out='C:\\temp\\cohort.md' 會被拒絕（exit 1），repo 裡不會多出怪檔名（Codex 主審第 1 輪 P2）",
  ignore: Deno.build.os === "windows",
  fn: async () => {
    // 不給寫檔與網路權限：就算守門壞了也寫不進 repo、打不到 API。
    const command = new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--cached-only",
        "--allow-env",
        "--allow-read",
        new URL("./report.ts", import.meta.url).pathname,
        "--project-ref=fake-ref",
        "--week=2026-W40",
        "--weeks=1",
        "--out=C:\\temp\\cohort.md",
      ],
      cwd: REPO_ROOT,
      env: { SUPABASE_ACCESS_TOKEN: "", HOME: "/nonexistent" },
      stdout: "piped",
      stderr: "piped",
    });
    const { code, stderr } = await command.output();
    const err = new TextDecoder().decode(stderr);
    assertEquals(code, 1);
    assertStringIncludes(err, "看起來是 Windows 路徑");
    assertStringIncludes(err, "反斜線不是路徑分隔符");
    for (const junk of ["C:\\temp\\cohort.md", "C:\\temp", "C:"]) {
      assertThrows(
        () => Deno.lstatSync(`${REPO_ROOT}${junk}`),
        Deno.errors.NotFound,
      );
    }
  },
});
