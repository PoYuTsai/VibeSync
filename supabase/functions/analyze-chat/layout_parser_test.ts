import {
  applyLayoutFirstParser,
  type LayoutFirstMessage,
} from "./layout_parser.ts";

function buildMessage(
  side: "left" | "right" | "unknown",
  content: string,
  options?: {
    quotedReplyPreview?: string;
  },
): LayoutFirstMessage {
  return {
    side,
    isFromMe: side === "right",
    content,
    quotedReplyPreview: options?.quotedReplyPreview,
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
