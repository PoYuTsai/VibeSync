import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ANALYZE_CORE_PROMPT_V2,
  buildImageAnalysisPrompt,
  SYSTEM_PROMPT,
} from "./analyze_system_prompt.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "./prompt_leak.ts";
import { SAFETY_RULES } from "./guardrails.ts";
import { classifyAnalyzeChatRequest } from "./request_shape.ts";
import { shouldIncludeLegacyDraftPrompt } from "./request_mode.ts";
import { buildStreamSystemPrompt } from "./stream_prompt.ts";

function utf8Bytes(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

Deno.test("active stream uses a runtime lean core and is at least half the base prompt", () => {
  const baseStreamPrompt = buildStreamSystemPrompt(SYSTEM_PROMPT);
  const activeStreamPrompt = buildStreamSystemPrompt(ANALYZE_CORE_PROMPT_V2);

  assert(
    utf8Bytes(activeStreamPrompt) * 2 <= utf8Bytes(baseStreamPrompt),
    `active=${utf8Bytes(activeStreamPrompt)} base=${utf8Bytes(baseStreamPrompt)}`,
  );
  assert(activeStreamPrompt.includes(SAFETY_RULES));
  assert(activeStreamPrompt.includes(PROMPT_LEAK_DEFENSE_DIRECTIVE));
  assert(activeStreamPrompt.includes("canonical reply plan"));
  assert(activeStreamPrompt.includes("coordination_handoff"));
  assert(activeStreamPrompt.includes("15–25%"));
  assert(activeStreamPrompt.includes("exact same sourceIndex/sourceMessage set"));
  assert(activeStreamPrompt.includes("There is no minimum of 3"));

  // These belong to the legacy one-object/image-draft path, not active stream.
  for (const legacyOnly of [
    "用戶訊息優化功能",
    "optimizedMessage",
    "## 輸出格式 (JSON)",
    "完整範例 1",
    "Server-enforced floor",
    "rejects and forces a retry",
  ]) {
    assertEquals(
      activeStreamPrompt.includes(legacyOnly),
      false,
      `stream prompt unexpectedly contains ${legacyOnly}`,
    );
  }
});

Deno.test("legacy SYSTEM_PROMPT still owns structured draft and image behavior", () => {
  assert(SYSTEM_PROMPT.includes("用戶訊息優化功能"));
  assert(SYSTEM_PROMPT.includes("optimizedMessage"));
  assert(SYSTEM_PROMPT.includes("## 輸出格式 (JSON)"));
  assert(SYSTEM_PROMPT.includes("replyOptions"));

  const imagePrompt = buildImageAnalysisPrompt({
    imageCount: 1,
    contextInfo: "",
    partnerContextInfo: "",
    styleContextInfo: "",
    historicalContextInfo: "",
    compiledConversationText: "她：嗨",
  });
  assert(imagePrompt.includes("recognizedConversation"));
  assert(imagePrompt.includes("First extract the visible conversation"));
});

Deno.test("draft-with-images stays on the legacy draft prompt seam", () => {
  const shape = classifyAnalyzeChatRequest({
    userDraft: "想約妳喝咖啡",
    images: ["ZmFrZQ=="],
  });

  assert(shape.ok);
  if (!shape.ok) return;
  assertEquals(shape.shape.kind, "draft_with_images_analyze");
  assertEquals(
    shouldIncludeLegacyDraftPrompt({
      responseMode: "legacy",
      isMyMessageMode: false,
      userDraft: "想約妳喝咖啡",
    }),
    true,
  );
});

Deno.test("lean core keeps the canonical-plan and style guardrails at the reasoning seam", () => {
  for (const anchor of [
    "goal",
    "reply/pause",
    "nextAction/logistics",
    "knownFacts",
    "unknowns",
    "timing",
    "commitment/exit room",
    "pressure",
    "same sourceIndex/sourceMessage set, order, and count",
    "她明確問怎麼約",
    "先完成眼前事",
    "不可腦補住家、接送、目的地、誰移動",
    "tease",
    "humor",
    "coldRead",
  ]) {
    assert(ANALYZE_CORE_PROMPT_V2.includes(anchor), `missing ${anchor}`);
  }
});
