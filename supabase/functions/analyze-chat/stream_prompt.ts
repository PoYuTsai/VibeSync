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
    "0. `analysis.inventory` first, before the decision and before anything else. Take the ball inventory (盤點) you build before replying and emit it here as a `balls` array — one entry per message and per media marker in her latest run ([Photo], [Missed call] each count as one). Each entry needs `sourceIndex` (1-based position in her run), `sourceMessage` (her original text), `disposition` (`接` / `併` / `略`), and a one-line `reason`. Classify every ball here before you pick a style; never silently drop a ball. Put the inventory in this event, not only inside `finalRecommendation.reason`. This is the inventory, not the reply.",
    'Example inventory line: {"type":"analysis.inventory","balls":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","disposition":"接","reason":"生活分享可順勢延伸"},{"sourceIndex":2,"sourceMessage":"等等去樂華夜市","disposition":"併","reason":"與晚餐同生活片段，合併接"},{"sourceIndex":3,"sourceMessage":"[Photo]","disposition":"略","reason":"無文字訊息點可接"}]}',
    "1. `analysis.decision`, as soon as you know the next move. Do not wait for the full report. Include `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, and `confidence`. Your `selectedStyle`'s segments must come only from balls you marked `接` or `併` in the inventory.",
    "2. `analysis.recommendation` once, thin: only `selectedStyle`, `reason`, and `expectedReaction` (one short line on how she will likely react). `analysis.recommendation` is REQUIRED even though it repeats the decision's selectedStyle; the recommendation card cannot render without it. Do not repeat the reply text here; the selected style's `analysis.reply_option` is the single source of the reply wording.",
    'Example recommendation line: {"type":"analysis.recommendation","selectedStyle":"extend","reason":"兩顆球都接住才有互動感","expectedReaction":"她大概會分享夜市買了什麼"}',
    `3. Emit exactly ${replyStyles.length} \`analysis.reply_option\` events: one for each allowed reply style (${styleList}). Emit the selected style first, then the other allowed styles.`,
    "Complete all required `analysis.reply_option` events before any metrics, report sections, or done event.",
    "Each `analysis.reply_option` must include `style`, `reason`, and `segments`: one segment per caught ball (up to 5), each with non-empty `sourceIndex` (1-based position in her latest run), `sourceMessage` (her original text), `reply`, and `reason`. Do not write a flat `message` field; the server joins `segments` into legacy fields.",
    'Example reply_option line: {"type":"analysis.reply_option","style":"extend","reason":"接住晚餐球再順勢延伸夜市","segments":[{"sourceIndex":1,"sourceMessage":"剛來吃晚餐","reply":"吃了什麼好料？","reason":"接住晚餐球"},{"sourceIndex":2,"sourceMessage":"等等要去樂華夜市","reply":"夜市幫我吃份地瓜球","reason":"延伸夜市話題"}]}',
    "4. `analysis.metrics` once.",
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
    "Write user-facing content in Traditional Chinese.",
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
