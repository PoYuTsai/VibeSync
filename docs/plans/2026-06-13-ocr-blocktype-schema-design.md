# OCR ②blockType Schema 設計（bake-off arm-2）

> 案：`ocr_ghost_bakeoff`。日期 2026-06-13。狀態：**設計定稿，未實作**（下一 session 進 TDD＋Codex 雙審）。
> 前置決策：bake-off scope=**(A) 先只做 blockType 一根**，跑 baseline vs blockType 兩臂；暗色預處理那根延後（早期訊號 exactText 95%+ → 瓶頸在契約而非可讀性）。
> 高風險區：`analyze-chat` vision schema＋prompt＋parser。**bake-off 期間絕不 push**（push 會 auto-deploy 進 prod）。

## 問題（一句話）

vision prompt 已重度指示模型「把引用卡塞 `quotedReplyPreview`、別吐成獨立 row」，但單行純漢字引用卡照樣被當 live message 吐出（`quotedPreviewRemovedCount=0`，S__5513242 親驗）。根因＝**要模型自己做「合併/省略」這個認知任務，它一直失敗**。

## 核心翻轉

把「合併」從模型手上拿掉，交給確定性的碼：

- 模型只做**忠實分類**：每個視覺區塊吐成一個 row，帶 `blockType`。
- 極簡 taxonomy：`message` / `quoted_preview`（活動卡先不碰＝YAGNI）。
- 引用卡 → 吐成 `quoted_preview` row（不再叫模型省略）。
- **parser 確定性折疊** `quoted_preview` → 前/後 message 的 `quotedReplyPreview`，並從 live list 移除。

## Schema 改動

- Vision 輸出 JSON 每 row 加 `blockType: "message" | "quoted_preview"`（缺省 = `message`，向後相容）。
- TS interface（`index.ts:636/646` 區）對應加欄。
- 既有 `quotedReplyPreview` / `quotedReplyPreviewIsFromMe` / `outerColumn` / `horizontalPosition` / `side` / `isFromMe` 全保留不動。

## Prompt 手術

- 把現有「don't emit a separate row / only keep the larger main reply」整段指令**翻轉**為「每個視覺區塊都吐成 row 並標 `blockType`；引用卡標 `quoted_preview`」。
- 範例（`:1040/:1060` 區）改成展示 `quoted_preview` row 後接 owner `message` row。
- 保留「Preserve visible names exactly／不猜不正規化漢字」「layout beats semantics（側別）」這些**與 blockType 無關**的既有鐵律。

## Parser 折疊規則（心臟）

新確定性函式，**先於舊 strip 跑**：

1. **向後折**：每個 `quoted_preview` row → 折進**下一個同側的 `message` row**：設該 message 的 `quotedReplyPreview` = 本 row 文字、`quotedReplyPreviewIsFromMe` = 本 row 自己側別；移除本 row。
2. **(i) 無主**（後面無同側 message）→ **整個丟棄**（脈絡非 live 球，留則成鬼）。
3. **(ii) 下一則不同側** → **丟棄而非硬塞**（守 must-NOT，寧漏脈絡不污染 live list）。
4. **(iii) 連續多張** → 各自獨立向後找主人，找不到各自丟棄。

## 共存

- 舊 `stripQuotedReplyPreviewMessages`（:3267）＋`isLikelyQuotedReplyPreviewNameLine` **降級為 fallback**：只處理**沒帶 blockType 或折疊後仍殘留**的 row，避免雙重折疊。
- 幾何閘（`9f74885`，已上 prod）**零改動**＝維持 parser-only scope。

## Invariants（不可破）

1. 首訊息永不被當引用 strip（`!!previous` 不放寬）。
2. 幾何閘零改動。
3. strip/折疊**只搬不丟正常 message**（只有 orphan `quoted_preview` 才丟）。
4. side 連續 guard 不放寬。
5. blockType 缺省＝`message`（漏標時退回舊行為，不無聲吞訊息）。

## Failure matrix（負向測試靶）

- **must-fold**：S__5513242 兩張單行漢字引用卡（`這小孩也太刺激`/`北鼻我睏睏想躺一下`）→ 折進 owner、live list 零鬼、`quotedPreviewLeakTotal=0`。
- **must-NOT**：①首訊息 ②正常連發同側 message ③真訊剛好像引用卡的短句 ④orphan 不硬塞對側——皆不得被折/丟。

## 量測（bake-off arm-2）

- 新 telemetry：`blockTypeCounts` / `foldedCount` / `droppedOrphanCount`。
- arm-2 build 完，baseline vs blockType **同 session 連跑多輪**（控 side variance，尤其 S__5513243）。
- before/after 報：`quotedPreviewLeakTotal`（目標→0）、side acc、recall、exactText、quotePreviewAccuracy。
- labels 仍 DRAFT、單輪 variance 大 → 只取方向性，多輪聚合。

## 流程閘

TDD 紅→綠（export helper→鏡射 must-fold＋must-NOT 負測→最小實作→`deno test`/`deno check` 綠）→ 多輪跑分 before/after → **Codex 雙審 APPROVED＋Eric 確認後才考慮 push**。bake-off 階段只在本機 serve 跑，**絕不 push**。

## 暴露面（如實揭露）

- Prompt 翻轉動到重度調校過的區段，可能回歸目前已正確的 only_left 等案——**baseline vs blockType 對照正是為了抓這個**。
- 折疊「(ii) 不同側一律丟棄」在罕見「真引用卡＋owner 剛好被幾何救援翻側」時會誤丟脈絡（非污染、可接受），靠負測＋Codex 盯。
