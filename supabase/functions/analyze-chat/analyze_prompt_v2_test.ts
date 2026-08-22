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

Deno.test("active stream contract carries complete analysis event payloads", () => {
  const prompt = buildStreamSystemPrompt(ANALYZE_CORE_PROMPT_V2);
  const metricsStart = prompt.indexOf("`analysis.metrics`");
  const coachStart = prompt.indexOf("`analysis.coach_hint`");
  const reportStart = prompt.indexOf("`analysis.report_section`");
  const doneStart = prompt.indexOf("`analysis.done`");
  assert(metricsStart >= 0 && coachStart > metricsStart);
  assert(coachStart >= 0 && reportStart > coachStart);
  assert(reportStart >= 0 && doneStart > reportStart);

  const metrics = prompt.slice(metricsStart, coachStart);
  for (const key of [
    "enthusiasm",
    "score",
    "level",
    "dimensions",
    "heat",
    "engagement",
    "topicDepth",
    "replyWillingness",
    "emotionalConnection",
    "current",
    "suggestion",
    "gameStage",
    "status",
    "nextStep",
  ]) {
    assert(metrics.includes(key), `metrics missing ${key}`);
  }

  const coach = prompt.slice(coachStart, reportStart);
  for (const key of [
    "coachActionHint",
    "catchablePoint",
    "read",
    "microMove",
    "avoid",
    "actionType",
    "confidence",
  ]) {
    assert(coach.includes(key), `coach hint missing ${key}`);
  }

  const report = prompt.slice(reportStart, doneStart);
  for (const key of [
    "section",
    "payload",
    "psychology",
    "strategy",
    "reminder",
    "targetProfile",
    "healthCheck",
    "issues",
    "suggestions",
    "empty arrays",
  ]) {
    assert(report.includes(key), `report section missing ${key}`);
  }

  const done = prompt.slice(doneStart);
  for (const key of [
    "finalResult",
    "scenarioDetected",
    "warnings",
    "legacy-compatible",
  ]) {
    assert(done.includes(key), `done payload missing ${key}`);
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
