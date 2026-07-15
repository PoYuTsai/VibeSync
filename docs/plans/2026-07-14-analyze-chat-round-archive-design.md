# analyze-chat 分輪封存重設計（需求定案 v2 — 純顯示層）

> **SUPERSEDED — 2026-07-15。** Sam／Bruce 回饋與 Eric 後續拍板已改成「獨立分析紀錄」；現行規格見 `2026-07-15-analyze-chat-independent-records-implementation.md`。本文提到的單一對話分輪、FIFO 等內容不得實作。

- 日期：2026-07-14
- 狀態：需求 LOCKED（砍薄定案）→ writing-plans 已出 plan
- 參與：Eric（產品）、Bruce（夥伴，關鍵校正）、Claude（Opus，主討論）
- 交接對象：GLM 分頁實作
- 現況地圖：`docs/plans/2026-07-14-analyze-chat-round-archive-current-state.md`（附行號，仍有效）

---

## 一句話

**唯一問題是「疊加」。** 主畫面對話筐只顯示「最新上傳的那一輪」，舊輪次收進右上角封存盒。**分析方式、模型輸入、計費，一個 byte 都不動。** 這是純顯示層 + 一個輕量本地封存盒。

## 背景與痛點

analyze-chat 讓用戶把與某對象的對話截圖 OCR 後做 AI 分析。分析完可按「補聊天紀錄」接新片段重新分析。

現況唯一痛點：
- **越拉越長（疊加）**：每補一輪，新內容疊在頁面最底，舊輪次仍佔頂端；用戶要「展開全部 X 則訊息」再往下拉一大段才看得到剛補的最新一輪。最新的東西被埋在最下面（元兇：`analysis_screen.dart:5560-5618`，`:5590` 那個「展開全部 X 則」）。

（原本一度把 CTA 難找、模型被歷史逐字稿搞亂等也列為問題並想重架構——**已推翻**。夥伴校正：就只有疊加有問題。其餘照舊。）

---

## 需求定案（砍薄版）

### 核心模型
1. **主畫面 = 只顯示「當前這一輪」**：這一輪的逐字稿片段 ＋ 這一輪的建議，自成一塊，落地即見，不用捲。
2. **舊輪次封存**到右上角盒子（mailbox）。**一次分析 = 一張卡**，卡是自足的（存當輪片段＋當輪建議快照）。
3. **歸檔時機**：每次「補聊天紀錄」分析出新一輪 → 舊的當前輪自動滑進盒子。
4. **範圍**：以**單次對話（conversationId）為單位**，每個對話最多保留 **5 張卡**，FIFO（第 6 張進來擠掉最舊）。

### 明確不動（「其餘一切照舊」）
- **模型輸入不動**：`_runAnalysis` 送給模型的 `sourceMessages` 維持現狀（現在送什麼就送什麼）。
- **計費不動**：charCount baseline / 扣費口徑一律照舊。
- **分析 prompt / partnerSummary 注入不動**：耐久資料管線（特質/熱度/興趣/備註）已在且不依賴當輪逐字稿，原樣保留。
- **熱度/特質 aggregate 讀 conversation 級 `lastAnalysisSnapshotJson`**——只改顯示、絕不誤觸回寫。

### 封存卡內容
- 一張卡 = 「當輪 OCR 逐字稿片段」＋「那輪的 AI 建議快照」＋ createdAt。點進去看得到「當時她說了什麼 ＋ AI 當時怎麼建議」，唯讀。
- 卡自足（複製當輪內容進封存），不靠事後從 `messages` derive——來源對話被刪也不破圖。

### 建議顯示
- 主畫面只釘最新一輪的建議，重新分析時原地更新、不往下疊（現況狀態層已是單值覆寫，見 current-state Q5，幾乎零改動）。
- 封存卡各自保留自己當時的建議（隨卡一起存）。

---

## 明確不做（YAGNI）
- **不**改模型輸入 / 計費 / prompt（本案不碰高風險 AI 行為）。
- **不**新增 Hive typeId adapter（否決「重蓋型別結構」）；封存走既有 `settingsBox` 動態 Map 先例（`HiveConversationArchiveStore` 同款）。
- **不**把跨輪逐字稿拼成連續 scroll。
- **不**做無上限保留（硬上限 5 張 / 對話）。

---

## 資料模型（技術定案）

- **邊界**：當輪起點 = 該輪分析**開跑前**的 `lastAnalyzedMessageCount`（conversation.dart:58-59）。主畫面渲染 `messages[起點 .. 結尾]`。
- **儲存層**：Hive `settingsBox` 動態 `Map<String,String>`，key = `conversationId`，value = JSON（`List<卡>`，FIFO 裁 5）。比照 `conversation_archive_store.dart:64-153`，owner-scoped、fail-open、免 build_runner。
- **歸檔 hook**：分析完成時，把「上一個當前輪（片段＋建議快照）」封成一張卡 push 進盒，再更新邊界。server 端無狀態、**不需 migration**。

## 風險與雙審
- 本案**不碰** AI prompt / token / cost（模型輸入不動）→ 原「必 Codex 雙審」觸發**解除**。仍屬 analyze-chat UI，**輕量自審 + 端到端回歸**即可宣稱 dogfood safe。
- 唯一資料風險：封存寫入 / FIFO / 邊界計算的正確性 → 以 TDD 覆蓋（plan Phase A/B）。

## 待 Eric 可否決
- **範圍**：目前定 conversationId（綁單次對話，開新對話不帶過去）。若要改「綁對象（partnerId）、開新對話保留該對象歷史」→ 改 key = partnerId + legacy null fallback，工程量略增（current-state Q4）。
- **保留張數**：5 / 對話。

## 下一步
1. 依本定案跑 `superpowers:writing-plans`（已出：`2026-07-14-analyze-chat-round-archive-plan.md`）。
2. 計畫檔交 GLM 分頁實作 ＋ 跑測試。
3. 輕量自審 ＋ 端到端回歸（非高風險，免 Codex 雙審）。
