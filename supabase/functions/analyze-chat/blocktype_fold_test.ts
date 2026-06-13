// blocktype_fold 單元測試（bake-off arm-2）
// 跑法：deno test supabase/functions/analyze-chat/blocktype_fold_test.ts
//
// 鏡射 docs/plans/2026-06-13-ocr-blocktype-schema-design.md 的 Failure matrix：
//   must-fold：單行漢字引用卡 → 折進 owner、live list 零鬼。
//   must-NOT：①首訊息 ②正常連發同側 ③真訊像引用卡 ④orphan 不硬塞對側。

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type BlockType,
  type FoldableMessage,
  foldQuotedPreviewBlocks,
  normalizeBlockType,
} from "./blocktype_fold.ts";

function msg(
  side: "left" | "right",
  content: string,
  blockType: BlockType,
): FoldableMessage {
  return { side, isFromMe: side === "right", content, blockType };
}

// ── normalizeBlockType ──────────────────────────────────────────────

Deno.test("normalizeBlockType: 解析 quoted_preview", () => {
  assertEquals(
    normalizeBlockType({ blockType: "quoted_preview" }),
    "quoted_preview",
  );
});

Deno.test("normalizeBlockType: 解析 message", () => {
  assertEquals(normalizeBlockType({ blockType: "message" }), "message");
});

Deno.test("normalizeBlockType: 大小寫/空白不敏感", () => {
  assertEquals(
    normalizeBlockType({ blockType: "  Quoted_Preview " }),
    "quoted_preview",
  );
});

Deno.test("normalizeBlockType: 缺省 → undefined（向後相容）", () => {
  assertEquals(normalizeBlockType({}), undefined);
});

Deno.test("normalizeBlockType: 無法辨識 → undefined（不無聲吞）", () => {
  assertEquals(normalizeBlockType({ blockType: "activity_card" }), undefined);
  assertEquals(normalizeBlockType({ blockType: 42 }), undefined);
});

// ── must-fold ───────────────────────────────────────────────────────

Deno.test("must-fold: 單張引用卡折進下一個同側 message", () => {
  const input: FoldableMessage[] = [
    msg("left", "這小孩也太刺激", "quoted_preview"),
    msg("left", "哈哈哈對啊", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 1);
  assertEquals(r.messages[0].content, "哈哈哈對啊");
  assertEquals(r.messages[0].quotedReplyPreview, "這小孩也太刺激");
  // quotedReplyPreviewIsFromMe = 本卡自己側別（left → false）。
  assertEquals(r.messages[0].quotedReplyPreviewIsFromMe, false);
  assertEquals(r.foldedCount, 1);
  assertEquals(r.droppedOrphanCount, 0);
  assertEquals(r.hadBlockType, true);
});

Deno.test("must-fold: S__5513242 兩張卡各自折進各自 owner、live list 零鬼", () => {
  const input: FoldableMessage[] = [
    msg("left", "這小孩也太刺激", "quoted_preview"),
    msg("left", "笑死", "message"),
    msg("left", "北鼻我睏睏想躺一下", "quoted_preview"),
    msg("left", "快去睡", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.map((m) => m.content), ["笑死", "快去睡"]);
  assertEquals(r.messages[0].quotedReplyPreview, "這小孩也太刺激");
  assertEquals(r.messages[1].quotedReplyPreview, "北鼻我睏睏想躺一下");
  assertEquals(r.foldedCount, 2);
  assertEquals(r.droppedOrphanCount, 0);
  // live list 零 quoted_preview 殘留。
  assertEquals(
    r.messages.some((m) => m.blockType === "quoted_preview"),
    false,
  );
});

Deno.test("must-fold: 右側卡折進右側 owner，quotedReplyPreviewIsFromMe=true", () => {
  const input: FoldableMessage[] = [
    msg("right", "你昨天說的那家店", "quoted_preview"),
    msg("right", "對就是那家", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 1);
  assertEquals(r.messages[0].quotedReplyPreviewIsFromMe, true);
});

Deno.test("連續兩張卡共一 owner：各自折入、取較長者", () => {
  const input: FoldableMessage[] = [
    msg("left", "短", "quoted_preview"),
    msg("left", "這是比較長的引用內容", "quoted_preview"),
    msg("left", "收到", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 1);
  assertEquals(r.messages[0].quotedReplyPreview, "這是比較長的引用內容");
  assertEquals(r.foldedCount, 2);
});

// ── must-NOT ────────────────────────────────────────────────────────

Deno.test("must-NOT ①: 首訊息（message）永不被折掉", () => {
  const input: FoldableMessage[] = [
    msg("left", "嗨在嗎", "message"),
    msg("left", "在喔", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.map((m) => m.content), ["嗨在嗎", "在喔"]);
  assertEquals(r.foldedCount, 0);
  assertEquals(r.droppedOrphanCount, 0);
});

Deno.test("must-NOT ②: 正常連發同側 message 不被動", () => {
  const input: FoldableMessage[] = [
    msg("left", "到家了", "message"),
    msg("left", "正要吃飯", "message"),
    msg("left", "抱抱", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 3);
  assertEquals(r.foldedCount, 0);
});

Deno.test("must-NOT ③: 真訊息剛好像引用卡（標 message）不被折", () => {
  // 短句、像引用卡，但 vision 標 message → 確定性信任標型，不折。
  const input: FoldableMessage[] = [
    msg("left", "你說的對", "message"),
    msg("left", "嗯嗯", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 2);
  assertEquals(r.messages[0].content, "你說的對");
  assertEquals(r.foldedCount, 0);
});

Deno.test("must-NOT ④: orphan 卡下一則不同側 → 丟棄而非硬塞對側", () => {
  const input: FoldableMessage[] = [
    msg("left", "你之前提的事", "quoted_preview"),
    msg("right", "嗯我記得", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  // 卡被丟棄，右側 message 不得被污染。
  assertEquals(r.messages.length, 1);
  assertEquals(r.messages[0].content, "嗯我記得");
  assertEquals(r.messages[0].quotedReplyPreview, undefined);
  assertEquals(r.foldedCount, 0);
  assertEquals(r.droppedOrphanCount, 1);
});

Deno.test("orphan: 後面無同側 message → 整個丟棄", () => {
  const input: FoldableMessage[] = [
    msg("left", "在嗎", "message"),
    msg("left", "孤兒引用卡", "quoted_preview"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.map((m) => m.content), ["在嗎"]);
  assertEquals(r.droppedOrphanCount, 1);
  assertEquals(r.foldedCount, 0);
});

// ── 向後相容 / 缺省 ─────────────────────────────────────────────────

Deno.test("缺省 blockType（undefined）一律當 message，不折、hadBlockType=false", () => {
  const input: FoldableMessage[] = [
    { side: "left", isFromMe: false, content: "嗨" },
    { side: "left", isFromMe: false, content: "在嗎" },
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 2);
  assertEquals(r.hadBlockType, false);
  assertEquals(r.foldedCount, 0);
});

// ── B-prime double-fold guard ───────────────────────────────────────
// B-prime：fold 後一律再跑 legacy strip。前提＝fold 輸出永不殘留 quoted_preview
// row，否則 legacy strip 會二次處理同一張卡（double-fold）。下面鎖死此不變式。

Deno.test("double-fold guard：fold 輸出零 quoted_preview 殘留（含折入＋丟孤兒）", () => {
  const input: FoldableMessage[] = [
    msg("left", "折得進的卡", "quoted_preview"),
    msg("left", "主訊", "message"),
    msg("left", "尾端孤兒卡", "quoted_preview"), // 無後續 owner → 丟棄
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(
    r.messages.every((m) => m.blockType !== "quoted_preview"),
    true,
  );
});

Deno.test("B-prime regression：模型有 blockType 意識但漏標卡（qpTagged=0）→ fold 原樣放行交給 legacy", () => {
  // 鏡射 S__5513242：模型把引用卡誤標成 message。fold 不得吞它，原樣傳下游讓
  // legacy strip 安全網接手（hadBlockType=true 不再關掉 legacy）。
  const input: FoldableMessage[] = [
    msg("left", "這小孩也太刺激", "message"), // 真引用卡被誤標 message
    msg("left", "哈哈哈對啊", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.messages.length, 2); // fold 是 no-op，一則都沒少
  assertEquals(r.hadBlockType, true);
  assertEquals(r.foldedCount, 0);
  assertEquals(r.droppedOrphanCount, 0);
});

Deno.test("blockTypeCounts 統計正確", () => {
  const input: FoldableMessage[] = [
    msg("left", "卡", "quoted_preview"),
    msg("left", "主訊", "message"),
    msg("left", "另一則", "message"),
  ];
  const r = foldQuotedPreviewBlocks(input);

  assertEquals(r.blockTypeCounts, { message: 2, quoted_preview: 1 });
});
