// AnalyzeChat Edge 行為基準鎖（fc8bbe84）。
//
// 重構期間的安全網：prompt bytes、模型選擇、token/quota 常數的原始碼切片
// SHA-256 必須與 baseline_fixtures.json 一致。搬移程式碼時只能改 fixtures 的
// file 欄位（指向新家），sha256 永遠是 baseline 的值——期望值不得由新實作
// 重新產生。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
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

Deno.test("baseline：prompt/model/token 原始碼切片 hash 與 fc8bbe84 一致", async () => {
  for (const [name, slice] of Object.entries(fixtures.promptSlices)) {
    const source = await readSource(slice.file);
    const extracted = extractSlice(source, slice, name);
    assertEquals(
      await sha256Hex(extracted),
      slice.sha256,
      `${name} 的原始碼位元組偏離 baseline（${slice.file}）`,
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
