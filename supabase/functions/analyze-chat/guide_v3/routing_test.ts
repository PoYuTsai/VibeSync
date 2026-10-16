// 什麼請求走 v3，以及 F04 的扣費字數。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  billingMessagesFor,
  F04_MAX_EXCLUDED_CHARS,
  F04_MAX_EXCLUDED_MESSAGES,
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
  assertEquals(billingMessagesFor([], 3), []);
  assertEquals(billingMessagesFor([him, her, him], 2), [him, her, him]);
  assertEquals(billingMessagesFor([him, her, him], 1), [him, her, him]);
});

Deno.test("F04 上限：超過 5 則或 300 字、或整段都是他的，就照舊全算", () => {
  const her = { isFromMe: false, content: "她" };
  const him = (n: number) => ({ isFromMe: true, content: "字".repeat(n) });
  const five = Array.from({ length: F04_MAX_EXCLUDED_MESSAGES }, () => him(1));
  assertEquals(billingMessagesFor([her, ...five], 3), [her]);
  const six = [...five, him(1)];
  assertEquals(billingMessagesFor([her, ...six], 3), [her, ...six]);
  const atCap = [him(F04_MAX_EXCLUDED_CHARS)];
  assertEquals(billingMessagesFor([her, ...atCap], 3), [her]);
  // trim 後才算字數（照 billing.ts）。
  assertEquals(
    billingMessagesFor([her, {
      isFromMe: true,
      content: `  ${"字".repeat(F04_MAX_EXCLUDED_CHARS)}  `,
    }], 3).length,
    1,
  );
  const overCap = [him(F04_MAX_EXCLUDED_CHARS + 1)];
  assertEquals(billingMessagesFor([her, ...overCap], 3), [her, ...overCap]);
  assertEquals(billingMessagesFor([him(1), him(1)], 3), [him(1), him(1)]);
});
