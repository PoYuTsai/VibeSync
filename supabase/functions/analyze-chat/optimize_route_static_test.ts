import { assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test({
  name:
    "optimize_message uses dedicated prompt instead of full analysis prompt",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assertStringIncludes(
      source,
      'import { OPTIMIZE_MESSAGE_SYSTEM_PROMPT } from "./optimize_prompt.ts";',
    );
    assertStringIncludes(source, "? OPTIMIZE_MESSAGE_SYSTEM_PROMPT");
    assertStringIncludes(source, ": isOptimizeMessageMode");
    assertStringIncludes(source, "## User Draft To Polish");
    assertStringIncludes(source, "!isOptimizeMessageMode && !isMyMessageMode");
    assertStringIncludes(
      source,
      "(isMyMessageMode || isOptimizeMessageMode) ? 512 : 1536",
    );
  },
});
