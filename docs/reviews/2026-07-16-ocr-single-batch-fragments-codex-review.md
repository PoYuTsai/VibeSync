# OCR 單批獨立片段 Codex 終審

- 日期：2026-07-16
- 分支：`codex/ocr-single-batch-fragments`
- 基準：`origin/main` @ `f91ab68b`
- 結論：**APPROVED**，最終 diff 無未解決 P0／P1／P2

## 鎖定的產品契約

1. 一次選取 1–3 張截圖就是一次完整 OCR 批次。
2. 分析前重新選圖時，整批取代草稿，不逐則追加、不串成長逐字稿。
3. 片段完成分析後即唯讀；後續內容另建同一 Partner 下的新片段。
4. OCR 只用 canonical Partner 名稱做身分核對，不得以辨識名稱覆蓋 Partner 或自訂片段標題。
5. 舊版已疊加資料不猜測切割，但不得再顯示「分析新增內容」、逐則輸入或加入方式。

## 審查發現與修正

第一輪獨立審查發現兩項：

- P1：整批取代時若保留舊 `summaries`，新分析仍可能收到上一批摘要。已在 `replaceDraftBatch` 同步清除摘要並加回歸測試。
- P2：純 OCR request 若仍帶舊 messages，Edge prompt 會把即將丟棄的內容當 Existing Thread Context。已由 service 層強制 `recognizeOnly` 的 messages 為空，並用 transport test 鎖定 request body。

第二輪 race／可達性審查再確認：

- OCR 確認視窗開啟期間若原片段完成，送出時會重新讀最新 Conversation 並另建片段，舊完成紀錄不變。
- 新片段保留 `partnerId` 並使用 canonical Partner 名稱；Partner row 缺失時不會拿自訂片段標題冒充聯絡人名稱。
- 完成片段即使帶有舊版待分析尾巴，也不會重開或顯示追加入口。
- 錯誤 CTA 只會導向重新選圖或建立新片段，不會回到舊逐則輸入器。
- 舊 import mode API 與所有可達 UI 路徑均已移除。

最終獨立 reviewer verdict：**APPROVED**。

## 驗證矩陣

- `flutter test --no-pub`：7 個直接相關 unit/widget 檔，共 **111 tests 全通過**。
- `flutter analyze --no-pub`：**No issues found**。
- `git diff --check`：通過。
- 舊 import mode symbol 全域搜尋：0 筆。
- `pubspec.lock`、`.gstack/`、`AGENTS.md`、`CLAUDE.md`：未修改。

本次為 client-only Flutter 行為與本機資料邊界調整；沒有 Edge Function、DB migration、訂閱、額度或計費部署。
