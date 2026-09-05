import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseArgs } from "./report.ts";

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
