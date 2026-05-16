import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test({
  name: "OPENER_PROMPT teaches users how to reply, not just what to paste",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("讓用戶看懂「怎麼去回」"));
    assert(source.includes("先選哪顆球、用什麼框架接"));
    assert(source.includes("回完要留下什麼下一球"));
    assert(source.includes("profileAnalysis.openingStrategy 請用一句話教用戶"));
    assert(source.includes("先接哪個線索、避開哪類題、用哪種球丟回去"));
    assert(source.includes("recommendation.reason 必須像教練講解「怎麼回」"));
    assert(source.includes("刪掉哪種錯誤接法"));
    assert(
      source.includes(
        "教用戶怎麼回：這句示範了什麼框架、接哪顆球、刪掉哪種錯誤接法、女生可以怎麼接回來",
      ),
    );
  },
});

Deno.test({
  name:
    "opener no-charge billing is decided server-side, AI insufficientInfo flag is telemetry only",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Prompt: AI is told the flag is observability, not a billing lever.
    assert(
      source.includes("## 資訊不足自評（profileAnalysis.insufficientInfo）"),
    );
    assert(source.includes("AI 對自己輸出品質的誠實自評"));
    assert(source.includes("這個欄位**不**直接決定扣帳"));
    assert(
      source.includes(
        "後端會獨立依請求內容（是否有圖、是否有 bio/interests/meetingContext 實質內容）判斷",
      ),
    );
    assert(source.includes('"insufficientInfo": false'));

    // Handler: server-side eligibility is the source of truth for billing.
    assert(
      source.includes(
        "// Server-side eligibility for no-charge: when input is objectively",
      ),
    );
    assert(source.includes("const hasProfileSubstance ="));
    assert(
      source.includes(
        "const serverEligibleForNoCharge =\n        imageCount === 0 && !hasProfileSubstance;",
      ),
    );
    assert(
      source.includes(
        "const upfrontGateCost = serverEligibleForNoCharge ? 0 : openerCost;",
      ),
    );
    // Upfront 429 gate must use the eligibility-aware cost.
    assert(
      source.includes(
        "sub.monthly_messages_used + upfrontGateCost > monthlyLimit",
      ),
    );
    assert(
      source.includes(
        "sub.daily_messages_used + upfrontGateCost > dailyLimit",
      ),
    );
    // Final billing must be driven by server eligibility, not the AI flag.
    assert(
      source.includes(
        "const effectiveOpenerCost = serverEligibleForNoCharge ? 0 : openerCost;",
      ),
    );
    assert(source.includes("!accountIsTest && effectiveOpenerCost > 0"));
    // AI flag is captured for telemetry only.
    assert(source.includes("const aiInsufficientFlag ="));
    assert(source.includes("serverEligibleForNoCharge,\n        aiInsufficientFlag,"));

    // Single chokepoint: both the substance check and the prompt builder
    // must read from the same normalized profileInfo. A non-string field
    // (e.g. `interests: ["咖啡"]`) cannot bypass billing while slipping
    // into the prompt via JS string coercion.
    assert(
      source.includes(
        'import {\n  hasOpenerProfileSubstance,\n  normalizeOpenerProfileInfo,\n} from "./opener_profile.ts";',
      ),
    );
    assert(
      source.includes(
        "const normalizedProfile = normalizeOpenerProfileInfo(rawProfileInfo);",
      ),
    );
    assert(
      source.includes(
        "const hasProfileSubstance = hasOpenerProfileSubstance(normalizedProfile);",
      ),
    );
    assert(
      source.includes(
        "const { name, bio, interests, meetingContext } = normalizedProfile;",
      ),
    );
    // The prior fragile read pattern must not come back.
    assert(
      !source.includes("rawProfileInfo as Record<string, string>"),
      "prompt builder must not cast rawProfileInfo to Record<string,string>; use normalizedProfile instead",
    );
  },
});

Deno.test({
  name:
    "opener flat-cost: 3 quota per request regardless of image count, user-text-only case prompted to avoid blind A/B guessing",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Cost is now flat 3 regardless of image count. The per-image
    // surcharge formula must not come back.
    assert(source.includes("const openerCost = 3;"));
    assert(
      !source.includes("const openerCost = 3 + (imageCount * 2);"),
      "openerCost must be flat 3, not 3 + imageCount*2",
    );
    // Comment explaining the flat-cost decision should stay close to
    // the assignment so future readers don't reintroduce per-image surcharge.
    assert(
      source.includes("Flat cost regardless of image count"),
    );

    // The system prompt must now include guidance for the
    // "user-supplied text but no image" case so the model doesn't fall
    // back to generic "比較喜歡 A 還是 B" guessing on second-hand info.
    assert(
      source.includes("沒有截圖、只有用戶手填的文字"),
    );
    assert(
      source.includes("「用戶口中的對方」**二手**資訊"),
    );
    assert(
      source.includes("避開「比較喜歡 A 還是 B」"),
    );
  },
});
