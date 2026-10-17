// F04 扣費字數鏡像（JS 端）：伺服器的 billingMessagesFor 要跟共用樣本一致。
// Dart 端：test/unit/services/message_calculator_test.dart 讀同一份 fixture；
// 改規則就重產 fixture（tools/billing/gen_f04_fixture.ts），兩端一起跑。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { computeBillingPayloadHash, countPayloadChars } from "../billing.ts";
import { billingMessagesFor } from "./routing.ts";

type Content = string | { repeat: string; times: number };

Deno.test("F04 鏡像：伺服器跟共用樣本一致", async () => {
  const url = new URL(
    "../../../../test/fixtures/f04_billing_mirror_vectors.json",
    import.meta.url,
  );
  const fixture = JSON.parse(await Deno.readTextFile(url)) as {
    vectors: Array<{
      name: string;
      messages: Array<{ content: Content; isFromMe: boolean }>;
      billingCount: number;
      billingChars: number;
      billingSha256: string;
    }>;
  };
  assertEquals(fixture.vectors.length > 10, true);
  for (const v of fixture.vectors) {
    const messages = v.messages.map((m) => ({
      content: typeof m.content === "string"
        ? m.content
        : m.content.repeat.repeat(m.content.times),
      isFromMe: m.isFromMe,
    }));
    const billing = billingMessagesFor(messages, {
      contractVersion: 3,
      plainStreamAnalysis: true,
    });
    assertEquals(billing.length, v.billingCount, `${v.name}: count`);
    assertEquals(
      countPayloadChars(billing),
      v.billingChars,
      `${v.name}: chars`,
    );
    assertEquals(
      await computeBillingPayloadHash(billing),
      v.billingSha256,
      `${v.name}: hash`,
    );
  }
});
