// 正規式不准用 v 旗標（Eric 2026-10-20，兩段式主審第 2 輪前）：正式環境的 Edge 還沒有函式用過 v 旗標，
// 模組層級的正規式要是解析不了，整個 analyze-chat 都開不起來（每個請求都掛，不只兩段式）。掃 analyze-chat
// 與它載入的 _shared 的程式檔（測試檔不算），正規式寫法或 new RegExp 的旗標有 v 就失敗。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

/// 正規式寫法：前面是會接正規式的符號（或 return），斜線之間沒有換行，結尾的旗標裡有 v。
const LITERAL_WITH_V =
  /(?:^|[=(,:[!&|?{};]|\breturn)\s*\/(?![/*])(?:[^/\n\\[]|\\.|\[(?:[^\]\n\\]|\\.)*\])+\/[dgimsuy]*v[dgimsuy]*(?![\w$])/gm;
/// new RegExp(…, "…v…")：第二個參數是只有旗標字母、而且有 v 的字串。
const CONSTRUCTOR_WITH_V =
  /new\s+RegExp\s*\([^;]*?,\s*["'`][dgimsuy]*v[dgimsuy]*["'`]\s*\)/g;

export function regexVFlagUses(source: string): string[] {
  return [
    ...[...source.matchAll(LITERAL_WITH_V)].map((m) => m[0].trim()),
    ...[...source.matchAll(CONSTRUCTOR_WITH_V)].map((m) => m[0].trim()),
  ];
}

async function sourceFiles(dir: URL): Promise<URL[]> {
  const out: URL[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isDirectory) {
      if (entry.name === "testdata" || entry.name === "node_modules") continue;
      out.push(...await sourceFiles(new URL(`${entry.name}/`, dir)));
    } else if (
      entry.isFile && entry.name.endsWith(".ts") &&
      !entry.name.endsWith("_test.ts")
    ) {
      out.push(new URL(entry.name, dir));
    }
  }
  return out;
}

Deno.test("找 v 旗標的檢查本身：正規式寫法與 new RegExp 帶 v 都抓得到；u、g 旗標、除法、網址、註解不算", () => {
  for (
    const bad of [
      "const A = /\\p{RGI_Emoji}/gv;",
      "const B = /a|b/v;",
      "  return /[x]/vg.test(s);",
      'const C = new RegExp("a", "v");',
      "const D = new RegExp(`a${x}`, 'gv');",
    ]
  ) {
    assertEquals(regexVFlagUses(bad).length, 1, bad);
  }
  for (
    const ok of [
      "const A = /\\p{Extended_Pictographic}/gu;",
      "const B = x / y / value;",
      'const C = "https://example.com/a/v1/vibe";',
      "// 舊寫法 /a/gv 不能用",
      'const D = new RegExp("a", "gu");',
      "const E = a / 2 / v;",
    ]
  ) {
    assertEquals(regexVFlagUses(ok), [], ok);
  }
});

Deno.test("analyze-chat 與 _shared 的程式檔（測試檔不算）沒有用 v 旗標的正規式", async () => {
  const files = [
    ...await sourceFiles(new URL("./", import.meta.url)),
    ...await sourceFiles(new URL("../_shared/", import.meta.url)),
  ];
  assert(files.length > 50);
  assert(files.some((f) => f.pathname.endsWith("/guide_v3/rules.ts")));
  const found: string[] = [];
  for (const file of files) {
    for (const use of regexVFlagUses(await Deno.readTextFile(file))) {
      found.push(`${file.pathname}: ${use}`);
    }
  }
  assertEquals(found, []);
});
