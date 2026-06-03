import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { OPTIMIZE_MESSAGE_SYSTEM_PROMPT } from "./optimize_prompt.ts";

Deno.test("optimize prompt stays focused on optimizedMessage only", () => {
  assertStringIncludes(
    OPTIMIZE_MESSAGE_SYSTEM_PROMPT,
    '"optimizedMessage"',
  );
  assertStringIncludes(
    OPTIMIZE_MESSAGE_SYSTEM_PROMPT,
    "Return ONLY valid JSON",
  );
  assertStringIncludes(
    OPTIMIZE_MESSAGE_SYSTEM_PROMPT,
    "Do not generate a full conversation analysis",
  );
  assertStringIncludes(
    OPTIMIZE_MESSAGE_SYSTEM_PROMPT,
    "Do not output suggestions",
  );
  assert(OPTIMIZE_MESSAGE_SYSTEM_PROMPT.length < 3000);
});
