import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasCustomerExplanationLeak,
  sanitizeCustomerExplanationText,
} from "./customer_explanation.ts";
import { filterOpenerPayloadForAllowedFeatures } from "./opener_payload.ts";

Deno.test("客戶解釋守門：只擋可列舉內部話，不當品味評分器", () => {
  for (
    const leaked of [
      "怪 選項，切角要新",
      "旁路冷讀：從作息切進去",
      "用雙球讓她挑一顆球回",
      "warm_up 階段用 whyItWorks 說明",
      "openingStrategy 先填框架維持",
    ]
  ) {
    assertEquals(hasCustomerExplanationLeak(leaked), true, leaked);
    assertEquals(sanitizeCustomerExplanationText(leaked, 500), null, leaked);
  }

  for (
    const natural of [
      "她如果反駁，就順著她補充的細節聊",
      "這張照片的構圖框架很有趣",
      "最近卡住了就換個輕鬆話題",
      "你們是一起長大的嗎",
    ]
  ) {
    assertEquals(hasCustomerExplanationLeak(natural), false, natural);
    assertEquals(sanitizeCustomerExplanationText(natural, 500), natural);
  }
});

Deno.test("客戶解釋守門：繁體化，擋 JSON 與超長", () => {
  assertEquals(
    sanitizeCustomerExplanationText("她的动态给了一個很具体的线索", 100),
    "她的動態給了一個很具體的線索",
  );
  assertEquals(sanitizeCustomerExplanationText('{"topics":[]}', 100), null);
  assertEquals(sanitizeCustomerExplanationText("```json", 100), null);
  assertEquals(sanitizeCustomerExplanationText("太".repeat(101), 100), null);
});

Deno.test("客戶解釋守門：allowedText 只放行用戶自己寫過的詞，沒給就照舊擋", () => {
  const cases: Array<[string, string]> = [
    ["她在重看人間失格，接後續最好回", "她說最近在重看人間失格"],
    ["她回了就問她雙球會怎麼配口味", "路過一家雙球冰淇淋只要五十元的店"],
    ["她高中迷 One Direction，聊那段很自然", "她說高中超迷 One Direction"],
    ["用你自己 stuck 的小事開場", "這週寫報告一直 stuck 在第一段"],
    // 素材用簡體寫，解釋已被轉成繁體：一樣算用戶的字。
    ["她在重看人間失格", "她说最近在重看人间失格"],
  ];
  for (const [text, allowedText] of cases) {
    assertEquals(hasCustomerExplanationLeak(text), true, text);
    assertEquals(sanitizeCustomerExplanationText(text, 500), null, text);
    assertEquals(hasCustomerExplanationLeak(text, allowedText), false, text);
    assertEquals(
      sanitizeCustomerExplanationText(text, 500, allowedText),
      text,
      text,
    );
  }
  // 素材沒有的術語照擋。
  assertEquals(
    hasCustomerExplanationLeak(
      "人間失格這題用旁路冷讀",
      "她說最近在重看人間失格",
    ),
    true,
  );
});

Deno.test("客戶解釋守門：開場救星呼叫端不帶 allowedText，素材詞照舊擋", () => {
  const reasonOf = (reason: string) =>
    (filterOpenerPayloadForAllowedFeatures(
      {
        openers: { extend: "妳也在看那本書嗎" },
        recommendation: { pick: "extend", reason },
      },
      ["extend"],
    )?.recommendation as Record<string, unknown> | undefined)?.reason;
  assertEquals(reasonOf("她的追星時期很好聊"), "她的追星時期很好聊");
  assertEquals(reasonOf("她最近在看人間失格，順著聊最自然"), undefined);
  assertEquals(reasonOf("她的 One Direction 時期很好聊"), undefined);
});
