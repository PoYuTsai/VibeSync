// 週報寫到哪裡（Onboarding 第 8 步補；Eric 2026-10-27「照預設」）。
//
// repo 是公開的，週報有註冊、付費、退款人數，所以週報只能寫到 repo 以外的本機
// 路徑，之後存進 Dev Brain 的 VibeSync 週報筆記，由 agent 經 Brain Publisher 收錄。
// `--out` 指到 repo 裡面（含 docs/）一律拒絕，沒有逃生口。
//
// 判斷只看路徑字串：先換成絕對路徑、消掉 `.` 與 `..`，再逐段比對（名字相近的
// 資料夾不會被當成 repo）。不碰檔案系統，所以只有 env 權限的 dry-run 也能檢查；
// 不追 symlink——這是防手誤的護欄，不是安全邊界。

import type { CohortWeek } from "./sql.ts";

/** 預設存放處：家目錄底下這個資料夾。 */
export const DEFAULT_OUT_DIR = "vibesync-weekly-cohort";

const WINDOWS = Deno.build.os === "windows";

function fileUrlToPath(url: URL): string {
  const path = decodeURIComponent(url.pathname);
  if (url.hostname) return `\\\\${url.hostname}${path.replaceAll("/", "\\")}`;
  return /^\/[A-Za-z]:\//.test(path) ? path.slice(1) : path;
}

/** 這支工具所在的 repo 根目錄（tools/weekly-cohort-report/ 往上兩層）。 */
export const REPO_ROOT = fileUrlToPath(new URL("../../", import.meta.url));

export interface OutPathContext {
  /** 不准寫進去的 repo 根目錄。 */
  readonly repoRoot: string;
  /** 家目錄：預設存放處的根，也用來展開 `~`。 */
  readonly home: string | undefined;
  /** 相對路徑以這裡為準。 */
  readonly cwd: () => string;
}

export function defaultOutContext(): OutPathContext {
  return {
    repoRoot: REPO_ROOT,
    home: Deno.env.get("HOME") ?? Deno.env.get("USERPROFILE"),
    cwd: () => Deno.cwd(),
  };
}

function isAbsolutePath(path: string): boolean {
  return /^(?:[\\/]|[A-Za-z]:[\\/])/.test(path);
}

/** 用 base 自己的分隔符接（Windows 家目錄是反斜線）。 */
function joinPath(base: string, ...parts: string[]): string {
  const separator = base.includes("\\") && !base.includes("/") ? "\\" : "/";
  return [base.replace(/[\\/]+$/, ""), ...parts].join(separator);
}

/** 絕對路徑拆成段，消掉 `.` 與 `..`（`..` 不退過磁碟機代號）。 */
function segments(path: string, caseInsensitive: boolean): string[] {
  const out: string[] = [];
  for (const raw of path.split(/[\\/]+/)) {
    const part = caseInsensitive ? raw.toLowerCase() : raw;
    if (part === "" || part === ".") continue;
    if (part === "..") {
      if (out.length > 0 && !/^[a-z]:$/i.test(out[out.length - 1])) out.pop();
      continue;
    }
    out.push(part);
  }
  return out;
}

/** `path` 是不是 `dir` 本身或在它底下（兩個都要是絕對路徑；Windows 大小寫不分）。 */
export function isInsideDir(
  path: string,
  dir: string,
  caseInsensitive = WINDOWS,
): boolean {
  const target = segments(path, caseInsensitive);
  const root = segments(dir, caseInsensitive);
  return root.length <= target.length &&
    root.every((part, index) => part === target[index]);
}

/** 換成絕對路徑：`~` 開頭換成家目錄，相對路徑以 cwd 為準。 */
function toAbsolute(path: string, ctx: OutPathContext): string {
  if (ctx.home && /^~(?:[\\/]|$)/.test(path)) return ctx.home + path.slice(1);
  return isAbsolutePath(path) ? path : joinPath(ctx.cwd(), path);
}

/** 落在 repo 裡面（含 docs/）就報錯並說明原因；通過就回傳絕對路徑。 */
export function assertOutsideRepo(path: string, ctx: OutPathContext): string {
  if (path.trim() === "") throw new Error("invalid --out: 不能是空的");
  const absolute = toAbsolute(path, ctx);
  if (isInsideDir(absolute, ctx.repoRoot)) {
    throw new Error(
      `invalid --out: ${path} 在 repo 裡面（${ctx.repoRoot}）。repo 是公開的，週報有註冊、付費、退款人數，不能放進 repo；請寫到 repo 以外的本機路徑（預設 ~/${DEFAULT_OUT_DIR}/），再由 agent 經 Brain Publisher 收進 Dev Brain。`,
    );
  }
  return absolute;
}

/** `--out` 沒給就用家目錄底下的預設資料夾；兩種都要通過 repo 檢查。 */
export function resolveOutPath(
  raw: string | undefined,
  week: CohortWeek,
  ctx: OutPathContext,
): string {
  if (raw !== undefined) return assertOutsideRepo(raw, ctx);
  if (!ctx.home) {
    throw new Error(
      "找不到家目錄（HOME／USERPROFILE）：請用 --out 指定 repo 以外的路徑",
    );
  }
  return assertOutsideRepo(
    joinPath(ctx.home, DEFAULT_OUT_DIR, `${week.label}.md`),
    ctx,
  );
}
