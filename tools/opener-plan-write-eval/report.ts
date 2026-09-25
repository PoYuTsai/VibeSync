// 黑箱彙整：讀 judge.ts 的 judged.json，依臂 × 重複列出閘門指標（需求凍結 §6-3）。
// 用法：deno run -A tools/opener-plan-write-eval/report.ts <judged.json> [> report.md]

import { graphemeLength } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import { longestProfileCopy } from "../../supabase/functions/analyze-chat/opener_pick.ts";

interface Row {
  key: string;
  arm: string;
  caseId: string;
  repeat: number;
  status: number;
  elapsedMs?: number;
  costUsd?: number;
  pickText?: string;
  pickWilling?: boolean | null;
  pickCodes?: string[] | null;
  willingCount?: number | null;
  cardCount?: number;
  judgeBestIsPick?: boolean | null;
  bio?: string;
}

const judged = JSON.parse(await Deno.readTextFile(Deno.args[0])) as { rows: Row[] };
const rows = judged.rows;
const pct = (n: number, d: number) => d ? `${n}/${d}` : "—";
const quantile = (xs: number[], q: number) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(q * s.length) - 1)];
};

const lines: string[] = ["# 結構刀黑箱彙整", "", "| 臂 | 次 | 交付 | 推薦願意傳 | 推薦=評審最想傳 | 全卡願意傳 | 推薦兩問 | 推薦照抄自介≥6字 | 推薦中位字數 | p50 秒 | p95 秒 | 平均成本 US$ |", "|---|---|---|---|---|---|---|---|---|---|---|---|"];
const arms = [...new Set(rows.map((r) => r.arm))].sort();
const repeats = [...new Set(rows.map((r) => r.repeat))].sort();
for (const arm of arms) {
  for (const repeat of [...repeats, 0]) {
    const rs = rows.filter((r) => r.arm === arm && (repeat === 0 || r.repeat === repeat));
    const ok = rs.filter((r) => r.status === 200 && r.pickText);
    const judgedOk = ok.filter((r) => r.pickWilling !== null && r.pickWilling !== undefined);
    const lengths = ok.map((r) => graphemeLength(r.pickText!));
    const lat = rs.filter((r) => typeof r.elapsedMs === "number").map((r) => r.elapsedMs! / 1000);
    const costs = rs.filter((r) => typeof r.costUsd === "number").map((r) => r.costUsd!);
    lines.push(`| ${arm} | ${repeat || "合計"} | ${pct(ok.length, rs.length)} | ${pct(judgedOk.filter((r) => r.pickWilling).length, judgedOk.length)} | ${pct(judgedOk.filter((r) => r.judgeBestIsPick).length, judgedOk.length)} | ${pct(judgedOk.reduce((s, r) => s + (r.willingCount ?? 0), 0), judgedOk.reduce((s, r) => s + (r.cardCount ?? 0), 0))} | ${ok.filter((r) => (r.pickText!.match(/[?？]+/gu) ?? []).length >= 2).length} | ${ok.filter((r) => longestProfileCopy(r.pickText!, r.bio ?? "") >= 6).length} | ${quantile(lengths, 0.5) ?? "—"} | ${quantile(lat, 0.5)?.toFixed(1) ?? "—"} | ${quantile(lat, 0.95)?.toFixed(1) ?? "—"} | ${costs.length ? (costs.reduce((a, b) => a + b, 0) / costs.length).toFixed(4) : "—"} |`);
  }
}

lines.push("", "## 推薦句不願意傳的代碼（合計）", "", "| 臂 | " + ["known_answer", "first_invite", "self_hook", "private_probe", "two_threads", "cold_read", "hard_to_answer", "fabricated", "awkward"].join(" | ") + " |", "|---|" + "---|".repeat(9));
for (const arm of arms) {
  const counts: Record<string, number> = {};
  for (const r of rows.filter((x) => x.arm === arm)) for (const c of r.pickCodes ?? []) counts[c] = (counts[c] ?? 0) + 1;
  lines.push(`| ${arm} | ` + ["known_answer", "first_invite", "self_hook", "private_probe", "two_threads", "cold_read", "hard_to_answer", "fabricated", "awkward"].map((c) => counts[c] ?? 0).join(" | ") + " |");
}

lines.push("", "## 逐題推薦句（每臂每次）", "");
for (const caseId of [...new Set(rows.map((r) => r.caseId))]) {
  lines.push(`### ${caseId}`);
  for (const r of rows.filter((x) => x.caseId === caseId).sort((a, b) => a.arm.localeCompare(b.arm) || a.repeat - b.repeat)) {
    const mark = r.pickWilling === true ? "✓" : r.pickWilling === false ? `✗ ${(r.pickCodes ?? []).join(",")}` : "";
    lines.push(`- ${r.arm}#${r.repeat} ${r.status === 200 ? r.pickText : `（${r.status}）`} ${mark}`);
  }
  lines.push("");
}
console.log(lines.join("\n"));
