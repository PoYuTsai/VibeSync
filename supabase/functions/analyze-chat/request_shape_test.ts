import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { classifyAnalyzeChatRequest } from "./request_shape.ts";

function kindOf(input: Parameters<typeof classifyAnalyzeChatRequest>[0]) {
  const resolution = classifyAnalyzeChatRequest(input);
  assert(resolution.ok);
  return resolution.ok ? resolution.shape.kind : "";
}

Deno.test("形狀分類：優先序鏡射 handler 分支順序", () => {
  assertEquals(kindOf({ mode: "new_topic", recognizeOnly: true }), "new_topic");
  assertEquals(kindOf({ mode: "opener", recognizeOnly: true }), "opener");
  assertEquals(kindOf({ mode: "opener", analyzeMode: "my_message" }), "opener");
  assertEquals(
    kindOf({ recognizeOnly: true, analyzeMode: "my_message" }),
    "recognize",
  );
  assertEquals(
    kindOf({ analyzeMode: "my_message", userDraft: "草稿" }),
    "my_message",
  );
  assertEquals(kindOf({ userDraft: "草稿" }), "optimize_message");
  assertEquals(kindOf({}), "plain_analyze");
});

Deno.test("形狀分類：optimize 形狀要求沒有圖；draft＋圖是獨立活形狀", () => {
  assertEquals(
    kindOf({ userDraft: "草稿", images: ["ZmFrZQ=="] }),
    "draft_with_images_analyze",
  );
  assertEquals(kindOf({ userDraft: "   ", images: [] }), "plain_analyze");
  assertEquals(kindOf({ userDraft: "草稿", images: [] }), "optimize_message");
  // 截圖分析（有圖、無草稿）是 plain analyze，必須吃 streaming-only guard。
  assertEquals(kindOf({ images: ["ZmFrZQ=="] }), "plain_analyze");
});

Deno.test("形狀分類：recognizeOnly raw 旗標與 dispatch 形狀分開回傳", () => {
  const resolution = classifyAnalyzeChatRequest({
    mode: "opener",
    recognizeOnly: true,
  });
  assert(resolution.ok);
  if (resolution.ok) {
    assertEquals(resolution.shape.kind, "opener");
    assertEquals(resolution.recognizeOnlyRequested, true);
  }
});

Deno.test("形狀分類：recognizeOnly 非布林值 fail-closed", () => {
  const resolution = classifyAnalyzeChatRequest({ recognizeOnly: "true" });
  assertEquals(resolution.ok, false);
  const nullish = classifyAnalyzeChatRequest({ recognizeOnly: null });
  assert(nullish.ok);
  if (nullish.ok) assertEquals(nullish.recognizeOnlyRequested, false);
});
