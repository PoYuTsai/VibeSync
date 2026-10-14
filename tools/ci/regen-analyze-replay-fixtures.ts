// 重播測試的期望值：把錄下的模型原始輸出原樣餵回現行伺服器（analyze_replay_harness.ts），
// 把它送給 App 的事件與落帳結果存成 testdata/analyze_replay_fixtures.json。不呼叫模型、
// 不連網、不花錢。來源有兩種：
//   - 新錄音：黑箱 run_blackbox.ts --keep-raw 產生的 arm-C.json，取每案第 1 次。
//   - 有意改了伺服器處理：直接給現有的 analyze_replay_fixtures.json，沿用裡面錄好的
//     原始輸出重產期望值，審查時看差異（原始錄音檔不必進 repo）。
//
//   deno run --allow-read --allow-env \
//     --allow-write=supabase/functions/analyze-chat/testdata \
//     tools/ci/regen-analyze-replay-fixtures.ts <arm-C.json 或 analyze_replay_fixtures.json>
import { CORPUS } from "../analyze-v2-blackbox/corpus.ts";

const [sourcePath] = Deno.args;
if (!sourcePath) {
  console.error("usage: regen-analyze-replay-fixtures.ts <arm-C.json>");
  Deno.exit(2);
}

// 分析處理會寫 ai_logs（送到 deps.supabaseUrl），有些模組在載入時就抓住 fetch，
// 所以先換成不連網的替身，再載入重播工具。
globalThis.fetch = (() =>
  Promise.resolve(
    new Response("{}", {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  )) as typeof fetch;
const { normalizeReplayOutcome, replayAnalyzeStream } = await import(
  "../../supabase/functions/analyze-chat/analyze_replay_harness.ts"
);

const source = JSON.parse(await Deno.readTextFile(sourcePath));
const corpusById = new Map(CORPUS.map((c) => [c.id, c]));
const fromFixtures = Array.isArray(source.cases);
const inputs: { name: string; rawText: unknown }[] = fromFixtures
  ? source.cases
  : source.results.filter((r: { name: string }) =>
    String(r.name).endsWith("#1")
  );
const cases = [];
for (const r of inputs) {
  const name = String(r.name);
  if (typeof r.rawText !== "string" || r.rawText.trim() === "") {
    throw new Error(`${name}: 錄音沒有 rawText，要用 --keep-raw 重錄`);
  }
  const spec = corpusById.get(name.replace(/#\d+$/, ""));
  if (!spec) throw new Error(`${name}: 不在語料裡`);
  const replayCase = {
    name,
    messages: spec.messages.map((m) => ({
      isFromMe: m.isFromMe,
      content: m.content,
    })),
    rawText: r.rawText,
  };
  const expected = normalizeReplayOutcome(
    await replayAnalyzeStream(replayCase),
  );
  const again = normalizeReplayOutcome(await replayAnalyzeStream(replayCase));
  // 同一份輸入重播兩次要完全一樣，否則期望值裡有跟行為無關的欄位，要先處理。
  if (JSON.stringify(expected) !== JSON.stringify(again)) {
    throw new Error(`${name}: 重播兩次結果不同`);
  }
  cases.push({ ...replayCase, expected });
}
cases.sort((a, b) => a.name.localeCompare(b.name));
const out = {
  meta: fromFixtures ? { ...source.meta, cases: cases.length } : {
    source: sourcePath.replace(/^.*tools\/analyze-v2-blackbox\//, ""),
    sourceTag: source.meta?.tag ?? null,
    sourceCommit: source.meta?.commit ?? null,
    model: "claude-sonnet-5-5",
    cases: cases.length,
  },
  cases,
};
const target = new URL(
  "../../supabase/functions/analyze-chat/testdata/analyze_replay_fixtures.json",
  import.meta.url,
).pathname;
await Deno.writeTextFile(target, JSON.stringify(out, null, 1) + "\n");
console.error(`寫入 ${cases.length} 案：${target}`);
