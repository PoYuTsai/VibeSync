// The single external seam for the active AnalyzeChat streaming prompt.
// Callers provide only the styles available to this request; all prompt
// composition details remain private to the AnalyzeChat prompt module.

import { SYSTEM_PROMPT } from "./analyze_prompt/system_prompt.ts";
import {
  buildStreamSystemPrompt,
  type StreamPromptOptions,
} from "./stream_prompt.ts";

export function buildAnalyzeStreamSystemPrompt(
  requestedReplyStyles: readonly string[],
  options: StreamPromptOptions = {},
): string {
  return buildStreamSystemPrompt(SYSTEM_PROMPT, requestedReplyStyles, options);
}
