import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasCustomerExplanationLeak,
  sanitizeCustomerExplanationText,
} from "./customer_explanation.ts";

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
