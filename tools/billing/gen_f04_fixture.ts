// F04 扣費字數鏡像 fixture 生成器：以伺服器權威實作
// （guide_v3/routing.ts 的 billingMessagesFor＋billing.ts）產生期望值，
// Dart 端（message_calculator_test.dart）與 JS 端
// （guide_v3/f04_billing_mirror_test.ts）共同對拍。
import {
  computeBillingPayloadHash,
  countPayloadChars,
} from "../../supabase/functions/analyze-chat/billing.ts";
import { billingMessagesFor } from "../../supabase/functions/analyze-chat/guide_v3/routing.ts";

type Content = string | { repeat: string; times: number };
type Spec = { name: string; messages: Array<[Content, boolean]> };

// [內容, isFromMe]；true＝他傳的。
const specs: Spec[] = [
  {
    name: "ends_with_hers",
    messages: [["在嗎", false], ["在啊", true], ["好", false]],
  },
  {
    name: "one_trailing_his",
    messages: [["週末要幹嘛", false], ["還沒想耶", true]],
  },
  {
    name: "five_trailing_his",
    messages: [["妳呢", false], ["a", true], ["b", true], ["c", true], [
      "d",
      true,
    ], ["e", true]],
  },
  {
    name: "six_trailing_his_bills_all",
    messages: [
      ["妳呢", false],
      ["a", true],
      ["b", true],
      ["c", true],
      ["d", true],
      ["e", true],
      ["f", true],
    ],
  },
  {
    name: "trailing_his_exactly_300",
    messages: [["嗯嗯", false], [{ repeat: "好", times: 300 }, true]],
  },
  {
    name: "trailing_his_301_bills_all",
    messages: [["嗯嗯", false], [{ repeat: "好", times: 301 }, true]],
  },
  {
    name: "trailing_his_split_301_bills_all",
    messages: [["嗯嗯", false], [{ repeat: "a", times: 150 }, true], [{
      repeat: "b",
      times: 151,
    }, true]],
  },
  {
    name: "trailing_his_trimmed",
    messages: [["哈哈", false], ["  在幹嘛  ", true]],
  },
  {
    name: "trailing_his_emoji_300_units",
    messages: [["哈哈", false], [{ repeat: "😀", times: 150 }, true]],
  },
  {
    name: "trailing_his_emoji_302_units_bills_all",
    messages: [["哈哈", false], [{ repeat: "😀", times: 151 }, true]],
  },
  { name: "all_his_bills_all", messages: [["嗨", true], ["在嗎", true]] },
  {
    name: "his_in_middle_not_trailing",
    messages: [["嗨", false], ["嗨嗨", true], ["今天好累", false]],
  },
  { name: "empty", messages: [] },
];

function expand(c: Content): string {
  return typeof c === "string" ? c : c.repeat.repeat(c.times);
}

const vectors = [];
for (const spec of specs) {
  const messages = spec.messages.map(([content, isFromMe]) => ({
    content: expand(content),
    isFromMe,
  }));
  const billing = billingMessagesFor(messages, {
    contractVersion: 3,
    plainStreamAnalysis: true,
  });
  vectors.push({
    name: spec.name,
    messages: spec.messages.map(([content, isFromMe]) => ({
      content,
      isFromMe,
    })),
    billingCount: billing.length,
    billingChars: countPayloadChars(billing),
    billingSha256: await computeBillingPayloadHash(billing),
  });
}
console.log(JSON.stringify(
  {
    _comment:
      "F04（Eric 2026-10-16）JS/Dart 扣費鏡像共用樣本：協定 3 的一般文字串流分析，對話最後面連續的「他」的訊息（最多 5 則、合計 300 字）不算扣費字數與超額確認雜湊。由 tools/billing/gen_f04_fixture.ts 以伺服器 guide_v3/routing.ts 生成；兩端測試（guide_v3/f04_billing_mirror_test.ts / message_calculator_test.dart）必須同時讀本檔。",
    vectors,
  },
  null,
  2,
));
