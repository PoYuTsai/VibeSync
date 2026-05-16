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
    "OPENER_PROMPT declares insufficientInfo self-evaluation and no-charge contract",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(
      source.includes("## 資訊不足自評（profileAnalysis.insufficientInfo）"),
    );
    assert(source.includes("設為 true 的條件：以下三項**同時**成立"));
    assert(source.includes("套用到任何人都通用的句子"));
    assert(source.includes("否則一律設為 false"));
    assert(source.includes("不要為了幫使用者省額度而濫用 true"));
    assert(source.includes("後端只是會跳過扣帳"));
    assert(source.includes('"insufficientInfo": false'));
    assert(
      source.includes(
        "// Honor AI self-evaluation: when input is too thin to produce a",
      ),
    );
    assert(source.includes("profileAnalysisObj?.insufficientInfo === true"));
    assert(source.includes("const effectiveOpenerCost = insufficientInfo ? 0 : openerCost"));
    assert(source.includes("!accountIsTest && effectiveOpenerCost > 0"));
    assert(source.includes("insufficientInfo,"));
  },
});
