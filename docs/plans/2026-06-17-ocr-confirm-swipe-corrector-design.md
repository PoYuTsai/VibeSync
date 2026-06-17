# OCR 確認頁改成滑動左右校正器 — 設計

> 日期：2026-06-17 · 狀態：DESIGN（待 TDD）
> 影響檔：`lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`
> 風險：高（`isFromMe` 直接餵 `analyze-chat` 匯入資料）。測試 + Codex review 通過前不得宣稱 dogfood-safe。

## 背景與定位

OCR side 自動判斷已收斂證偽（暗色 only-left 救不回、雙側 mixed 幻覺右泡與真右泡零獨立訊號）。
決議是「回 product-UX 一鍵兜底」。因此**確認頁就是那個 load-bearing 的手動安全網**。

現況 3.jpg 對新用戶不友善，根因是塞太多工程語言（依左/右重新套用、右側泡泡、方向穩定、
逐則確認、這幾則連在一起、信心 chip）。新用戶其實只需要回答一件事：**這句是她說還是我說。**

定位拆分：
- **確認頁 = 快速左右校正器**（滑動改邊，畫面像真聊天）
- **單則 Edit sheet = 進階內容編輯**（改錯字 / 刪除 / 引用唯讀顯示）

## 使用者流程

上傳截圖 → OCR → 確認頁（滑動校正左右）→ 確認加入對話 / 進分析。
要改錯字或看引用，才點泡泡開單則 Edit sheet。

## 設計 A：確認頁 = 滑動校正器

畫面（沿用現有 `_buildReadOnlyPreviewRow` 的左右泡泡排版，升級成可互動）：

- 左泡 = 她說；右泡 = 我說；圖片/貼圖用 placeholder 泡泡，一樣可滑。
- 頂部只留一行提示：**「判錯邊？左右滑動訊息即可切換。」**（取代現有整段說明）
- 底部保留大顆 **「全部都是對方說的」**（only-left 正式兜底，接現有 `_markAllAsOtherPerson`）
  + 「確認加入對話 / 稍後再加入」。

手勢（絕對方向映射）：

- 往**右**滑 → 一律 `isFromMe = true`（我說）。
- 往**左**滑 → 一律 `isFromMe = false`（她說）。
- 已在目標側再往該側滑 = no-op / 彈回。
- 門檻：水平位移超過 `bubbleWidth * 0.25` 或約 64px 才 commit；未過彈回。
  避免與 ListView 上下捲動誤觸（gesture arena 以主軸判定 + 距離門檻雙保險）。
- 拖曳時泡泡後方露出色塊提示「改成我說 / 改成她說」（仿 iOS swipe action）。
- commit 後泡泡用 `AnimatedAlign` 滑到正確側。

移除（從確認頁砍掉，不只是隱藏）：

- `_applySpeakerToKnownSides` + 「依左／右重新套用」按鈕與說明。
- 群組卡：`_shouldShowBatchCard` / `_applySpeakerToGroup` / `_contiguousSideIndexes` 的 UI。
- 「原本看起來在左/右邊」side label（`_sideLabel`）。
- `_showDetailedEditor` 全展開逐則列表分支、信心/側別 chip 那串。
- `_buildSpeakerChip` 在確認頁的她說/我說 chip（改由滑動取代）。

## 設計 B：單則 Edit sheet = 進階編輯

- **點**泡泡 → 開該則的 bottom sheet：
  - 文字編輯（複用現有 `message.controller` + TextField）。
  - 刪除這則（複用 `_confirmRemoveMessage`）。
  - 引用 preview **唯讀顯示**（第一版不做「引用是誰說的」編輯）。
- 一次只編一則，符合「大多數人只修 1–2 則」。**不**保留一次展開全部的逐則列表。

## 不做（YAGNI / 第一版範圍外）

- 引用歸屬（quotedReplyPreviewIsFromMe）編輯 → 唯讀。
- 拖拉換邊、標籤切換（Eric 已否決：拖拉太重、標籤畫面複雜）。
- 訊息重新排序。

## 測試計畫（TDD，widget test 為主）

1. 右滑超過門檻 → 該則 `isFromMe == true`、泡泡移到右側。
2. 左滑超過門檻 → 該則 `isFromMe == false`、泡泡移到左側。
3. 門檻內放開 → `isFromMe` 不變、彈回原側。
4. 「全部都是對方說的」→ 全部 `isFromMe == false`。
5. 點泡泡 → 開單則 Edit sheet；改文字後 `controller.text` 同步；刪除後該則消失。
6. 既有 `_submit` 驗證（至少保留一則非空）不被破壞。
7. 既有 byte-for-byte / 匯入資料相關測試全綠。

## 完成標準

- 上述 widget 測試全綠 + `flutter test` 全 suite 綠。
- Codex review 通過（高風險區）。
- Eric / Bruce 實機目檢有感後才 CLOSE。
