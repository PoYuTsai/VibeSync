import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertOutsideRepo,
  DEFAULT_OUT_DIR,
  defaultOutContext,
  isInsideDir,
  type OutPathContext,
  REPO_ROOT,
  resolveOutPath,
} from "./out_path.ts";
import { parseIsoWeek } from "./sql.ts";

const W43 = parseIsoWeek("2026-W43");
// 假的路徑：repo 在 /work/VibeSync、家目錄在 /home/tester、目前目錄是 repo 根。
const CTX: OutPathContext = {
  repoRoot: "/work/VibeSync",
  home: "/home/tester",
  cwd: () => "/work/VibeSync",
};

Deno.test("預設路徑：家目錄底下 vibesync-weekly-cohort/<週>.md，在 repo 以外", () => {
  const out = resolveOutPath(undefined, W43, CTX);
  assertEquals(out, "/home/tester/vibesync-weekly-cohort/2026-W43.md");
  assertEquals(isInsideDir(out, CTX.repoRoot), false);
});

Deno.test("預設路徑換成這台機器真的家目錄與這個 repo，也在 repo 以外", () => {
  // REPO_ROOT 真的指到 repo 根目錄（文件就在它底下）。
  assertEquals(
    Deno.statSync(`${REPO_ROOT}docs/integrations/weekly-cohort-report.md`)
      .isFile,
    true,
  );
  const out = resolveOutPath(undefined, W43, defaultOutContext());
  assertEquals(
    out.replaceAll("\\", "/").endsWith(`/${DEFAULT_OUT_DIR}/2026-W43.md`),
    true,
    out,
  );
  assertEquals(isInsideDir(out, REPO_ROOT), false, out);
});

Deno.test("--out 指到 repo 裡面（含 docs/）一律拒絕，並說明原因", () => {
  const inTools: OutPathContext = { ...CTX, cwd: () => "/work/VibeSync/tools" };
  const cases: Array<[string, OutPathContext]> = [
    ["docs/reports/weekly-cohort/2026-W43.md", CTX],
    ["docs/x.md", CTX],
    ["./docs/x.md", CTX],
    ["x.md", CTX],
    ["/work/VibeSync/docs/integrations/x.md", CTX],
    ["/work/VibeSync", CTX],
    ["/work/VibeSync/", CTX],
    ["/work/VibeSync/tools/../docs/x.md", CTX],
    ["/tmp/../work/VibeSync/x.md", CTX],
    ["sub/x.md", inTools],
    ["../docs/x.md", inTools],
    ["~/x.md", { ...CTX, home: "/work/VibeSync/home" }],
  ];
  for (const [out, ctx] of cases) {
    const error = assertThrows(
      () => assertOutsideRepo(out, ctx),
      Error,
      "在 repo 裡面",
      out,
    );
    assertStringIncludes(error.message, "repo 是公開的");
    assertStringIncludes(error.message, "Brain Publisher");
  }
});

Deno.test("--out 在 repo 以外就收：名字相近的資料夾不算 repo、../ 跳出 repo 也收、~ 換成家目錄", () => {
  assertEquals(
    assertOutsideRepo("/work/VibeSync-notes/x.md", CTX),
    "/work/VibeSync-notes/x.md",
  );
  assertEquals(
    assertOutsideRepo("../notes/x.md", CTX),
    "/work/VibeSync/../notes/x.md",
  );
  assertEquals(
    assertOutsideRepo("~/notes/x.md", CTX),
    "/home/tester/notes/x.md",
  );
  assertEquals(assertOutsideRepo("/tmp/weekly.md", CTX), "/tmp/weekly.md");
});

Deno.test("Windows 路徑：反斜線也認、大小寫不分；Linux 大小寫有分", () => {
  assertEquals(
    isInsideDir(
      "C:\\Users\\Eric\\VibeSync\\docs\\x.md",
      "c:/users/eric/vibesync/",
      true,
    ),
    true,
  );
  assertEquals(
    isInsideDir(
      "C:\\Users\\Eric\\VibeSync-notes\\x.md",
      "C:\\Users\\Eric\\VibeSync",
      true,
    ),
    false,
  );
  // `..` 不會退過磁碟機代號。
  assertEquals(
    isInsideDir(
      "C:\\..\\Users\\Eric\\VibeSync\\x.md",
      "C:\\Users\\Eric\\VibeSync",
      true,
    ),
    true,
  );
  assertEquals(
    isInsideDir("/Work/VibeSync/x.md", "/work/VibeSync", false),
    false,
  );
  // Windows 家目錄用反斜線接預設資料夾。
  assertEquals(
    resolveOutPath(undefined, W43, {
      repoRoot: "C:\\code\\VibeSync",
      home: "C:\\Users\\Eric",
      cwd: () => "C:\\code\\VibeSync",
    }),
    "C:\\Users\\Eric\\vibesync-weekly-cohort\\2026-W43.md",
  );
});

Deno.test("找不到家目錄又沒給 --out 就報錯；空的 --out 也報錯", () => {
  assertThrows(
    () => resolveOutPath(undefined, W43, { ...CTX, home: undefined }),
    Error,
    "找不到家目錄",
  );
  for (const out of ["", "   "]) {
    assertThrows(() => resolveOutPath(out, W43, CTX), Error, "不能是空的");
  }
});
