# OCR ③ 鬼訊息 strip-gap 修復設計（2026-06-13）

> 高風險區（OCR / analyze-chat prod code）。本檔為動碼前的 invariants ＋ failure matrix 契約。
> 狀態：設計定稿（Eric 拍板 A／下刀位置／N=5／failure matrix）。**尚未實作**，下一 session 進 TDD。

## 問題（CONFIRMED REAL）

S__5513242 prod raw 親驗：OCR 把兩張引用卡（`這小孩也太刺激`／`北鼻我睏睏想躺一下`）吐成**獨立 live 訊息**，真 owner 訊息 `quotedReplyPreview` 欄空，`stripQuotedReplyPreviewMessages`（`supabase/functions/analyze-chat/index.ts:3267`）完全沒攔（telemetry `quotedPreviewRemovedCount=0`）⟹ analyze-chat 收 5 則含 2 鬼（舊引用脈絡被當她剛丟的新球）＝真 dogfood 污染 bug。

## 根因（精確）

單行純漢字預覽列**兩條 strip 路徑都漏**：

- **Explicit path**（`isLikelyQuotedReplyPreviewContent`, line 3219）：要求 `lines.length >= 2`（名稱列＋內文列卡片結構）。單行鬼只有 1 行 → false。
- **Body-only path**（`isLikelyBodyOnlyQuotedReplyPreviewCandidate`, line 3252-3257）：`這小孩也太刺激` 全漢字無空格 → `isLikelyQuotedReplyPreviewNameLine` 判 true（誤當聯絡人名）→ 提早 return false。

## 修法（A：收緊判別，局部化下刀）

**關鍵精修**：`isLikelyQuotedReplyPreviewNameLine` 被兩條路徑**反向使用**——
- explicit path 要它對名稱回 true（含長暱稱）；
- body-only path 用它當排除條件。

∴ **絕不全域收緊** `isLikelyQuotedReplyPreviewNameLine`（會傷 explicit path 的長暱稱卡辨識）。
改為**只在 body-only 候選裡**把排除條件改成：

```
line[0] 是 name-line 但「看起來是句子不是名字」→ 不排除（視為鬼候選）
```

「看起來是句子」訊號＝**單一連續漢字 run（無空格、無拉丁字）長度 ≥ 5**（N=5，可調參數，靠測試釘死）。
理由：繁中聯絡人名/暱稱在預覽**內文位置**極少 5+ 連續漢字。`這小孩也太刺激`(7)、`北鼻我睏睏想躺一下`(8) 通過；`早安`(2)、`謝謝你`(3) 仍受保護。

## Invariants（strip 永不違反）

1. **首訊息永不被 strip**：body-only 維持 `!!previous`，本修不放寬。
2. **explicit path 行為零改動**：不動共用 `isLikelyQuotedReplyPreviewNameLine`。
3. **strip 只搬不丟**：鬼文字經 `extractQuotedReplyPreviewContent` 掛到 next 的 `quotedReplyPreview` 欄（既有邏輯不改）。
4. **side 連續性 guard 不放寬**：`current.side===next.side || unknown` 維持。

## Failure Matrix

| 案例 | 形狀 | 期望 | 守門機制 |
|------|------|------|---------|
| **must-strip** S__5513242 | 單行純漢字鬼在側翻後、next 是短 reply target | strip→掛 preview | 新 ≥5 Han = 非名 |
| must-NOT ① 真首訊息像名 | 首位短漢字、無 previous | 保留 | `!!previous` |
| must-NOT ② 真連發 | 兩則實質訊息連續同側、next 非短 reply target | 保留 | `isLikelyShortReplyTargetContent(next)` |
| must-NOT ③ 真短名預覽 | line[0] 真是 2-4 字聯絡人名 | 既有行為不變 | <5 Han 仍判名 |
| must-NOT ④ 中段短漢字真訊 | 5+ 漢字真訊但 next 非短 target／無側翻 | 保留 | previous 側翻＋next short target 雙 guard |

**剩餘暴露面（如實揭露）**：must-NOT ④ 若某真訊息剛好 5+ 漢字、前有側翻、next 又是媒體/短續——會被誤 strip。N=5 與 body-only guard 的病態巧合無法 100% 排除；靠負向測試釘典型真連發，Codex 雙審盯此點。

## 實作步驟（下一 session，TDD 紅→綠）

1. **Export for test**：`stripQuotedReplyPreviewMessages`（或 helper）目前未 export、無專測，需先 export。
2. **紅燈先行**：鏡射 S__5513242 must-strip 形狀回歸測試 ＋ must-NOT ①〜④ 負向測試。
   - must-strip 精確 5-message 序列（含 sides）需自 prod raw 確認／或依本檔結構描述重建。
3. **最小修** `isLikelyBodyOnlyQuotedReplyPreviewCandidate`：≥5 連續漢字 run 視為句子非名。
4. `deno test` ＋ `deno check` 綠。本機 only。
5. **重跑測試集**（Eric 要的最終回報）：fix 後對 dark/quoted 多輪跑分，回報 `quotedPreviewLeakTotal`→0、side/recall/exactText/quotePreviewAccuracy before vs after。
6. **Codex 雙審**（高風險 gate）→ APPROVED。
7. **僅在 APPROVED ＋ Eric 確認後** push/deploy（auto-deploy aware；幾何閘 9f74885 已於 2026-06-13 上 prod，本案 push 只帶鬼訊息修法本身）。

## 絕不

- 絕不未經 Codex APPROVED＋Eric 確認就 push（OCR/analyze-chat prod 高風險區，push 即 auto-deploy 進 prod）。
- 絕不放寬 `!!previous`（首訊息保護）。
- 絕不全域改 `isLikelyQuotedReplyPreviewNameLine`（傷 explicit path）。
