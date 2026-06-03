// Streaming prompt adapter for analyze-chat.
//
// Keep the base reasoning prompt as the source of truth. This wrapper changes
// only the transport contract so Claude emits complete JSONL events in the
// order the streaming reframer can validate and assemble.

export function buildStreamSystemPrompt(basePrompt: string): string {
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
    "1. `analysis.progress` two to four times.",
    "2. `analysis.decision` once with `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, and `confidence`.",
    "3. `analysis.recommendation` once with the official reply recommendation and fields `selectedStyle`, `message`, `reason`, and `quotedContext`.",
    "4. `analysis.reply_option` for the selected style first, then the other styles.",
    "5. `analysis.metrics` once.",
    "6. `analysis.coach_hint` once when useful.",
    "7. `analysis.report_section` for deeper sections.",
    "8. `analysis.done` once at the end. Include `finalResult` with a legacy-compatible analysis result.",
    "",
    "Use only these style values: `extend`, `resonate`, `tease`, `humor`, `coldRead`.",
    "The `analysis.recommendation.selectedStyle` must match the final recommendation direction in `analysis.done.finalResult`.",
    "Write user-facing content in Traditional Chinese.",
  ].join("\n");
}
