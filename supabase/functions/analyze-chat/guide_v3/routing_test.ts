// 什麼請求走 v3，以及 F04 的扣費字數。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  billingMessagesFor,
  guideV3Mode,
  shouldUseGuideV3,
} from "./routing.ts";

Deno.test("開關：沒設、空白、打錯都當 off；大小寫與空白不影響", () => {
  for (const raw of [undefined, "", "true", "1", "yes", "offf"]) {
    assertEquals(guideV3Mode(raw), "off", String(raw));
  }
  assertEquals(guideV3Mode(" ON "), "on");
  assertEquals(guideV3Mode("Test"), "test");
});

Deno.test("走 v3：要協定版本 3；test 只給測試帳號；off 誰都不走", () => {
  const cases: [Parameters<typeof shouldUseGuideV3>[0], boolean][] = [
    [{ mode: "on", contractVersion: 3, accountIsTest: false }, true],
    [{ mode: "on", contractVersion: 2, accountIsTest: true }, false],
    [{ mode: "on", contractVersion: 1, accountIsTest: false }, false],
    [{ mode: "test", contractVersion: 3, accountIsTest: true }, true],
    [{ mode: "test", contractVersion: 3, accountIsTest: false }, false],
    [{ mode: "off", contractVersion: 3, accountIsTest: true }, false],
  ];
  for (const [args, expected] of cases) {
    assertEquals(shouldUseGuideV3(args), expected, JSON.stringify(args));
  }
});

Deno.test("F04：協定 3 不算她最後一則之後他連續傳的；協定 2 以下照舊全算", () => {
  const her = { isFromMe: false, content: "她" };
  const him = { isFromMe: true, content: "他" };
  assertEquals(billingMessagesFor([him, her, him, him], 3), [him, her]);
  assertEquals(billingMessagesFor([him, her], 3), [him, her]);
  assertEquals(billingMessagesFor([him, him], 3), []);
  assertEquals(billingMessagesFor([], 3), []);
  assertEquals(billingMessagesFor([him, her, him], 2), [him, her, him]);
  assertEquals(billingMessagesFor([him, her, him], 1), [him, her, him]);
});
