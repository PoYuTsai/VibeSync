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
import { estimateCostUsd, SONNET_5_PRICING } from "../../supabase/functions/_shared/model_pricing.ts";
import { type EvalContribution, type EvalScenario, legacySupplementFor, SCENARIOS } from "./fixtures.ts";

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
if (run && !confirmPaid) {
  console.error("真跑付費模型需要同時帶 --run --confirm-paid（Eric 授權後）。");
  Deno.exit(2);
}
const outDir = new URL(`./out/${tag}/`, import.meta.url);
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

function record(base: Omit<CallRecord, "costUsd">): void {
  records.push({ ...base, costUsd: estimateCostUsd({ inputTokens: base.inputTokens, outputTokens: base.outputTokens, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING) });
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

function checkArm(scenario: EvalScenario, arm: EvalContribution | null, openers: Record<string, string>, pick: string): Pick<ArmOutput, "forbiddenHits" | "anchorHit" | "profileForbiddenHits"> {
  const all = Object.values(openers).join("\n");
  const forbiddenHits = (arm?.forbidden ?? []).filter((w) => all.includes(w));
  const profileForbiddenHits = (scenario.profileForbidden ?? []).filter((w) => all.includes(w));
  const visible = OPENER_FREE_V2_TYPES.filter((t) => openers[t]);
  const anchorHit = !arm?.anchors ? true : [pick, ...visible].some((t) => arm.anchors!.some((w) => (openers[t] ?? "").includes(w)));
  return { forbiddenHits, anchorHit, profileForbiddenHits };
}

const summary: string[] = [`# opener two-stage eval · ${tag} · ${MODEL} · ${new Date().toISOString()} · ${run ? "RUN" : "DRY-RUN"}`, ""];
const blind: Array<{ key: string; scenario: string; profile: string; contribution: string; openers: Record<string, string> }> = [];
let dryInput = 0, dryOutput = 0, dryCalls = 0;

for (const scenario of SCENARIOS) {
  if (only && !only.includes(scenario.id)) continue;
  const profile = normalizeOpenerProfileInfo(scenario.profileInfo);
  const analyzeUser = buildOpenerAnalyzeUserContent({ profile, imageCount: 0, initialUserNote: null });
  summary.push(`## ${scenario.id}（${scenario.shape}）`);

  if (!run) {
    // dry-run：估算 1 次分析 + 3 臂 × repeat 次生成 + legacyRepeat 次舊單段。
    const analyzeIn = estimateTokens(OPENER_ANALYZE_PROMPT + analyzeUser);
    const generateIn = estimateTokens(OPENER_GENERATE_PROMPT) + 900;
    const legacyIn = estimateTokens(OPENER_PROMPT + analyzeUser);
    dryCalls += 1 + 3 * repeat + legacyRepeat;
    dryInput += analyzeIn + 3 * repeat * generateIn + legacyRepeat * legacyIn;
    dryOutput += 900 + 3 * repeat * 1600 + legacyRepeat * 1400;
    summary.push(`- 分析 user content ${analyzeUser.length} 字；預估 analyze in≈${analyzeIn}、generate in≈${generateIn}、legacy in≈${legacyIn}`, "");
    continue;
  }

  // 第一段（每組一次；三臂共用同一份快照，對應真實產品的同一局）。
  const analyzeRes = await callModel(OPENER_ANALYZE_PROMPT, analyzeUser, OPENER_ANALYZE_MAX_TOKENS);
  const snapshot = buildOpenerAnalysisSnapshot({ parsed: parseJsonObjectFromText(analyzeRes.text), rawProfileInfo: scenario.profileInfo, imageCount: 0, initialNoteProvided: false });
  record({ scenario: scenario.id, arm: "-", stage: "analyze", attempt: 1, elapsedMs: analyzeRes.elapsedMs, inputTokens: analyzeRes.usage.input_tokens, outputTokens: analyzeRes.usage.output_tokens, ok: snapshot !== null });
  await Deno.writeTextFile(new URL(`${scenario.id}.analyze.json`, outDir), JSON.stringify({ user: analyzeUser, raw: analyzeRes.text, snapshot }, null, 2));
  if (!snapshot) {
    summary.push("- 第一段快照無效，略過本組", "");
    continue;
  }
  summary.push(`- 第一段：mode=${snapshot.approach.mode}；線索 ${snapshot.cues.map((c) => c.label).join("／") || "無"}；題目 ${snapshot.question ? `「${snapshot.question.text}」（${snapshot.question.options.map((o) => `${o.label}=${o.meaning}`).join("、")}）` : "無"}`);

  const arms: Array<[string, EvalContribution | null]> = [["A", scenario.armA], ["B", scenario.armB], ["skip", null]];
  for (const [armName, arm] of arms) {
    for (let attempt = 1; attempt <= repeat; attempt++) {
      const contribution = contributionFor(snapshot, arm);
      const check = validateContributionAgainstSnapshot(contribution, snapshot);
      const materials = buildOpenerMaterials({ snapshot, contribution, option: check.ok ? check.option : null });
      const user = buildOpenerGenerateUserContent({ snapshot, materials });
      let res;
      try {
        res = await callModel(OPENER_GENERATE_PROMPT, user, OPENER_GENERATE_MAX_TOKENS);
      } catch (error) {
        record({ scenario: scenario.id, arm: armName, stage: "generate", attempt, elapsedMs: 0, inputTokens: 0, outputTokens: 0, ok: false, note: String(error) });
        continue;
      }
      const parsed = parseJsonObjectFromText(res.text);
      const normalized = normalizeOpenerGenerateOutput(parsed, materials);
      const flags = normalized.ok ? hardFlags(checkOpenersAgainstMaterials(normalized.value.openers, materials)) : [];
      const projected = normalized.ok ? projectOpenerGenerateResult({ normalized: normalized.value, materials, visibleTypes: OPENER_TYPES, servedTier: "essential", contractVersion: 2 }) : null;
      record({ scenario: scenario.id, arm: armName, stage: "generate", attempt, elapsedMs: res.elapsedMs, inputTokens: res.usage.input_tokens, outputTokens: res.usage.output_tokens, ok: normalized.ok && flags.length === 0, note: normalized.ok ? flags.map((f) => f.code).join(",") : normalized.reason });
      await Deno.writeTextFile(new URL(`${scenario.id}.${armName}.${attempt}.json`, outDir), JSON.stringify({ user, contribution, raw: res.text, projected, flags }, null, 2));
      if (!normalized.ok || !projected) {
        summary.push(`- ${armName}#${attempt}：五句不齊（${normalized.ok ? "投影失敗" : normalized.reason}）`);
        continue;
      }
      const openers = projected.openers as Record<string, string>;
      const c = checkArm(scenario, arm, openers, projected.recommendation.pick);
      summary.push(`- ${armName}#${attempt}（${arm ? `補充：${arm.freeText ?? ""}${contribution.selectedOptionId ? `；選項 ${contribution.selectedOptionId}` : ""}` : "略過"}）trace=${projected.materialUse.traceStatus} 硬錯誤=${flags.length} 禁字=${c.forbiddenHits.join("、") || "0"} 她的抱怨=${c.profileForbiddenHits.join("、") || "0"} 原料進可見卡=${c.anchorHit}`);
      for (const t of OPENER_TYPES) summary.push(`  - ${t}${projected.recommendation.pick === t ? " ★" : ""}：${openers[t] ?? "（缺）"}`);
      summary.push(`  - 推薦理由：${projected.recommendation.reason ?? ""}；採用說明：${projected.materialUse.displayNote ?? "—"}`);
      blind.push({ key: `${scenario.id}|${armName}|${attempt}`, scenario: scenario.id, profile: JSON.stringify(scenario.profileInfo), contribution: arm ? (arm.freeText ?? "（只選選項）") : "（略過）", openers });
    }
  }

  // 舊單段對照（同資料；A 臂補充以 supplement 形式注入，鏡像 tools/opener-blackbox）。
  for (let attempt = 1; attempt <= legacyRepeat; attempt++) {
    const supplement = legacySupplementFor(scenario.armA);
    const user = analyzeUser.replace("請依系統指示只輸出第一段 JSON：不寫開場白。", "") +
      (supplement ? `\n用戶補充（他本人的一手資訊，只用來決定開場方向與可用素材；不得寫成對方說過的話、不得假造共同點）：${supplement}\n` : "") +
      "\n請根據以上可見資訊生成 5 種風格的開場白；只使用明確線索，不要補不存在的人格或共同點。";
    let res;
    try {
      res = await callModel(OPENER_PROMPT, user, OPENER_MAX_TOKENS);
    } catch (error) {
      record({ scenario: scenario.id, arm: "legacy", stage: "legacy", attempt, elapsedMs: 0, inputTokens: 0, outputTokens: 0, ok: false, note: String(error) });
      continue;
    }
    const parsed = parseJsonObjectFromText(res.text) as Record<string, unknown> | null;
    const openers = (parsed?.openers ?? {}) as Record<string, string>;
    record({ scenario: scenario.id, arm: "legacy", stage: "legacy", attempt, elapsedMs: res.elapsedMs, inputTokens: res.usage.input_tokens, outputTokens: res.usage.output_tokens, ok: OPENER_TYPES.every((t) => typeof openers[t] === "string") });
    await Deno.writeTextFile(new URL(`${scenario.id}.legacy.${attempt}.json`, outDir), JSON.stringify({ user, raw: res.text }, null, 2));
    const c = checkArm(scenario, scenario.armA, openers, (parsed?.recommendation as Record<string, string> | undefined)?.pick ?? "extend");
    summary.push(`- legacy#${attempt}（舊單段＋A 臂補充）禁字=${c.forbiddenHits.join("、") || "0"} 她的抱怨=${c.profileForbiddenHits.join("、") || "0"} 原料進可見卡=${c.anchorHit}`);
    for (const t of OPENER_TYPES) summary.push(`  - ${t}：${openers[t] ?? "（缺）"}`);
    blind.push({ key: `${scenario.id}|legacy|${attempt}`, scenario: scenario.id, profile: JSON.stringify(scenario.profileInfo), contribution: scenario.armA.freeText ?? "", openers });
  }
  summary.push("");
}

if (!run) {
  const cost = estimateCostUsd({ inputTokens: dryInput, outputTokens: dryOutput, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }, SONNET_5_PRICING);
  summary.push(`## 預算估算（dry-run，未打模型）`, `- 呼叫數：${dryCalls}（每組 1 分析＋3 臂×${repeat} 生成＋${legacyRepeat} 舊單段）`, `- 預估 input ${dryInput} / output ${dryOutput} tokens`, `- 預估成本 ≈ $${cost.toFixed(2)}（Sonnet 5 $2/M in、$10/M out；實際以 API 回報為準）`, `- 真跑指令：deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com tools/opener-two-stage-eval/run.ts --tag=<名稱> --repeat=${repeat} --run --confirm-paid`);
} else {
  const totalIn = records.reduce((a, r) => a + r.inputTokens, 0);
  const totalOut = records.reduce((a, r) => a + r.outputTokens, 0);
  const totalCost = records.reduce((a, r) => a + r.costUsd, 0);
  const byStage = (stage: CallRecord["stage"]) => records.filter((r) => r.stage === stage);
  const avg = (rows: CallRecord[], key: "elapsedMs") => rows.length ? Math.round(rows.reduce((a, r) => a + r[key], 0) / rows.length) : 0;
  summary.push(`## 時間／token／成本`, `- 呼叫 ${records.length}；in ${totalIn} / out ${totalOut} tokens；成本 ≈ $${totalCost.toFixed(3)}`, `- 平均耗時：analyze ${avg(byStage("analyze"), "elapsedMs")}ms、generate ${avg(byStage("generate"), "elapsedMs")}ms、legacy ${avg(byStage("legacy"), "elapsedMs")}ms`, `- 格式／硬檢查失敗：${records.filter((r) => !r.ok).length} 次`);
  await Deno.writeTextFile(new URL("cost.json", outDir), JSON.stringify(records, null, 2));

  // 盲審：打亂順序、不附 AI 自述的推薦理由與 traceStatus；answer key 另存。
  let seed = 20260917;
  const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const shuffled = [...blind].sort(() => rand() - 0.5);
  const blindLines = ["# 盲審（順序已打亂；先看資料、回答與候選句再評分）", ""];
  const key: Record<string, string> = {};
  shuffled.forEach((item, index) => {
    const code = `R${String(index + 1).padStart(3, "0")}`;
    key[code] = item.key;
    blindLines.push(`## ${code}`, `- 對方資料：${item.profile}`, `- 用戶回答：${item.contribution}`);
    for (const t of OPENER_TYPES) blindLines.push(`- ${t}：${item.openers[t] ?? "（缺）"}`);
    blindLines.push(`- 評分（忠於本人／事實正確／原料影響／自然好讀／對方好接／備選價值／原意保留，各 1–5）：`, "");
  });
  await Deno.writeTextFile(new URL("blind_review.md", outDir), blindLines.join("\n"));
  await Deno.writeTextFile(new URL("answer_key.json", outDir), JSON.stringify(key, null, 2));
}

await Deno.writeTextFile(new URL("summary.md", outDir), summary.join("\n"));
console.log(summary.join("\n"));
