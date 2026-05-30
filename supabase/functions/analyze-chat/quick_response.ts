// supabase/functions/analyze-chat/quick_response.ts
//
// Phase 1.3 — parse + sanitize the slim quick-mode JSON payload, and look up
// the conservative ETA the UI shows while the full-mode call is still in flight.
//
// These three helpers are intentionally pure / side-effect-free so they can be
// unit-tested without spinning up the Edge runtime. The handler in `index.ts`
// glues them to:
//   1. callClaudeWithFallback (Haiku 4.5, 400 max_tokens, 15s timeout, no fallback)
//   2. hashConversation (conversation_hash.ts)
//   3. AnalysisRunStore.createChargedRun (atomic charge + insert via RPC)
//
// Per plan I8: if `parseQuickResponse` fails or the Claude call throws, the
// handler MUST return before `createChargedRun` runs, so no row is inserted and
// no quota is charged.

const VALID_CONFIDENCE = new Set(["low", "medium", "high"] as const);
type Confidence = "low" | "medium" | "high";
const VALID_REPLY_PICK = new Set([
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
] as const);
export type ReplyPick =
  | "extend"
  | "resonate"
  | "tease"
  | "humor"
  | "coldRead";

export interface QuickPayload {
  nextStep: string;
  pick: ReplyPick;
  recommendedReply: string;
  shortReason: string;
  insufficientContext: boolean;
  confidence: Confidence;
}

export type ParseError =
  | "NO_JSON"
  | "INVALID_JSON"
  | "MISSING_REQUIRED_FIELD";

export type ParseQuickResult =
  | { ok: true; payload: QuickPayload }
  | { ok: false; error: ParseError };

export function parseQuickResponse(rawText: string): ParseQuickResult {
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return { ok: false, error: "NO_JSON" };

  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonMatch[0]);
  } catch {
    return { ok: false, error: "INVALID_JSON" };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, error: "INVALID_JSON" };
  }
  const obj = parsed as Record<string, unknown>;

  const nextStep = coerceString(obj.nextStep);
  const pickRaw = coerceString(obj.pick);
  const recommendedReply = coerceString(obj.recommendedReply);
  const shortReason = coerceString(obj.shortReason);

  // Plan I7 + Codex P2 review: 上方精華卡同時 bind 到 nextStep ("本回合怎麼接")
  // 與 recommendedReply (可貼的訊息原文)。少了任一個，quick 都沒辦法 render
  // 完整的 above-the-fold UX，當作 parse failure 比較誠實 — handler 會回 502
  // 且 I8 保證不會留 row / 不會扣 quota。
  if (recommendedReply.length === 0 || nextStep.length === 0) {
    return { ok: false, error: "MISSING_REQUIRED_FIELD" };
  }
  if (!VALID_REPLY_PICK.has(pickRaw as ReplyPick)) {
    return { ok: false, error: "MISSING_REQUIRED_FIELD" };
  }

  const confidenceRaw = typeof obj.confidence === "string"
    ? obj.confidence.toLowerCase().trim()
    : "";
  const confidence: Confidence =
    VALID_CONFIDENCE.has(confidenceRaw as Confidence)
      ? (confidenceRaw as Confidence)
      : "medium";

  return {
    ok: true,
    payload: {
      nextStep,
      pick: pickRaw as ReplyPick,
      recommendedReply,
      shortReason,
      insufficientContext: coerceBoolean(obj.insufficientContext),
      confidence,
    },
  };
}

function coerceString(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim();
}

function coerceBoolean(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const lower = value.toLowerCase().trim();
    if (lower === "true") return true;
    if (lower === "false") return false;
  }
  return false;
}

// ----------------------------------------------------------------------------
// Guardrails
// ----------------------------------------------------------------------------
//
// Quick mode produces only `recommendedReply` + `nextStep` as user-visible
// surfaces, so the legacy `checkAiOutput` shape (replies map + enthusiasm)
// doesn't fit. We re-use the same BLOCKED_PATTERNS list with a small adapter.
//
// On hit:
//   - both `recommendedReply` and `nextStep` are swapped for a generic safe
//     placeholder (the slim equivalent of getSafeReplies)
//   - `safetyFiltered: true` is propagated so the handler can mark the AI log
//     and the UI can show a soft notice
//
// I9: same guardrails on both response paths (full path keeps using
// checkAiOutput in the existing post-processing block).

const QUICK_BLOCKED_PATTERNS: RegExp[] = [
  /跟蹤|stalking/i,
  /不要放棄.*一直/i,
  /她說不要.*但其實/i,
  /強迫|逼.*答應/i,
  /騷擾|harassment/i,
  /威脅|勒索/i,
  /死纏爛打/i,
  /不尊重.*意願/i,
  /忽視.*拒絕/i,
];

const SAFE_QUICK_FALLBACK: Pick<
  QuickPayload,
  "nextStep" | "pick" | "recommendedReply" | "shortReason"
> = {
  nextStep: "先放慢腳步，給彼此一些空間",
  pick: "resonate",
  recommendedReply: "好的，我先讓你忙，你方便的時候再聊。",
  shortReason: "不施壓、給對方退路是穩定關係的基底",
};

export interface QuickGuardrailResult {
  payload: QuickPayload;
  safetyFiltered: boolean;
}

export function applyQuickGuardrails(payload: QuickPayload): QuickGuardrailResult {
  const surfaces = [payload.recommendedReply, payload.nextStep, payload.shortReason]
    .filter((value): value is string => typeof value === "string");
  const combined = surfaces.join(" ");
  const hit = QUICK_BLOCKED_PATTERNS.some((re) => re.test(combined));
  if (!hit) return { payload, safetyFiltered: false };

  return {
    payload: {
      ...payload,
      nextStep: SAFE_QUICK_FALLBACK.nextStep,
      pick: SAFE_QUICK_FALLBACK.pick,
      recommendedReply: SAFE_QUICK_FALLBACK.recommendedReply,
      shortReason: SAFE_QUICK_FALLBACK.shortReason,
      confidence: "low",
    },
    safetyFiltered: true,
  };
}

// ----------------------------------------------------------------------------
// Full-phase ETA lookup
// ----------------------------------------------------------------------------
//
// Build 213 baseline (per plan §1.3): table lookup, not a real predictor.
// Conservative — round up. Server returns a single integer; client widens it
// into an `[eta-2, eta+3]` range string so the UI doesn't feel like a broken
// promise if the actual call lands 1-2s late.

export interface EstimateFullInput {
  model: string;
  hasImages: boolean;
  cacheHit?: boolean; // reserved for future calibration; not used in v1
}

export function estimateFullSeconds(input: EstimateFullInput): number {
  if (input.hasImages) return 22; // Sonnet vision ≈ 18-25s
  if (input.model.toLowerCase().includes("haiku")) return 5;
  return 17; // Sonnet text ≈ 15-20s
}
