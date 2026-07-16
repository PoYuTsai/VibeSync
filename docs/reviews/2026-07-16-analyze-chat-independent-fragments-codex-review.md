# analyze-chat 獨立分析片段 Codex 終審

> 後續契約修訂：本檔保留當時終審歷史；「第一次分析前可補同一批內容」已由 ADR #20 同日修訂取代。現行規則是一次選圖形成一批，重新選圖整批取代，分析頁不再逐則追加。

- 日期：2026-07-16
- 分支：`codex/independent-analysis-segments`
- 起始基準：`b09b6dd1`
- 結論：**APPROVED**，最新 diff 無剩餘 P0／P1／P2

## 產品不變量

> 真正使用者只會加入這次想給 AI 解析的新片段；不同時間、不同平台的內容通常不連貫，不能一路疊成逐字稿。

- 一次分析請求對應一個獨立 Conversation／fragment。
- 第一次分析前可補同一批內容；成功後立即關閉、唯讀並收進右上「分析紀錄」。
- 完成後的新截圖或手動訊息一律建立同 partner 的新 Conversation id。
- 平台只做使用者設定的 metadata／filter；未知來源留在「全部」，不顯示「未分類」。
- 舊版疊加資料不猜測切割，但有完成證據後不得再追加。

## 審查中發現並修正

- 刪除後的延遲寫入可能復活 record：加入 item tombstone、revision／boundary gate 與 cleanup recovery。
- 已完成聊天仍可編輯，會讓 frozen snapshot 與 canonical conversation 分歧：完成片段 UI 與 mutation path 全部唯讀。
- 付費回覆刷新可能在 canonical snapshot 已更新、archive 尚未更新時中斷：限定同邊界、同 revision 的 archived refresh，並由 cold repair 補中斷窗。
- 空白、舊 snapshot 損壞或只有部分完成證據時可能誤開輸入：以 durable completion evidence 統一判斷，完成邊界保持關閉。
- 完整獨立 record 與舊「已收起的對話」重複顯示：只對 owner、完整邊界、精確 revision、唯一 record 的 Conversation 去重；legacy multi／partial record 保守保留。
- 刪除單一片段會誤取消同 partner 最新的 48 小時提醒：刪除 commit 後只有該 partner 已無任何 Conversation 才取消，涵蓋刪舊片段、放棄空白新片段與一般 tile 刪除。

## 驗證證據

- `flutter analyze`：通過，0 issue。
- `git diff --check`：通過。
- 14 個相關測試檔、共 210 項 targeted tests：全部通過。
- 獨立終審：114 項 controller／policy／store／archive／partner tests 通過，無 P0／P1／P2。
- 全專案測試：2206 passed、4 skipped；4 個既有 baseline failures 與本案無關（onboarding 舊文案、safe-batch visual proof 測試環境、partner-list 舊精確文案、widget smoke 未注入 notification gateway）。
- `pubspec.lock`、`.gstack/`：未修改。

## 部署影響

本案為 client-only Flutter／local persistence 變更；需要重新 build TestFlight，不需要 Edge Function 或資料庫部署。
