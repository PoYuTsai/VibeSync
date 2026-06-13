// supabase/functions/analyze-chat/quoted_reply_context_test.ts
// 自我引用文案中性化（Eric 2026-06-13 拍板）：餵給模型的對話脈絡裡，引用回覆
// 一律中性、不做認人歸屬——認人不可靠（單側截圖無錨點），中性永不錯。
// 不得再輸出 "my earlier message" / "her earlier message"，否則模型會把女生
// 「接著自己稍早說的」誤寫成「引用剛剛對方說的」。
import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { assertNotMatch } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildQuotedReplyPrefix } from "./quoted_reply_context.ts";

Deno.test("自我引用（她引用自己稍早的訊息）不標『her earlier message』，一律中性", () => {
  const prefix = buildQuotedReplyPrefix({
    quotedReplyPreview: "無糖的好喝耶",
    quotedReplyPreviewIsFromMe: false,
  });
  assertNotMatch(prefix, /her earlier message/);
  assertNotMatch(prefix, /對方/);
  assertEquals(prefix, ` (replying to: "無糖的好喝耶")`);
});

Deno.test("她引用使用者稍早的訊息也不標『my earlier message』，一律中性", () => {
  const prefix = buildQuotedReplyPrefix({
    quotedReplyPreview: "騎來搭車",
    quotedReplyPreviewIsFromMe: true,
  });
  assertNotMatch(prefix, /my earlier message/);
  assertEquals(prefix, ` (replying to: "騎來搭車")`);
});

Deno.test("isFromMe 未知（null/undefined）維持中性引用", () => {
  assertEquals(
    buildQuotedReplyPrefix({ quotedReplyPreview: "你說的那家店" }),
    ` (replying to: "你說的那家店")`,
  );
  assertEquals(
    buildQuotedReplyPrefix({
      quotedReplyPreview: "你說的那家店",
      quotedReplyPreviewIsFromMe: null,
    }),
    ` (replying to: "你說的那家店")`,
  );
});

Deno.test("中性引用仍保留被引用的原文（模型仍看得到引用脈絡）", () => {
  const prefix = buildQuotedReplyPrefix({
    quotedReplyPreview: "無糖的好喝耶",
    quotedReplyPreviewIsFromMe: false,
  });
  assertStringIncludes(prefix, "無糖的好喝耶");
});

Deno.test("沒有 quotedReplyPreview 時回空字串（不加任何前綴）", () => {
  assertEquals(buildQuotedReplyPrefix({}), "");
  assertEquals(buildQuotedReplyPrefix({ quotedReplyPreview: "   " }), "");
  assertEquals(
    buildQuotedReplyPrefix({ quotedReplyPreview: "", quotedReplyPreviewIsFromMe: false }),
    "",
  );
});

Deno.test("引用原文做空白壓縮與雙引號→單引號淨化（沿用原行為）", () => {
  assertEquals(
    buildQuotedReplyPrefix({ quotedReplyPreview: "  多  空白\n換行  " }),
    ` (replying to: "多 空白 換行")`,
  );
  assertEquals(
    buildQuotedReplyPrefix({ quotedReplyPreview: `她說"超好笑"` }),
    ` (replying to: "她說'超好笑'")`,
  );
});
