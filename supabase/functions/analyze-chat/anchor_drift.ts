// supabase/functions/analyze-chat/anchor_drift.ts
//
// Phase 2.2 — pure helper that detects whether the full-mode
// `finalRecommendation.content` drifted away from the quick-mode
// `recommendedReply` anchor (plan I7).
//
// In v1 this is warn-only telemetry. Phase 4 may turn it into a hard reject
// if drift rate in production is high.
//
// Similarity model — bigram CONTAINMENT, not Jaccard.
//   containment(quick ⊂ full) = |bigrams(quick) ∩ bigrams(full)| / |bigrams(quick)|
//
// Why containment over Jaccard:
//   The full-mode prompt explicitly allows elaboration on the same topic
//   ("怎麼接 + 為什麼"). Jaccard penalizes the longer full string for
//   "adding bigrams that aren't in quick", so a faithful expansion would
//   look like drift. Containment only asks "did full PRESERVE the quick
//   anchor", which matches I7's intent.
//
// Why bigrams over single characters:
//   Single-character Jaccard/containment over short Chinese sentences is
//   dominated by function chars (的/了/嗎/？) that inflate similarity even
//   for unrelated replies. Bigrams preserve local order ("週六" vs "六週"
//   are different) so cross-topic noise gets filtered.

export const DRIFT_THRESHOLD = 0.8; // ≥ 80% containment = no drift (plan §2.1 test 9)

export interface QuickAnchor {
  recommendedReply?: string;
  [key: string]: unknown;
}

export interface FullResultShape {
  finalRecommendation?: {
    content?: string;
    [key: string]: unknown;
  };
  [key: string]: unknown;
}

export interface DriftReport {
  driftedFields: string[];
  replyOverlapRatio: number; // [0, 1], higher = more anchor preserved
}

export function detectAnchorDrift(
  quick: QuickAnchor | Record<string, unknown>,
  full: FullResultShape,
): DriftReport {
  const quickReply = normalize(stringOr((quick as QuickAnchor).recommendedReply));
  const fullReply = normalize(stringOr(full?.finalRecommendation?.content));

  // Degenerate: no quick anchor to drift FROM. Don't fire false alarms —
  // log overlap=1 so dashboards aren't polluted.
  if (quickReply.length === 0) {
    return { driftedFields: [], replyOverlapRatio: 1 };
  }
  // Empty full reply is unambiguous drift (full produced nothing).
  if (fullReply.length === 0) {
    return { driftedFields: ["recommendedReply"], replyOverlapRatio: 0 };
  }

  const ratio = bigramContainment(quickReply, fullReply);
  const driftedFields = ratio < DRIFT_THRESHOLD ? ["recommendedReply"] : [];
  return { driftedFields, replyOverlapRatio: ratio };
}

function stringOr(v: unknown): string {
  return typeof v === "string" ? v : "";
}

function normalize(s: string): string {
  // NFC normalize so combining marks line up; collapse internal whitespace
  // so " ? " vs "?" aren't treated as different bigrams.
  return s.normalize("NFC").trim().replace(/\s+/g, "");
}

function bigramContainment(quick: string, full: string): number {
  const bq = bigrams(quick);
  const bf = bigrams(full);
  if (bq.size === 0) {
    // Single-char or empty after normalization: fall back to direct equality.
    return quick === full ? 1 : 0;
  }
  let hits = 0;
  for (const g of bq) if (bf.has(g)) hits++;
  return hits / bq.size;
}

function bigrams(s: string): Set<string> {
  const out = new Set<string>();
  const chars = Array.from(s); // surrogate-pair safe
  for (let i = 0; i < chars.length - 1; i++) {
    out.add(chars[i] + chars[i + 1]);
  }
  return out;
}
