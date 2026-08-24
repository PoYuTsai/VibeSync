// Private composer for the stable AnalyzeChat base prompt.
// Section order and concatenation are part of the byte-level contract.

import { SAFETY_RULES } from "../guardrails.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../prompt_leak.ts";
import { CONVERSATION_POLICY_PROMPT } from "./conversation_policy.ts";
import { EXAMPLES_LEGACY_PROMPT } from "./examples_legacy.ts";
import { REASONING_CORE_PROMPT } from "./reasoning_core.ts";
import { REPLY_VOICE_PROMPT } from "./reply_voice.ts";
import { REPORT_CONTRACT_PROMPT } from "./report_contract.ts";

const SYSTEM_PROMPT = REASONING_CORE_PROMPT +
  CONVERSATION_POLICY_PROMPT +
  REPLY_VOICE_PROMPT +
  REPORT_CONTRACT_PROMPT +
  EXAMPLES_LEGACY_PROMPT +
  SAFETY_RULES +
  PROMPT_LEAK_DEFENSE_DIRECTIVE;

export { SYSTEM_PROMPT };
