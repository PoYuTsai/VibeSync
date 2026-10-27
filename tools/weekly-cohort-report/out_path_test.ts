import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertOutsideRepo,
  assertRealPathOutsideRepo,
  DEFAULT_OUT_DIR,
  defaultOutContext,
  isInsideDir,
  type OutPathContext,
  REPO_ROOT,
  resolveOutPath,
  writeOutsideRepo,
} from "./out_path.ts";
import { parseIsoWeek } from "./sql.ts";

const W43 = parseIsoWeek("2026-W43");
// 假的路徑：repo 在 /work/VibeSync、家目錄在 /home/tester、目前目錄是 repo 根，照 Linux 規則。
const CTX: OutPathContext = {
  repoRoot: "/work/VibeSync",
  home: "/home/tester",
  cwd: () => "/work/VibeSync",
  platform: "posix",
};
// 同一套情境換成 Windows 規則。
const WIN_CTX: OutPathContext = {
  repoRoot: "C:\\code\\VibeSync",
  home: "C:\\Users\\Eric",
  cwd: () => "C:\\code\\VibeSync",
  platform: "windows",
};

Deno.test("預設路徑：家目錄底下 vibesync-weekly-cohort/<週>.md，在 repo 以外", () => {
  const out = resolveOutPath(undefined, W43, CTX);
  assertEquals(out, "/home/tester/vibesync-weekly-cohort/2026-W43.md");
  assertEquals(isInsideDir(out, CTX.repoRoot, "posix"), false);
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

Deno.test("--out 在 repo 以外就收：名字相近的資料夾不算 repo、../ 跳出 repo 也收、~ 換成家目錄；回傳正規化路徑", () => {
  assertEquals(
    assertOutsideRepo("/work/VibeSync-notes/x.md", CTX),
    "/work/VibeSync-notes/x.md",
  );
  assertEquals(assertOutsideRepo("../notes/x.md", CTX), "/work/notes/x.md");
  assertEquals(
    assertOutsideRepo("~/notes/x.md", CTX),
    "/home/tester/notes/x.md",
  );
  assertEquals(assertOutsideRepo("/tmp/weekly.md", CTX), "/tmp/weekly.md");
  assertEquals(assertOutsideRepo("/tmp/a/./b/../c.md", CTX), "/tmp/a/c.md");
});

Deno.test("Linux／WSL 上看起來像 Windows 的路徑一律拒絕，並說明反斜線不是分隔符", () => {
  for (
    const out of [
      "C:\\temp\\x.md",
      "C:/temp/x.md",
      "\\\\server\\share\\x.md",
      "dir\\x.md",
      // 在 repo 根目錄執行時，主審重現的那一條。
      "C:\\temp\\cohort.md",
      "c:x.md",
      "~\\x.md",
      "/tmp/ok\\x.md",
    ]
  ) {
    const error = assertThrows(
      () => assertOutsideRepo(out, CTX),
      Error,
      "看起來是 Windows 路徑",
      out,
    );
    assertStringIncludes(error.message, "反斜線不是路徑分隔符");
  }
});

Deno.test("Windows 規則：反斜線與斜線都認、大小寫不分、UNC 與 \\\\?\\ 前綴都認；Linux 大小寫有分", () => {
  assertEquals(
    isInsideDir(
      "C:\\Users\\Eric\\VibeSync\\docs\\x.md",
      "c:/users/eric/vibesync/",
      "windows",
    ),
    true,
  );
  assertEquals(
    isInsideDir(
      "C:\\Users\\Eric\\VibeSync-notes\\x.md",
      "C:\\Users\\Eric\\VibeSync",
      "windows",
    ),
    false,
  );
  // `..` 不會退過磁碟機代號。
  assertEquals(
    isInsideDir(
      "C:\\..\\Users\\Eric\\VibeSync\\x.md",
      "C:\\Users\\Eric\\VibeSync",
      "windows",
    ),
    true,
  );
  assertEquals(
    isInsideDir("\\\\?\\C:\\code\\VibeSync\\x.md", WIN_CTX.repoRoot, "windows"),
    true,
  );
  assertEquals(
    isInsideDir("/Work/VibeSync/x.md", "/work/VibeSync", "posix"),
    false,
  );
  // Windows 家目錄用反斜線接預設資料夾。
  assertEquals(
    resolveOutPath(undefined, W43, WIN_CTX),
    "C:\\Users\\Eric\\vibesync-weekly-cohort\\2026-W43.md",
  );
  assertEquals(assertOutsideRepo("C:\\temp\\x.md", WIN_CTX), "C:\\temp\\x.md");
  assertEquals(
    assertOutsideRepo("\\\\server\\share\\x.md", WIN_CTX),
    "\\\\server\\share\\x.md",
  );
  for (
    const out of [
      "c:/code/vibesync/docs/x.md",
      "docs\\x.md",
      // 單一個 \ 開頭＝目前磁碟機的根目錄。
      "\\code\\VibeSync\\docs\\x.md",
    ]
  ) {
    assertThrows(
      () => assertOutsideRepo(out, WIN_CTX),
      Error,
      "在 repo 裡面",
      out,
    );
  }
  assertThrows(
    () => assertOutsideRepo("C:x.md", WIN_CTX),
    Error,
    "磁碟代號接相對路徑",
  );
});

Deno.test("找不到家目錄又沒給 --out 就報錯；~ 展開不了、空的 --out 也報錯", () => {
  assertThrows(
    () => resolveOutPath(undefined, W43, { ...CTX, home: undefined }),
    Error,
    "找不到家目錄",
  );
  assertThrows(
    () => resolveOutPath("~/x.md", W43, { ...CTX, home: undefined }),
    Error,
    "找不到家目錄",
  );
  for (const out of ["", "   "]) {
    assertThrows(() => resolveOutPath(out, W43, CTX), Error, "不能是空的");
  }
});

/** 在暫存資料夾裡搭一個假的 repo（絕不碰真的 repo），跑完整個刪掉。 */
async function withFakeRepo(
  run: (dirs: { tmp: string; repo: string; outside: string }) => Promise<void>,
) {
  const tmp = Deno.realPathSync(
    await Deno.makeTempDir({ prefix: "weekly-cohort-out-" }),
  );
  try {
    const repo = `${tmp}/repo`;
    const outside = `${tmp}/outside`;
    await Deno.mkdir(`${repo}/docs`, { recursive: true });
    await Deno.mkdir(outside);
    await run({ tmp, repo, outside });
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
}

function fakeRepoContext(repo: string, cwd: string): OutPathContext {
  return { repoRoot: repo, home: undefined, cwd: () => cwd, platform: "posix" };
}

Deno.test({
  name:
    "寫檔前用真實路徑再擋：經過 symlink 指進 repo、輸出檔本身是 symlink、路徑上有壞掉的 symlink 都不寫",
  ignore: Deno.build.os === "windows", // 建 symlink 在 Windows 要額外權限
  fn: () =>
    withFakeRepo(async ({ tmp, repo, outside }) => {
      const ctx = fakeRepoContext(repo, outside);
      Deno.symlinkSync(repo, `${tmp}/link-to-repo`);
      Deno.symlinkSync(`${repo}/docs/leak.md`, `${outside}/leak.md`);
      Deno.symlinkSync(`${repo}/new-dir`, `${outside}/dangling`);

      // 字串檢查看起來在 repo 外，真實路徑在 repo 裡。
      assertEquals(isInsideDir(`${tmp}/link-to-repo/docs/x.md`, repo), false);
      await assertRejects(
        () => writeOutsideRepo(`${tmp}/link-to-repo/docs/x.md`, "數字", ctx),
        Error,
        "解開 symlink 之後實際會寫到 repo 裡面",
      );
      await assertRejects(
        () => writeOutsideRepo(`${outside}/leak.md`, "數字", ctx),
        Error,
        "本身是 symlink",
      );
      await assertRejects(
        () => writeOutsideRepo(`${outside}/dangling/x.md`, "數字", ctx),
        Error,
        "壞掉的 symlink",
      );
      // 假 repo 裡什麼都沒多出來。
      assertEquals([...Deno.readDirSync(`${repo}/docs`)].length, 0);
      assertEquals([...Deno.readDirSync(repo)].map((entry) => entry.name), [
        "docs",
      ]);
    }),
});

Deno.test("寫檔：repo 外的一般路徑照寫（缺的資料夾會建）；寫的是檢查過的正規化路徑", () =>
  withFakeRepo(async ({ repo, outside }) => {
    const ctx = fakeRepoContext(repo, outside);
    const written = await writeOutsideRepo(
      `${outside}/a/./b/../2026-W43.md`,
      "週報",
      ctx,
    );
    assertEquals(written, `${outside}/a/2026-W43.md`);
    assertEquals(await Deno.readTextFile(written), "週報");
    assertEquals(assertRealPathOutsideRepo(written, repo), written);
  }));

Deno.test("寫檔：在 repo 根目錄給 C:\\temp\\cohort.md，碰檔案系統之前就拒絕，repo 裡不會多出怪檔名", () =>
  withFakeRepo(async ({ repo }) => {
    // 目前目錄就是（假的）repo 根目錄，跟主審重現的情境一樣。
    const ctx = fakeRepoContext(repo, repo);
    for (const out of ["C:\\temp\\cohort.md", "C:/temp/cohort.md"]) {
      await assertRejects(
        () => writeOutsideRepo(out, "數字", ctx),
        Error,
        "看起來是 Windows 路徑",
        out,
      );
    }
    assertEquals([...Deno.readDirSync(repo)].map((entry) => entry.name), [
      "docs",
    ]);
  }));
