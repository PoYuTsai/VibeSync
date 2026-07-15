# analyze-chat 獨立分析紀錄 — Codex 終審證據

- 日期：2026-07-15
- 分支：`docs/analyze-chat-round-archive`
- 程式 commit：`255803c0`
- 結論：APPROVED；沒有未解 P0／P1／P2

## 審查範圍

本輪針對 analyze-chat 的顯示邊界、本地加密持久化、刪除／合併生命週期、冷啟動修復與既有 AI／額度契約做高風險覆核。這是 client-only 改動；未修改 Edge Function 或資料庫。

## 不變條件

| 不變條件 | 終審結果 |
|---|---|
| 主畫面只顯示 current 或 pending；archive 只顯示較舊成功案例 | 通過 |
| AI request messages、prompt、schema、quota、billing 不變 | 通過 |
| owner key/body 雙重隔離，跨帳號資料不會被列出或清除 | 通過 |
| completion replay 必須同 key、同邊界、同 snapshot；片段以 validated current boundary 推進 | 通過 |
| conversation 主資料 commit 後仍完成 local cascade，cleanup marker 可恢復中斷清理 | 通過 |
| tombstone 阻擋刪除後抵達的 stale record/source write | 通過 |
| source 寫入序列化；明確清除不會被 repair 還原 | 通過 |
| partner `metVia` 正確跟隨 merge/delete，conversation delete 不會誤刪 | 通過 |

## 第一輪發現與修補

第一輪雙路審查為 `REVISE_REQUIRED`，主要發現：固定 completion key 可能誤判 replay、conversation 刪除的 partial failure 缺少明確 commit point、損壞 record 的 cascade 與 owner 邊界不足、canonical snapshot 成功但 record 失敗時冷啟動可能漏存，以及來源標記與 record persist 可能競寫。

修補後加入 owner-scoped v2 record key、cleanup marker recovery、損壞 value 依 key 清理、snapshot equality replay gate、冷啟動 record repair 與來源寫入序列化。

## 終審再加固

- `ConversationDeleteOutcome` 區分主資料是否已 commit；secondary cleanup 錯誤不會跳過本地 cascade。
- record tombstone 先於清理寫入，拒絕刪除後的 stale writers；若主對話仍有效，recovery 會撤銷 marker／tombstone。
- repair 持續失敗時硬性阻擋新分析，保留 canonical snapshot；畫面用 canonical 邊界顯示正確片段。
- fallback completion key 納入 snapshot SHA-256；相同訊息數但內容不同不會誤 replay。
- 使用 validated current `segmentEnd` 作唯一推進起點，過期 caller baseline 不會造成重疊或跳段。
- source 明確清除保存空值 sentinel；repair 不會復活舊標記。
- partner merge 採「目標有值優先，否則承接來源」，delete 會移除 metadata；即使下游 cascade 報錯，metadata lifecycle 仍完成。

## 審查結論

- 儲存終審：APPROVED，無 P0／P1／P2；額外 store／partner 測試 30/30。
- 流程終審：APPROVED，無 P0／P1／P2；額外 partner controller 測試 16/16。
- 最終 sanity check：APPROVE，無 P0／P1；確認 AI request、prompt、quota、billing 未改。

## 驗證

- `flutter analyze`：0 issue。
- 12 個相關 test files，共 148 項 unit／widget tests：全數通過。
- `git diff --check`：通過。

這是 targeted validation，不等同全專案完整回歸。新的 UI 與本地資料行為需要新的 TestFlight client build 做實機驗收；不需 Edge／DB deploy。
