import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const entitlementReaders = [
  "../analyze-chat/subscription_access.ts",
  "../analyze-chat/optimize_refine_flow.ts",
  "../practice-chat/handler.ts",
  "../practice-chat/draw_handler.ts",
  "../coach-chat/index.ts",
  "../coach-follow-up/index.ts",
  "../keyboard-assist/index.ts",
  "../keyboard-reply/index.ts",
];

async function source(file: string): Promise<string> {
  return await Deno.readTextFile(new URL(file, import.meta.url));
}

Deno.test("runtime entitlement readers use the shared read-time source contract", async () => {
  for (const file of entitlementReaders) {
    const text = await source(file);
    assert(
      text.includes("resolveSourceAwareSubscriptionRow"),
      `${file} must resolve store state at read time`,
    );
    assert(
      /sourceAware(?:\w+)?\.row/.test(text),
      `${file} must consume the merged source-aware row`,
    );
  }
});

Deno.test("analyze and practice gates cannot use a bare legacy tier after lookup", async () => {
  const analyzeAccess = await source("../analyze-chat/subscription_access.ts");
  const optimize = await source("../analyze-chat/optimize_refine_flow.ts");
  const practice = await source("../practice-chat/handler.ts");
  const draw = await source("../practice-chat/draw_handler.ts");

  assert(analyzeAccess.includes("sub = sourceAware.row"));
  assert(optimize.includes("sourceAwareUsage.row"));
  assert(optimize.includes("sourceAwareSub.row"));
  assert(practice.includes("sourceAware.row.tier"));
  assert(draw.includes("sourceAware.row.tier"));
});

Deno.test(
  "practice entitlement projection is wired before both limit and claim decisions",
  async () => {
    const practice = await source("../practice-chat/handler.ts");
    const draw = await source("../practice-chat/draw_handler.ts");

    const chatProjection =
      /const preparedSub = preparedSubscriptionFromRpc\(preparedSubData\)[\s\S]*?const sourceAware = await resolveSourceAwareSubscriptionRow\([\s\S]*?const sub = preparedSubscriptionFromRpc\(sourceAware\.row\)/m;
    const drawProjection =
      /const preparedSub = preparedSubscriptionFromRpc\(preparedSubData\)[\s\S]*?const sourceAware = await resolveSourceAwareSubscriptionRow\([\s\S]*?const sub = preparedSubscriptionFromRpc\(sourceAware\.row\)/m;

    const chatMatch = chatProjection.exec(practice);
    const drawMatch = drawProjection.exec(draw);
    assert(chatMatch, "practice chat must project the prepared row first");
    assert(drawMatch, "practice draw must project the prepared row first");

    const chatProjectionEnd = (chatMatch?.index ?? 0) + chatMatch![0].length;
    const drawProjectionEnd = (drawMatch?.index ?? 0) + drawMatch![0].length;
    assert(
      practice.indexOf("const limits = resolveLimits(sub.tier)") >
        chatProjectionEnd,
      "practice chat limits must use the source-aware tier",
    );
    assert(
      draw.indexOf("const limits = resolveLimits(tier)") > drawProjectionEnd,
      "practice draw limits must use the source-aware tier",
    );
    assert(
      draw.indexOf('"claim_practice_profile_draw"') > drawProjectionEnd,
      "practice draw claim must follow source-aware tier projection",
    );
  },
);
