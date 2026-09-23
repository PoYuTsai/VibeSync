// 開場救星兩段式：離線內容回放（第五輪驗收 reviewer 標籤 → 正式路徑回歸）。
//
// 用已捕獲的 snapshot＋contribution＋模型 raw，注入正式的
// validateContributionAgainstSnapshot → buildOpenerMaterials → normalizeOpenerGenerateOutput
// → 內容硬檢查（含原料採用）→ projectOpenerGenerateResult（Free 三卡／paid 五卡），
// 對照 labels.json：expect_flag（該卡必須被硬檢查抓到）、expect_clean（不得誤判）、
// adoption（miss／partial／clear）。不打模型；這是舊 raw 的離線斷言，不代表新 prompt 的輸出。
//
//   deno run --allow-read --allow-write tools/opener-content-replay/run.ts [--out=<dir>]
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { type OpenerAnalysisSnapshot, type OpenerContribution, validateContributionAgainstSnapshot } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import * as material from "../../supabase/functions/analyze-chat/opener_material.ts";
import { normalizeOpenerGenerateOutput, projectOpenerGenerateResult } from "../../supabase/functions/analyze-chat/opener_flow_payload.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES, type OpenerType } from "../../supabase/functions/analyze-chat/opener_payload.ts";

const outDir = Deno.args.find((a) => a.startsWith("--out="))?.slice(6) ?? "tools/opener-content-replay/out";
await Deno.mkdir(outDir, { recursive: true });
const labels = JSON.parse(await Deno.readTextFile(new URL("./labels.json", import.meta.url))) as {
  cases: Array<{ id: string; source: string; expect_flag: Record<string, string>; expect_clean?: string[]; expect_soft?: Record<string, string>; adoption: "miss" | "partial" | "clear" | "exempt" | null; note?: string; informational?: Record<string, string> }>;
};
// 修正後才有的正式入口（採用檢查／證據判定）；不存在時就是紅燈，不在 harness 自己實作替身。
const mod = material as unknown as Record<string, unknown>;
const checkAdoption = typeof mod.checkMaterialAdoption === "function"
  ? mod.checkMaterialAdoption as (i: { openers: Record<string, string>; materials: material.OpenerMaterialSet; visibleTypes: readonly OpenerType[]; rankedPicks: OpenerType[]; flags: material.OpenerQualityFlag[] }) => material.OpenerQualityFlag[]
  : null;
const cardAdopts = typeof mod.cardAdoptsMaterial === "function"
  ? mod.cardAdoptsMaterial as (text: string, set: material.OpenerMaterialSet) => boolean
  : null;

interface Row { id: string; check: string; status: "PASS" | "FAIL"; detail: string }
const rows: Row[] = [];
const lines: string[] = [`# opener 內容離線回放 · ${new Date().toISOString()}`, `- 採用檢查入口：${checkAdoption ? "有" : "無（未修正版本）"}；證據判定入口：${cardAdopts ? "有" : "無"}`, ""];
const add = (id: string, check: string, ok: boolean, detail: string) => { rows.push({ id, check, status: ok ? "PASS" : "FAIL", detail }); };

for (const c of labels.cases) {
  const fx = JSON.parse(await Deno.readTextFile(new URL(`./fixtures/${c.source}`, import.meta.url))) as { snapshot: OpenerAnalysisSnapshot; contribution: OpenerContribution; raw: string; captured_flags: string[] };
  const check = validateContributionAgainstSnapshot(fx.contribution, fx.snapshot);
  const materials = material.buildOpenerMaterials({ snapshot: fx.snapshot, contribution: fx.contribution, option: check.ok ? check.option : null });
  const normalized = normalizeOpenerGenerateOutput(parseJsonObjectFromText(fx.raw), materials);
  lines.push(`## ${c.id}（${c.source}）adoption=${c.adoption ?? "—"}${c.note ? `；${c.note}` : ""}`);
  if (!normalized.ok) { lines.push(`- 格式無法正規化：${normalized.reason}`, ""); add(c.id, "normalize", false, normalized.reason); continue; }
  const openers = normalized.value.openers;
  const allFlags = material.checkOpenersAgainstMaterials(openers, materials, fx.snapshot);
  const baseFlags = material.hardFlags(allFlags);
  const soft = new Map<string, string[]>();
  for (const f of allFlags.filter((f) => f.severity === "soft")) soft.set(f.style ?? "?", [...(soft.get(f.style ?? "?") ?? []), `${f.code}${f.detail ? `(${f.detail})` : ""}`]);
  const flagged = new Map<string, string[]>();
  for (const f of baseFlags) flagged.set(f.style ?? "?", [...(flagged.get(f.style ?? "?") ?? []), `${f.code}${f.detail ? `(${f.detail})` : ""}`]);
  lines.push(`- 硬檢查：${[...flagged.entries()].map(([s, v]) => `${s}=${v.join("+")}`).join("、") || "無"}；soft：${[...soft.entries()].map(([s, v]) => `${s}=${v.join("+")}`).join("、") || "無"}`);
  for (const [style, why] of Object.entries(c.expect_soft ?? {})) {
    const ok = soft.has(style) && !flagged.has(style);
    add(c.id, `expect_soft:${style}`, ok, ok ? soft.get(style)!.join("+") : `應為 soft（${why}）；hard=${flagged.get(style)?.join("+") ?? "無"} soft=${soft.get(style)?.join("+") ?? "無"}`);
  }
  for (const [style, why] of Object.entries(c.expect_flag)) {
    const ok = flagged.has(style);
    add(c.id, `expect_flag:${style}`, ok, ok ? flagged.get(style)!.join("+") : `未抓到（${why}）`);
  }
  for (const style of c.expect_clean ?? []) {
    const ok = !flagged.has(style);
    add(c.id, `expect_clean:${style}`, ok, ok ? "無誤判" : `誤判 ${flagged.get(style)!.join("+")}`);
  }
  for (const [tier, visible] of [["free", OPENER_FREE_V2_TYPES], ["paid", OPENER_TYPES]] as const) {
    const adoptionFlags = checkAdoption ? checkAdoption({ openers, materials, visibleTypes: visible, rankedPicks: normalized.value.rankedPicks, flags: baseFlags }) : [];
    const unused = adoptionFlags.some((f) => (f.code as string) === "material_unused");
    const projected = projectOpenerGenerateResult({ normalized: normalized.value, materials, visibleTypes: visible, servedTier: tier === "free" ? "free" : "essential", contractVersion: 2 });
    const pick = projected?.recommendation.pick ?? null;
    const pickAdopts = pick && cardAdopts ? cardAdopts(openers[pick], materials) : null;
    lines.push(`- [${tier}] 推薦=${pick} 推薦有原料證據=${pickAdopts ?? "無法判定"} material_unused=${unused} trace=${projected?.materialUse.traceStatus}`);
    const pickFlagged = pick ? flagged.has(pick) : false;
    const pickOk = pickAdopts === true && !pickFlagged;
    if (c.adoption === "miss" || c.adoption === "partial") {
      // 產品判準：推薦卡必須在內容上接住原料且本身乾淨；否則整組要被 material_unused 擋下去修正。
      // 離線投影不知道硬檢查；正式流程裡被標記的卡會先進修正、修不好整組 502 不扣，所以「推薦卡本身被標記」也算已擋。
      add(c.id, `adoption:${tier}`, unused || pickFlagged || pickOk, unused ? "material_unused 已擋（交修正）" : pickFlagged ? `推薦 ${pick} 本身被硬檢查標記（交修正／不交付）` : pickOk ? `推薦改到有證據且乾淨的卡 ${pick}` : `推薦 ${pick} 不接原料（adopts=${pickAdopts}），也沒被擋`);
    } else if (c.adoption === "clear") {
      add(c.id, `adoption:${tier}`, !unused && pickAdopts !== false, !unused && pickAdopts !== false ? `推薦 ${pick} 有證據、無誤擋` : `誤判：material_unused=${unused} pickAdopts=${pickAdopts}`);
    } else if (c.adoption === "exempt") {
      // 純排除／否定型補充：遵守就是採用，沒有要被接住的正向內容，只能斷言不得誤擋。
      // 2026-09-24 教練定位：想約目標型補充這一則不邀約、不要求採用，同樣只斷言不得誤擋。
      add(c.id, `adoption:${tier}`, !unused, !unused ? `純排除型／想約目標型補充未被誤擋（推薦 ${pick}）` : `誤判：material_unused=${unused}`);
    }
  }
  lines.push("");
}
const failed = rows.filter((r) => r.status === "FAIL");
lines.push(`## 結果：${rows.length - failed.length}/${rows.length} PASS${failed.length ? `；${failed.length} FAIL` : ""}`);
for (const r of failed) lines.push(`- FAIL ${r.id} ${r.check}：${r.detail}`);
await Deno.writeTextFile(`${outDir}/results.md`, lines.join("\n") + "\n");
await Deno.writeTextFile(`${outDir}/results.json`, JSON.stringify(rows, null, 2));
console.log(lines.join("\n"));
Deno.exit(failed.length ? 1 : 0);
