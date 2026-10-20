// 「關於我」只給 Coach 1:1（2026-08-04）的原始碼守門：開場救星與新話題的檔案不得碰
// effectiveStyleContext／styleContext；舊版 App 帶來的值只准進重送指紋與「有沒有帶」的
// log。行為面由 opener_legacy_about_me_test.ts 與 new_topic_handler_test.ts 的埋記號測試
// 鎖住；這裡擋的是日後有人把它接回提示詞、素材判斷或共鳴開場。
// 對話分析那一側（my_message、optimize／refine、截圖分析）還沒拆，拆完再把它們加進來。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const STYLE_CONTEXT = /stylecontext/i;

/**
 * 開場救星與新話題裡准許提到它的檔案，各自另外檢查用法；其他 opener_*／new_topic_*
 * （含日後新增的檔案）一律不准。
 */
const ALLOWED = new Set([
  // 請求驗證與型別：照舊驗證、接收，給指紋用。
  "new_topic_payload.ts",
  // 重送指紋。
  "new_topic_billing.ts",
  "opener_charge.ts",
  // handler：只准進指紋與 log（下面兩個測試）。
  "new_topic_handler.ts",
  "opener_handler.ts",
  // composeResonateOpener 純函式（評測工具與純函式測試用）；handler 一律給 null。
  "opener_payload.ts",
  // 舊單段的系統提示不改字（新版 App 輸出一字不變），只准出現在 OPENER_PROMPT 裡。
  "opener_prompt.ts",
]);

async function read(file: string): Promise<string> {
  return await Deno.readTextFile(new URL(`./${file}`, import.meta.url));
}

function count(text: string, needle: string): number {
  return text.split(needle).length - 1;
}

/** `start` 之後第一個 `end` 為止的那一段（找不到就讓測試失敗）。 */
function block(text: string, start: string, end: string): string {
  const from = text.indexOf(start);
  assert(from >= 0, `找不到 ${start}`);
  const to = text.indexOf(end, from + start.length);
  assert(to > from, `找不到 ${start} 之後的 ${end}`);
  return text.slice(from, to + end.length);
}

Deno.test("關於我隔離：開場救星與新話題的檔案（白名單以外）都不提 styleContext", async () => {
  const scanned: string[] = [];
  for await (const entry of Deno.readDir(new URL("./", import.meta.url))) {
    const name = entry.name;
    if (!entry.isFile || !name.endsWith(".ts") || name.endsWith("_test.ts")) {
      continue;
    }
    if (!name.startsWith("opener_") && !name.startsWith("new_topic_")) {
      continue;
    }
    if (ALLOWED.has(name)) continue;
    scanned.push(name);
    assert(!STYLE_CONTEXT.test(await read(name)), `${name} 不得提到 styleContext`);
  }
  // 掃描範圍沒有意外變空（例如檔名規則改了）。
  assert(scanned.includes("new_topic_slots.ts"));
  assert(scanned.includes("new_topic_prompt_plan.ts"));
  assert(scanned.includes("opener_flow_prompt.ts"));
});

Deno.test("關於我隔離：舊單段開場的提示詞只在不改字的系統提示裡提到風格設定", async () => {
  const source = await read("opener_prompt.ts");
  const systemPrompt = block(source, "const OPENER_PROMPT =", "`;\n");
  const rest = source.replace(systemPrompt, "");
  assert(STYLE_CONTEXT.test(systemPrompt), "定位系統提示");
  assert(!STYLE_CONTEXT.test(rest), "系統提示以外不得提到 styleContext");
  const builder = block(
    rest,
    "function buildLegacyOpenerUserContent(",
    "\n}\n",
  );
  assert(!builder.includes("風格設定"), "user content 不放用戶自己的設定");
});

Deno.test("關於我隔離：舊單段開場 handler 只把舊值給指紋與 log，共鳴開場不拿它", async () => {
  const source = await read("opener_handler.ts");
  // 取值只有一處：經 legacyStyleContextForHash，不合法就當作沒帶。
  assertEquals(count(source, "deps.rawEffectiveStyleContext"), 1);
  assert(
    source.includes(
      "legacyStyleContextForHash(\n    sanitizeEffectiveStyleContext(deps.rawEffectiveStyleContext),\n  )",
    ),
  );
  // 用到它的只有三處：宣告、重送指紋、log。
  assertEquals(count(source, "legacyOpenerStyleContextForHash"), 3);
  const hash = block(source, "await computeOpenerInputHash({", "});");
  assert(
    hash.includes("effectiveStyleContext: legacyOpenerStyleContextForHash,"),
  );
  assert(
    source.includes(
      "hasStyleContext: legacyOpenerStyleContextForHash !== null,",
    ),
  );
  // 共鳴開場與修格式共用的 normalizeOpts：設定固定給 null。
  const normalizeOpts = block(
    source,
    "const normalizeOpts: Parameters<typeof normalizeOpenerPayload>[1] = {",
    "\n  };",
  );
  assert(normalizeOpts.includes("styleContext: null,"));
  // 組 user content 不收設定。
  const userContent = block(source, "buildLegacyOpenerUserContent({", "});");
  assert(!STYLE_CONTEXT.test(userContent));
});

Deno.test("關於我隔離：新話題 handler 只把舊值給指紋與 log，提示詞與素材判斷都不拿它", async () => {
  const source = await read("new_topic_handler.ts");
  // 用到它的只有三處：重送指紋、兩個 log 的 hasStyleContext。
  assertEquals(count(source, "newTopicRequest.effectiveStyleContext"), 3);
  assertEquals(
    count(
      source,
      "hasStyleContext: newTopicRequest.effectiveStyleContext !== null,",
    ),
    2,
  );
  const hash = block(source, "await computeNewTopicInputHash({", "});");
  assert(
    hash.includes(
      "effectiveStyleContext: newTopicRequest.effectiveStyleContext,",
    ),
  );
  const plan = block(source, "planNewTopicPrompt({", "});");
  assert(!STYLE_CONTEXT.test(plan), "提示詞路由不收關於我");
  // 素材判斷：只帶關於我不算素材。
  const material = block(
    await read("new_topic_payload.ts"),
    "export function hasNewTopicMaterial(",
    "\n}\n",
  );
  assert(!STYLE_CONTEXT.test(material));
});
