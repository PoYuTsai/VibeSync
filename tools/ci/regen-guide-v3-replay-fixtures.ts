// v3 重播測試的期望值：把錄下的兩段模型原始輸出原樣餵回現行的 v3 流程
//（guide_v3/replay_harness.ts），把它送給 App 的事件、扣費呼叫與落帳結果存成
// supabase/functions/analyze-chat/testdata/guide_v3_replay_fixtures.json。不呼叫模型、
// 不連網、不花錢。來源有兩種：
//   - 新錄音：v3 黑箱 run_v3.ts 產生的 v3-records.json，只取內建語料（corpus.ts）每案
//     第 1 次；本機額外題目（D 測試、B47 題）可能改寫自課程，不進 repo。
//   - 有意改了伺服器處理：直接給現有的 guide_v3_replay_fixtures.json，沿用裡面錄好的
//     原始輸出重產期望值，審查時看差異。
//
//   deno run --allow-read --allow-env \
//     --allow-write=supabase/functions/analyze-chat/testdata \
//     tools/ci/regen-guide-v3-replay-fixtures.ts <v3-records.json 或 guide_v3_replay_fixtures.json>
import { CORPUS } from "../analyze-v2-blackbox/corpus.ts";
import { replayGuideV3 } from "../../supabase/functions/analyze-chat/guide_v3/replay_harness.ts";

const OUT =
  "supabase/functions/analyze-chat/testdata/guide_v3_replay_fixtures.json";

const [sourcePath] = Deno.args;
if (!sourcePath) {
  console.error("usage: regen-guide-v3-replay-fixtures.ts <v3-records.json>");
  Deno.exit(2);
}

/// 錄音早於讀局面的自傷欄位（10/16 加）：補上 false，其他欄位一字不動。
function withSelfHarmField(readText: string): string {
  const tags = JSON.parse(readText);
  return "selfHarmSignal" in tags
    ? readText
    : JSON.stringify({ ...tags, selfHarmSignal: false });
}

const source = JSON.parse(await Deno.readTextFile(sourcePath));
const corpusById = new Map(CORPUS.map((c) => [c.id, c]));
type Input = {
  name: string;
  messages: { isFromMe: boolean; content: string }[];
  readText: string;
  writeText: string;
};
let inputs: Input[];
let meta: Record<string, unknown>;
if (Array.isArray(source.cases)) {
  inputs = source.cases;
  meta = source.meta;
} else {
  inputs = (source.records as {
    caseId: string;
    rep: number;
    readText: string;
    writeText: string;
    error: string | null;
  }[])
    .filter((r) => r.rep === 1 && corpusById.has(r.caseId) && !r.error)
    .map((r) => ({
      name: `${r.caseId}#1`,
      messages: corpusById.get(r.caseId)!.messages.map((m) => ({
        isFromMe: m.isFromMe,
        content: m.content,
      })),
      readText: withSelfHarmField(r.readText),
      writeText: r.writeText,
    }));
  meta = {
    source: String(source.meta?.tag ?? sourcePath.split("/").at(-2)),
    model: source.meta?.model ?? null,
    guideSha256: source.meta?.guideSha256 ?? null,
    note:
      "內建語料每案第 1 次；讀局面的 JSON 補了 selfHarmSignal:false（錄音早於這個欄位）。",
  };
}
inputs.sort((a, b) => a.name.localeCompare(b.name));
const cases = [];
for (const input of inputs) {
  const outcome = await replayGuideV3(input);
  cases.push({ ...input, expected: outcome });
}
await Deno.writeTextFile(OUT, JSON.stringify({ meta, cases }, null, 2) + "\n");
console.error(`wrote ${cases.length} cases → ${OUT}`);
