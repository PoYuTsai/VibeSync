// 開場救星兩段式第二段的結果整理：模型輸出→正規化→權益投影→可保存結果。
//
// 與舊單段 opener_payload.ts 的差別（附件 §7.4、F14）：不套共鳴「我也＋設定
// 引文」組句器、不用 stripFirstPersonClauses 清洗——新路徑的第一人稱事實
// 由 opener_material.ts 依本次原料檢核，合法的人物關係（我妹是美容師）不會
// 被舊清洗器刪掉。可直接送出的句子仍走同一條 sanitizeOpenerText 正規化。

import { cardAdoptsMaterial, checkMaterialAdoption, checkOpenersAgainstMaterials } from "./opener_material.ts";
import type { OpenerAnalysisSnapshot } from "./opener_stage.ts";
import { checkOmittedMaterialUse, materialHandlingNote, type OpenerMaterialSelection, referenceUsesEligibleMaterial, refineOpenerMaterialReading, resolveOpenerMaterialSelection } from "./opener_material_selection.ts";
import { isPlainObject } from "../_shared/quota.ts";
import { sanitizeCustomerExplanationText } from "./customer_explanation.ts";
import {
  buildOpenerAccess,
  normalizeStretchLevels,
  OPENER_TYPES,
  type OpenerType,
  sanitizeOpenerText,
  type StretchLevel,
} from "./opener_payload.ts";
import { normalizeOutgoingMessageText } from "./outgoing_message_text.ts";
import {
  type OpenerInputState,
  type OpenerMaterialReadingItem,
  type OpenerMaterialReference,
  type OpenerMaterialSet,
  type OpenerQualityFlag,
  sanitizeMaterialReading,
  sanitizeMaterialReferences,
} from "./opener_material.ts";

export type OpenerTraceStatus = "matched" | "uncertain" | "conflict" | "no_input";

export interface OpenerGenerateNormalized {
  openers: Record<OpenerType, string>;
  cardReasons: Partial<Record<OpenerType, string>>;
  rankedPicks: OpenerType[];
  references: OpenerMaterialReference[];
  /** 每張卡自己的採用說明（R3：不再有整包全域 note）。 */
  displayNotes: Partial<Record<OpenerType, string>>;
  reading: OpenerMaterialReadingItem[];
  selection: OpenerMaterialSelection;
  stretchLevels: Record<OpenerType, StretchLevel>;
  pioneerPlan: Record<string, string> | null;
  profileAnalysis: Record<string, unknown> | null;
  /** 來源紀錄／引文對不上等 soft flag（不擋交付，進 telemetry）。 */
  flags: OpenerQualityFlag[];
}

export type OpenerGenerateNormalizeResult =
  | { ok: true; value: OpenerGenerateNormalized }
  | { ok: false; reason: "not_object" | "incomplete_openers" | "invalid_material_usage"; missing: OpenerType[] };

/** Shared by the live handler and paired eval: tier-specific content checks,
 * including each visible explanation field without joining field boundaries.
 */
export function checkOpenerGenerationContent(
  value: OpenerGenerateNormalized,
  materials: OpenerMaterialSet,
  snapshot: OpenerAnalysisSnapshot,
  visibleTypes: readonly OpenerType[],
): OpenerQualityFlag[] {
  const base = checkOpenersAgainstMaterials(value.openers, materials, snapshot);
  const eligible = value.selection.eligible;
  const sourceFlags = value.selection.omitted.length ? checkOpenersAgainstMaterials(value.openers, eligible, snapshot) : [];
  const omittedFlags = [value.openers, value.cardReasons, value.displayNotes]
    .flatMap((surface) => checkOmittedMaterialUse(surface, value.selection))
    .filter((flag, index, flags) => flags.findIndex((other) =>
      other.style === flag.style && other.materialId === flag.materialId
    ) === index);
  const guardFlags = [...base, ...sourceFlags, ...omittedFlags];
  return [...guardFlags, ...checkMaterialAdoption({ openers: value.openers, materials: eligible, visibleTypes, rankedPicks: value.rankedPicks, flags: guardFlags })];
}

const PIONEER_KEYS = ["ifCold", "ifShortPositive", "ifEngaged", "handoff"] as const;
const PROFILE_ARRAY_KEYS = ["positiveHooks", "avoidTopics"] as const;

function customerText(value: unknown, max: number): string | null {
  const text = sanitizeCustomerExplanationText(value, 4000);
  if (text === null) return null;
  return text.length > max ? text.slice(0, max) : text;
}

export function missingOpenerFlowTypes(parsed: Record<string, unknown> | null): OpenerType[] {
  const raw = parsed && isPlainObject(parsed.openers) ? parsed.openers : {};
  return OPENER_TYPES.filter((type) => sanitizeOpenerText(raw[type]) === null);
}

export function normalizeOpenerGenerateOutput(
  parsed: Record<string, unknown> | null,
  materials: OpenerMaterialSet,
  requireMaterialUsage = false,
): OpenerGenerateNormalizeResult {
  if (!parsed) return { ok: false, reason: "not_object", missing: [...OPENER_TYPES] };
  const rawOpeners = isPlainObject(parsed.openers) ? parsed.openers : {};
  const openers = {} as Record<OpenerType, string>;
  const missing: OpenerType[] = [];
  for (const type of OPENER_TYPES) {
    const text = sanitizeOpenerText(rawOpeners[type]);
    if (text) openers[type] = text;
    else missing.push(type);
  }
  if (missing.length > 0) return { ok: false, reason: "incomplete_openers", missing };
  const selection = resolveOpenerMaterialSelection(parsed.materialReading, materials, requireMaterialUsage);
  if (!selection.valid) return { ok: false, reason: "invalid_material_usage", missing: [] };

  const cardReasons: Partial<Record<OpenerType, string>> = {};
  const rawReasons = isPlainObject(parsed.cardReasons) ? parsed.cardReasons : {};
  for (const type of OPENER_TYPES) {
    const reason = customerText(rawReasons[type], 200);
    if (reason) cardReasons[type] = reason;
  }

  const rankedRaw = Array.isArray(parsed.rankedPicks) ? parsed.rankedPicks : [];
  const rankedPicks: OpenerType[] = [];
  for (const item of rankedRaw) {
    if (typeof item === "string" && (OPENER_TYPES as readonly string[]).includes(item) && !rankedPicks.includes(item as OpenerType)) {
      rankedPicks.push(item as OpenerType);
    }
  }
  // 舊形狀相容：模型只給 recommendation.pick 時當第一名。
  const legacyPick = isPlainObject(parsed.recommendation) && typeof parsed.recommendation.pick === "string" &&
      (OPENER_TYPES as readonly string[]).includes(parsed.recommendation.pick)
    ? parsed.recommendation.pick as OpenerType
    : null;
  if (legacyPick && !rankedPicks.includes(legacyPick)) rankedPicks.unshift(legacyPick);
  for (const type of OPENER_TYPES) if (!rankedPicks.includes(type)) rankedPicks.push(type);

  const materialUseRaw = isPlainObject(parsed.materialUse) ? parsed.materialUse : {};
  const rawRefs = Array.isArray(materialUseRaw.references)
    ? materialUseRaw.references.map((ref) =>
      isPlainObject(ref) && typeof ref.outputSpan === "string"
        ? { ...ref, outputSpan: normalizeOutgoingMessageText(ref.outputSpan) ?? ref.outputSpan }
        : ref
    )
    : [];
  const { references: sourceReferences, flags: refFlags } = sanitizeMaterialReferences(rawRefs, openers, selection.eligible.materials);
  const references = sourceReferences.filter((ref) =>
    !selection.omitted.some((item) => item.materialId === ref.materialId) ||
    referenceUsesEligibleMaterial(ref.outputSpan, ref.materialId, selection)
  );
  const { reading, flags: readingFlags } = sanitizeMaterialReading(parsed.materialReading, materials.materials);
  const displayNotes: Partial<Record<OpenerType, string>> = {};
  const rawNotes = isPlainObject(materialUseRaw.displayNotes) ? materialUseRaw.displayNotes : {};
  for (const type of OPENER_TYPES) {
    const note = customerText(rawNotes[type], 60);
    if (note) displayNotes[type] = note;
  }

  let pioneerPlan: Record<string, string> | null = null;
  if (isPlainObject(parsed.pioneerPlan)) {
    const plan: Record<string, string> = {};
    for (const key of PIONEER_KEYS) {
      const text = customerText(parsed.pioneerPlan[key], 500);
      if (text && checkOmittedMaterialUse({ [key]: text }, selection).length === 0) plan[key] = text;
    }
    if (Object.keys(plan).length > 0) pioneerPlan = plan;
  }

  let profileAnalysis: Record<string, unknown> | null = null;
  if (isPlainObject(parsed.profileAnalysis)) {
    const pa: Record<string, unknown> = {};
    for (const key of PROFILE_ARRAY_KEYS) {
      const raw = parsed.profileAnalysis[key];
      if (!Array.isArray(raw)) continue;
      const items = raw.map((item) => customerText(item, 240)).filter((item): item is string => item !== null && checkOmittedMaterialUse({ [key]: item }, selection).length === 0);
      if (items.length > 0) pa[key] = items;
    }
    const strategy = customerText(parsed.profileAnalysis.openingStrategy, 500);
    if (strategy && checkOmittedMaterialUse({ strategy }, selection).length === 0) pa.openingStrategy = strategy;
    if (Object.keys(pa).length > 0) profileAnalysis = pa;
  }

  return {
    ok: true,
    value: {
      openers,
      cardReasons,
      rankedPicks,
      references,
      displayNotes,
      reading,
      selection,
      stretchLevels: normalizeStretchLevels(parsed),
      pioneerPlan,
      profileAnalysis,
      flags: [...refFlags, ...readingFlags],
    },
  };
}

/** 內容修正只換被標記風格；採用衝突時可縮小 use，既有 omit 不得回復。
 * 合併後仍須對整組結果重跑來源、取捨、採用與方案檢查。
 */
export function mergeOpenerCorrection(
  original: Record<string, unknown>,
  corrected: Record<string, unknown> | null,
  stylesToReplace: string[],
  selectionSource?: OpenerMaterialSet,
): Record<string, unknown> {
  if (!corrected) return original;
  // A sentence-only correction keeps the already validated source partition.
  const reading = selectionSource && corrected.materialReading !== undefined
    ? refineOpenerMaterialReading(original.materialReading, corrected.materialReading, selectionSource)
    : original.materialReading;
  if (selectionSource && reading === null) return original;
  const origOpeners = isPlainObject(original.openers) ? { ...original.openers } : {};
  const corrOpeners = isPlainObject(corrected.openers) ? corrected.openers : {};
  const origReasons = isPlainObject(original.cardReasons) ? { ...original.cardReasons } : {};
  const corrReasons = isPlainObject(corrected.cardReasons) ? corrected.cardReasons : {};
  for (const style of stylesToReplace) {
    if (typeof corrOpeners[style] === "string") origOpeners[style] = corrOpeners[style];
    if (typeof corrReasons[style] === "string") origReasons[style] = corrReasons[style];
  }
  const origUse = isPlainObject(original.materialUse) ? original.materialUse : {};
  const corrUse = isPlainObject(corrected.materialUse) ? corrected.materialUse : {};
  const origRefs = Array.isArray(origUse.references) ? origUse.references : [];
  const corrRefs = Array.isArray(corrUse.references) ? corrUse.references : [];
  const keptRefs = origRefs.filter((ref) => !(isPlainObject(ref) && stylesToReplace.includes(ref.style as string)));
  const newRefs = corrRefs.filter((ref) => isPlainObject(ref) && stylesToReplace.includes(ref.style as string));
  // 採用說明也綁卡：被換掉的卡丟舊說明，只採用修正輸出裡同一張卡的說明。
  const origNotes = isPlainObject(origUse.displayNotes) ? { ...origUse.displayNotes } : {};
  const corrNotes = isPlainObject(corrUse.displayNotes) ? corrUse.displayNotes : {};
  for (const style of stylesToReplace) {
    delete origNotes[style];
    if (typeof corrNotes[style] === "string") origNotes[style] = corrNotes[style];
  }
  return {
    ...original,
    materialReading: reading,
    openers: origOpeners,
    cardReasons: origReasons,
    materialUse: { ...origUse, references: [...keptRefs, ...newRefs], displayNotes: origNotes },
  };
}

export interface OpenerGenerateLedgerResult {
  openers: Partial<Record<OpenerType, string>>;
  recommendation: { pick: OpenerType; reason?: string };
  cardReasons: Partial<Record<OpenerType, string>>;
  access: ReturnType<typeof buildOpenerAccess> & { cardSet?: 2 };
  materialUse: {
    inputState: OpenerInputState;
    references: OpenerMaterialReference[];
    traceStatus: OpenerTraceStatus;
    displayNote: string | null;
    handlingNote?: string;
  };
  stretchLevels: Partial<Record<OpenerType, StretchLevel>>;
  pioneerPlan?: Record<string, string>;
  profileAnalysis?: Record<string, unknown>;
  recommendedPick: OpenerType;
  recommendedReason?: string;
}

/**
 * 權益投影（附件 §9.4）：先依方案保留可見卡，再從可見卡裡依 rankedPicks 選
 * 推薦，用那張卡自己的理由；鎖卡的句子、理由、來源引用一律不出 server。
 * displayNote 只在推薦卡確實有對得上的來源紀錄時保留。
 */
export function projectOpenerGenerateResult(input: {
  normalized: OpenerGenerateNormalized;
  materials: OpenerMaterialSet;
  visibleTypes: readonly OpenerType[];
  servedTier: string;
  contractVersion: 1 | 2;
}): OpenerGenerateLedgerResult | null {
  const { normalized, materials, visibleTypes } = input;
  const visible = new Set(visibleTypes);
  const openers: Partial<Record<OpenerType, string>> = {};
  const cardReasons: Partial<Record<OpenerType, string>> = {};
  const stretchLevels: Partial<Record<OpenerType, StretchLevel>> = {};
  for (const type of visibleTypes) {
    const text = normalized.openers[type];
    if (!text) continue;
    openers[type] = text;
    stretchLevels[type] = normalized.stretchLevels[type];
    const reason = normalized.cardReasons[type];
    if (reason) cardReasons[type] = reason;
  }
  // 第五輪 A：先讓候選忠於本次原料再排序——有有效原料時，推薦只從「內容上真的用到
  // 原料」的可見卡裡依 rankedPicks 取第一張；模型自稱的 references 不算證據。
  const ranked = normalized.rankedPicks.filter((type) => openers[type]);
  const eligible = normalized.selection.eligible;
  // 推薦偏好只看話題部分：背景型補充（想約、家人、過去經歷）不把推薦推到含原字的卡。
  const adopting = eligible.hasEffectiveMaterial ? ranked.filter((type) => cardAdoptsMaterial(openers[type]!, eligible, "topic")) : [];
  const pick = adopting[0] ?? ranked[0] ?? visibleTypes.find((type) => openers[type]);
  if (!pick) return null;

  const references = normalized.references.filter((ref) => visible.has(ref.style) && openers[ref.style]);
  const pickReferenced = references.some((ref) => ref.style === pick);
  let traceStatus: OpenerTraceStatus;
  if (!materials.hasEffectiveMaterial) {
    traceStatus = "no_input";
  } else if (cardAdoptsMaterial(openers[pick]!, eligible) && pickReferenced) {
    traceStatus = "matched";
  } else {
    traceStatus = "uncertain";
  }
  // 採用說明只用最終可見 pick 自己那一句，且要它真的有對得上的來源紀錄。
  const displayNote = traceStatus === "matched" && pickReferenced ? (normalized.displayNotes[pick] ?? null) : null;
  const reason = cardReasons[pick];

  const result: OpenerGenerateLedgerResult = {
    openers,
    recommendation: reason ? { pick, reason } : { pick },
    cardReasons,
    access: buildOpenerAccess({
      contractVersion: input.contractVersion,
      servedTier: input.servedTier,
      visibleTypes,
    }),
    materialUse: {
      inputState: materials.inputState,
      references,
      traceStatus,
      displayNote,
      ...(materialHandlingNote(normalized.selection) ? { handlingNote: materialHandlingNote(normalized.selection)! } : {}),
    },
    stretchLevels,
    recommendedPick: pick,
  };
  if (reason) result.recommendedReason = reason;
  if (normalized.pioneerPlan) result.pioneerPlan = normalized.pioneerPlan;
  if (normalized.profileAnalysis) result.profileAnalysis = normalized.profileAnalysis;
  return result;
}

/** DB 回放的結果做防禦式驗證（鏡像 SQL validate_opener_generation_result）。 */
export function isValidOpenerGenerateLedgerResult(raw: unknown): raw is OpenerGenerateLedgerResult {
  if (!isPlainObject(raw)) return false;
  if (!isPlainObject(raw.openers) || !isPlainObject(raw.recommendation) || !isPlainObject(raw.access) || !isPlainObject(raw.materialUse)) {
    return false;
  }
  const keys = Object.keys(raw.openers);
  if (keys.length === 0) return false;
  for (const key of keys) {
    const text = raw.openers[key];
    if (!(OPENER_TYPES as readonly string[]).includes(key) || typeof text !== "string" || !text.trim() || text.length > 180) {
      return false;
    }
  }
  const pick = raw.recommendation.pick;
  if (typeof pick !== "string" || !(pick in raw.openers)) return false;
  return Array.isArray(raw.access.visibleTypes) && typeof raw.access.servedTier === "string";
}
