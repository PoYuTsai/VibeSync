// The single external seam for the active AnalyzeChat streaming prompt.
// Callers provide only the styles available to this request; all prompt
// composition details remain private to the AnalyzeChat prompt module.

import { SYSTEM_PROMPT } from "./analyze_prompt/system_prompt.ts";
import { STREAM_STYLES } from "./stream_events.ts";
import { buildStreamSystemPrompt } from "./stream_prompt.ts";

export function buildAnalyzeStreamSystemPrompt(
  requestedReplyStyles: readonly string[] = STREAM_STYLES,
): string {
  return buildStreamSystemPrompt(SYSTEM_PROMPT, requestedReplyStyles);
}
