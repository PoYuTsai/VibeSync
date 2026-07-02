import {
  applyLayoutFirstParser,
  type LayoutFirstMessage,
} from "./layout_parser.ts";

function buildMessage(
  side: "left" | "right" | "unknown",
  content: string,
  options?: {
    quotedReplyPreview?: string;
    geometryDecisive?: boolean;
    metaDecisive?: boolean;
  },
): LayoutFirstMessage {
  return {
    side,
    isFromMe: side === "right",
    content,
    quotedReplyPreview: options?.quotedReplyPreview,
    geometryDecisive: options?.geometryDecisive,
    metaDecisive: options?.metaDecisive,
  };
}

Deno.test("fills an unknown run sandwiched by the same side", () => {
  const result = applyLayoutFirstParser([
    buildMessage("left", "第一句"),
    buildMessage("unknown", "看不太清楚"),
    buildMessage("left", "第三句"),
  ]);

  if (result.messages[1].side !== "left" || result.messages[1].isFromMe) {
    throw new Error("Expected the middle row to be repaired to left side");
  }
});

Deno.test("drops centered system rows before grouping speakers", () => {
  const result = applyLayoutFirstParser([
    buildMessage("left", "See you soon"),
    buildMessage("unknown", "Today"),
    buildMessage("right", "Sounds good"),
  ]);

  if (result.systemRowsRemovedCount !== 1) {
    throw new Error("Expected one centered system row to be removed");
  }

  if (result.messages.length !== 2) {
    throw new Error("Expected only actual chat bubbles to remain");
  }
});

Deno.test("keeps a quoted left-side tail on the same speaker run", () => {
  const result = applyLayoutFirstParser([
    buildMessage("left", "教小孩真不容易", {
      quotedReplyPreview: "你前面那句",
    }),
    buildMessage("left", "等等見", { quotedReplyPreview: "另一句舊訊息" }),
    buildMessage("right", "剛到永春～"),
  ]);

  if (result.messages[2].side !== "left" || result.messages[2].isFromMe) {
    throw new Error("Expected the trailing bubble to stay on the left run");
  }
});

Deno.test("repairs a media bridge between same-side messages", () => {
  const result = applyLayoutFirstParser([
    buildMessage("right", "1800"),
    buildMessage("left", "[Photo of a room interior with chairs]"),
    buildMessage("right", "陽台還很大"),
    buildMessage("left", "超爽"),
  ]);

  if (result.messages[1].side !== "right" || !result.messages[1].isFromMe) {
    throw new Error(
      "Expected the media placeholder to follow the right-side run",
    );
  }
});

Deno.test("never flips a geometry-decisive run against neighbors and dominant side", () => {
  // 5513245 級聯重現：明確 right（幾何決定性）被 dominant=left＋兩側 left 鄰居吞成 left。
  const result = applyLayoutFirstParser([
    buildMessage("left", "在嗎"),
    buildMessage("left", "今天好嗎"),
    buildMessage("right", "我很好", { geometryDecisive: true }),
    buildMessage("right", "妳呢", { geometryDecisive: true }),
    buildMessage("left", "我也不錯"),
    buildMessage("left", "在幹嘛"),
  ]);

  if (result.messages[2].side !== "right" || !result.messages[2].isFromMe) {
    throw new Error("Expected the first geometry-decisive bubble to stay right");
  }
  if (result.messages[3].side !== "right" || !result.messages[3].isFromMe) {
    throw new Error(
      "Expected the second geometry-decisive bubble to stay right",
    );
  }
});

Deno.test("never flips a meta-decisive bubble against neighbors and dominant side", () => {
  // 已讀鎖 invariant：readReceipt=true 的單顆 right 短句被 dominant=left＋
  // 兩側 left 鄰居包夾，也不得翻——與 geometryDecisive 同款鎖。
  const result = applyLayoutFirstParser([
    buildMessage("left", "在嗎"),
    buildMessage("left", "今天好嗎"),
    buildMessage("right", "好", { metaDecisive: true }),
    buildMessage("left", "我也不錯"),
    buildMessage("left", "在幹嘛"),
  ]);

  if (result.messages[2].side !== "right" || !result.messages[2].isFromMe) {
    throw new Error("Expected the meta-decisive bubble to stay right");
  }
});

Deno.test("still rescues a non-decisive run in the same shape", () => {
  // 同形狀但 right 來自字串 fallback（非幾何決定性）＝救援允許區，維持既有翻面行為。
  const result = applyLayoutFirstParser([
    buildMessage("left", "在嗎"),
    buildMessage("left", "今天好嗎"),
    buildMessage("right", "我很好"),
    buildMessage("right", "妳呢"),
    buildMessage("left", "我也不錯"),
    buildMessage("left", "在幹嘛"),
  ]);

  if (result.messages[2].side !== "left" || result.messages[2].isFromMe) {
    throw new Error("Expected the non-decisive bubble to be rescued to left");
  }
});

Deno.test("fills an unknown run between decisive anchors without moving them", () => {
  const result = applyLayoutFirstParser([
    buildMessage("right", "我先說", { geometryDecisive: true }),
    buildMessage("unknown", "看不太清楚"),
    buildMessage("right", "再補一句", { geometryDecisive: true }),
  ]);

  if (result.messages[0].side !== "right" || result.messages[2].side !== "right") {
    throw new Error("Expected the decisive anchors to stay right");
  }
  if (result.messages[1].side !== "right" || !result.messages[1].isFromMe) {
    throw new Error("Expected the unknown row to be filled to the right run");
  }
});

Deno.test("drops LINE zh-TW system rows (date/weekday/time/retraction)", () => {
  const result = applyLayoutFirstParser([
    buildMessage("left", "等等見"),
    buildMessage("unknown", "今天"),
    buildMessage("unknown", "星期三"),
    buildMessage("unknown", "下午1:03"),
    buildMessage("unknown", "已收回訊息"),
    buildMessage("right", "好啊"),
  ]);

  if (result.systemRowsRemovedCount !== 4) {
    throw new Error(
      `Expected four zh-TW system rows removed, got ${result.systemRowsRemovedCount}`,
    );
  }

  if (result.messages.length !== 2) {
    throw new Error("Expected only actual chat bubbles to remain");
  }
});

Deno.test("repairs a media bridge with zh-TW placeholders (照片/貼圖)", () => {
  const result = applyLayoutFirstParser([
    buildMessage("left", "今天上班超級忙的啦。"),
    buildMessage("right", "我剛剛去看了那個新房子喔。"),
    buildMessage("left", "[照片]"),
    buildMessage("left", "[貼圖]"),
    buildMessage("right", "陽台真的很大很好。"),
    buildMessage("right", "而且採光超級好的呢。"),
  ]);

  if (result.messages[2].side !== "right" || !result.messages[2].isFromMe) {
    throw new Error("Expected the zh photo placeholder to follow the right run");
  }
  if (result.messages[3].side !== "right" || !result.messages[3].isFromMe) {
    throw new Error("Expected the zh sticker placeholder to follow the right run");
  }
});
