import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  DEFAULT_LOGS_LIMIT,
  fetchDbRows,
  fetchLogRows,
  LOGS_DAY_GAP_MS,
  parseArgs,
} from "./report.ts";
import { dayWindows } from "./sql.ts";

Deno.test("parseArgs 讀 project ref、日期、付費人數與輸出路徑", () => {
  const opts = parseArgs([
    "--project-ref=abcdef",
    "--from=2026-08-29",
    "--to=2026-09-05",
    "--payers-starter=10",
    "--payers-essential=5",
    "--out=docs/reports/x.md",
  ]);
  assertEquals(opts.projectRef, "abcdef");
  assertEquals(opts.range, { from: "2026-08-29", to: "2026-09-05" });
  assertEquals(opts.payers, { starter: 10, essential: 5 });
  assertEquals(opts.out, "docs/reports/x.md");
  assertEquals(opts.dryRun, false);
});

Deno.test("parseArgs 缺付費人數就不給 payers；--out 預設用 to 日期", () => {
  const opts = parseArgs(["--to=2026-09-05", "--from=2026-08-29"]);
  assertEquals(opts.payers, undefined);
  assertEquals(opts.out, "docs/reports/2026-09-05-practice-weekly.md");
});

Deno.test("--dry-run 走 CLI 只印 SQL、不需要 token、不落檔", async () => {
  const command = new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "--allow-read",
      "--allow-env",
      new URL("./report.ts", import.meta.url).pathname,
      "--dry-run",
      "--project-ref=fake",
      "--from=2026-08-29",
      "--to=2026-09-05",
    ],
    env: { SUPABASE_ACCESS_TOKEN: "", HOME: "/nonexistent" },
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await command.output();
  const out = new TextDecoder().decode(stdout);
  assertEquals(code, 0, new TextDecoder().decode(stderr));
  assertStringIncludes(out, "SELECT");
  assertStringIncludes(out, "public.practice_chat_sessions");
  assertStringIncludes(out, "public.ai_logs");
  assertEquals(out.toLowerCase().includes("bearer"), false);
});

Deno.test("--dry-run 也印 function logs 那條 SQL", async () => {
  const command = new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "--allow-read",
      "--allow-env",
      new URL("./report.ts", import.meta.url).pathname,
      "--dry-run",
      "--from=2026-08-29",
      "--to=2026-09-05",
      "--logs-limit=250",
    ],
    env: { SUPABASE_ACCESS_TOKEN: "", HOME: "/nonexistent" },
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout } = await command.output();
  const out = new TextDecoder().decode(stdout);
  assertEquals(code, 0);
  assertStringIncludes(out, "-- function logs");
  assertStringIncludes(out, "function_logs");
  assertStringIncludes(out, "practice_chat_succeeded");
  assertStringIncludes(out, "limit 250");
});

Deno.test("parseArgs 的 logs limit 預設值與覆寫", () => {
  assertEquals(parseArgs([]).logsLimit, DEFAULT_LOGS_LIMIT);
  assertEquals(parseArgs(["--logs-limit=42"]).logsLimit, 42);
});

function fakeResponse(status: number, body: string): Response {
  return new Response(body, { status });
}

Deno.test("429 退避重試三次後成功；每天一次呼叫、之間有間隔", async () => {
  const calls: string[] = [];
  const slept: number[] = [];
  let attempts = 0;
  const result = await fetchLogRows({
    projectRef: "ref",
    token: "t",
    sql: "SELECT 1",
    windows: dayWindows({ from: "2026-08-30", to: "2026-09-01" }),
    fetchImpl: ((url: string | URL) => {
      calls.push(String(url));
      attempts += 1;
      // 第一天的頭兩發被限流（一次 429、一次 ThrottlerException body）。
      if (attempts === 1) return Promise.resolve(fakeResponse(429, "nope"));
      if (attempts === 2) {
        return Promise.resolve(
          fakeResponse(
            200,
            '{"message":"ThrottlerException: Too Many Requests"}',
          ),
        );
      }
      return Promise.resolve(
        fakeResponse(200, '{"result":[{"timestamp":1,"event_message":"x"}]}'),
      );
    }) as unknown as typeof fetch,
    sleep: (ms) => {
      slept.push(ms);
      return Promise.resolve();
    },
  });
  assertEquals(result.rows.length, 2);
  assertEquals(result.missingDays, []);
  assertEquals(calls.length, 4);
  assertStringIncludes(
    calls[0],
    "iso_timestamp_start=2026-08-30T00%3A00%3A00Z",
  );
  // 退避 1s、2s ＋ 兩天之間的 500ms 間隔。
  assertEquals(slept, [1000, 2000, LOGS_DAY_GAP_MS]);
});

Deno.test("退避用完仍被限流：那一天標成未取得，其他天照常", async () => {
  let attempts = 0;
  const result = await fetchLogRows({
    projectRef: "ref",
    token: "t",
    sql: "SELECT 1",
    windows: dayWindows({ from: "2026-08-30", to: "2026-09-01" }),
    fetchImpl: (() => {
      attempts += 1;
      return Promise.resolve(
        attempts <= 4 ? fakeResponse(429, "slow down") : fakeResponse(
          200,
          '{"result":[{"timestamp":2,"event_message":"y"}]}',
        ),
      );
    }) as unknown as typeof fetch,
    sleep: () => Promise.resolve(),
  });
  assertEquals(result.missingDays, ["2026-08-30"]);
  assertEquals(result.rows.length, 1);
  assertEquals(attempts, 5);
});

Deno.test("非限流的 HTTP 錯誤照樣往上丟", async () => {
  await assertRejects(
    () =>
      fetchLogRows({
        projectRef: "ref",
        token: "t",
        sql: "SELECT 1",
        windows: dayWindows({ from: "2026-08-30", to: "2026-08-31" }),
        fetchImpl: (() =>
          Promise.resolve(
            fakeResponse(500, "boom"),
          )) as unknown as typeof fetch,
        sleep: () => Promise.resolve(),
      }),
    Error,
    "Logs API 500",
  );
});

Deno.test("--out path 空格式要收得到，不能靜默寫進預設路徑", () => {
  assertEquals(
    parseArgs(["--out", "docs/reports/manual.md", "--from", "2026-08-30"]).out,
    "docs/reports/manual.md",
  );
  assertEquals(parseArgs(["--from", "2026-08-30"]).range.from, "2026-08-30");
});

Deno.test("未知參數、孤立參數、缺值一律報錯不靜默", () => {
  assertThrows(() => parseArgs(["--nope=1"]), Error, "unknown flag");
  assertThrows(() => parseArgs(["stray"]), Error, "unexpected argument");
  assertThrows(() => parseArgs(["--out"]), Error, "missing value");
  assertThrows(() => parseArgs(["--out", "--from=2026-08-30"]), Error);
});

Deno.test("守門在送出前擋下：寫入語句一個位元組都不會離開這台機器", async () => {
  let called = false;
  const spy = (() => {
    called = true;
    return Promise.resolve(fakeResponse(200, '{"result":[]}'));
  }) as unknown as typeof fetch;

  await assertRejects(
    () =>
      fetchLogRows({
        projectRef: "ref",
        token: "t",
        sql: "DELETE FROM ai_logs",
        windows: dayWindows({ from: "2026-08-30", to: "2026-08-31" }),
        fetchImpl: spy,
        sleep: () => Promise.resolve(),
      }),
    Error,
    "read_only_guard",
  );
  await assertRejects(
    () =>
      fetchDbRows({
        projectRef: "ref",
        token: "t",
        sql: "SELECT pg_sleep(60)",
        fetchImpl: spy,
      }),
    Error,
    "read_only_guard",
  );
  assertEquals(called, false);
});

Deno.test("parseArgs 擋掉不存在的日子與顛倒的區間", () => {
  assertThrows(
    () => parseArgs(["--from=2026-02-31", "--to=2026-09-05"]),
    Error,
    "invalid_date",
  );
  assertThrows(
    () => parseArgs(["--from=2026-09-05", "--to=2026-09-05"]),
    Error,
    "invalid_range",
  );
});

Deno.test("--out 預設只能寫進 docs/reports/", () => {
  assertEquals(
    parseArgs(["--out", "docs/reports/manual.md"]).out,
    "docs/reports/manual.md",
  );
  assertThrows(
    () => parseArgs(["--out=/tmp/report.md"]),
    Error,
    "--allow-out-anywhere",
  );
  assertThrows(
    () => parseArgs(["--out=lib/report.md"]),
    Error,
    "invalid --out",
  );
});

Deno.test("--allow-out-anywhere 是逃生口，但 .. 永遠擋", () => {
  assertEquals(
    parseArgs(["--out=/tmp/scratch/report.md", "--allow-out-anywhere"]).out,
    "/tmp/scratch/report.md",
  );
  assertThrows(
    () => parseArgs(["--out=docs/reports/../../etc/x.md"]),
    Error,
    "路徑穿越",
  );
  assertThrows(
    () => parseArgs(["--out=../escape.md", "--allow-out-anywhere"]),
    Error,
    "路徑穿越",
  );
});

Deno.test("截斷是逐日判斷：只有回滿 limit 的那天被標，總數超過不算", async () => {
  const full = '{"result":[{"timestamp":1,"event_message":"a"},' +
    '{"timestamp":2,"event_message":"b"}]}';
  const partial = '{"result":[{"timestamp":3,"event_message":"c"}]}';
  let day = 0;
  const result = await fetchLogRows({
    projectRef: "ref",
    token: "t",
    sql: "SELECT 1",
    windows: dayWindows({ from: "2026-08-30", to: "2026-09-02" }),
    limit: 2,
    fetchImpl: (() => {
      day += 1;
      return Promise.resolve(fakeResponse(200, day === 2 ? full : partial));
    }) as unknown as typeof fetch,
    sleep: () => Promise.resolve(),
  });
  // 三天共 4 列 > limit 2，但只有第二天真的回滿。
  assertEquals(result.rows.length, 4);
  assertEquals(result.truncatedDays, ["2026-08-31"]);
});
