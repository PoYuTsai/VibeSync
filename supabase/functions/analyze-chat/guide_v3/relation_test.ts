// 關係訊號（開關 ANALYZE_GUIDE_V3_RELATION，Bruce 2026-10-19 路線二）：開關怎麼讀、入口怎麼接。
// 不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { guideV3Mode, shouldReadGuideV3Relation } from "./routing.ts";

Deno.test("關係訊號開關：沒設或打錯都不開；test 只給測試帳號；on 誰都開", () => {
  for (const raw of [undefined, "", "true", "1", "offf"]) {
    for (const accountIsTest of [true, false]) {
      assertEquals(
        shouldReadGuideV3Relation({ mode: guideV3Mode(raw), accountIsTest }),
        false,
        `${raw}/${accountIsTest}`,
      );
    }
  }
  assertEquals(
    shouldReadGuideV3Relation({ mode: "test", accountIsTest: true }),
    true,
  );
  assertEquals(
    shouldReadGuideV3Relation({ mode: "test", accountIsTest: false }),
    false,
  );
  for (const accountIsTest of [true, false]) {
    assertEquals(
      shouldReadGuideV3Relation({ mode: guideV3Mode(" On "), accountIsTest }),
      true,
    );
  }
});

const handlerSource = await Deno.readTextFile(
  new URL("../analyze_chat_handler.ts", import.meta.url),
);

function at(needle: string): number {
  const index = handlerSource.indexOf(needle);
  assert(index >= 0, `找不到：${needle}`);
  return index;
}

Deno.test("關係訊號開關只在 v3 入口讀一次，交給流程（每次請求讀，跟對象記憶一樣）", () => {
  const v3Call = at("return await handleGuideV3Stream({");
  const v2Dispatch = at(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  );
  const wiring = at(
    'relation: shouldReadGuideV3Relation({\n          mode: guideV3Mode(Deno.env.get("ANALYZE_GUIDE_V3_RELATION")),\n          accountIsTest,\n        }),',
  );
  assert(v3Call < wiring && wiring < v2Dispatch);
  assertEquals(
    handlerSource.split('Deno.env.get("ANALYZE_GUIDE_V3_RELATION")').length -
      1,
    1,
  );
});
