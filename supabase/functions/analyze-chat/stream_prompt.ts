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
    "0. `analysis.inventory` first, before the decision and before anything else. Take the ball inventory (盤點) you build before replying and emit it here as a `balls` array — one entry per message and per media marker in her latest run ([Photo], [Missed call] each count as one). Each entry needs `sourceIndex` (1-based position in her run), `sourceMessage` (her original text), `disposition` (`接` / `併` / `略`), and a one-line `reason`. Classify every line here before you pick a style; never silently drop one. `接` means an independent conversational move that deserves its own reply segment. `併` means useful background, image, emotion, or follow-up from the same episode that MUST be folded into a nearby `接` segment, never given a standalone segment. `略` means an acknowledgement, duplicate, or detail that needs no reply. Put the inventory here, not only inside `finalRecommendation.reason`.",
    "Disposition rule: do not mark every textual line `接` just because it has a hook. Group by conversational move first. A personal callback or inside joke can be `接` or `併`; play along or tease back, and never mark it `略` only because you lack the backstory.",
    'Example inventory line: {"type":"analysis.inventory","balls":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","disposition":"接","reason":"晚餐生活球"},{"sourceIndex":2,"sourceMessage":"這家排超久","disposition":"併","reason":"同一晚餐球的背景"},{"sourceIndex":3,"sourceMessage":"等等去樂華夜市","disposition":"接","reason":"另一個可延伸行程"},{"sourceIndex":4,"sourceMessage":"哈哈","disposition":"略","reason":"收尾語氣，不需獨立回"}]}',
    "1. `analysis.decision`, as soon as you know the next move. Do not wait for the full report. Include `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, and `confidence`. Your `selectedStyle`'s segment sources must be balls marked `接`; their wording may incorporate related `併` context.",
    "2. `analysis.recommendation` once, thin: only `selectedStyle`, `reason`, and `expectedReaction` (one short line on how she will likely react). `analysis.recommendation` is REQUIRED even though it repeats the decision's selectedStyle; the recommendation card cannot render without it. Do not repeat the reply text here; the selected style's `analysis.reply_option` is the single source of the reply wording.",
    'Example recommendation line: {"type":"analysis.recommendation","selectedStyle":"extend","reason":"兩顆球都接住才有互動感","expectedReaction":"她大概會分享夜市買了什麼"}',
    `3. Emit exactly ${replyStyles.length} \`analysis.reply_option\` events: one for each allowed reply style (${styleList}). Emit the selected style first, then the other allowed styles.`,
    "Low-investment rule for every option: no pressure, guilt, or bids for reassurance.",
    "Complete all required `analysis.reply_option` events before any metrics, report sections, or done event.",
    'Each `analysis.reply_option` must include `style`, `reason`, `segments`, and `stretchLevel`: one segment per independent ball marked `接` (up to 5). Fold `併` context naturally into its related `接` segment; never create a segment just to acknowledge a `併` or `略` line. Use stated/established facts only; never invent. Keep time exact: "next month" is not "first day promoted". Each segment needs non-empty `sourceIndex` (the primary `接` ball\'s 1-based position), `sourceMessage` (her original text), `reply`, and `reason`. Do not write a flat `message` field; the server joins `segments` into legacy fields.',
    "`stretchLevel` (`within`/`stretch`/`far`): his current level, one step bolder but doable, or too big a jump. At least one style must be `stretch`; no comfort-zone info → `within` for all.",
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
    "Server-enforced floor: EVERY `analysis.reply_option` — not only the selected style — must contain at least min(3, number of independent balls marked 接) segments, each sourced from a different `接` ball. The floor is the minimum, not the target: keep one segment per `接` ball (up to 5) in every option, so all options cover the same set of `接` balls as the selected style. The server rejects and forces a retry if any option misses that floor, pulls from a `略` ball, or drops a `接` ball the selected style covers, so satisfy it without inventing extra balls. A `併` line enriches a related segment but does not raise the floor.",
    "The selected style is the reply the user will actually send, but write every option with equal effort: same `接` ball coverage, full quality in that style's own voice. An option does not need to match the longest alternative in length — equal effort means equal ball coverage, not equal word count. Keep each segment sharp; precision beats padding.",
    'Example reply_option line: {"type":"analysis.reply_option","style":"extend","reason":"把排隊併進晚餐球，再接夜市行程","stretchLevel":"stretch","segments":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","reply":"排那麼久，希望真的有好吃到值得","reason":"接晚餐並合併排隊背景"},{"sourceIndex":3,"sourceMessage":"等等去樂華夜市","reply":"夜市幫我吃份地瓜球","reason":"接另一個獨立行程球"}]}',
    "4. `analysis.metrics` once. Include `gameStage`: `current` one of `opening`/`premise`/`qualification`/`narrative`/`close`, `status` one of `normal`/`stuckFriend`/`canAdvance`/`shouldRetreat`. Judge the stage from the whole conversation plus the 認識場景 context — 已是伴侶 or clearly dating is never `opening` unless restarting after a long silence.",
    "5. `analysis.coach_hint` once when useful.",
    "6. `analysis.report_section` for deeper sections.",
    "7. `analysis.done` once at the end. Include a compact `finalResult` with legacy-compatible analysis fields.",
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

function normalizeReplyStyles(values: readonly string[]): StreamStyle[] {
  const normalized: StreamStyle[] = [];
  for (const value of values) {
    if (isStreamStyle(value) && !normalized.includes(value)) {
      normalized.push(value);
    }
  }
  return normalized.length > 0 ? normalized : [...STREAM_STYLES];
}
