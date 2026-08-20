import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { stripUnexpectedForeignClauses } from "./unexpected_foreign_text.ts";

Deno.test("外語 token 清洗會丟整個子句，不留下殘句", () => {
  assertEquals(
    stripUnexpectedForeignClauses(
      "大夜班還在學新東西，應該比妳自己糾結怎麼約простее。妳平常都幾點睡",
    ),
    "大夜班還在學新東西，妳平常都幾點睡",
  );
  assertEquals(
    stripUnexpectedForeignClauses("妳學新東西的時間都long在白天，感覺很自律"),
    "感覺很自律",
  );
});

Deno.test("外語 token 清洗保留台灣聊天裡合理的文字系統", () => {
  for (
    const text of [
      "妳那張照片很 chill 欸",
      "NASA 是工作還是興趣",
      "日文の用法妳也懂喔",
      "Long time no see",
      "妳玩 longboard 嗎",
      "oolong茶妳也喝喔",
      "這個歸屬 belong在誰那邊",
    ]
  ) {
    assertEquals(stripUnexpectedForeignClauses(text), text);
  }
});

Deno.test("整句只有外語時才退回逐字清除，清完為空就拒絕", () => {
  assertEquals(
    stripUnexpectedForeignClauses("안녕妳今天很忙嗎"),
    "妳今天很忙嗎",
  );
  assertEquals(stripUnexpectedForeignClauses("простее"), null);
  assertEquals(stripUnexpectedForeignClauses(null), null);
});
