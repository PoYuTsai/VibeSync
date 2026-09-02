// Streaming prompt adapter for analyze-chat.
//
// Keep the base reasoning prompt as the source of truth. This wrapper changes
// only the transport contract so Claude emits complete JSONL events in the
// order the streaming reframer can validate and assemble.

import {
  isStreamStyle,
  STREAM_STYLES,
  type StreamStyle,
} from "./stream_events.ts";

export interface StreamPromptOptions {
  /// analysisContractVersion >= 2: the model may answer with a no-send
  /// decision instead of reply options. Off by default so the v1 prompt stays
  /// byte-identical (baseline_contract_test hash lock).
  noSendDecisions?: boolean;
  /// Phase 2 (§11): guidance lines of the social-knowledge atoms selected for
  /// this request. Rendered only when non-empty, so the v1 prompt stays
  /// byte-identical.
  situationKnowledge?: readonly string[];
}

// §11.3 衝突順序：高層可禁止生成，低層 voice 不得覆蓋高層。
const SITUATION_KNOWLEDGE_HEADER = [
  "## Situation Knowledge (selected for this request)",
  "Apply these rules before composing; they narrow the reasoning above and never loosen it. When two rules conflict, the earlier layer wins: boundary/rejection → evidence sufficiency → investment/mutuality → stage/action → ball selection → reply construction → voice.",
];

export function buildSituationKnowledgeSection(
  guidance: readonly string[],
): string {
  const lines = guidance.map((line) => line.trim()).filter((line) =>
    line !== ""
  );
  if (lines.length === 0) return "";
  return [
    ...SITUATION_KNOWLEDGE_HEADER,
    ...lines.map((line) => `- ${line}`),
  ].join("\n");
}

// Phase 1b message decision gate. Appended right after step 1 so the model
// decides before it writes a single reply; v1 wording above and below is
// untouched.
const NO_SEND_DECISION_GATE = [
  "1a. Message decision gate (this request supports it): every `analysis.decision` must include `messageDecision`, one of `send`, `do_not_send`, `acknowledge_and_stop`, `need_context`. Decide this before any reply wording.",
  "Use `send` when there is a reasonable, low-risk next message; then follow steps 1-3 exactly as written. Use `do_not_send` when her latest fragment is low-effort, repeats non-uptake, or adds no new content, so replying would only keep the conversation alive for her. Use `need_context` when you cannot tell who said what or the fragment is incomplete. Use `acknowledge_and_stop` when she set a boundary, cancelled, or the polite move is one neutral closing line.",
  "Every instruction below that is marked `[send decisions only]` applies only when `messageDecision` is `send`; for the three non-send decisions those events are forbidden, not optional.",
  "For the three non-send decisions: omit `selectedStyle`; include `action` (`stop`/`connect`/`extend`/`filter`/`invite`/`pause`), `reason` (why not now, grounded in her actual messages), and `stopCondition` (what she must do before you reconsider); for `acknowledge_and_stop` also include `closingMessage` (one short neutral line, Traditional Chinese). Then skip steps 2 and 3 entirely: emit no `analysis.recommendation` and no `analysis.reply_option`, continue from step 4, and put no replies in `finalResult`. A non-send decision is a complete, successful analysis, not a failure, and it is never a way to avoid a hard reply.",
  'Example no-send line: {"type":"analysis.decision","messageDecision":"do_not_send","action":"pause","reason":"她只回「哈哈」，沒有新內容也沒有問句","stopCondition":"等她主動提到新的話題或問你問題"}',
];

export function buildStreamSystemPrompt(
  basePrompt: string,
  requestedReplyStyles: readonly string[] = STREAM_STYLES,
  options: StreamPromptOptions = {},
): string {
  const replyStyles = normalizeReplyStyles(requestedReplyStyles);
  const styleList = replyStyles.map((style) => `\`${style}\``).join(", ");
  // Under the decision gate every style / recommendation / reply_option rule
  // is scoped to `send`; the v1 text is returned untouched when the gate is off.
  const sendOnly = (text: string) =>
    options.noSendDecisions ? `[send decisions only] ${text}` : text;

  const situationKnowledge = buildSituationKnowledgeSection(
    options.situationKnowledge ?? [],
  );

  return [
    basePrompt.trim(),
    ...(situationKnowledge === "" ? [] : ["", situationKnowledge]),
    "",
    "## Streaming Output Contract",
    "Return JSONL only: one complete minified JSON object per line.",
    "Use newline only as the record separator. Do not use markdown, code fences, prose, arrays, or pretty-printed JSON.",
    "If a string needs a line break, escape it as \\n inside the JSON string.",
    "Every object must include a string `type` field.",
    "",
    "Emit events in this exact order:",
    "0. `analysis.inventory` first; before you pick a style, emit one ball per item in her Latest Analysis Fragment. Never use earlier messages, conversationSummary, or partnerSummary as a ball/sourceMessage. Each needs 1-based `sourceIndex`, `sourceMessage`, `disposition` (`接`/`併`/`略`), `reason`. `接` needs a reply; `併` folds into `接`; `略` = an acknowledgement, duplicate, or detail that needs no reply. Put it here, not only in `finalRecommendation.reason`.",
    "Disposition rule: do not mark every textual line `接` just because it has a hook. Group by conversational move first. A personal callback or inside joke can be `接` or `併`; play along or tease back, and never mark it `略` only because you lack the backstory.",
    'Example inventory line: {"type":"analysis.inventory","balls":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","disposition":"接","reason":"晚餐生活球"},{"sourceIndex":2,"sourceMessage":"這家排超久","disposition":"併","reason":"同一晚餐球的背景"},{"sourceIndex":3,"sourceMessage":"等等去樂華夜市","disposition":"接","reason":"另一個可延伸行程"},{"sourceIndex":4,"sourceMessage":"哈哈","disposition":"略","reason":"收尾語氣，不需獨立回"}]}',
    options.noSendDecisions
      ? "1. `analysis.decision`, as soon as you know the next move. Do not wait for the full report. Include `messageDecision` (see 1a) and, only when it is `send`, `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, and `confidence`. A send decision's `selectedStyle` segment sources must be balls marked `接`; their wording may incorporate related `併` context."
      : "1. `analysis.decision`, as soon as you know the next move. Do not wait for the full report. Include `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, and `confidence`. Your `selectedStyle`'s segment sources must be balls marked `接`; their wording may incorporate related `併` context.",
    ...(options.noSendDecisions ? NO_SEND_DECISION_GATE : []),
    sendOnly(
      "2. `analysis.recommendation` once, thin: only `selectedStyle`, `reason`, and `expectedReaction` (one short line on how she will likely react). `analysis.recommendation` is REQUIRED even though it repeats the decision's selectedStyle; the recommendation card cannot render without it. Do not repeat the reply text here; the selected style's `analysis.reply_option` is the single source of the reply wording.",
    ),
    sendOnly(
      'Example recommendation line: {"type":"analysis.recommendation","selectedStyle":"extend","reason":"兩顆球都接住才有互動感","expectedReaction":"她大概會分享夜市買了什麼"}',
    ),
    sendOnly(
      `3. Emit exactly ${replyStyles.length} \`analysis.reply_option\` events: one for each allowed reply style (${styleList}). Emit the selected style first, then the other allowed styles.`,
    ),
    sendOnly(
      "Low-investment rule for every option: no pressure, guilt, or bids for reassurance.",
    ),
    sendOnly(
      "Complete all required `analysis.reply_option` events before any metrics, report sections, or done event.",
    ),
    sendOnly(
      'Each `analysis.reply_option` must include `style`, `reason`, `segments`, and `stretchLevel`: one segment per independent ball marked `接` (up to 5). Fold `併` context naturally into its related `接` segment; never create a segment just to acknowledge a `併` or `略` line. Use stated/established facts only; never invent. Keep time exact: "next month" is not "first day promoted". Each segment needs non-empty `sourceIndex` (the primary `接` ball\'s 1-based position), `sourceMessage` (her original text), `reply`, and `reason`. Do not write a flat `message` field; the server joins `segments` into legacy fields.',
    ),
    sendOnly(
      "`stretchLevel` (`within`/`stretch`/`far`): his current level, one step bolder but doable, or too big a jump. At least one style must be `stretch`; no comfort-zone info → `within` for all.",
    ),
    // ⚠️ 字面已非真實（2026-06-13 fail-soft，f417bd8）：server 不再 reject／retry，
    //    floor 現為 prompt-only 準則，違反只記 log（見 reframer.ts ball_inventory canary）。
    //    這句「server rejects」措辭刻意保留——它是模型乖乖達標的 compliance 壓力來源，
    //    dogfood 已驗證有效。絕不據此句重新加硬 enforcement。改字串＝動高風險 prompt，必黑箱重驗。
    //    2026-08-09 球數對齊批：floor 從「只約束 SELECTED」擴成 EVERY option——黑箱
    //    實證模型會把非選中風格寫少段（見 b2），使用者橫滑挑其他風格時吃到漏球版。
    //    上線一週後用 [ball_coverage] telemetry 對拍驗成效（黑箱重驗）。
    //    同日追修：首筆真機 telemetry（selected 4/4、其他全 3/4）顯示模型只把
    //    reject 威嚇當 floor=3 合規線——威嚇句必須把「漏接選中已覆蓋的接球」
    //    也列為違規，same-set 才有服從壓力。
    sendOnly(
      "Server-enforced floor: EVERY `analysis.reply_option` — not only the selected style — must contain at least min(3, number of independent balls marked 接) segments, each sourced from a different `接` ball. The floor is the minimum, not the target: keep one segment per `接` ball (up to 5) in every option, so all options cover the same set of `接` balls as the selected style. The server rejects and forces a retry if any option misses that floor, pulls from a `略` ball, or drops a `接` ball the selected style covers, so satisfy it without inventing extra balls. A `併` line enriches a related segment but does not raise the floor.",
    ),
    sendOnly(
      "The selected style is sent; write every option with equal effort: equal effort means equal ball coverage, not equal word count. An option does not need to match the longest alternative; precision beats padding.",
    ),
    sendOnly(
      'Example reply_option line: {"type":"analysis.reply_option","style":"extend","reason":"把排隊併進晚餐球，再接夜市行程","stretchLevel":"stretch","segments":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","reply":"排那麼久，希望真的有好吃到值得","reason":"接晚餐並合併排隊背景"},{"sourceIndex":3,"sourceMessage":"等等去樂華夜市","reply":"夜市幫我吃份地瓜球","reason":"接另一個獨立行程球"}]}',
    ),
    "4. `analysis.metrics`: gameStage.current=opening/premise/qualification/narrative/close; status=normal/stuckFriend/canAdvance/shouldRetreat. Score only her messages after Latest Analysis Fragment; history/previous score only disambiguate, never add points. Stage = latest task, not relationship level; current evidence beats Stage Continuity (weak prior, never floor). Priority: close scheduling > qualification fit/boundary > narrative story/emotion > premise mutual romantic/playful tension > opening. Stage may skip/retreat. `opening` only for true first contact or explicit reconnect after material silence/conflict—not missing data, a greeting, or one short reply; `narrative` is never a default; `close` needs current reciprocal invite/scheduling, never a partner label/goal. 認識場景/Partner Context only tunes advice; never changes score/stage or excuses low investment. Topic Depth limits reply escalation, not stage.",
    "5. `analysis.coach_hint` once when useful.",
    "6. `analysis.report_section` for deeper sections.",
    "7. `analysis.done` once at the end. Include a compact `finalResult` with legacy-compatible analysis fields.",
    sendOnly(
      "Do not spend finalResult tokens duplicating the full five-style replyOptions or reply segments; the stream assembler copies emitted `analysis.reply_option` events into `replies`, `replyOptions`, and the final recommendation.",
    ),
    "`analysis.progress` is optional after `analysis.decision` only. It must contain status/waiting copy only. Do not include advice, reply text, selected style, doThis, avoidThis, or conversation-specific coaching in progress events.",
    "",
    sendOnly(`Use only these style values for this request: ${styleList}.`),
    "Do not emit reply styles outside this request list.",
    sendOnly(
      "The `analysis.recommendation.selectedStyle` must match the final recommendation direction in `analysis.done.finalResult`.",
    ),
    sendOnly("The selected style must be one of the request style values."),
    sendOnly(
      "If output is getting long, shorten optional report sections before you omit any required `analysis.reply_option` event or any of its `segments`.",
    ),
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
