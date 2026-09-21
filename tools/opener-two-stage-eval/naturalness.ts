// Same engineering implementation on both sides; only the prompt bundle differs.
// All catalog inputs are synthetic. No transport/credentials/DB in this module.
import catalogData from "./naturalness_cases.json" with { type: "json" };
import baseline from "./baseline-prompts.json" with { type: "json" };
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { normalizeOpenerProfileInfo } from "../../supabase/functions/analyze-chat/opener_profile.ts";
import { approachStillApplies, buildOpenerAnalysisSnapshot, graphemeLength, OPENER_FLOW_PROMPT_VERSION, parseOpenerGenerateRequest, type OpenerAnalysisSnapshot, type OpenerContribution, validateContributionAgainstSnapshot } from "../../supabase/functions/analyze-chat/opener_stage.ts";
import { buildOpenerAnalyzeUserContent, buildOpenerGenerateUserContent, OPENER_ANALYZE_PROMPT, OPENER_GENERATE_PROMPT, OPENER_ANALYZE_MAX_TOKENS, OPENER_GENERATE_MAX_TOKENS, OPENER_FLOW_MODEL } from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import { buildOpenerMaterials, cardAdoptsMaterial, hardFlags } from "../../supabase/functions/analyze-chat/opener_material.ts";
import { checkOpenerGenerationContent, normalizeOpenerGenerateOutput, projectOpenerGenerateResult } from "../../supabase/functions/analyze-chat/opener_flow_payload.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES } from "../../supabase/functions/analyze-chat/opener_payload.ts";
import { hasAnalyzeChatPromptLeak } from "../../supabase/functions/analyze-chat/prompt_leak.ts";

export type Variant = "current" | "candidate";
export type Mode = "generate-only" | "full-two-stage";
export type Arm = "A" | "B" | "skip";
export const CASES = catalogData.cases;
export type Scenario = typeof CASES[number];
export const SETTINGS = { model: OPENER_FLOW_MODEL, analyzeMaxTokens: OPENER_ANALYZE_MAX_TOKENS, generateMaxTokens: OPENER_GENERATE_MAX_TOKENS, thinking: "disabled", promptCache: "none" } as const;
export const BUNDLES = {
  current: { version: baseline.promptVersion, analyze: baseline.analyze, generate: baseline.generate, sourceHead: baseline.sourceHead },
  candidate: { version: OPENER_FLOW_PROMPT_VERSION, analyze: OPENER_ANALYZE_PROMPT, generate: OPENER_GENERATE_PROMPT, sourceHead: "runtime-head" },
};
export const QUALITY_DIMENSIONS = ["想法忠實", "容易回答", "近的下一步", "自然精簡", "平等低壓", "相關性"];
export const LIMITATIONS = [
  "Pure-function comparison; no Edge/DB settlement or real repair/fallback calls.",
  "generate-only uses identical synthetic snapshots from the production builder, not real first-stage output.",
  "N09 has synthetic image evidence only; full-two-stage is NOT_RUN_REQUIRES_ACTUAL_IMAGE.",
  "Suitability, paraphrases, naturalness and recipient intent require blinded human review; guards are not semantic proof.",
  "N03 all-use conflicting invitation still triggers material_unused; changing adoption strategy is outside this phase.",
  "Continuations/UI/newTopic/conversation-analysis are not evaluated.",
];

export async function sha256(text: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))].map(b => b.toString(16).padStart(2, "0")).join("");
}

export async function verifyCatalog(): Promise<void> {
  if (new Set(CASES.map(c => c.id)).size !== 12 || CASES.length !== 12) throw new Error("Expected 12 unique cases");
  if (await sha256(baseline.analyze) !== baseline.sha256.analyze || await sha256(baseline.generate) !== baseline.sha256.generate) throw new Error("Baseline prompt hash mismatch");
  if (baseline.settings.model !== SETTINGS.model || baseline.settings.analyzeMaxTokens !== SETTINGS.analyzeMaxTokens || baseline.settings.generateMaxTokens !== SETTINGS.generateMaxTokens) throw new Error("Comparison settings drift");
  if (BUNDLES.current.version === BUNDLES.candidate.version) throw new Error("Candidate version was not changed");
  for (const c of CASES) {
    if (c.contributions.map(a => a.arm).join(",") !== "A,B,skip") throw new Error(`Bad arms ${c.id}`);
    for (const arm of c.contributions) contribution(c, arm.arm as Arm);
  }
}

export function contribution(c: Scenario, arm: Arm): OpenerContribution {
  const item = c.contributions.find(a => a.arm === arm);
  if (!item) throw new Error(`Missing ${c.id}/${arm}`);
  const parsed = parseOpenerGenerateRequest({
    rawFlowVersion: 1, rawSessionId: "11111111-1111-4111-8111-111111111111", rawGenerationId: "22222222-2222-4222-8222-222222222222", rawAnalysisRevision: 1,
    rawContribution: { ...item, questionId: null, selectedOptionId: null },
  });
  if (!parsed.ok) throw new Error(`${c.id}/${arm}: ${parsed.code}`);
  return parsed.request.contribution;
}

// Exact, sourced text cues used only for the synthetic generate-only control.
const CUE_QUOTES: Record<string, string[]> = {
  N01: ["羽球", "貓", "電影"], N02: ["鼎泰豐", "喝酒"], N03: ["羽球", "科幻片"],
  N04: ["電影", "咖啡", "看展"], N05: ["旅行", "城市"], N06: ["跑步", "賽後恢復"],
  N07: ["巴黎", "河邊散步"], N08: ["咖啡店", "看書"], N10: ["養狗", "咖啡店"],
  N11: [], N12: ["電影", "公園"],
};
export function buildSnapshot(c: Scenario, raw: Record<string, unknown>, actualPromptVersion: string): OpenerAnalysisSnapshot | null {
  const snapshot = buildOpenerAnalysisSnapshot({ parsed: raw, rawProfileInfo: c.profileInfo, imageCount: c.syntheticSnapshotEvidence?.imageCount ?? 0, initialUserNote: c.initialUserNote ?? null });
  // Eval-only provenance: builder supplies real fingerprint, cue validation and
  // invalidation rules. Do not label a baseline call with the imported candidate version.
  return snapshot ? { ...snapshot, promptVersion: actualPromptVersion } : null;
}
export function syntheticSnapshot(c: Scenario): OpenerAnalysisSnapshot {
  const evidence = c.syntheticSnapshotEvidence;
  const cues = evidence?.cues ?? (CUE_QUOTES[c.id] ?? []).map((quote, i) => ({ id: `cue_${i + 1}`, label: quote, source: "profile_text", evidence: { field: "bio", quote } }));
  const snapshot = buildSnapshot(c, {
    profileDigest: evidence?.profileDigest ?? c.profileInfo.bio ?? "沒有對方資料",
    approach: { mode: cues.length ? "anchor_hooks" : "low_info", summary: "依可核對的資料與本次補充選題", avoid: [] },
    cues, question: null,
  }, "synthetic-fixture-v1");
  if (!snapshot || snapshot.cues.length !== cues.length) throw new Error(`Invalid synthetic snapshot ${c.id}`);
  return snapshot;
}
export function analyzeInput(c: Scenario): string {
  return buildOpenerAnalyzeUserContent({ profile: normalizeOpenerProfileInfo(c.profileInfo), imageCount: 0, initialUserNote: c.initialUserNote ?? null });
}
export function generateInput(c: Scenario, arm: Arm, snapshot: OpenerAnalysisSnapshot) {
  const current = contribution(c, arm);
  const validation = validateContributionAgainstSnapshot(current, snapshot);
  if (!validation.ok) throw new Error(validation.message);
  const materials = buildOpenerMaterials({ snapshot, contribution: current, option: validation.option });
  return {
    contribution: current, materials,
    initialUserNote: c.initialUserNote ?? null,
    initialNoteFingerprint: snapshot.initialNoteFingerprint,
    approachStillApplies: approachStillApplies(snapshot, current.freeText),
    user: buildOpenerGenerateUserContent({ snapshot, materials, currentFreeText: current.freeText }),
  };
}
export function intentGroup(c: Scenario, arm: Arm): string {
  if (arm === "skip") return "no_input";
  if (arm === "A" && ["N03", "N04"].includes(c.id)) return "conflicting_or_inapplicable_goal";
  if (arm === "A" && c.id === "N05") return "inapplicable_observation";
  if (arm === "A" && c.id === "N12") return "restriction_only";
  return "positive_intent";
}

/** Exactly the handler's content checks and projection, separately for each tier.
 * There is no repair call here: blocked raw output has no deliverable projection.
 */
export function inspectGeneration(c: Scenario, arm: Arm, snapshot: OpenerAnalysisSnapshot, raw: string) {
  const input = generateInput(c, arm, snapshot);
  const parsed = parseJsonObjectFromText(raw);
  const normalized = normalizeOpenerGenerateOutput(parsed, input.materials, true);
  const leak = hasAnalyzeChatPromptLeak(raw);
  const inspectTier = (tier: "free" | "paid") => {
    const visibleTypes = tier === "free" ? OPENER_FREE_V2_TYPES : OPENER_TYPES;
    if (!normalized.ok || leak) return { delivered: false, projected: null, flags: [], formatFailure: normalized.ok ? null : normalized.reason, promptLeak: leak };
    const flags = [...normalized.value.flags, ...checkOpenerGenerationContent(normalized.value, input.materials, snapshot, visibleTypes)];
    const projected = hardFlags(flags).length ? null : projectOpenerGenerateResult({ normalized: normalized.value, materials: input.materials, visibleTypes, servedTier: tier === "free" ? "free" : "essential", contractVersion: 2 });
    const openers = projected?.openers ?? {};
    const recommended = projected?.recommendedPick;
    const eligible = normalized.value.selection.eligible;
    return {
      delivered: !!projected, projected, flags, formatFailure: null, promptLeak: false,
      positiveIntentDenominator: intentGroup(c, arm) === "positive_intent",
      recommendedAdoption: recommended ? cardAdoptsMaterial(openers[recommended] ?? "", eligible) : false,
      alternativeAdoption: Object.entries(openers).some(([style, text]) => style !== recommended && cardAdoptsMaterial(text, eligible)),
      adoptionMetric: "lexical_evidence_not_semantic_score",
      visibleLengths: Object.fromEntries(Object.entries(openers).map(([style, text]) => [style, graphemeLength(text)])),
      qualityScores: null,
    };
  };
  const tiers = { free: inspectTier("free"), paid: inspectTier("paid") };
  return {
    rawModelRanking: parsed?.rankedPicks ?? null,
    normalizedModelRanking: normalized.ok ? normalized.value.rankedPicks : null,
    materialReading: parsed?.materialReading ?? null,
    materialSelection: normalized.ok ? normalized.value.selection : null,
    tiers, repairPathExercised: false, formatRepairCalls: 0, contentRepairCalls: 0, repairedOutput: null,
  };
}

export function plannedCalls(cases: Scenario[], mode: Mode, repeat: number): number {
  const count = cases.filter(c => mode === "generate-only" || c.inputSurface === "text").length;
  return count * repeat * (mode === "generate-only" ? 6 : 8);
}

export interface BlindItem {
  key: string; mode: Mode; variant: Variant; caseId: string; arm: Arm; attempt: number;
  tier: "free" | "paid"; profile: unknown; initialUserNote: string | null;
  contribution: OpenerContribution; visibleEvidence: string | null;
  openers: Record<string, string>; pick: string;
}
export function blindArtifacts(items: BlindItem[], seed: number) {
  let state = seed >>> 0;
  const random = () => { state = (Math.imul(1664525, state) + 1013904223) >>> 0; return state / 4294967296; };
  const shuffled = [...items];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  const key: Record<string, unknown> = {};
  const documents: Record<string, string> = {};
  for (const tier of ["free", "paid"] as const) {
    const lines = [`# ${tier === "free" ? "Free" : "付費"} 可見訊息盲審`, "", `各 1–5 分：${QUALITY_DIMENSIONS.join("／")}。失敗與硬錯另列，不靠問號、字數或風格標籤評分。`, ""];
    shuffled.filter(item => item.tier === tier).forEach((item, index) => {
      const code = `${tier === "free" ? "F" : "P"}${String(index + 1).padStart(3, "0")}`;
      key[code] = { key: item.key, mode: item.mode, variant: item.variant, caseId: item.caseId, arm: item.arm, attempt: item.attempt, tier };
      lines.push(`## ${code}`, `對方資料：${JSON.stringify(item.profile)}`);
      if (item.visibleEvidence) lines.push(`合成圖片可見資訊：${item.visibleEvidence}`);
      lines.push(`原初稿：${item.initialUserNote ?? "（無）"}`, `目前補充：${item.contribution.freeText ?? "（略過）"}`);
      OPENER_TYPES.filter(style => item.openers[style]).forEach((style, i) => lines.push(`- 句子 ${i + 1}${item.pick === style ? " ★" : ""}：${item.openers[style]}`));
      lines.push("評分與理由：", "");
    });
    documents[tier] = lines.join("\n");
  }
  return { documents, key };
}
