// AnalyzeChat Edge 行為基準鎖（源自 fc8bbe84）。
//
// 重構期間的安全網：active prompt 鎖 rendered bytes；模型選擇、token/quota
// 常數與其他非 prompt helper 才鎖原始碼切片。只有已核准且另有行為測試的
// 產品規格變更，才可更新 baseline，避免把意外漂移誤當成新行為。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildAnalyzeStreamSystemPrompt } from "./analyze_prompt.ts";
import { SYSTEM_PROMPT } from "./analyze_system_prompt.ts";
import { resolveRequestMode } from "./request_mode.ts";

interface PromptSlice {
  file: string;
  start: string;
  end: string;
  sha256: string;
}

interface BaselineFixtures {
  requestModeRejections: Record<string, {
    status: number;
    code: string;
    message: string;
    shouldChargeQuota: boolean;
  }>;
  promptSlices: Record<string, PromptSlice>;
  renderedPrompts: Record<string, {
    charCount: number;
    lineCount: number;
    sha256: string;
  }>;
}

const fixtures: BaselineFixtures = JSON.parse(
  await Deno.readTextFile(
    new URL("./baseline_fixtures.json", import.meta.url),
  ),
);

const sourceCache = new Map<string, string>();
async function readSource(file: string): Promise<string> {
  const cached = sourceCache.get(file);
  if (cached !== undefined) return cached;
  const text = await Deno.readTextFile(new URL(`./${file}`, import.meta.url));
  sourceCache.set(file, text);
  return text;
}

function extractSlice(
  source: string,
  slice: PromptSlice,
  name: string,
): string {
  const start = source.indexOf(slice.start);
  assert(start >= 0, `${name}: start marker not found in ${slice.file}`);
  assert(
    source.indexOf(slice.start, start + 1) < 0,
    `${name}: start marker not unique in ${slice.file}`,
  );
  const end = source.indexOf(slice.end, start + slice.start.length);
  assert(end >= 0, `${name}: end marker not found in ${slice.file}`);
  return source.slice(start, end + slice.end.length);
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("baseline：active Analyze rendered prompts 與穩定版完全相同", async () => {
  const rendered: Record<string, string> = {
    base: SYSTEM_PROMPT,
    paidFiveStyle: buildAnalyzeStreamSystemPrompt(),
    freeOneStyle: buildAnalyzeStreamSystemPrompt(["extend"]),
  };

  for (const [name, prompt] of Object.entries(rendered)) {
    const expected = fixtures.renderedPrompts[name];
    assert(expected, `${name}: rendered baseline fixture missing`);
    assertEquals(prompt.length, expected.charCount, `${name}: char count`);
    assertEquals(prompt.split("\n").length, expected.lineCount, `${name}: lines`);
    assertEquals(await sha256Hex(prompt), expected.sha256, `${name}: SHA-256`);
  }
});

Deno.test("baseline：prompt/model/token 原始碼切片 hash 與核准 fixture 一致", async () => {
  for (const [name, slice] of Object.entries(fixtures.promptSlices)) {
    const source = await readSource(slice.file);
    const extracted = extractSlice(source, slice, name);
    const actualHash = await sha256Hex(extracted);
    assertEquals(
      actualHash,
      slice.sha256,
      `${name} 的原始碼位元組偏離 baseline（${slice.file}）：${actualHash}`,
    );
  }
});

Deno.test("baseline：quick/full/plain legacy 請求維持 410/400 tombstone 判定", () => {
  const cases: Array<
    [key: string, input: Parameters<typeof resolveRequestMode>[0]]
  > = [
    ["quick", { responseMode: "quick", plainAnalyzeRequest: true }],
    ["full", { responseMode: "full", plainAnalyzeRequest: true }],
    ["plainLegacy", { responseMode: undefined, plainAnalyzeRequest: true }],
    ["invalid", { responseMode: "batch", plainAnalyzeRequest: true }],
  ];
  for (const [key, input] of cases) {
    const expected = fixtures.requestModeRejections[key];
    const resolution = resolveRequestMode(input);
    assert(!resolution.ok, `${key}: 應被拒絕`);
    if (resolution.ok) continue;
    assertEquals(resolution.status, expected.status, `${key}: status`);
    assertEquals(resolution.code, expected.code, `${key}: code`);
    assertEquals(expected.shouldChargeQuota, false, `${key}: 不得扣額度`);
  }
});

Deno.test("baseline：tombstone 對用戶的訊息文案未漂移", async () => {
  const source = await readSource("analyze_chat_handler.ts");
  const seen = new Set<string>();
  for (const rejection of Object.values(fixtures.requestModeRejections)) {
    if (seen.has(rejection.message)) continue;
    seen.add(rejection.message);
    assert(
      source.includes(JSON.stringify(rejection.message).slice(1, -1)) ||
        source.includes(rejection.message),
      `找不到 tombstone 文案：${rejection.message}`,
    );
  }
});
