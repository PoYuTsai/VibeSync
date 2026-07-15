# analyze-chat 獨立分析紀錄 — 實作與驗收紀錄

- 日期：2026-07-15
- 狀態：完成；Codex 儲存／流程雙路終審與最終 sanity check 均 APPROVED
- 決策者：Eric
- 回饋來源：Sam、Bruce

## 一句話

主畫面只保留「本次已分析片段」或「待分析的新片段」；完成下一次分析後，上一筆分析才移入右上角的「分析紀錄」。每筆紀錄自帶當時的聊天片段與 AI 建議快照，不拼成長逐字稿。

## 產品契約

1. 一次成功分析是一筆獨立案例；舊案例不會自動接成逐字稿，也不會再送回 AI。
2. 目前這一筆留在主畫面，不重複出現在分析紀錄；只有完成較新的片段後，前一筆才成為舊紀錄。
3. 同一個對象可跨 Omi、LINE、IG、Threads、Tinder、Bumble 或自訂平台；平台由使用者標記，OCR 不猜。
4. `認識平台（metVia）` 是對象層級資料；`分析來源（sourcePlatform）` 是每筆案例在分析完成當下的快照，兩者不可混用。
5. 不設 FIFO、不自動裁舊紀錄；只允許使用者手動刪除舊案例。刪除目前案例被拒絕。
6. 原有整段對話收起功能仍保留，使用者名稱改成「已收起的對話」，與「分析紀錄」清楚分流。
7. 本案只改 client 顯示與本地持久化；AI request messages、prompt、分析 schema、quota、計費與 Edge Function 全部不動。

## 狀態機

| 完成事件 | 結果 |
|---|---|
| 第一筆成功分析 | 建立 current；分析紀錄仍空 |
| 同一片段重新分析／同 completion replay | 覆寫或重放 current，不新增舊案例 |
| 有新訊息且成功完成較新分析 | 新結果成為 current，舊 current 進分析紀錄 |
| 分析途中又收到新訊息 | 本次只固定到開跑時的訊息邊界；新增訊息留在待分析片段 |
| 分析失敗／快照尚未 canonical persist | 不建立、不推進紀錄 |

## 資料與隱私

- 使用既有 AES-256 加密 `settingsBox`，不新增 Hive typeId。
- 每筆紀錄獨立一個 key：`analysis_record_v2:<ownerUserId>:<conversationId>:<recordId>`；conversation scope 直接進 key，value 即使損壞也能確實 cascade delete。
- 每個對話的 current pointer：`analysis_record_state_v1:<ownerUserId>:<conversationId>`。
- 對話來源：`analysis_conversation_source_v1:<ownerUserId>:<conversationId>`。
- 認識平台：`analysis_partner_met_via_v1:<ownerUserId>:<partnerId>`。
- 刪除復原 marker：`analysis_record_cleanup_v1:<ownerUserId>:<conversationId>`。
- 已刪除對話 tombstone：`analysis_record_deleted_v1:<ownerUserId>:<conversationId>`；先寫 tombstone 再清紀錄，阻擋刪除後才抵達的舊寫入把資料復活。
- 所有讀寫都要求 owner scope；紀錄內也保存 owner、conversation、partner 與內容 revision 供交叉驗證。
- 聊天訊息、引用預覽、熱度與 AI snapshot 都在成功當下 deep copy，避免原對話後續編輯讓舊案例變形。
- 刪除對話前先寫 cleanup marker；marker 寫失敗就不刪主對話。repository 以 `ConversationDeleteOutcome` 明確回報主資料是否已完成 commit；主對話刪除成功後即使 secondary cleanup 中斷，controller 仍完成本地 cascade，再把原錯誤交給 UI。marker 會在 write controller 重建時補清；若主對話仍存在則撤銷 marker／tombstone，不碰有效紀錄。
- 刪除對話時一併刪除該對話的 current、舊紀錄、state 與來源標記；對象層級 `metVia` 保留。登入失效或 owner 不符時拒絕 cascade。帳號清除仍沿用既有整個加密盒清除流程。
- 合併對象時，目標已設定的 `metVia` 優先；否則承接來源值並移除來源 key。刪除對象時移除其 `metVia`。即使對象主資料已 commit 後的下游 cascade 報錯，metadata 搬移／清除仍會完成，再回拋原錯誤。
- 讀取損壞或 box 尚未就緒時 fail-safe 為空；寫入錯誤不吞掉，讓呼叫端可重試或顯示失敗。
- canonical conversation snapshot 成功但獨立 record 暫時寫失敗時，冷啟動會用 snapshot 內的 message count／content revision 補建 current；補建持續失敗時禁止啟動新分析，避免覆寫尚未落地的 canonical 快照。主畫面仍以 canonical 邊界顯示正確片段，不退回過期 current。
- 紀錄寫入期間會立刻重建 pending counter，平台 pill 暫停寫入；使用者明確清除來源會保存空值 sentinel，repair 不會把舊平台復活。
- completion replay 除了 completion key 與邊界，還必須與訊息 snapshot 完全相同；fallback completion key 包含 snapshot SHA-256。推進片段時以已驗證 current 的 `segmentEnd` 為唯一邊界，不採用可能過期的 caller baseline。

## UI

- analyze-chat 右上角新增分析紀錄入口；原對象資料／匯出移入更多選單。
- 主畫面來源 pill 可設定這次片段的平台。
- 分析紀錄以對象聚合所有仍存在的對話，支援平台篩選、唯讀明細與單筆刪除。
- 明細顯示當時聊天片段、熱度／階段及保存當下的 AI 建議，不依賴現行 conversation 重新推導。
- 空狀態明講「目前這次留在主畫面，下一次完成後才會收進來」。

## 實作位置

- Model：`lib/features/analysis/domain/entities/analysis_record.dart`
- Store：`lib/features/analysis/data/repositories/analysis_record_store.dart`
- Providers：`lib/features/analysis/data/providers/analysis_record_providers.dart`
- 分析串接：`lib/features/analysis/presentation/screens/analysis_screen.dart`
- UI：`partner_analysis_records_screen.dart`、`analysis_record_detail_screen.dart`、`analysis_platform_picker.dart`
- 刪除 cascade：`lib/features/conversation/data/providers/conversation_write_controller.dart`
- 對象 metadata lifecycle：`lib/features/partner/data/providers/partner_write_controller.dart`

## 驗證與審查

- `flutter analyze`：全專案 0 issue。
- 148 項 targeted unit／widget tests：全數通過。涵蓋 owner 隔離、completion replay、current/archive 狀態、無 FIFO、損壞 value 刪除、cleanup marker／tombstone recovery、expired/mismatched owner、cold restore repair hard gate、平台重標／清除、對象 merge/delete metadata 與窄螢幕 UI。
- 第一輪雙路只讀審查：`REVISE_REQUIRED`，共修正 replay、刪除 partial failure／owner、損壞 record cascade、cold restore 漏存與來源標記競寫。
- 儲存終審：APPROVED，無 P0/P1/P2；加跑 store／partner 30/30。
- 流程終審：APPROVED，無 P0/P1/P2；加跑 partner controller 16/16。
- 最終 sanity check：APPROVE，無 P0/P1；確認 AI request、prompt、quota、billing 均未改動。
- 完整審查證據：`docs/reviews/2026-07-15-analyze-chat-independent-records-codex-review.md`。
- 本案為 client-only；不需 Edge／DB deploy，但要產出新的 TestFlight build 才能實機驗收。
