// 跨兩次真跑做盲選表：<基準 records.json> 的某臂 vs <候選 records.json> 的某臂，
// 每個 rep 一份表（甲乙隨機）。不打模型。
// deno run --allow-read --allow-write=tools/analyze-v2-blackbox/out tools/analyze-v2-blackbox/blind_pair.ts \
//   <base-records.json> <A> <cand-records.json> <C> <reps> <out-dir>
import { buildBlindSheet, type CallRecord } from "./ab.ts";

const [baseFile, baseArm, candFile, candArm, repsArg, outDir] = Deno.args;
if (!outDir) throw new Error("usage: base arm cand arm reps outDir");
const load = async (file: string, arm: string, as: "A" | "B") =>
  (JSON.parse(await Deno.readTextFile(file)).records as CallRecord[])
    .filter((r) => r.arm === arm)
    .map((r) => ({ ...r, arm: as }) as CallRecord);
const base = await load(baseFile, baseArm, "A");
const cand = await load(candFile, candArm, "B");
for (let rep = 1; rep <= Number(repsArg); rep++) {
  const asRep1 = [...base, ...cand]
    .filter((r) => r.rep === rep)
    .map((r) => ({ ...r, rep: 1 }) as CallRecord);
  const sheet = buildBlindSheet(asRep1, 20261002 + rep, 999);
  if (!sheet) throw new Error(`rep ${rep}: no paired cases`);
  await Deno.writeTextFile(`${outDir}/blind-r${rep}.md`, sheet.markdown);
  await Deno.writeTextFile(
    `${outDir}/blind-r${rep}-reveal.json`,
    JSON.stringify(
      {
        base: `${baseFile}:${baseArm}`,
        cand: `${candFile}:${candArm}`,
        A: "base",
        B: "cand",
        ...sheet.reveal,
      },
      null,
      2,
    ),
  );
  console.log(`rep ${rep}: ${(sheet.reveal.cases as unknown[]).length} pairs`);
}
