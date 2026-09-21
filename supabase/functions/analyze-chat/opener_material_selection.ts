// The model judges suitability in the existing generation call. This module only
// verifies source spans and applies that decision consistently; it is not a
// keyword-based safety classifier or proof of semantic correctness.
import { isPlainObject } from "../_shared/quota.ts";
import { cardAdoptsMaterial, type OpenerMaterialSet, type OpenerQualityFlag } from "./opener_material.ts";

const OMIT_REASONS = ["irrelevant", "unsuitable_opener", "harassing", "instruction"] as const;
type OmitReason = typeof OMIT_REASONS[number];
export interface OmittedOpenerMaterial {
  materialId: string;
  quote: string;
  reason: OmitReason;
}
export interface OpenerMaterialSelection {
  eligible: OpenerMaterialSet;
  omitted: OmittedOpenerMaterial[];
  valid: boolean;
}

const separatorsOnly = (text: string) => /^[\s\p{P}]*$/u.test(text);
const compact = (text: string) => text.replace(/[\s\p{P}]/gu, "");

/** Each usage decision covers the complete current source, in source order.
 * Unaccounted words, duplicate/overlapping spans and invented quotes fail closed.
 * Absent usage can only be accepted by explicit legacy callers, not new requests.
 */
export function resolveOpenerMaterialSelection(
  rawReading: unknown,
  source: OpenerMaterialSet,
  requireUsage = false,
): OpenerMaterialSelection {
  const entries = Array.isArray(rawReading) ? rawReading : [];
  const materials: OpenerMaterialSet["materials"] = [];
  const omitted: OmittedOpenerMaterial[] = [];
  const ids = new Set(source.materials.map((m) => m.id));
  let valid = !entries.some((item) => isPlainObject(item) && item.usage !== undefined && !ids.has(String(item.materialId)));
  for (const material of source.materials) {
    // Options are structured user choices, never permission for the model to skip.
    if (material.origin !== "user_text") {
      materials.push(material);
      continue;
    }
    const matching = entries.filter((item) => isPlainObject(item) && item.materialId === material.id && item.usage !== undefined);
    if (!matching.length && !requireUsage) {
      materials.push(material);
      continue;
    }
    const item = matching[0];
    if (matching.length !== 1 || !isPlainObject(item) || item.quote !== material.originalText || !Array.isArray(item.usage) || !item.usage.length || item.usage.length > 12) {
      valid = false;
      continue;
    }
    let cursor = 0;
    const kept: string[] = [];
    const excluded: OmittedOpenerMaterial[] = [];
    for (const part of item.usage) {
      if (!isPlainObject(part) || typeof part.quote !== "string" || !compact(part.quote)) {
        valid = false;
        break;
      }
      const start = material.originalText.indexOf(part.quote, cursor);
      if (start < cursor || !separatorsOnly(material.originalText.slice(cursor, start))) {
        valid = false;
        break;
      }
      cursor = start + part.quote.length;
      if (part.action === "use") {
        kept.push(part.quote);
      } else if (part.action === "omit" && OMIT_REASONS.includes(part.reason as OmitReason) && material.kind !== "restriction") {
        excluded.push({ materialId: material.id, quote: part.quote, reason: part.reason as OmitReason });
      } else {
        valid = false;
        break;
      }
    }
    if (!separatorsOnly(material.originalText.slice(cursor))) valid = false;
    omitted.push(...excluded);
    if (kept.length) materials.push({ ...material, originalText: kept.join("，") });
  }
  // Invalid source decisions never grant an exemption from the original checks.
  if (!valid) return { eligible: source, omitted: [], valid: false };
  return {
    valid: true,
    omitted,
    eligible: {
      ...source,
      materials,
      hasEffectiveMaterial: materials.length > 0,
      senderFactAllowed: materials.some((m) => m.allowedUse.includes("sender_fact")),
      // Exclusions, negated facts and no-experience constraints always retain
      // their original source, even when no positive material remains.
    },
  };
}

/** Exact reintroduction is a detectable contradiction. Paraphrased suitability
 * remains a semantic quality question and must be covered by model evaluations.
 */
export function checkOmittedMaterialUse(
  textsByStyle: Record<string, string>,
  selection: OpenerMaterialSelection,
): OpenerQualityFlag[] {
  const flags: OpenerQualityFlag[] = [];
  for (const [style, text] of Object.entries(textsByStyle)) {
    for (const item of selection.omitted) {
      const quote = compact(item.quote);
      if (quote.length >= 2 && compact(text).includes(quote)) {
        flags.push({ code: "omitted_material_used", severity: "hard", style, materialId: item.materialId });
        break;
      }
    }
  }
  return flags;
}

/** A partial material's ID alone cannot attest to use of its retained content. */
export function referenceUsesEligibleMaterial(span: string, materialId: string, selection: OpenerMaterialSelection): boolean {
  const materials = selection.eligible.materials.filter((m) => m.id === materialId);
  return materials.length > 0 && cardAdoptsMaterial(span, { ...selection.eligible, materials, hasEffectiveMaterial: true });
}

export function materialHandlingNote(selection: OpenerMaterialSelection): string | null {
  if (!selection.omitted.length) return null;
  return selection.eligible.materials.length
    ? "這次採用適合開場的部分，其餘補充先不放進訊息。"
    : "這段補充先不放進開場，改用容易接話的方向。";
}
