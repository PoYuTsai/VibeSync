// 開場救星兩段式：一次內容修正的離線回放 runner（只供驗收；付費要 --run --confirm-paid）。
//
//   deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com tools/opener-repair-replay/run.ts \
//     --manifest=<jobs/manifest.json> --captured-root=<packet root> --tag=<name> --budget-usd=0.60 [--run --confirm-paid]
//
// 固定清單（manifest）→ 核對 raw／snapshot 檔案 sha256 → prepareJob（正式 material／normalize／guard／adoption）
// → 保守成本預檢（輸入估算×1.3＋正式 max_tokens 全滿）→ 順序執行，每筆最多一次呼叫、無隱式重試
// → applyCorrection（正式 merge／normalize／guard／adoption／方案投影）→ 逐筆保存＋ledger＋盲審包＋解盲表。
import { estimateCostUsd, SONNET_5_PRICING } from "../../supabase/functions/_shared/model_pricing.ts";
import { OPENER_FLOW_MODEL, OPENER_GENERATE_MAX_TOKENS, OPENER_GENERATE_PROMPT } from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import { OPENER_FLOW_PROMPT_VERSION } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import { type JobRun, type ModelResult, prepareJob, type PreparedJob, type RepairJob, runJob } from "./pipeline.ts";

const arg = (n: string) => Deno.args.find((a) => a.startsWith(`--${n}=`))?.slice(n.length + 3) ?? null;
const manifestPath = arg("manifest");
const capturedRoot = arg("captured-root");
const tag = arg("tag") ?? "dry-run";
const budgetUsd = Number(arg("budget-usd") ?? "0.60");
const maxCalls = Number(arg("max-calls") ?? "12");
const run = Deno.args.includes("--run");
const confirmPaid = Deno.args.includes("--confirm-paid");
if (!manifestPath || !capturedRoot) { console.error("需要 --manifest 與 --captured-root"); Deno.exit(2); }
if (run && !confirmPaid) { console.error("真跑付費模型需要同時帶 --run --confirm-paid（Eric 授權後）。"); Deno.exit(2); }

const outDir = new URL(`./out/${tag}/`, import.meta.url);
await Deno.mkdir(new URL("jobs/", outDir), { recursive: true });
const startedAt = new Date().toISOString();

async function sha256Text(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function sha256File(path: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", await Deno.readFile(path));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function estimateTokens(text: string): number {
  return Math.ceil(text.length / 1.1);
}
function worstCaseUsd(system: string, user: string): number {
  return estimateCostUsd({ inputTokens: Math.ceil(estimateTokens(system + user) * 1.3), outputTokens: OPENER_GENERATE_MAX_TOKENS, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING);
}
function actualUsd(usage: { input_tokens: number; output_tokens: number }): number {
  return estimateCostUsd({ inputTokens: usage.input_tokens, outputTokens: usage.output_tokens, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING);
}

/** 單次 fetch、無 SDK、無隱式重試；沒有 usage 的結果一律當失敗（成本以最壞情況計）。 */
async function callModel(system: string, user: string, maxTokens: number): Promise<ModelResult> {
  const apiKey = (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`)).trim();
  const started = Date.now();
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model: OPENER_FLOW_MODEL, max_tokens: maxTokens, system, messages: [{ role: "user", content: user }] }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`API 失敗（HTTP ${res.status}）：${JSON.stringify(json.error)}`);
  if (!json.usage) throw new Error(`API 回應沒有 usage（HTTP ${res.status}）`);
  const text = (json.content as Array<{ type: string; text?: string }>).find((b) => b.type === "text")?.text ?? "";
  return { text, stopReason: json.stop_reason, usage: { input_tokens: json.usage.input_tokens, output_tokens: json.usage.output_tokens }, elapsedMs: Date.now() - started, model: json.model ?? OPENER_FLOW_MODEL, rawBody: json };
}

const manifest = JSON.parse(await Deno.readTextFile(manifestPath)) as { candidate_sha: string; authorization: Record<string, unknown>; jobs: RepairJob[] };
const jobs = manifest.jobs;
if (jobs.length > maxCalls) { console.error(`清單 ${jobs.length} 筆超過 --max-calls=${maxCalls}`); Deno.exit(2); }

// 1. 核對輸入檔 sha256 與準備（正式函式重算旗標）。
const prepared: Array<{ job: RepairJob; p: PreparedJob; rawSha: string; snapSha: string; shaOk: boolean; worst: number }> = [];
for (const job of jobs) {
  const rawPath = `${capturedRoot}/${job.raw_file}`;
  const snapPath = `${capturedRoot}/${job.snapshot_file}`;
  const rawSha = await sha256File(rawPath);
  const snapSha = await sha256File(snapPath);
  const rawJson = JSON.parse(await Deno.readTextFile(rawPath));
  const snapJson = JSON.parse(await Deno.readTextFile(snapPath));
  const p = prepareJob(job, snapJson.snapshot, rawJson.raw);
  const shaOk = rawSha === job.raw_file_sha256 && snapSha === job.snapshot_file_sha256;
  const contributionSame = JSON.stringify(rawJson.contribution) === JSON.stringify(job.contribution);
  prepared.push({ job, p, rawSha, snapSha, shaOk: shaOk && contributionSame, worst: p.correctionUser ? worstCaseUsd(OPENER_GENERATE_PROMPT, p.correctionUser) : 0 });
}

const summary: string[] = [`# opener 一次內容修正回放 · ${tag} · ${OPENER_FLOW_MODEL} · ${startedAt} · ${run ? "RUN" : "DRY-RUN"}`, `候選 ${manifest.candidate_sha}；清單 ${jobs.length} 筆；硬上限 $${budgetUsd}；每筆最多一次呼叫、無重試。`, "", "## 前置核對", "| 作業 | 方案 | sha 核對 | hardBefore（正式重算） | 換卡 | 修正提示字數 | 最壞成本 |", "|---|---|---|---|---|---|---|"];
let worstTotal = 0;
for (const x of prepared) {
  worstTotal += x.worst;
  summary.push(`| ${x.job.job_id} | ${x.job.tier_label} | ${x.shaOk ? "OK" : "**不符**"} | ${x.p.hardBefore.map((f) => `${f.style}:${f.code}${f.detail ? `(${f.detail})` : ""}`).join("、") || `（${x.p.preflight}）`} | ${x.p.stylesToReplace.join(",") || "—"} | ${x.p.correctionUser?.length ?? 0} | $${x.worst.toFixed(4)} |`);
}
summary.push("", `- 全部最壞情況合計 $${worstTotal.toFixed(4)}（輸入估算×1.3＋max_tokens ${OPENER_GENERATE_MAX_TOKENS} 全滿；${worstTotal <= budgetUsd ? "在上限內" : "**超過上限，真跑不得開始**"}）`);
const preflightBad = prepared.filter((x) => !x.shaOk || x.p.preflight !== "ok");
if (preflightBad.length) summary.push(`- **前置不符 ${preflightBad.length} 筆**：${preflightBad.map((x) => `${x.job.job_id}（${x.shaOk ? x.p.preflight : "sha/contribution 不符"}）`).join("、")}`);

const runs: Array<{ job: RepairJob; run: JobRun; costUsd: number; costBasis: "usage" | "worst_case" | "none" }> = [];
let spent = 0;
let stopped = false;
if (run) {
  if (worstTotal > budgetUsd) { summary.push("- 真跑未開始：保守估算超過上限。"); }
  else if (preflightBad.length) { summary.push("- 真跑未開始：清單有前置不符，先修正清單／檔案定位。"); }
  else {
    for (const x of prepared) {
      if (stopped || spent + x.worst > budgetUsd) {
        stopped = true;
        runs.push({ job: x.job, run: { prepared: x.p, calls: 0, request: null, response: null, error: null, outcome: { classification: "not_run_budget_or_preflight", reason: `預算守門：已計 $${spent.toFixed(4)}＋最壞 $${x.worst.toFixed(4)} 超過 $${budgetUsd}`, correctionText: null, correctionParsed: null, merged: null, normalizeAfter: null, openersAfter: null, flagsAfter: [], hardAfter: [], untouchedPreserved: null, projectionAfter: null } }, costUsd: 0, costBasis: "none" });
        continue;
      }
      const r = await runJob(x.p, callModel, OPENER_FLOW_MODEL);
      const cost = r.response?.usage ? actualUsd(r.response.usage) : (r.calls ? x.worst : 0);
      spent += cost;
      runs.push({ job: x.job, run: r, costUsd: cost, costBasis: r.response?.usage ? "usage" : r.calls ? "worst_case" : "none" });
    }
  }
}

// 2. 逐筆保存（完整：snapshot／contribution／初次 raw／精確修正提示／request／response／merge／前後 flags／投影）。
for (const x of (run ? runs : prepared.map((x) => ({ job: x.job, run: null, costUsd: 0, costBasis: "none" as const, p: x.p })))) {
  const p = "p" in x ? x.p : x.run!.prepared;
  const r = "run" in x ? x.run : null;
  await Deno.writeTextFile(new URL(`jobs/${x.job.job_id}.json`, outDir), JSON.stringify({
    job: x.job, candidateSha: manifest.candidate_sha,
    snapshot: p.snapshot, contribution: p.contribution, contributionCheckOk: p.contributionCheckOk,
    materials: p.materials, visibleTypes: p.visibleTypes,
    initialRaw: p.initialRaw, initialParsed: p.parsedJson, normalizeBefore: p.normalizeBefore, initialOpeners: p.initialOpeners,
    flagsBefore: p.flagsBefore, hardBefore: p.hardBefore, stylesToReplace: p.stylesToReplace, projectionBefore: p.projectionBefore,
    correctionPrompt: p.correctionUser, request: r?.request ?? null, response: r?.response ?? null, error: r?.error ?? null, calls: r?.calls ?? 0,
    outcome: r?.outcome ?? null, costUsd: x.costUsd, costBasis: x.costBasis,
  }, null, 2));
}

// 3. ledger／meta／summary／盲審包／解盲表。
const productFiles = ["opener_flow_prompt.ts", "opener_material.ts", "opener_flow_payload.ts", "opener_flow_handler.ts", "opener_stage.ts", "opener_payload.ts", "json_text.ts"];
const productSha: Record<string, string> = {};
for (const f of productFiles) productSha[f] = await sha256File(new URL(`../../supabase/functions/analyze-chat/${f}`, import.meta.url).pathname);
const toolSha = { "pipeline.ts": await sha256File(new URL("./pipeline.ts", import.meta.url).pathname), "run.ts": await sha256File(new URL("./run.ts", import.meta.url).pathname) };
await Deno.writeTextFile(new URL("meta.json", outDir), JSON.stringify({
  tag, run, candidateSha: manifest.candidate_sha, manifestPath, capturedRoot, model: OPENER_FLOW_MODEL, maxTokens: OPENER_GENERATE_MAX_TOKENS, thinking: "not sent (同正式 defaultInvokeModel)", promptCache: "none", retries: "none (正式 callClaudeWithFallback maxRetries=1；本回放停用)",
  promptVersion: OPENER_FLOW_PROMPT_VERSION, generatePromptSha256: await sha256Text(OPENER_GENERATE_PROMPT), productFileSha256: productSha, toolFileSha256: toolSha,
  pricing: SONNET_5_PRICING, budgetUsd, maxCalls, authorization: manifest.authorization, startedAt, finishedAt: new Date().toISOString(),
}, null, 2));
if (run) {
  const ledger = runs.map((x) => ({ job_id: x.job.job_id, tier: x.job.tier_label, source_key: x.job.source_key, calls: x.run.calls, model: x.run.response?.model ?? null, stopReason: x.run.response?.stopReason ?? null, inputTokens: x.run.response?.usage?.input_tokens ?? null, outputTokens: x.run.response?.usage?.output_tokens ?? null, elapsedMs: x.run.response?.elapsedMs ?? null, costUsd: x.costUsd, costBasis: x.costBasis, classification: x.run.outcome.classification, reason: x.run.outcome.reason, error: x.run.error }));
  await Deno.writeTextFile(new URL("cost.json", outDir), JSON.stringify({ budgetUsd, spentUsd: spent, budgetStopped: stopped, paidCalls: runs.reduce((a, x) => a + x.run.calls, 0), ledger }, null, 2));
  await Deno.writeTextFile(new URL("results.json", outDir), JSON.stringify(ledger, null, 2));
  const count = (c: string, tier?: string) => runs.filter((x) => x.run.outcome.classification === c && (!tier || x.job.tier_label === tier)).length;
  summary.push("", "## 執行結果", `- 付費呼叫 ${runs.reduce((a, x) => a + x.run.calls, 0)}／上限 ${maxCalls}；實際計入 $${spent.toFixed(4)}／上限 $${budgetUsd}；預算守門停止：${stopped ? "是" : "否"}`);
  for (const tier of ["free", "paid"]) summary.push(`- ${tier}：ready_for_content_review ${count("ready_for_content_review", tier)}、content_rejected ${count("content_rejected", tier)}、format_or_provider_failure ${count("format_or_provider_failure", tier)}、not_run ${count("not_run_budget_or_preflight", tier)}`);
  summary.push("", "| 作業 | 方案 | 結果 | in/out tokens | 耗時 | 成本 | 換卡 | 修後 hard | 未標記卡逐字保留 | 推薦 |", "|---|---|---|---|---|---|---|---|---|---|");
  for (const x of runs) summary.push(`| ${x.job.job_id} | ${x.job.tier_label} | ${x.run.outcome.classification} | ${x.run.response?.usage ? `${x.run.response.usage.input_tokens}/${x.run.response.usage.output_tokens}` : "—"} | ${x.run.response?.elapsedMs ?? "—"}ms | $${x.costUsd.toFixed(4)}（${x.costBasis}） | ${x.run.prepared.stylesToReplace.join(",")} | ${x.run.outcome.hardAfter.map((f) => `${f.style}:${f.code}`).join("、") || "無"} | ${x.run.outcome.untouchedPreserved ?? "—"} | ${x.run.outcome.projectionAfter?.pick ?? "—"} |`);
  summary.push("", "## 逐筆內容（修正前→後）");
  for (const x of runs) {
    const p = x.run.prepared;
    summary.push(`### ${x.job.job_id}（${x.job.source_key}，${x.job.tier_label}）`, `- 用戶回答：${p.contribution.freeText ?? "（只選選項）"}`, `- hardBefore：${p.hardBefore.map((f) => `${f.style}:${f.code}${f.detail ? `(${f.detail})` : ""}`).join("、")}`);
    for (const style of p.stylesToReplace) summary.push(`- ${style}：「${p.initialOpeners?.[style as keyof typeof p.initialOpeners] ?? ""}」→「${x.run.outcome.openersAfter?.[style as keyof typeof x.run.outcome.openersAfter] ?? "（無）"}」`);
    summary.push(`- 結果：${x.run.outcome.classification}：${x.run.outcome.reason}${x.run.error ? `；錯誤：${x.run.error}` : ""}`, "");
  }

  // 盲審：Free／paid 各自；只呈現來源、用戶想法、可見推薦★與備選；被拒絕者標「未交付」但保留草稿供追查。
  let seed = 20260918;
  const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const shuffled = [...runs].map((x) => ({ x, k: rand() })).sort((a, b) => a.k - b.k).map((o) => o.x);
  const key: Record<string, unknown> = {};
  for (const tier of ["free", "paid"] as const) {
    const items = shuffled.filter((x) => x.job.tier_label === tier);
    const lines = [`# 一次內容修正後盲審（${tier === "free" ? "Free 三卡" : "paid 五卡"}）· 候選 ${manifest.candidate_sha.slice(0, 8)} · 順序已打亂`, "", "每題請評：忠於本人／事實正確／原料影響／自然好讀／對方好接／備選價值／原意保留（各 1–5），並註明推薦（★）是否是你會選的那句；有事實錯誤或違反用戶限制請點名。", "標「未交付」的題目是正式流程不會交付的結果（修正後仍有硬錯誤或格式失敗），草稿只供追查，不算成品。", ""];
    items.forEach((x, i) => {
      const code = `${tier === "free" ? "RF" : "RP"}${String(i + 1).padStart(2, "0")}`;
      const p = x.run.prepared;
      const o = x.run.outcome;
      key[code] = { job_id: x.job.job_id, source_key: x.job.source_key, tier, classification: o.classification, reason: o.reason, stylesToReplace: p.stylesToReplace, hardBefore: p.hardBefore, hardAfter: o.hardAfter, flagsAfter: o.flagsAfter, pick: o.projectionAfter?.pick ?? null, recommendationReason: o.projectionAfter?.recommendationReason ?? null, traceStatus: o.projectionAfter?.traceStatus ?? null, displayNote: o.projectionAfter?.displayNote ?? null, pickAdopts: o.projectionAfter?.pickAdopts ?? null };
      lines.push(`## ${code}`, `- 對方資料：${JSON.stringify(p.snapshot.profileText)}`, `- 用戶回答：${p.contribution.state === "answered" ? `${p.contribution.freeText ?? "（只選選項）"}${p.contribution.selectedOptionId ? `；選項 ${p.snapshot.question?.options.find((op) => op.id === p.contribution.selectedOptionId)?.label ?? p.contribution.selectedOptionId}` : ""}` : "（無補充）"}`);
      if (o.classification !== "ready_for_content_review") {
        lines.push(`- **未交付**（${o.classification}）`);
        const draft = o.projectionAfter?.visibleOpeners ?? Object.fromEntries(p.visibleTypes.filter((t) => o.openersAfter?.[t]).map((t) => [t, o.openersAfter![t]]));
        for (const [t, text] of Object.entries(draft)) lines.push(`- 草稿 ${t}：${text}`);
      } else {
        for (const [t, text] of Object.entries(o.projectionAfter!.visibleOpeners)) lines.push(`- ${t}${o.projectionAfter!.pick === t ? " ★" : ""}：${text}`);
      }
      lines.push(`- 評分：`, "");
    });
    await Deno.writeTextFile(new URL(`blind_review_${tier}.md`, outDir), lines.join("\n"));
  }
  await Deno.writeTextFile(new URL("answer_key.json", outDir), JSON.stringify(key, null, 2));
}
await Deno.writeTextFile(new URL("summary.md", outDir), summary.join("\n") + "\n");
console.log(summary.join("\n"));
Deno.exit(run && runs.some((x) => x.run.outcome.classification === "not_run_budget_or_preflight") ? 3 : 0);
