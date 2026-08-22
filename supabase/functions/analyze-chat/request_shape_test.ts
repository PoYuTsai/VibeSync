import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  acceptsUserStyleContext,
  classifyAnalyzeChatRequest,
  routeUserStyleContext,
} from "./request_shape.ts";

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

Deno.test("style context 只進輔助寫訊息路徑，主分析與 OCR 一律丟棄", () => {
  for (
    const kind of [
      "my_message",
      "optimize_message",
      "new_topic",
      "opener",
    ] as const
  ) {
    assert(acceptsUserStyleContext({ kind }));
  }
  for (
    const kind of [
      "plain_analyze",
      "draft_with_images_analyze",
      "recognize",
    ] as const
  ) {
    assertEquals(acceptsUserStyleContext({ kind }), false);
  }
});

Deno.test("主分析把 legacy style 留在 hash 相容層，但不送進模型", () => {
  const valid = { effectiveStyleContext: "偏好自然短句" };
  assertEquals(
    routeUserStyleContext({ kind: "plain_analyze" }, valid),
    { hashValue: "偏好自然短句" },
  );
  assertEquals(
    routeUserStyleContext({ kind: "draft_with_images_analyze" }, valid),
    { hashValue: "偏好自然短句" },
  );
  assertEquals(
    routeUserStyleContext({ kind: "my_message" }, valid),
    {
      modelValue: "偏好自然短句",
      hashValue: "偏好自然短句",
      error: undefined,
    },
  );
});

Deno.test("主分析忽略非法 legacy style；輔助路徑維持 400", () => {
  const invalid = { error: "Invalid effectiveStyleContext" };
  assertEquals(
    routeUserStyleContext({ kind: "plain_analyze" }, invalid),
    {},
  );
  assertEquals(
    routeUserStyleContext({ kind: "optimize_message" }, invalid),
    {
      modelValue: undefined,
      hashValue: undefined,
      error: "Invalid effectiveStyleContext",
    },
  );
});
