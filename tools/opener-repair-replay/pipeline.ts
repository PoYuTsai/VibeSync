// 開場救星兩段式：一次內容修正的離線回放管線（只供驗收；不改產品程式）。
//
// 每筆依正式 handler（opener_flow_handler.ts 步驟 6b）的接線順序：
//   validateContributionAgainstSnapshot → buildOpenerMaterials → parseJsonObjectFromText(初次 raw)
//   → normalizeOpenerGenerateOutput → checkOpenerGenerationContent(與 handler contentFlags 同一個函式：硬檢查＋略過回流＋方案可見卡採用)
//   → hardBefore／stylesToReplace → buildOpenerContentCorrectionPrompt(同 handler 參數) → （一次模型呼叫）
//   → mergeOpenerCorrection(只換被標記的卡；material_unused 時同 handler 可縮小 use) → 再 normalize／checkOpenerGenerationContent → projectOpenerGenerateResult(方案投影)。
// 正式路徑另有 deadline、claim／settle、串流與 502 回應形狀，這裡不覆蓋；每筆最多一次模型呼叫，沒有第二次。
// 與正式路徑的刻意差異：normalize 不強制 materialReading.usage（handler 傳 true），因為 9/18 捕獲的 raw 還沒有 usage 欄；
// 每件補充都有 usage 的新 raw 兩者結果相同；缺 usage 時正式路徑會先走格式修復，這裡照單接受。
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { type OpenerAnalysisSnapshot, type OpenerContribution, validateContributionAgainstSnapshot } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import { buildOpenerMaterials, cardAdoptsMaterial, hardFlags, type OpenerMaterialSet, type OpenerQualityFlag } from "../../supabase/functions/analyze-chat/opener_material.ts";
import { buildOpenerContentCorrectionPrompt, OPENER_GENERATE_MAX_TOKENS, OPENER_GENERATE_PROMPT } from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import { checkOpenerGenerationContent, mergeOpenerCorrection, normalizeOpenerGenerateOutput, projectOpenerGenerateResult } from "../../supabase/functions/analyze-chat/opener_flow_payload.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES, type OpenerType } from "../../supabase/functions/analyze-chat/opener_payload.ts";

export interface RepairJob {
  job_id: string;
  source_key: string;
  tier_label: "free" | "paid";
  served_tier: string;
  contract_version: number;
  raw_file: string;
  raw_file_sha256: string;
  snapshot_file: string;
  snapshot_file_sha256: string;
  contribution: OpenerContribution;
}

export interface ModelResult {
  text: string;
  stopReason?: string;
  usage: { input_tokens: number; output_tokens: number } | null;
  elapsedMs: number;
  model: string;
  /** 完整 API 回應 body（供追查沒有 text 區塊、stop_reason 等情況；repair-01 教訓：只存 text 追不回來）。 */
  rawBody?: unknown;
}
export type ModelInvoker = (system: string, user: string, maxTokens: number) => Promise<ModelResult>;

export type Classification =
  | "ready_for_content_review"
  | "content_rejected"
  | "format_or_provider_failure"
  | "not_run_budget_or_preflight";

export interface Projection {
  pick: string | null;
  pickAdopts: boolean | null;
  traceStatus: string | null;
  recommendationReason: string | null;
  displayNote: string | null;
  visibleOpeners: Record<string, string>;
  visibleReasons: Record<string, string>;
}

export interface PreparedJob {
  job: RepairJob;
  snapshot: OpenerAnalysisSnapshot;
  contribution: OpenerContribution;
  contributionCheckOk: boolean;
  materials: OpenerMaterialSet;
  visibleTypes: readonly OpenerType[];
  initialRaw: string;
  parsedJson: Record<string, unknown> | null;
  normalizeBefore: { ok: boolean; reason?: string };
  initialOpeners: Record<string, string> | null;
  flagsBefore: OpenerQualityFlag[];
  hardBefore: OpenerQualityFlag[];
  stylesToReplace: string[];
  correctionUser: string | null;
  projectionBefore: Projection | null;
  /** 前置不符（初次結果沒有 hard／格式壞）就不送模型。 */
  preflight: "ok" | "no_hard_before" | "initial_not_normalizable";
}

/** 與 handler 的 visibleTypesFor 相同：free→Free 三卡（contract v2），其他→五卡。 */
export function visibleTypesFor(servedTier: string, contractVersion: number): readonly OpenerType[] {
  if (contractVersion < 2) throw new Error("本回放只支援 contract v2");
  return servedTier === "free" ? OPENER_FREE_V2_TYPES : OPENER_TYPES;
}

function projectFor(normalized: Parameters<typeof projectOpenerGenerateResult>[0]["normalized"], materials: OpenerMaterialSet, job: RepairJob): Projection | null {
  const visibleTypes = visibleTypesFor(job.served_tier, job.contract_version);
  const projected = projectOpenerGenerateResult({ normalized, materials, visibleTypes, servedTier: job.served_tier, contractVersion: 2 });
  if (!projected) return null;
  const openers = projected.openers as Record<string, string>;
  const pick = projected.recommendation.pick;
  return {
    pick,
    pickAdopts: pick ? cardAdoptsMaterial(openers[pick], materials) : null,
    traceStatus: projected.materialUse.traceStatus ?? null,
    recommendationReason: projected.recommendation.reason ?? null,
    displayNote: projected.materialUse.displayNote ?? null,
    visibleOpeners: openers,
    visibleReasons: (projected.cardReasons ?? {}) as Record<string, string>,
  };
}

export function prepareJob(job: RepairJob, snapshot: OpenerAnalysisSnapshot, initialRaw: string): PreparedJob {
  const contribution = job.contribution;
  const check = validateContributionAgainstSnapshot(contribution, snapshot);
  const materials = buildOpenerMaterials({ snapshot, contribution, option: check.ok ? check.option : null });
  const visibleTypes = visibleTypesFor(job.served_tier, job.contract_version);
  const parsedJson = parseJsonObjectFromText(initialRaw);
  const normalized = normalizeOpenerGenerateOutput(parsedJson, materials);
  const base: Omit<PreparedJob, "flagsBefore" | "hardBefore" | "stylesToReplace" | "correctionUser" | "projectionBefore" | "initialOpeners" | "preflight" | "normalizeBefore"> = {
    job, snapshot, contribution, contributionCheckOk: check.ok, materials, visibleTypes, initialRaw, parsedJson,
  };
  if (!normalized.ok || !parsedJson) {
    return { ...base, normalizeBefore: { ok: false, reason: normalized.ok ? "no_json" : normalized.reason }, initialOpeners: null, flagsBefore: [], hardBefore: [], stylesToReplace: [], correctionUser: null, projectionBefore: null, preflight: "initial_not_normalizable" };
  }
  const flagsBefore = checkOpenerGenerationContent(normalized.value, materials, snapshot, visibleTypes);
  const hardBefore = hardFlags(flagsBefore);
  const stylesToReplace = [...new Set(hardBefore.map((f) => f.style).filter((s): s is string => typeof s === "string"))];
  const reconsiderSelection = hardBefore.some((f) => f.code === "material_unused");
  const correctionUser = hardBefore.length
    ? buildOpenerContentCorrectionPrompt({ previousJson: JSON.stringify(parsedJson), flags: hardBefore, materials: reconsiderSelection ? materials : normalized.value.selection.eligible, omitted: normalized.value.selection.omitted, snapshot })
    : null;
  return {
    ...base,
    normalizeBefore: { ok: true },
    initialOpeners: normalized.value.openers,
    flagsBefore, hardBefore, stylesToReplace, correctionUser,
    projectionBefore: projectFor(normalized.value, materials, job),
    preflight: hardBefore.length ? "ok" : "no_hard_before",
  };
}

export interface CorrectionOutcome {
  classification: Classification;
  reason: string;
  correctionText: string | null;
  correctionParsed: Record<string, unknown> | null;
  merged: Record<string, unknown> | null;
  normalizeAfter: { ok: boolean; reason?: string } | null;
  openersAfter: Record<string, string> | null;
  flagsAfter: OpenerQualityFlag[];
  hardAfter: OpenerQualityFlag[];
  /** 被換掉的卡以外的句子是否逐字保留（正式 merge 規則的核對）。 */
  untouchedPreserved: boolean | null;
  projectionAfter: Projection | null;
}

/** 修正輸出經正式 parser／merge／normalize／guard／adoption／投影；沒有第二次修正。 */
export function applyCorrection(prepared: PreparedJob, correctionText: string | null, failure?: string): CorrectionOutcome {
  const empty: CorrectionOutcome = { classification: "format_or_provider_failure", reason: failure ?? "no_correction_text", correctionText, correctionParsed: null, merged: null, normalizeAfter: null, openersAfter: null, flagsAfter: [], hardAfter: [], untouchedPreserved: null, projectionAfter: null };
  if (failure || correctionText === null || !prepared.parsedJson) return empty;
  const correctionParsed = parseJsonObjectFromText(correctionText);
  if (!correctionParsed) return { ...empty, reason: "correction_not_json（正式流程：合併失敗→仍有硬錯誤→502 不扣）", correctionParsed: null };
  const reconsiderSelection = prepared.hardBefore.some((f) => f.code === "material_unused");
  const merged = mergeOpenerCorrection(prepared.parsedJson, correctionParsed, prepared.stylesToReplace, reconsiderSelection ? prepared.materials : undefined);
  const normalized = normalizeOpenerGenerateOutput(merged, prepared.materials);
  if (!normalized.ok) {
    return { ...empty, reason: `merged_not_normalizable:${normalized.reason}（正式流程：mergedNormalized 不 ok→保留原組硬錯誤→502 不扣）`, correctionParsed, merged, normalizeAfter: { ok: false, reason: normalized.reason } };
  }
  const openersAfter = normalized.value.openers;
  const untouchedPreserved = Object.entries(prepared.initialOpeners ?? {}).every(([style, text]) => prepared.stylesToReplace.includes(style) || (openersAfter as Record<string, string>)[style] === text);
  const flagsAfter = checkOpenerGenerationContent(normalized.value, prepared.materials, prepared.snapshot, prepared.visibleTypes);
  const hardAfter = hardFlags(flagsAfter);
  const projectionAfter = projectFor(normalized.value, prepared.materials, prepared.job);
  return {
    classification: hardAfter.length ? "content_rejected" : "ready_for_content_review",
    reason: hardAfter.length ? `修正後仍有 hard：${hardAfter.map((f) => `${f.style}:${f.code}${f.detail ? `(${f.detail})` : ""}`).join("、")}（正式流程：502 OPENER_CONTENT_CONFLICT 不扣不計次）` : "修正後零 hard，通過方案投影；尚待人讀內容",
    correctionText, correctionParsed, merged, normalizeAfter: { ok: true }, openersAfter, flagsAfter, hardAfter, untouchedPreserved, projectionAfter,
  };
}

export interface JobRun {
  prepared: PreparedJob;
  calls: number;
  request: { model: string; maxTokens: number; systemSha256: string; user: string } | null;
  response: ModelResult | null;
  error: string | null;
  outcome: CorrectionOutcome;
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** 每筆最多一次模型呼叫；前置不符或呼叫失敗都不再試。 */
export async function runJob(prepared: PreparedJob, invoke: ModelInvoker, model: string): Promise<JobRun> {
  if (prepared.preflight !== "ok" || !prepared.correctionUser) {
    return { prepared, calls: 0, request: null, response: null, error: null, outcome: { ...applyCorrection(prepared, null, `preflight:${prepared.preflight}`), classification: "not_run_budget_or_preflight", reason: `前置不符：${prepared.preflight}` } };
  }
  const request = { model, maxTokens: OPENER_GENERATE_MAX_TOKENS, systemSha256: await sha256(OPENER_GENERATE_PROMPT), user: prepared.correctionUser };
  try {
    const response = await invoke(OPENER_GENERATE_PROMPT, prepared.correctionUser, OPENER_GENERATE_MAX_TOKENS);
    return { prepared, calls: 1, request, response, error: null, outcome: applyCorrection(prepared, response.text) };
  } catch (error) {
    return { prepared, calls: 1, request, response: null, error: String(error), outcome: applyCorrection(prepared, null, `provider_error:${String(error).slice(0, 300)}`) };
  }
}
