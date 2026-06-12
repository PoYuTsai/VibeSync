import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildStreamSystemPrompt } from "./stream_prompt.ts";

Deno.test("stream prompt wraps base prompt with JSONL event contract", () => {
  const prompt = buildStreamSystemPrompt("Base full reasoning prompt.");

  assert(prompt.includes("Base full reasoning prompt."));
  assert(prompt.includes("Return JSONL only"));
  assert(prompt.includes("one complete minified JSON object per line"));
  assert(prompt.includes("analysis.progress"));
  assert(prompt.includes("analysis.decision"));
  assert(prompt.includes("analysis.recommendation"));
  assert(prompt.includes("analysis.reply_option"));
  assert(prompt.includes("analysis.metrics"));
  assert(prompt.includes("analysis.coach_hint"));
  assert(prompt.includes("analysis.report_section"));
  assert(prompt.includes("analysis.done"));
  assert(prompt.includes("Emit exactly 5 `analysis.reply_option` events"));
  assert(
    prompt.includes(
      "Complete all required `analysis.reply_option` events before any metrics, report sections, or done event.",
    ),
  );
  assert(
    prompt.includes(
      "Do not spend finalResult tokens duplicating the full five-style replyOptions",
    ),
  );
  assertEquals(
    prompt.includes(
      "analysis.done.finalResult.replies and `replyOptions` must include every allowed reply style",
    ),
    false,
  );
  assert(
    prompt.indexOf("analysis.decision") <
      prompt.indexOf("analysis.recommendation"),
  );
  assert(prompt.includes("first, as soon as you know the next move"));
  assert(prompt.includes("analysis.progress` is optional after"));
  assert(prompt.includes("status/waiting copy only"));
  assert(prompt.includes("Do not include advice"));
  assert(prompt.includes("doThis"));
  assert(prompt.includes("avoidThis"));
  for (const style of ["extend", "resonate", "tease", "humor", "coldRead"]) {
    assert(prompt.includes(style));
  }
  assert(prompt.includes("Traditional Chinese"));
  // v2 加 few-shot 後放寬，仍鎖上限防 contract 無限膨脹。
  assert(prompt.length < 5000);
});

Deno.test("stream prompt trims the base prompt before appending contract", () => {
  const prompt = buildStreamSystemPrompt("  Base prompt.  ");

  assertEquals(
    prompt.startsWith("Base prompt.\n\n## Streaming Output Contract"),
    true,
  );
});

Deno.test("stream prompt can restrict reply styles for the active tier", () => {
  const prompt = buildStreamSystemPrompt("Base prompt.", ["extend"]);

  assert(
    prompt.includes("Use only these style values for this request: `extend`."),
  );
  assert(prompt.includes("Emit exactly 1 `analysis.reply_option` events"));
  assert(
    prompt.includes("Do not emit reply styles outside this request list."),
  );
  assertEquals(prompt.includes("`resonate`"), false);
  assertEquals(prompt.includes("`tease`"), false);
  assertEquals(prompt.includes("`humor`"), false);
  assertEquals(prompt.includes("`coldRead`"), false);
});

// ---------------------------------------------------------------------------
// 方案二件3 stream 協議 v2 — segments[] 一等公民 + 瘦 recommendation + few-shot
//
// #12 root cause：分段規格從未進事件協議（只在 finalResult 一句話帶過，又被
// compact 指令吃掉）。v2 把 segments 直接定義在 reply_option 事件上，模型不再
// 寫 flat message（D4，server join 合成相容欄位）、recommendation 不再帶回覆
// 全文（D2 瘦推薦卡，字只寫一次在 selected reply_option）。
// ---------------------------------------------------------------------------

Deno.test("v2: reply_option spec makes segments first-class, no flat message", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`segments`"));
  assert(prompt.includes("`sourceIndex`"));
  assert(prompt.includes("`sourceMessage`"));
  assert(prompt.includes("one segment per caught ball"));
  // D4：模型不寫 flat message，server join 合成。
  assert(prompt.includes("Do not write a flat `message` field"));
  // 舊規格殘骸不得留下：finalResult replySegments 條款與 max 3 cap。
  assertEquals(
    prompt.includes("finalResult.finalRecommendation.replySegments"),
    false,
  );
  assertEquals(prompt.includes("(max 3)"), false);
  // D1：cap 放寬到 5。
  assert(prompt.includes("up to 5"));
});

Deno.test("v2: recommendation event is thin (selectedStyle + reason + expectedReaction)", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`expectedReaction`"));
  // 瘦卡：不再要求 message/quotedContext 全文欄位。
  assertEquals(
    prompt.includes(
      "fields `selectedStyle`, `message`, `reason`, and `quotedContext`",
    ),
    false,
  );
  assert(prompt.includes("Do not repeat the reply text"));
});

Deno.test("v2: thin recommendation is explicitly required with its own few-shot", () => {
  // prod 黑箱 r1：瘦卡內容少到被模型視為可省略 → 整條 stream 沒出
  // recommendation。標 REQUIRED + 給 few-shot，與 reply_option 同款待遇。
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("analysis.recommendation` is REQUIRED"));
  assert(prompt.includes('{"type":"analysis.recommendation"'));
  assert(prompt.includes('"expectedReaction"'));
});

Deno.test("v2: prompt carries a one-line multi-ball reply_option few-shot", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes('{"type":"analysis.reply_option"'));
  assert(prompt.includes('"segments":['));
  // few-shot 必須示範多球（≥2 段），單段範例會被模型當預設形狀。
  const example = prompt.slice(prompt.indexOf('{"type":"analysis.reply_option"'));
  assertEquals(example.split('"sourceIndex"').length >= 3, true);
});
