// v3 入口的位置：額度預查、功能權限、超額確認、模型限流都在它前面，它只在開關＋
// 協定版本 3 時接手，而且排在 v2 串流分派之前（v2 那段一字不動）。F04 的扣費字數
// 同時用在計費與超額確認雜湊。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("../analyze_chat_handler.ts", import.meta.url),
);

function at(needle: string): number {
  const index = source.indexOf(needle);
  assert(index >= 0, `找不到：${needle}`);
  return index;
}

Deno.test("v3 入口排在所有不打模型的關卡之後、v2 串流分派之前", () => {
  const subscription = at("// Check subscription");
  const claim = at("claimStore.claim");
  const rateLimit = at('scope: "analyze",');
  const v3Gate = at(
    'if (\n      responseMode === "stream" &&\n      shouldUseGuideV3({',
  );
  const v3Call = at("return await handleGuideV3Stream({");
  const v2Dispatch = at(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  );
  assert(subscription < claim && claim < rateLimit && rateLimit < v3Gate);
  assert(v3Gate < v3Call && v3Call < v2Dispatch);
  assertEquals(source.split("handleGuideV3Stream(").length - 1, 1);
  const gate = source.slice(v3Gate, v3Call);
  assert(gate.includes('mode: guideV3Mode(Deno.env.get("ANALYZE_GUIDE_V3"))'));
  // 續看一律交給 v2 handler。
  assert(gate.includes("isResume: analysisRunId !== null"));
  // 免費方案的張數在伺服器端把關。
  assert(
    source.slice(v3Call, v2Dispatch).includes(
      "maxCards: guideV3MaxCards(effectiveTier),",
    ),
  );
});

Deno.test("F04：只用在一般文字串流分析，計費與超額確認雜湊都用排除後的訊息", () => {
  const billingMessages = at(
    "const billingMessages = billingMessagesFor(messages, {",
  );
  const call = source.slice(
    billingMessages,
    at("const billing = resolveBilling({"),
  );
  assert(call.includes("contractVersion: contractParse.value,"));
  assert(
    call.includes(
      'plainStreamAnalysis: responseMode === "stream" && !hasImages &&\n        !recognizeOnly && !isMyMessageMode && !isOptimizeMessageMode,',
    ),
  );
  assert(billingMessages < at("messages: billingMessages,"));
  assert(
    at("computeBillingPayloadHash(\n        billingMessages,\n      )") > 0,
  );
  assertEquals(source.includes("computeBillingPayloadHash(messages)"), false);
});

Deno.test("v2 與 v3 用同一份對話雜湊輸入：開關切換時續看還對得上", () => {
  assert(at("conversationHash: await hashConversation(streamHashInput),") > 0);
  assert(at("hashInput: streamHashInput,") > 0);
});
