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
