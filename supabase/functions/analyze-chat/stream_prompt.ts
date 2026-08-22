// Streaming prompt adapter for analyze-chat.
//
// This wrapper states transport and event-level invariants: JSONL ordering,
// payload requirements, and the fail-soft checks the reframer observes. The
// selected base prompt remains responsible for reasoning and safety semantics.

import {
  isStreamStyle,
  STREAM_STYLES,
  type StreamStyle,
} from "./stream_events.ts";

export function buildStreamSystemPrompt(
  basePrompt: string,
  requestedReplyStyles: readonly string[] = STREAM_STYLES,
): string {
  const replyStyles = normalizeReplyStyles(requestedReplyStyles);
  const styleList = replyStyles.map((style) => `\`${style}\``).join(", ");

  return [
    basePrompt.trim(),
    "",
    "## Streaming Output Contract",
    "Return JSONL only: one complete minified JSON object per line.",
    "Use newline only as the record separator. Do not use markdown, code fences, prose, arrays, or pretty-printed JSON.",
    "If a string needs a line break, escape it as \\n inside the JSON string.",
    "Every object must include a string `type` field.",
    "",
    "Emit events in this exact order:",
    "0. `analysis.inventory` first; inventory every item in her Latest Analysis Fragment before choosing a style. Never use earlier messages, conversationSummary, or partnerSummary as a ball/sourceMessage. Each item needs 1-based `sourceIndex`, exact `sourceMessage`, `disposition` (`接`/`併`/`略`), and `reason`. Group by independent conversational move; `併` enriches a related `接`, and `略` needs no reply.",
    "1. `analysis.decision` as soon as the next move is known. Do not wait for the full report. Include `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, and `confidence`. Treat `doThis` as the canonical reply plan: goal, reply/pause, nextAction/logistics, knownFacts, unknowns, timing, commitment/exit room, and pressure. Do not add a new event or change the event shape.",
    "The canonical plan is shared by every style. Keep the exact same action, reply/pause decision, logistics, who goes where, destination, meeting timing, confirmation point, commitment, consent/exit room, and pressure across all options. Style is only a 15–25% tone overlay.",
    "2. `analysis.recommendation` once, thin: only `selectedStyle`, `reason`, and `expectedReaction` (one short line on how she will likely react). This event is REQUIRED even though it repeats the decision's selectedStyle. Do not repeat reply text here; the selected style's `analysis.reply_option` is the single source of reply wording.",
    `3. Emit exactly ${replyStyles.length} \`analysis.reply_option\` events: one for each allowed reply style (${styleList}). Emit the selected style first, then the other allowed styles.`,
    "Low-investment rule for every option: no pressure, guilt, or bids for reassurance.",
    "Complete all required `analysis.reply_option` events before any metrics, report sections, or done event.",
    "Each `analysis.reply_option` must include `style`, `reason`, `segments`, and `stretchLevel`. Use the exact same sourceIndex/sourceMessage set, order, and count in every option; the set must not change with style. Segment count equals independent conversational moves in the inventory, usually 1–3 and at most 5. There is no minimum of 3. Never split one move into filler segments, invent a ball, or repeat a move. Fold `併` context into its related `接`; never create a segment for `併` or `略` and never source a segment from `略`.",
    "Use stated/established facts only; never invent. Keep time exact and keep unknown logistics unknown. Each segment needs non-empty `sourceIndex`, exact `sourceMessage`, sendable `reply`, and short `reason`. Do not write a flat `message` field; the server joins `segments` into legacy-compatible fields.",
    "`stretchLevel` (`within`/`stretch`/`far`) describes the user's current level, one doable step beyond it, or too large a jump. With no comfort-zone information, use `within` for all.",
    "Runtime coverage validation is fail-soft and log-only. It never rejects an option or asks for a retry; exact source coverage is the quality signal.",
    "4. `analysis.metrics`: payload must carry `enthusiasm` (`score`,`level`), `dimensions` (`heat`,`engagement`,`topicDepth`,`replyWillingness`,`emotionalConnection`), `topicDepth` (`current`,`suggestion`), and `gameStage` (`current`,`status`,`nextStep`). `gameStage.current`=opening/premise/qualification/narrative/close; `status`=normal/stuckFriend/canAdvance/shouldRetreat. Score only her messages after Latest Analysis Fragment; history/previous score only disambiguate, never add points. Stage = latest task, not relationship level; current evidence beats Stage Continuity (weak prior, never a floor). Priority: close scheduling > qualification fit/boundary > narrative story/emotion > premise mutual romantic/playful tension > opening. Stage may skip/retreat. `opening` only for true first contact or explicit reconnect after material silence/conflict—not missing data, a greeting, or one short reply; `narrative` is never a default; `close` needs current reciprocal invite/scheduling, never a partner label/goal. 認識場景/Partner Context only tunes advice; never changes score/stage or excuses low investment. Topic Depth limits reply escalation, not stage.",
    "5. `analysis.coach_hint` once when useful; its payload must carry `coachActionHint` with `catchablePoint`, `read`, `microMove`, `avoid`, `actionType`, and `confidence`.",
    "6. `analysis.report_section` carries explicit `section` + `payload`; cover `psychology`, `strategy`, `reminder`, `targetProfile`, and `healthCheck`. `healthCheck` uses plural `issues` and `suggestions`; with no evidence both are empty arrays. Entitlement postprocess may remove gated report data after assembly.",
    "7. `analysis.done` once at the end. Its compact `finalResult` must preserve `scenarioDetected`, `warnings`, and every legacy-compatible analysis field not already carried by an event.",
    "Do not spend finalResult tokens duplicating the full five-style replyOptions or reply segments; the stream assembler copies emitted `analysis.reply_option` events into `replies`, `replyOptions`, and the final recommendation.",
    "`analysis.progress` is optional after `analysis.decision` only. It must contain status/waiting copy only. Do not include advice, reply text, selected style, doThis, avoidThis, or conversation-specific coaching in progress events.",
    "",
    `Use only these style values for this request: ${styleList}.`,
    "Do not emit reply styles outside this request list.",
    "The `analysis.recommendation.selectedStyle` must match the final recommendation direction in `analysis.done.finalResult`.",
    "The selected style must be one of the request style values.",
    "If output is getting long, shorten optional report sections before you omit any required `analysis.reply_option` event or any of its `segments`.",
    "Traditional Chinese (Taiwan) only; never Simplified.",
  ].join("\n");
}

const LEGAL_GAME_STAGES = [
  "opening",
  "premise",
  "qualification",
  "narrative",
  "close",
] as const;

export function normalizeStagePrior(previousStage: unknown): string | null {
  if (typeof previousStage !== "string") return null;
  const trimmed = previousStage.trim();
  return (LEGAL_GAME_STAGES as readonly string[]).includes(trimmed)
    ? trimmed
    : null;
}

/// 上次有效階段（partner-scoped 弱先驗）→ user prompt 的 Stage Continuity
/// 區塊。只接受五個合法 enum 名；缺值、未知值、大小寫不符一律回空字串——
/// 弱先驗缺失時不得偽造，也不得讓垃圾字串進 prompt。
export function buildStagePriorSection(previousStage: unknown): string {
  const normalized = normalizeStagePrior(previousStage);
  if (normalized === null) return "";
  return [
    "## Stage Continuity",
    `- Previous valid interaction stage for this partner: ${normalized}`,
    "- Weak prior only: keep it when current evidence is ambiguous; strong current evidence may advance, skip, or retreat. Never treat it as a floor.",
  ].join("\n");
}

export const LATEST_ANALYSIS_FRAGMENT_MARKER =
  "## Latest Analysis Fragment (only her messages below this marker are scored)";

export function markLatestAnalysisFragment(
  lines: readonly string[],
  startIndex: number,
): string {
  if (lines.length === 0) return "";
  const safeStart = Math.max(0, Math.min(lines.length - 1, startIndex));
  return [
    ...lines.slice(0, safeStart),
    LATEST_ANALYSIS_FRAGMENT_MARKER,
    ...lines.slice(safeStart),
  ].join("\n");
}

function normalizeReplyStyles(values: readonly string[]): StreamStyle[] {
  const normalized: StreamStyle[] = [];
  for (const value of values) {
    if (isStreamStyle(value) && !normalized.includes(value)) {
      normalized.push(value);
    }
  }
  return normalized.length > 0 ? normalized : [...STREAM_STYLES];
}
