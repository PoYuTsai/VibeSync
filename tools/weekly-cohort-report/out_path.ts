// 週報寫到哪裡（Onboarding 第 8 步補；Eric 2026-10-27「照預設」）。
//
// repo 是公開的，週報有註冊、付費、退款人數，所以週報只能寫到 repo 以外的本機
// 路徑，之後存進 Dev Brain 的 VibeSync 週報筆記，由 agent 經 Brain Publisher 收錄。
// `--out` 指到 repo 裡面（含 docs/）一律拒絕，沒有逃生口。
//
// 兩道檢查：
// 1. 路徑字串（parseArgs、dry-run 也跑，不碰檔案系統）：依執行平台的規則換成
//    正規化的絕對路徑（消掉 `.` 與 `..`）再逐段比對，名字相近的資料夾不算 repo。
//    在 Linux／WSL 上，看起來像 Windows 的路徑（磁碟代號開頭、含反斜線、UNC）一律
//    拒絕：反斜線在這裡只是普通字元，`C:\temp\x.md` 會在目前目錄寫出一個叫這個
//    名字的檔案（Codex 主審第 1 輪 P2）。
// 2. 真實路徑（真跑寫檔前，要讀檔權限）：解開 symlink 之後也必須在 repo 以外；
//    輸出檔本身是 symlink、路徑上有壞掉的 symlink 都不寫。寫檔用的就是檢查過的
//    那個正規化路徑。
// 這是防手誤的護欄，不是安全邊界。

import type { CohortWeek } from "./sql.ts";

/** 預設存放處：家目錄底下這個資料夾。 */
export const DEFAULT_OUT_DIR = "vibesync-weekly-cohort";

/** 照哪一套規則解析路徑。 */
export type PathPlatform = "windows" | "posix";
export const HOST_PLATFORM: PathPlatform = Deno.build.os === "windows"
  ? "windows"
  : "posix";

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
  /** 照哪個平台的規則解析；預設是這台機器（測試可以換）。 */
  readonly platform?: PathPlatform;
}

export function defaultOutContext(): OutPathContext {
  return {
    repoRoot: REPO_ROOT,
    home: Deno.env.get("HOME") ?? Deno.env.get("USERPROFILE"),
    cwd: () => Deno.cwd(),
    platform: HOST_PLATFORM,
  };
}

const REPO_IS_PUBLIC =
  `repo 是公開的，週報有註冊、付費、退款人數，不能放進 repo；請寫到 repo 以外的本機路徑（預設 ~/${DEFAULT_OUT_DIR}/），再由 agent 經 Brain Publisher 收進 Dev Brain。`;

/** 在非 Windows 平台上看起來像 Windows 的路徑：磁碟代號開頭，或含反斜線（含 UNC）。 */
export function looksLikeWindowsPath(path: string): boolean {
  return /^[A-Za-z]:/.test(path) || path.includes("\\");
}

/** 正規化的絕對路徑：root 是 `/`、`C:` 或 `\\server\share`，parts 已消掉 `.` 與 `..`。 */
interface AbsolutePath {
  readonly root: string;
  readonly parts: readonly string[];
}

function splitParts(rest: string, platform: PathPlatform): string[] {
  const parts: string[] = [];
  for (const part of rest.split(platform === "posix" ? "/" : /[\\/]/)) {
    if (part === "" || part === ".") continue;
    if (part === "..") {
      parts.pop(); // 根目錄再往上還是根目錄
      continue;
    }
    parts.push(part);
  }
  return parts;
}

function isAbsolute(path: string, platform: PathPlatform): boolean {
  return platform === "posix"
    ? path.startsWith("/")
    : /^(?:[\\/]{2}|[A-Za-z]:[\\/])/.test(path);
}

/** 已經是絕對路徑的字串 → root ＋ 正規化的段落。 */
function parseAbsolute(path: string, platform: PathPlatform): AbsolutePath {
  if (platform === "posix") {
    if (!path.startsWith("/")) throw new Error(`not_absolute: ${path}`);
    return { root: "/", parts: splitParts(path, platform) };
  }
  // Windows 的真實路徑可能帶 \\?\ 前綴。
  let rest = path;
  if (/^\\\\\?\\UNC\\/i.test(rest)) rest = `\\\\${rest.slice(8)}`;
  else if (rest.startsWith("\\\\?\\")) rest = rest.slice(4);
  const unc = /^[\\/]{2}([^\\/]+)[\\/]+([^\\/]+)(.*)$/.exec(rest);
  if (unc) {
    return {
      root: `\\\\${unc[1]}\\${unc[2]}`,
      parts: splitParts(unc[3], platform),
    };
  }
  const drive = /^([A-Za-z]:)[\\/](.*)$/.exec(rest);
  if (drive) {
    return {
      root: drive[1].toUpperCase(),
      parts: splitParts(drive[2], platform),
    };
  }
  throw new Error(`not_absolute: ${path}`);
}

function formatPath(path: AbsolutePath, platform: PathPlatform): string {
  if (platform === "posix") return `/${path.parts.join("/")}`;
  return path.parts.length === 0
    ? `${path.root}\\`
    : [path.root, ...path.parts].join("\\");
}

/** 把 `--out` 換成這個平台的絕對路徑；看不懂或模稜兩可的寫法直接報錯。 */
function toAbsolute(raw: string, ctx: OutPathContext): AbsolutePath {
  const platform = ctx.platform ?? HOST_PLATFORM;
  if (platform === "posix" && looksLikeWindowsPath(raw)) {
    throw new Error(
      `invalid --out: ${raw} 看起來是 Windows 路徑（磁碟代號、反斜線或 UNC）。這台機器不是 Windows，反斜線不是路徑分隔符，這種路徑會在目前目錄寫出一個怪檔名（可能就寫進 repo）；請改用這台機器的路徑，例如 /mnt/c/… 或 ~/…。`,
    );
  }
  let path = raw;
  if (/^~(?:[\\/]|$)/.test(path)) {
    if (!ctx.home) {
      throw new Error(`invalid --out: ${raw} 要展開 ~，但找不到家目錄`);
    }
    path = ctx.home + path.slice(1);
  }
  if (platform === "windows") {
    if (/^[A-Za-z]:(?![\\/])/.test(path)) {
      throw new Error(
        `invalid --out: ${raw} 是磁碟代號接相對路徑，看不出實際位置；請寫完整路徑，例如 C:\\Users\\…`,
      );
    }
    // 單一個 \ 開頭：目前磁碟機的根目錄。
    if (/^[\\/](?![\\/])/.test(path)) {
      return {
        root: parseAbsolute(ctx.cwd(), platform).root,
        parts: splitParts(path, platform),
      };
    }
  }
  const absolute = isAbsolute(path, platform)
    ? path
    : `${ctx.cwd()}${platform === "posix" ? "/" : "\\"}${path}`;
  if (platform === "posix" && looksLikeWindowsPath(absolute)) {
    throw new Error(
      `invalid --out: ${absolute} 含反斜線或磁碟代號，在這台機器上不是可靠的路徑`,
    );
  }
  return parseAbsolute(absolute, platform);
}

/** `path` 是不是 `dir` 本身或在它底下（兩個都要是絕對路徑；Windows 大小寫不分）。 */
export function isInsideDir(
  path: string,
  dir: string,
  platform: PathPlatform = HOST_PLATFORM,
): boolean {
  const target = parseAbsolute(path, platform);
  const root = parseAbsolute(dir, platform);
  const same = (a: string, b: string) =>
    platform === "windows" ? a.toLowerCase() === b.toLowerCase() : a === b;
  return same(target.root, root.root) &&
    root.parts.length <= target.parts.length &&
    root.parts.every((part, index) => same(part, target.parts[index]));
}

/** 落在 repo 裡面（含 docs/）就報錯並說明原因；通過就回傳正規化的絕對路徑。 */
export function assertOutsideRepo(path: string, ctx: OutPathContext): string {
  if (path.trim() === "") throw new Error("invalid --out: 不能是空的");
  const platform = ctx.platform ?? HOST_PLATFORM;
  const absolute = formatPath(toAbsolute(path, ctx), platform);
  if (isInsideDir(absolute, ctx.repoRoot, platform)) {
    throw new Error(
      `invalid --out: ${path} 在 repo 裡面（${ctx.repoRoot}）。${REPO_IS_PUBLIC}`,
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
  const separator = (ctx.platform ?? HOST_PLATFORM) === "posix" ? "/" : "\\";
  return assertOutsideRepo(
    [ctx.home.replace(/[\\/]+$/, ""), DEFAULT_OUT_DIR, `${week.label}.md`]
      .join(separator),
    ctx,
  );
}

function lstatOrUndefined(path: string): Deno.FileInfo | undefined {
  try {
    return Deno.lstatSync(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

/**
 * 寫檔前用真實路徑再檢查一次（要讀檔權限）。輸出檔本身不能是 symlink（寫下去會
 * 跟著連結走）；往上找到第一個存在的那一層取真實路徑（解開 symlink，壞掉的
 * symlink 直接拒絕），接回還不存在的那幾段，結果必須在 repo 的真實路徑以外。
 * 回傳解開後的真實路徑。
 */
export function assertRealPathOutsideRepo(
  path: string,
  repoRoot: string,
  platform: PathPlatform = HOST_PLATFORM,
): string {
  const target = parseAbsolute(path, platform);
  const parts = [...target.parts];
  const missing: string[] = [];
  let existing: string;
  for (;;) {
    const candidate = formatPath({ root: target.root, parts }, platform);
    const info = lstatOrUndefined(candidate);
    if (info) {
      if (info.isSymlink && missing.length === 0) {
        throw new Error(
          `invalid --out: ${path} 本身是 symlink，寫下去會跟著連結走；請指定一般檔案的路徑。`,
        );
      }
      try {
        existing = Deno.realPathSync(candidate);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
        throw new Error(
          `invalid --out: ${path} 的路徑上有壞掉的 symlink（${candidate}），看不出實際會寫到哪裡，不寫。`,
        );
      }
      break;
    }
    if (parts.length === 0) {
      throw new Error(`invalid --out: ${path} 找不到任何一層存在的上層資料夾`);
    }
    missing.unshift(parts.pop()!);
  }
  const resolved = parseAbsolute(existing, platform);
  const real = formatPath(
    { root: resolved.root, parts: [...resolved.parts, ...missing] },
    platform,
  );
  const realRepo = Deno.realPathSync(repoRoot);
  if (isInsideDir(real, realRepo, platform)) {
    throw new Error(
      `invalid --out: ${path} 解開 symlink 之後實際會寫到 repo 裡面（${real}）。${REPO_IS_PUBLIC}`,
    );
  }
  return real;
}

/**
 * 寫週報：路徑字串、真實路徑兩道檢查都過了，才建資料夾、寫檔（真跑用，要讀寫檔
 * 權限）。寫的是檢查過的那個正規化路徑；回傳它。
 */
export async function writeOutsideRepo(
  path: string,
  text: string,
  ctx: OutPathContext = defaultOutContext(),
): Promise<string> {
  const platform = ctx.platform ?? HOST_PLATFORM;
  const absolute = assertOutsideRepo(path, ctx);
  assertRealPathOutsideRepo(absolute, ctx.repoRoot, platform);
  const parsed = parseAbsolute(absolute, platform);
  if (parsed.parts.length > 1) {
    await Deno.mkdir(
      formatPath(
        { root: parsed.root, parts: parsed.parts.slice(0, -1) },
        platform,
      ),
      { recursive: true },
    );
  }
  await Deno.writeTextFile(absolute, text);
  return absolute;
}
