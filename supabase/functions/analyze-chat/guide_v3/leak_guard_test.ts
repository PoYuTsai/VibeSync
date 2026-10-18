// v3 送出前的外洩檢查走共用比對（主審兩輪 P2，Eric 2026-10-18）：主審實際拿來測的簡體照抄要擋下，
// 每一句哨兵的各種照抄寫法經過真正的定稿入口也要擋下。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { leakVariants } from "../../_shared/prompt_leak_harness.ts";
import {
  finalizeCard,
  GUIDE_V3_SENTINELS,
  GUIDE_V3_SENTINELS_NORMALIZED,
  vetCoachText,
} from "./finalize.ts";
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

Deno.test("判讀：主審的簡體照抄「用 户＝他（男生），对象＝她…」不給", () => {
  assertEquals(
    vetCoachText("用 户＝他（男生），对象＝她。他对她有兴趣，也在看"),
    { ok: false },
  );
});

Deno.test("說明書哨兵的每一句：各種照抄寫法經過出卡定稿與判讀檢查都擋下", () => {
  const missed: string[] = [];
  for (
    const sentinel of [...GUIDE_V3_SENTINELS, ...GUIDE_V3_SENTINELS_NORMALIZED]
  ) {
    for (const variant of leakVariants(sentinel)) {
      const card = finalizeCard(
        {
          card: 1,
          messages: [`好啊 ${variant}`],
          hasInventedDetail: false,
          expectedReaction: "",
        },
        { voice: "預設" },
        "",
      );
      if (card.ok || card.reason !== "prompt_leak") {
        missed.push(`卡：${JSON.stringify(variant)} → ${JSON.stringify(card)}`);
      }
      if (vetCoachText(`她在分享 ${variant}`).ok) {
        missed.push(`判讀：${JSON.stringify(variant)}`);
      }
    }
  }
  assertEquals(missed, []);
  // 對照：一般的卡與判讀照樣通過。
  assert(
    finalizeCard(
      {
        card: 1,
        messages: ["好啊 週六見"],
        hasInventedDetail: false,
        expectedReaction: "",
      },
      { voice: "預設" },
      "",
    ).ok,
  );
  assert(vetCoachText("她在分享日常，氣氛輕鬆").ok);
});
