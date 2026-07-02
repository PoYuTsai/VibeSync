// supabase/functions/analyze-chat/screenshot_ocr_rules_test.ts
// 單側 side 判別 meta 錨點（已讀/時間戳/邊欄頭像）prompt 規則測試。
// 黑箱 A/B/C 驗證（2026-07，18 張、baseline pattern 55.6% → C 臂 88.9%、
// 單側逐泡 76.8%→84.3%、雙側零回退）後落地；C 臂配方 = meta 錨點段
// ＋引用卡頭像堵漏＋metaSide/isFromMe 一致性強制＋證據欄位。

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isReadReceiptSideDecisive,
  META_ANCHOR_SCHEMA_NOTE,
  SCREENSHOT_OCR_ACCURACY_RULES,
  SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS,
} from "./screenshot_ocr_rules.ts";

// ── baseline 版：full-analysis 路徑沿用，必須維持現狀 ──

Deno.test("baseline rules 保留原 ignore 行（read receipts/timestamps 仍整行忽略）", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES.includes(
      '- Ignore LINE announcement banners, pinned-message jump banners, date separators, read receipts, timestamps, "回到最新訊息" style system hints, and other non-message UI. Do not turn them into chat messages.',
    ),
  );
});

Deno.test("baseline rules 保留原 outer-column 行（avatar/no-avatar 差異仍忽略）", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES.includes(
      "- The outer bubble column is the source of truth across chat apps. Ignore quoted preview cards, inner screenshots, photo/video thumbnails, and avatar/no-avatar differences when deciding left vs right.",
    ),
  );
});

Deno.test("baseline rules 不含 meta 錨點段（full-analysis 路徑輸出形狀不變）", () => {
  assertFalse(SCREENSHOT_OCR_ACCURACY_RULES.includes("MANDATORY META ANCHORS"));
  assertFalse(SCREENSHOT_OCR_ACCURACY_RULES.includes("metaSide"));
  assertFalse(SCREENSHOT_OCR_ACCURACY_RULES.includes("readReceipt"));
});

Deno.test("baseline rules 首尾行不變（layout-first 開頭、contactName 收尾）", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES.startsWith(
      "### MANDATORY FIRST STEP: Visual Layout Analysis",
    ),
  );
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES.endsWith(
      "- If the contact name is unclear, return `contactName: null`.",
    ),
  );
});

// ── meta-anchors 版：recognize-only 路徑專用（黑箱 C 臂配方）──

Deno.test("meta rules 含 MANDATORY META ANCHORS 段且緊接在 layout 首段之後", () => {
  const anchorAt = SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.indexOf(
    "### MANDATORY META ANCHORS (strongest side evidence — trust these over your own position estimate)",
  );
  const outerBubbleSectionAt = SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS
    .indexOf("### CRITICAL: What Counts as an 'Outer Bubble'");
  assert(anchorAt >= 0, "缺 MANDATORY META ANCHORS 段");
  assert(outerBubbleSectionAt >= 0, "缺原有 Outer Bubble 段（結構被改壞）");
  assert(
    anchorAt < outerBubbleSectionAt,
    "meta 錨點段必須插在 MANDATORY FIRST STEP 之後、Outer Bubble 段之前（同黑箱驗證版位）",
  );
});

Deno.test("meta rules 含已讀=我方的決定性規則", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      '- Read receipts ("已讀" / "Read" / "既読") appear ONLY beside messages that I sent. Any bubble with a read receipt beside it MUST be isFromMe: true — regardless of bubble color, theme, or your position estimate.',
    ),
  );
});

Deno.test("meta rules 含邊欄頭像=對方的錨點規則", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- A small circular profile photo (avatar) in the margin directly beside an outer bubble (NOT inside a quoted card) appears ONLY for the other person's messages.",
    ),
  );
});

Deno.test("meta rules 含衝突時錨點勝出規則", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- If your midline position estimate conflicts with these anchors, THE ANCHORS WIN. Re-examine the layout and correct the side.",
    ),
  );
});

Deno.test("meta rules 要求逐列回報三個證據欄位", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      '- For every message row, also report three evidence fields: "metaSide": "left" | "right" | "none" (which side of that bubble its timestamp/read-receipt sits on), "readReceipt": true | false, "avatarBeside": true | false.',
    ),
  );
});

Deno.test("meta rules 含引用卡內頭像堵漏（C 臂修 B 臂洩漏的關鍵行）", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- CRITICAL avatar scope: a margin avatar is a small circular photo OUTSIDE the bubble, hugging the far LEFT edge of the screen (x < 10%). An avatar rendered INSIDE a bubble, inside a quoted-reply card, or inside an embedded screenshot is NOT a margin avatar — set avatarBeside: false for those rows.",
    ),
  );
});

Deno.test("meta rules 含 metaSide/isFromMe 一致性強制", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- CONSISTENCY CHECK before returning JSON: metaSide and isFromMe must agree on every row — metaSide 'left' requires isFromMe true; metaSide 'right' requires isFromMe false. If any drafted row violates this, the metaSide observation wins: fix isFromMe (and side/outerColumn) to match it.",
    ),
  );
});

Deno.test("meta rules 含同側連發共用錨點規則", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- Same-side runs share anchors: if a row has no meta text of its own, inherit the side of the nearest row above/below it whose anchors are clear, unless the layout clearly switches columns.",
    ),
  );
});

Deno.test("meta rules 的 ignore 行改寫：meta 不當訊息輸出、但必須當側別錨點", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      '- Ignore LINE announcement banners, pinned-message jump banners, date separators, "回到最新訊息" style system hints, and other non-message UI as chat content. Read receipts and timestamps are NOT messages either — never output them as message rows — but you MUST use them as side anchors (see MANDATORY META ANCHORS above).',
    ),
  );
  assertFalse(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- Ignore LINE announcement banners, pinned-message jump banners, date separators, read receipts, timestamps,",
    ),
    "舊 ignore 行（叫模型忽略 read receipts/timestamps）不得殘留在 meta 版",
  );
});

Deno.test("meta rules 的 outer-column 行改寫：margin meta/margin avatar 是有效錨點", () => {
  assert(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "- The outer bubble column is the source of truth across chat apps. Ignore quoted preview cards, inner screenshots, and photo/video thumbnails when deciding left vs right — but margin meta text (timestamps/read receipts) and margin avatars beside the outer bubble ARE valid side anchors.",
    ),
  );
  assertFalse(
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(
      "and avatar/no-avatar differences when deciding left vs right",
    ),
    "舊 outer-column 行（叫模型忽略 avatar 差異）不得殘留在 meta 版",
  );
});

Deno.test("meta 版與 baseline 版除了兩行改寫＋錨點段外共用同一份規則", () => {
  // 共同尾段抽查：兩版都必須含相同的後段規則（結構分裂會讓其中一版掉行）。
  for (
    const line of [
      "### CRITICAL: Header Name vs Message Sender",
      "### Screen Pattern Detection",
      "### Quoted Reply Handling (emit every block and tag it)",
      "- Before returning JSON, double-check that no clearly right-aligned bubble is labeled `isFromMe: false` and no clearly left-aligned bubble is labeled `isFromMe: true`.",
      "- If the contact name is unclear, return `contactName: null`.",
    ]
  ) {
    assert(
      SCREENSHOT_OCR_ACCURACY_RULES.includes(line),
      `baseline 缺: ${line}`,
    );
    assert(
      SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS.includes(line),
      `meta 版缺: ${line}`,
    );
  }
});

// ── schema note：只給 recognize-only prompt 用 ──

Deno.test("META_ANCHOR_SCHEMA_NOTE 要求每列附三個證據欄位", () => {
  assert(
    META_ANCHOR_SCHEMA_NOTE.includes(
      'EVERY message row MUST also include "metaSide" ("left" | "right" | "none"), "readReceipt" (true/false), and "avatarBeside" (true/false)',
    ),
  );
});

// ── readReceipt 確定性 guard helper ──

Deno.test("isReadReceiptSideDecisive：readReceipt === true 才決定性", () => {
  assertEquals(isReadReceiptSideDecisive({ readReceipt: true }), true);
});

Deno.test("isReadReceiptSideDecisive：false/缺欄/字串/1 都不觸發", () => {
  assertEquals(isReadReceiptSideDecisive({ readReceipt: false }), false);
  assertEquals(isReadReceiptSideDecisive({}), false);
  assertEquals(isReadReceiptSideDecisive({ readReceipt: "true" }), false);
  assertEquals(isReadReceiptSideDecisive({ readReceipt: 1 }), false);
  assertEquals(isReadReceiptSideDecisive({ metaSide: "left" }), false);
});

Deno.test("isReadReceiptSideDecisive：quoted_preview row 不觸發（引用卡上的已讀屬 owner 訊息，翻卡會讓 fold 丟孤兒）", () => {
  assertEquals(
    isReadReceiptSideDecisive({
      readReceipt: true,
      blockType: "quoted_preview",
    }),
    false,
  );
  // 大小寫/空白容錯要跟 normalizeBlockType 一致。
  assertEquals(
    isReadReceiptSideDecisive({
      readReceipt: true,
      blockType: " Quoted_Preview ",
    }),
    false,
  );
});

Deno.test("isReadReceiptSideDecisive：message/缺省 blockType 維持觸發（向後相容）", () => {
  assertEquals(
    isReadReceiptSideDecisive({ readReceipt: true, blockType: "message" }),
    true,
  );
  assertEquals(
    isReadReceiptSideDecisive({ readReceipt: true, blockType: "unknown-x" }),
    true,
  );
});
