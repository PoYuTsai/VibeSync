// blockType 確定性折疊（bake-off arm-2）
//
// 核心翻轉：把「合併引用卡」從 vision 模型手上拿掉，交給確定性的碼。
// 模型只做忠實分類（每個視覺區塊一個 row，帶 blockType）；本模組把
// `quoted_preview` row 確定性折進它的主訊息，並從 live list 移除。
//
// 設計定稿：docs/plans/2026-06-13-ocr-blocktype-schema-design.md
//
// 與 index.ts 解耦成獨立模組，理由：index.ts 頂層有 `serve(...)`，直接 import
// 會啟動 HTTP server，無法單元測試。本模組純函式、零副作用、可 `deno test`。

export type BlockType = "message" | "quoted_preview";

// 結構型別：index.ts 的 NormalizedRecognizedMessage 為其超集（多 geometryDecisive
// 等欄）。fold 用泛型 <T extends FoldableMessage> 保留呼叫端的具體型別。
export interface FoldableMessage {
  side: "left" | "right" | "unknown";
  isFromMe: boolean;
  content: string;
  blockType?: BlockType;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
}

export interface BlockTypeCounts {
  message: number;
  quoted_preview: number;
}

export interface FoldResult<T extends FoldableMessage> {
  messages: T[];
  foldedCount: number;
  droppedOrphanCount: number;
  blockTypeCounts: BlockTypeCounts;
  // 任一 row 帶顯式 blockType → 模型具 blockType 意識，舊 strip 降為 fallback。
  hadBlockType: boolean;
}

// 解析 vision 輸出的 blockType 欄；缺省/無法辨識 → undefined（呼叫端視為 message）。
export function normalizeBlockType(
  record: Record<string, unknown>,
): BlockType | undefined {
  const raw = typeof record.blockType === "string"
    ? record.blockType.trim().toLowerCase()
    : "";
  if (raw === "quoted_preview") {
    return "quoted_preview";
  }
  if (raw === "message") {
    return "message";
  }
  return undefined;
}

// 確定性折疊：先於舊 strip 跑。規則（設計檔「Parser 折疊規則」）：
//   1. 向後折：每張 quoted_preview 卡折進「緊接其後的第一個 message row」，且該
//      message 必須與卡同側；設 message.quotedReplyPreview=卡文字、
//      quotedReplyPreviewIsFromMe=卡自己側別，移除卡。
//   2. (i) 後面無 message（孤兒在尾）→ 整個丟棄。
//   3. (ii) 緊接的下一則 message 不同側 → 丟棄而非硬塞（守 must-NOT）。
//   4. (iii) 連續多張 → 各自獨立向後找主人；共用同一 owner 時取較長者。
// 只搬/丟 quoted_preview，永不丟正常 message（invariant 3）。
export function foldQuotedPreviewBlocks<T extends FoldableMessage>(
  messages: T[],
): FoldResult<T> {
  const blockTypeCounts: BlockTypeCounts = { message: 0, quoted_preview: 0 };
  let hadBlockType = false;
  for (const message of messages) {
    if (message.blockType !== undefined) {
      hadBlockType = true;
    }
    if (message.blockType === "quoted_preview") {
      blockTypeCounts.quoted_preview += 1;
    } else {
      // 缺省 blockType 一律視為 message（向後相容，不無聲吞）。
      blockTypeCounts.message += 1;
    }
  }

  const out: T[] = [];
  // 等待主人的引用卡，依出現順序累積；遇到下一個 message row 時一次結算。
  let pendingCards: T[] = [];
  let foldedCount = 0;
  let droppedOrphanCount = 0;

  for (const message of messages) {
    const clone = { ...message };

    if (clone.blockType === "quoted_preview") {
      pendingCards.push(clone);
      continue;
    }

    for (const card of pendingCards) {
      const sameSide = card.side !== "unknown" && card.side === clone.side;
      if (!sameSide) {
        // (ii)/(iii) 下一則不同側 → 丟棄而非污染 live message。
        droppedOrphanCount += 1;
        continue;
      }
      const existing = clone.quotedReplyPreview?.trim() ?? "";
      const incoming = card.content.trim();
      // 共用 owner 時取較長者（與 index.ts choosePreferredQuotedReplyPreview 一致）。
      if (incoming.length > existing.length) {
        clone.quotedReplyPreview = incoming;
        clone.quotedReplyPreviewIsFromMe = card.isFromMe;
      }
      foldedCount += 1;
    }
    pendingCards = [];
    out.push(clone);
  }

  // (i) 結尾仍懸著的卡 → 無主人，整個丟棄。
  droppedOrphanCount += pendingCards.length;

  return {
    messages: out,
    foldedCount,
    droppedOrphanCount,
    blockTypeCounts,
    hadBlockType,
  };
}
