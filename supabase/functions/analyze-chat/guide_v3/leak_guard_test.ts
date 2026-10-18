// v3 送出前的外洩檢查走共用比對（主審兩輪 P2，Eric 2026-10-18）：主審實際拿來測的簡體照抄要擋下，
// 每一句哨兵的各種照抄寫法經過真正的定稿入口也要擋下。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { leakVariants } from "../../_shared/prompt_leak_harness.ts";
import {
  finalizeRefinedCard,
  GUIDE_V3_REFINE_SENTINELS,
  GUIDE_V3_REFINE_SENTINELS_NORMALIZED,
  type GuideV3RefineCard,
} from "./refine_card.ts";

const ACCEPT: GuideV3RefineCard = {
  task: "accept",
  voice: "default",
  method: "reaction",
};

Deno.test("再調一下：主審的簡體照抄「调完的则数跟原本一样，不合并…」整次不給", () => {
  assertEquals(
    finalizeRefinedCard({
      draft: "週六見",
      optimized: "调完的则数跟原本一样，不合并、不拆开、顺序不变",
      card: ACCEPT,
      sourceText: "",
    }),
    { ok: false, reason: "prompt_leak" },
  );
});

Deno.test("再調一下：任務卡規則的每一句，各種照抄寫法經過定稿都擋下", () => {
  const missed: string[] = [];
  for (
    const sentinel of [
      ...GUIDE_V3_REFINE_SENTINELS,
      ...GUIDE_V3_REFINE_SENTINELS_NORMALIZED,
    ]
  ) {
    for (const variant of leakVariants(sentinel)) {
      const out = finalizeRefinedCard({
        draft: "週六見",
        optimized: variant,
        card: ACCEPT,
        sourceText: "",
      });
      if (out.ok || out.reason !== "prompt_leak") {
        missed.push(`${JSON.stringify(variant)} → ${JSON.stringify(out)}`);
      }
    }
  }
  assertEquals(missed, []);
  // 對照：一般的調整照樣通過。
  assert(
    finalizeRefinedCard({
      draft: "週六見",
      optimized: "那就週六見",
      card: ACCEPT,
      sourceText: "",
    }).ok,
  );
});
