// 開場救星兩段式真模型成對評估（附件 §14.3／§14.4；local-only、付費）。
//
// 用生產的 prompt 與純函式（opener_stage／opener_material／opener_flow_payload）走
// 第一段→第二段，不經 Edge／DB；只有模型呼叫是真的。每組情境三臂：A／B（實質不同
// 的用戶原料）與略過；另用相同資料跑舊單段 OPENER_PROMPT 當對照。
//
// 預設 dry-run：不打模型，只印每次呼叫的 user content 長度、預估 token 與預算。
// 真跑要明確帶 --run --confirm-paid（附件與交辦：付費真模型跑量需 Eric 授權）。
//
//   deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com \
//     tools/opener-two-stage-eval/run.ts [--tag=名稱] [--repeat=3] [--only=id,id] \
//     [--legacy-repeat=3] [--run --confirm-paid]
//
// 輸出 tools/opener-two-stage-eval/out/<tag>/：每次呼叫 JSON、summary.md、
// blind_review.md（打亂順序、不含 AI 自述理由）、answer_key.json、cost.json。
// 分析 log 不保存用戶補充全文以外的私人內容（fixtures 是人工示例）。

import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { normalizeOpenerProfileInfo } from "../../supabase/functions/analyze-chat/opener_profile.ts";
import {
  buildOpenerAnalysisSnapshot,
  type OpenerAnalysisSnapshot,
  type OpenerContribution,
  validateContributionAgainstSnapshot,
} from "../../supabase/functions/analyze-chat/opener_stage.ts";
import {
  buildOpenerMaterials,
  checkOpenersAgainstMaterials,
  hardFlags,
} from "../../supabase/functions/analyze-chat/opener_material.ts";
import {
  buildOpenerAnalyzeUserContent,
  buildOpenerGenerateUserContent,
  OPENER_ANALYZE_MAX_TOKENS,
  OPENER_ANALYZE_PROMPT,
  OPENER_GENERATE_MAX_TOKENS,
  OPENER_GENERATE_PROMPT,
} from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import {
  normalizeOpenerGenerateOutput,
  projectOpenerGenerateResult,
} from "../../supabase/functions/analyze-chat/opener_flow_payload.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES } from "../../supabase/functions/analyze-chat/opener_payload.ts";
import { OPENER_MAX_TOKENS, OPENER_PROMPT } from "../../supabase/functions/analyze-chat/opener_prompt.ts";
import { OPENER_FLOW_PROMPT_VERSION } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import { estimateCostUsd, SONNET_5_PRICING } from "../../supabase/functions/_shared/model_pricing.ts";
import { type EvalContribution, type EvalScenario, legacySupplementFor, NOT_COVERED, SCENARIOS } from "./fixtures.ts";
import { legacyControlUserContent } from "./control.ts";
import { normalizeOpenerPayload, filterOpenerPayloadForAllowedFeatures } from "../../supabase/functions/analyze-chat/opener_payload.ts";

// New paired two-stage mode; the historical single-stage control remains intact.
if (Deno.args.some(arg => arg === "--compare-naturalness" || arg.startsWith("--compare-naturalness="))) {
  await (await import("./naturalness-run.ts")).main();
  Deno.exit(0);
}

const MODEL = "claude-sonnet-5";

function arg(name: string): string | null {
  const hit = Deno.args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}
const tag = arg("tag") ?? "dry-run";
const repeat = Number(arg("repeat") ?? "3");
const legacyRepeat = Number(arg("legacy-repeat") ?? "3");
const only = arg("only")?.split(",") ?? null;
const run = Deno.args.includes("--run");
const confirmPaid = Deno.args.includes("--confirm-paid");
// R6a：舊單段控制組＝原樣、不注入補充；「舊單段＋A 補充」只是附加實驗，要明確開。
const legacyPlusA = Deno.args.includes("--legacy-plus-a");
// 驗收：模型 API 費用硬上限（USD）。每次呼叫前用「已花費（實際 usage）＋這次最壞情況（輸入估算×1.3＋max_tokens 全滿）」
// 預檢，超過就不再發任何新呼叫；API 失敗但沒有 usage 的呼叫以最壞情況計入（未知成本不當 0）。
const budgetUsd = Number(arg("budget-usd") ?? "5");
const headSha = arg("head") ?? "unknown";
if (run && !confirmPaid) {
  console.error("真跑付費模型需要同時帶 --run --confirm-paid（Eric 授權後）。");
  Deno.exit(2);
}
const outDir = new URL(`./out/${tag}/`, import.meta.url);
const startedAt = new Date().toISOString();
await Deno.mkdir(outDir, { recursive: true });

// 粗估：中文約 1 字≈1 token、英文／JSON 約 4 字元≈1 token；這裡取 1.1 字元/token 的保守值。
function estimateTokens(text: string): number {
  return Math.ceil(text.length / 1.1);
}

interface CallRecord {
  scenario: string;
  arm: string;
  stage: "analyze" | "generate" | "legacy";
  attempt: number;
  elapsedMs: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  ok: boolean;
  note?: string;
}
const records: CallRecord[] = [];

async function callModel(system: string, user: string, maxTokens: number): Promise<{ text: string; usage: { input_tokens: number; output_tokens: number }; elapsedMs: number }> {
  const apiKey = (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`)).trim();
  const started = Date.now();
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, thinking: { type: "disabled" }, system, messages: [{ role: "user", content: user }] }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`API 失敗：${JSON.stringify(json.error)}`);
  const text = (json.content as Array<{ type: string; text?: string }>).find((b) => b.type === "text")?.text ?? "";
  return { text, usage: json.usage, elapsedMs: Date.now() - started };
}

let spentUsd = 0; // 實際 usage 估價＋失敗呼叫的最壞情況
let budgetStopped = false;
const notRun: string[] = [];
function worstCaseUsd(system: string, user: string, maxTokens: number): number {
  return estimateCostUsd({ inputTokens: Math.ceil(estimateTokens(system + user) * 1.3), outputTokens: maxTokens, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING);
}
/** 預算守門：回 false 代表不得發出這次呼叫（之後全部標 NOT_RUN）。 */
function budgetAllows(label: string, system: string, user: string, maxTokens: number): boolean {
  if (budgetStopped) { notRun.push(label); return false; }
  const worst = worstCaseUsd(system, user, maxTokens);
  if (spentUsd + worst > budgetUsd) {
    budgetStopped = true;
    notRun.push(label);
    summary.push(`- **預算守門停止**：已花 $${spentUsd.toFixed(3)}＋下一次最壞 $${worst.toFixed(3)} 會超過上限 $${budgetUsd}；自 ${label} 起全部未執行`);
    return false;
  }
  return true;
}
function record(base: Omit<CallRecord, "costUsd">): void {
  const cost = estimateCostUsd({ inputTokens: base.inputTokens, outputTokens: base.outputTokens, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING);
  records.push({ ...base, costUsd: cost });
  spentUsd += cost;
}
/** API 失敗（沒有 usage）：成本未知，以最壞情況計入預算。 */
function recordFailure(base: Omit<CallRecord, "costUsd" | "inputTokens" | "outputTokens">, system: string, user: string, maxTokens: number): void {
  const worst = worstCaseUsd(system, user, maxTokens);
  records.push({ ...base, inputTokens: 0, outputTokens: 0, costUsd: worst, note: `${base.note ?? ""}（成本未知，以最壞情況 $${worst.toFixed(3)} 計）` });
  spentUsd += worst;
}
async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function pickOption(snapshot: OpenerAnalysisSnapshot, arm: EvalContribution): { questionId: string | null; selectedOptionId: string | null } {
  const question = snapshot.question;
  if (!question || !arm.preferOptionMeaning) return { questionId: null, selectedOptionId: null };
  const option = question.options.find((o) => o.meaning === arm.preferOptionMeaning);
  return option ? { questionId: question.id, selectedOptionId: option.id } : { questionId: null, selectedOptionId: null };
}

function contributionFor(snapshot: OpenerAnalysisSnapshot, arm: EvalContribution | null): OpenerContribution {
  if (!arm) return { state: "skipped", questionId: null, selectedOptionId: null, freeText: null };
  const picked = pickOption(snapshot, arm);
  return { state: "answered", ...picked, freeText: arm.freeText ?? null };
}

interface ArmOutput {
  arm: string;
  contribution: OpenerContribution;
  openers: Record<string, string>;
  pick: string;
  reason: string | null;
  traceStatus: string;
  displayNote: string | null;
  hardFlags: string[];
  forbiddenHits: string[];
  anchorHit: boolean;
  profileForbiddenHits: string[];
}

/** R6a：推薦採用率只看「該投影的可見推薦卡」；備選採用另計，不用任一卡命中冒充推薦採用。 */
function checkArm(scenario: EvalScenario, arm: EvalContribution | null, openers: Record<string, string>, pick: string): Pick<ArmOutput, "forbiddenHits" | "anchorHit" | "profileForbiddenHits"> & { altHit: boolean } {
  const all = Object.values(openers).join("\n");
  const forbiddenHits = (arm?.forbidden ?? []).filter((w) => all.includes(w));
  const profileForbiddenHits = (scenario.profileForbidden ?? []).filter((w) => all.includes(w));
  const anchors = arm?.anchors;
  const anchorHit = !anchors ? true : anchors.some((w) => (openers[pick] ?? "").includes(w));
  const altHit = !anchors ? true : Object.entries(openers).some(([t, text]) => t !== pick && anchors.some((w) => text.includes(w)));
  return { forbiddenHits, anchorHit, profileForbiddenHits, altHit };
}

/** 依方案投影（Free 三卡／paid 五卡）並各自取推薦，盲審與採用率分開產出。 */
function projectBoth(normalized: Parameters<typeof projectOpenerGenerateResult>[0]["normalized"], materials: Parameters<typeof projectOpenerGenerateResult>[0]["materials"]) {
  return {
    free: projectOpenerGenerateResult({ normalized, materials, visibleTypes: OPENER_FREE_V2_TYPES, servedTier: "free", contractVersion: 2 }),
    paid: projectOpenerGenerateResult({ normalized, materials, visibleTypes: OPENER_TYPES, servedTier: "essential", contractVersion: 2 }),
  };
}

const summary: string[] = [
  `# opener two-stage eval · ${tag} · ${MODEL} · ${new Date().toISOString()} · ${run ? "RUN" : "DRY-RUN"}`,
  `控制組：舊單段原樣（同對方資料、不注入補充）${legacyPlusA ? "；另有附加實驗「舊單段＋A 補充」" : ""}。未涵蓋：${NOT_COVERED.join("；")}。`,
  "",
];
const blind: Array<{ key: string; scenario: string; version: "two-stage" | "legacy"; arm: string; attempt: number; profile: string; contribution: string; tier: string; openers: Record<string, string>; pick: string; reason: string | null; traceStatus: string | null; displayNote: string | null }> = [];
let dryInput = 0, dryOutput = 0, dryCalls = 0;

for (const scenario of SCENARIOS) {
  if (only && !only.includes(scenario.id)) continue;
  const profile = normalizeOpenerProfileInfo(scenario.profileInfo);
  const initialNote = scenario.initialUserNote ?? null;
  const analyzeUser = buildOpenerAnalyzeUserContent({ profile, imageCount: 0, initialUserNote: initialNote });
  summary.push(`## ${scenario.id}（${scenario.shape}）${initialNote ? `；初稿：「${initialNote}」` : ""}`);

  if (!run) {
    // dry-run：估算 1 次分析 + 3 臂 × repeat 次生成 + legacyRepeat 次舊單段。
    const analyzeIn = estimateTokens(OPENER_ANALYZE_PROMPT + analyzeUser);
    const generateIn = estimateTokens(OPENER_GENERATE_PROMPT) + 900;
    const legacyIn = estimateTokens(OPENER_PROMPT + legacyControlUserContent(scenario));
    const legacyArms = legacyPlusA ? 2 : 1;
    dryCalls += 1 + 3 * repeat + legacyArms * legacyRepeat;
    dryInput += analyzeIn + 3 * repeat * generateIn + legacyArms * legacyRepeat * legacyIn;
    dryOutput += 900 + 3 * repeat * 1600 + legacyArms * legacyRepeat * 1400;
    summary.push(`- 分析 user content ${analyzeUser.length} 字；預估 analyze in≈${analyzeIn}、generate in≈${generateIn}、legacy in≈${legacyIn}`, "");
    continue;
  }

  // 第一段（每組一次；三臂共用同一份快照，對應真實產品的同一局）。
  if (!budgetAllows(`${scenario.id}.analyze`, OPENER_ANALYZE_PROMPT, analyzeUser, OPENER_ANALYZE_MAX_TOKENS)) { summary.push("- NOT_RUN（預算守門）", ""); continue; }
  let analyzeRes;
  try {
    analyzeRes = await callModel(OPENER_ANALYZE_PROMPT, analyzeUser, OPENER_ANALYZE_MAX_TOKENS);
  } catch (error) {
    recordFailure({ scenario: scenario.id, arm: "-", stage: "analyze", attempt: 1, elapsedMs: 0, ok: false, note: String(error) }, OPENER_ANALYZE_PROMPT, analyzeUser, OPENER_ANALYZE_MAX_TOKENS);
    summary.push(`- 第一段 API 失敗：${String(error).slice(0, 200)}`, "");
    continue;
  }
  const snapshot = buildOpenerAnalysisSnapshot({ parsed: parseJsonObjectFromText(analyzeRes.text), rawProfileInfo: scenario.profileInfo, imageCount: 0, initialUserNote: initialNote });
  record({ scenario: scenario.id, arm: "-", stage: "analyze", attempt: 1, elapsedMs: analyzeRes.elapsedMs, inputTokens: analyzeRes.usage.input_tokens, outputTokens: analyzeRes.usage.output_tokens, ok: snapshot !== null });
  await Deno.writeTextFile(new URL(`${scenario.id}.analyze.json`, outDir), JSON.stringify({ user: analyzeUser, raw: analyzeRes.text, snapshot }, null, 2));
  if (!snapshot) {
    summary.push("- 第一段快照無效，略過本組", "");
    continue;
  }
  summary.push(`- 第一段：mode=${snapshot.approach.mode}；線索 ${snapshot.cues.map((c) => c.label).join("／") || "無"}；題目 ${snapshot.question ? `「${snapshot.question.text}」（${snapshot.question.options.map((o) => `${o.label}=${o.meaning}`).join("、")}）` : "無"}${initialNote ? `；F02 檢查：初稿已說清楚→${snapshot.question ? "仍問了一題（盲審判是否重問）" : "零題 ✓"}` : ""}`);

  const arms: Array<[string, EvalContribution | null]> = [["A", scenario.armA], ["B", scenario.armB], ["skip", null]];
  for (const [armName, arm] of arms) {
    for (let attempt = 1; attempt <= repeat; attempt++) {
      const contribution = contributionFor(snapshot, arm);
      const check = validateContributionAgainstSnapshot(contribution, snapshot);
      const materials = buildOpenerMaterials({ snapshot, contribution, option: check.ok ? check.option : null });
      const user = buildOpenerGenerateUserContent({ snapshot, materials, currentFreeText: contribution.freeText });
      if (!budgetAllows(`${scenario.id}.${armName}.${attempt}`, OPENER_GENERATE_PROMPT, user, OPENER_GENERATE_MAX_TOKENS)) continue;
      let res;
      try {
        res = await callModel(OPENER_GENERATE_PROMPT, user, OPENER_GENERATE_MAX_TOKENS);
      } catch (error) {
        recordFailure({ scenario: scenario.id, arm: armName, stage: "generate", attempt, elapsedMs: 0, ok: false, note: String(error) }, OPENER_GENERATE_PROMPT, user, OPENER_GENERATE_MAX_TOKENS);
        continue;
      }
      const parsed = parseJsonObjectFromText(res.text);
      const normalized = normalizeOpenerGenerateOutput(parsed, materials);
      const flags = normalized.ok ? hardFlags(checkOpenersAgainstMaterials(normalized.value.openers, materials)) : [];
      const both = normalized.ok ? projectBoth(normalized.value, materials) : { free: null, paid: null };
      record({ scenario: scenario.id, arm: armName, stage: "generate", attempt, elapsedMs: res.elapsedMs, inputTokens: res.usage.input_tokens, outputTokens: res.usage.output_tokens, ok: normalized.ok && flags.length === 0, note: normalized.ok ? flags.map((f) => f.code).join(",") : normalized.reason });
      await Deno.writeTextFile(new URL(`${scenario.id}.${armName}.${attempt}.json`, outDir), JSON.stringify({ user, contribution, raw: res.text, projectedFree: both.free, projectedPaid: both.paid, flags }, null, 2));
      if (!normalized.ok || !both.free || !both.paid) {
        summary.push(`- ${armName}#${attempt}：五句不齊（${normalized.ok ? "投影失敗" : normalized.reason}）`);
        continue;
      }
      summary.push(`- ${armName}#${attempt}（${arm ? `補充：${arm.freeText ?? ""}${contribution.selectedOptionId ? `；選項 ${contribution.selectedOptionId}` : ""}` : "略過"}）硬錯誤=${flags.length}`);
      for (const [tier, projected] of [["free", both.free], ["paid", both.paid]] as const) {
        const openers = projected.openers as Record<string, string>;
        const c = checkArm(scenario, arm, openers, projected.recommendation.pick);
        summary.push(`  - [${tier}] 推薦=${projected.recommendation.pick} trace=${projected.materialUse.traceStatus} 禁字=${c.forbiddenHits.join("、") || "0"} 她的抱怨=${c.profileForbiddenHits.join("、") || "0"} 推薦採用=${c.anchorHit} 備選採用=${c.altHit}`);
        for (const t of OPENER_TYPES) if (openers[t]) summary.push(`    - ${t}${projected.recommendation.pick === t ? " ★" : ""}：${openers[t]}`);
        summary.push(`    - 推薦理由：${projected.recommendation.reason ?? ""}；採用說明：${projected.materialUse.displayNote ?? "—"}`);
        // 盲審隱藏版本：略過臂與舊單段控制組都寫「（無補充）」，避免從標籤分辨新舊。
        blind.push({ key: `${scenario.id}|${armName}|${attempt}|${tier}`, scenario: scenario.id, version: "two-stage", arm: armName, attempt, profile: JSON.stringify(scenario.profileInfo), contribution: arm ? (arm.freeText ?? "（只選選項）") : "（無補充）", tier, openers, pick: projected.recommendation.pick, reason: projected.recommendation.reason ?? null, traceStatus: projected.materialUse.traceStatus ?? null, displayNote: projected.materialUse.displayNote ?? null });
      }
    }
  }

  // 舊單段控制組（R6a）：同對方資料、原樣舊 prompt、走舊產品的結果整理與 tier 投影；
  // 不注入任何補充。「舊單段＋A 補充」只是附加實驗（--legacy-plus-a）。
  // 控制組輸入只由對方資料決定（R6a 第二輪）：不從第一段 user content 刪句，初稿與 A／B 都碰不到它。
  const legacyUserBase = legacyControlUserContent(scenario);
  const legacyArms: Array<[string, string | null]> = [["legacy", null]];
  if (legacyPlusA) legacyArms.push(["legacy+A", legacySupplementFor(scenario.armA)]);
  for (const [legacyArm, supplement] of legacyArms) {
    for (let attempt = 1; attempt <= legacyRepeat; attempt++) {
      const user = supplement
        ? `${legacyUserBase}\n用戶補充（他本人的一手資訊，只用來決定開場方向與可用素材；不得寫成對方說過的話、不得假造共同點）：${supplement}`
        : legacyUserBase;
      if (!budgetAllows(`${scenario.id}.${legacyArm}.${attempt}`, OPENER_PROMPT, user, OPENER_MAX_TOKENS)) continue;
      let res;
      try {
        res = await callModel(OPENER_PROMPT, user, OPENER_MAX_TOKENS);
      } catch (error) {
        recordFailure({ scenario: scenario.id, arm: legacyArm, stage: "legacy", attempt, elapsedMs: 0, ok: false, note: String(error) }, OPENER_PROMPT, user, OPENER_MAX_TOKENS);
        continue;
      }
      // 走舊產品的整理與投影（normalizeOpenerPayload 含共鳴組句器；無風格設定＝her_situation）。
      const parsed = normalizeOpenerPayload(parseJsonObjectFromText(res.text), { styleContext: null });
      const legacyBoth = parsed
        ? {
          free: filterOpenerPayloadForAllowedFeatures(parsed, [...OPENER_FREE_V2_TYPES], { fallbackOrder: OPENER_FREE_V2_TYPES }),
          paid: filterOpenerPayloadForAllowedFeatures(parsed, [...OPENER_TYPES], { fallbackOrder: OPENER_TYPES }),
        }
        : { free: null, paid: null };
      record({ scenario: scenario.id, arm: legacyArm, stage: "legacy", attempt, elapsedMs: res.elapsedMs, inputTokens: res.usage.input_tokens, outputTokens: res.usage.output_tokens, ok: legacyBoth.free !== null && legacyBoth.paid !== null });
      await Deno.writeTextFile(new URL(`${scenario.id}.${legacyArm}.${attempt}.json`, outDir), JSON.stringify({ user, raw: res.text, projectedFree: legacyBoth.free, projectedPaid: legacyBoth.paid }, null, 2));
      if (!legacyBoth.free || !legacyBoth.paid) {
        summary.push(`- ${legacyArm}#${attempt}：舊單段整理失敗（五句不齊或無可用卡）`);
        continue;
      }
      summary.push(`- ${legacyArm}#${attempt}（${supplement ? "附加實驗：舊單段＋A 補充" : "控制組：舊單段原樣"}）`);
      for (const [tier, projected] of [["free", legacyBoth.free], ["paid", legacyBoth.paid]] as const) {
        const openers = projected.openers as Record<string, string>;
        const pick = projected.recommendedPick as string;
        const c = checkArm(scenario, supplement ? scenario.armA : null, openers, pick);
        summary.push(`  - [${tier}] 推薦=${pick} 她的抱怨=${c.profileForbiddenHits.join("、") || "0"}${supplement ? ` 禁字=${c.forbiddenHits.join("、") || "0"} 推薦採用=${c.anchorHit} 備選採用=${c.altHit}` : ""}`);
        for (const t of OPENER_TYPES) if (openers[t]) summary.push(`    - ${t}${pick === t ? " ★" : ""}：${openers[t]}`);
        blind.push({ key: `${scenario.id}|${legacyArm}|${attempt}|${tier}`, scenario: scenario.id, version: "legacy", arm: legacyArm, attempt, profile: JSON.stringify(scenario.profileInfo), contribution: supplement ?? "（無補充）", tier, openers, pick, reason: (projected as Record<string, unknown>).recommendationReason as string ?? null, traceStatus: null, displayNote: null });
      }
    }
  }
  summary.push("");
}

if (!run) {
  const cost = estimateCostUsd({ inputTokens: dryInput, outputTokens: dryOutput, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING);
  summary.push(`## 預算估算（dry-run，未打模型）`, `- 硬上限 $${budgetUsd}：${cost <= budgetUsd ? "估算在上限內" : "估算超過上限，真跑不得開始"}`, `- 呼叫數：${dryCalls}（每組 1 分析＋3 臂×${repeat} 生成＋${legacyPlusA ? 2 : 1}×${legacyRepeat} 舊單段${legacyPlusA ? "（含附加實驗）" : ""}）`, `- 預估 input ${dryInput} / output ${dryOutput} tokens`, `- 預估成本 ≈ $${cost.toFixed(2)}（Sonnet 5 $2/M in、$10/M out；實際以 API 回報為準）`, `- 真跑指令：deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com tools/opener-two-stage-eval/run.ts --tag=<名稱> --repeat=${repeat} --run --confirm-paid`);
} else {
  const totalIn = records.reduce((a, r) => a + r.inputTokens, 0);
  const totalOut = records.reduce((a, r) => a + r.outputTokens, 0);
  const totalCost = records.reduce((a, r) => a + r.costUsd, 0);
  const byStage = (stage: CallRecord["stage"]) => records.filter((r) => r.stage === stage);
  const avg = (rows: CallRecord[], key: "elapsedMs") => rows.length ? Math.round(rows.reduce((a, r) => a + r[key], 0) / rows.length) : 0;
  summary.push(`## 時間／token／成本`, `- 呼叫 ${records.length}；in ${totalIn} / out ${totalOut} tokens；成本 ≈ $${totalCost.toFixed(3)}`, `- 平均耗時：analyze ${avg(byStage("analyze"), "elapsedMs")}ms、generate ${avg(byStage("generate"), "elapsedMs")}ms、legacy ${avg(byStage("legacy"), "elapsedMs")}ms`, `- 格式／硬檢查失敗：${records.filter((r) => !r.ok).length} 次`);
  summary.push(`- 預算上限 $${budgetUsd}；實際計入 $${spentUsd.toFixed(3)}（含失敗呼叫的最壞情況）；預算守門停止：${budgetStopped ? "是" : "否"}；未執行 ${notRun.length} 次${notRun.length ? `（${notRun.slice(0, 5).join("、")}${notRun.length > 5 ? "…" : ""}）` : ""}`);
  summary.push(`- 修復／fallback／重試呼叫：0（本工具每次生成只打一次模型，不做修復或換模型）`);
  await Deno.writeTextFile(new URL("cost.json", outDir), JSON.stringify({ budgetUsd, spentUsd, budgetStopped, notRun, records }, null, 2));
  await Deno.writeTextFile(new URL("meta.json", outDir), JSON.stringify({
    tag, model: MODEL, headSha, promptVersion: OPENER_FLOW_PROMPT_VERSION, repeat, legacyRepeat, legacyPlusA, budgetUsd,
    pricing: SONNET_5_PRICING, thinking: "disabled", promptCache: "none",
    maxTokens: { analyze: OPENER_ANALYZE_MAX_TOKENS, generate: OPENER_GENERATE_MAX_TOKENS, legacy: OPENER_MAX_TOKENS },
    sha256: { analyzePrompt: await sha256(OPENER_ANALYZE_PROMPT), generatePrompt: await sha256(OPENER_GENERATE_PROMPT), legacyPrompt: await sha256(OPENER_PROMPT), fixtures: await sha256(await Deno.readTextFile(new URL("./fixtures.ts", import.meta.url))) },
    startedAt, finishedAt: new Date().toISOString(),
  }, null, 2));

  // 盲審：Free／paid 各一份、順序打亂；隱藏新舊版本標籤、推薦理由、traceStatus、採用說明；解盲表另存。
  let seed = 20260917;
  const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const shuffled = [...blind].sort(() => rand() - 0.5);
  const key: Record<string, unknown> = {};
  for (const tier of ["free", "paid"] as const) {
    const items = shuffled.filter((b) => b.tier === tier);
    const lines = [`# 盲審（${tier === "free" ? "Free 三卡" : "paid 五卡"}；順序已打亂；先看資料、回答與候選句再評分）`, "", "每題請評：忠於本人／事實正確／原料影響／自然好讀／對方好接／備選價值／原意保留（各 1–5），並註明推薦（★）是否是你會選的那句。", ""];
    items.forEach((item, index) => {
      const code = `${tier === "free" ? "F" : "P"}${String(index + 1).padStart(3, "0")}`;
      key[code] = { scenario: item.scenario, version: item.version, arm: item.arm, attempt: item.attempt, tier: item.tier, pick: item.pick, reason: item.reason, traceStatus: item.traceStatus, displayNote: item.displayNote, key: item.key };
      lines.push(`## ${code}`, `- 對方資料：${item.profile}`, `- 用戶回答：${item.contribution}`);
      for (const t of OPENER_TYPES) if (item.openers[t]) lines.push(`- ${t}${item.pick === t ? " ★" : ""}：${item.openers[t]}`);
      lines.push(`- 評分：`, "");
    });
    await Deno.writeTextFile(new URL(`blind_review_${tier}.md`, outDir), lines.join("\n"));
  }
  await Deno.writeTextFile(new URL("answer_key.json", outDir), JSON.stringify(key, null, 2));
}

await Deno.writeTextFile(new URL("summary.md", outDir), summary.join("\n"));
console.log(summary.join("\n"));
