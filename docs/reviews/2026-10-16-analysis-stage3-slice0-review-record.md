# 審查紀錄：對話分析第 3 階段第 0 片「扣費紀錄可以記 v3 任務卡」

- 日期：2026-10-16
- 範圍：migration `supabase/migrations/20261016120000_analysis_stream_runs_card_task.sql` 與 PGlite 契約測試 `supabase/functions/analyze-chat/stream_runs_decision_kind_migration_postgres_test.ts`
- 風險等級：R3（正式資料庫、扣費）
- 撰寫：Claude（Anthropic）；主審：Codex（OpenAI，唯讀）；反向預審：獨立 Claude 子代理（唯讀，不是主審）

## 決定依據

- Eric 2026-10-15：扣費紀錄改資料庫加欄位（不硬對應回五種風格）。
- Eric 2026-10-16：送出型第一張卡送到才扣；一張都沒送到不扣；先別回、停照現在算一次。

## 第 1 輪

- base `87c8c602` → head `5b455dd1`（tree `95bb488fb1e50b41e9f23b485ffb8466f6efde35`）
- 封包 SHA256SUMS.txt sha256 `f8c638efd0b84796d5ed70ab9bbde1fe02dedc43972ebab1f64db2f9c24eae25`
- 主審回覆 sha256 `61cded6af70743260e08557fef984e5bdc3606afbcc740028aba2a9a268186fe`，`VERDICT: BLOCKED`
  1. P2：任務卡列可以直接寫入不一致的 recommendation JSON。
  2. P2：CHECK 驗證期間的鎖表時間沒有上限。
  3. P3：測試沒有載入正式的 retention cleanup。
- 反向預審：`PREREVIEW: FINDINGS`，全部 P3。8 條不能壞條件在直接攻擊下都守住（含 Postgres 16 兩連線真併發不雙扣）；測試沒釘死 exactly-once 的順序與擁有者檢查（6 個變體沒被抓到）、cleanup 版本、函式說明的 retry 敘述、鎖、JSON 鍵不對稱；另列第 2 片接線的注意事項。

## 修正（`d8b932b1`）

- 加 CHECK `analysis_stream_runs_card_task_recommendation`：card_task 非空時，recommendation_json 一定是物件、decisionKind 是 send、cardTask 等於 card_task。
- 開頭 `SET LOCAL lock_timeout = '5s'`；四條 CHECK 改 `NOT VALID`（既有列 card_task 全是 NULL，改寫的扣費 CHECK 只多一個 OR，既有列必定符合；之後的寫入照樣檢查）。
- 測試載入 retention migration，驗 v3 列扣費 30 天後清除；補照回、擁有者與雜湊、錯置 JSON 鍵、先鎖列再判斷等測試；RPC 拒絕送出型帶 selectedStyle 鍵、不送型帶 cardTask 鍵；函式說明改正。
- PGlite 22 passed；用反向預審的手法在新 migration 上做 8 個變體，8 個都被測試抓到。

## 第 2 輪（差異複核）

- base `5b455dd1` → head `d8b932b1`（tree `8ba28f7a0729e0375e5b6c2889f346d53e5b74f5`）
- 封包 SHA256SUMS.txt sha256 `fe25306de2464a55cfad4e558d1397b636c0feac0adba3e71fc8b6cc24e0b63f`
- 主審回覆 sha256 `42603e706fc389d0a8eeab2d9395f9dc28cb61f0da8681e047c115e892b312bc`，`VERDICT: APPROVED_WITH_RISK`
  - 第 1 輪三項都修好。
  - 殘餘 P3：`SET LOCAL lock_timeout` 只在套用器把整份 migration 放在同一筆交易時，才保護後面的 DDL；封包沒有正式套用器的交易證據。

## 風險接受

- Eric 2026-10-16 選「接受，套用時加保護（建議）」。
- 套用時的保護：先唯讀檢查有沒有長時間開著的交易、正式環境的 CHECK 定義跟 repo 一致；避開每小時 cleanup 排程那一分鐘；檢查與正式套用都再問 Eric。

## 狀態

- 已審查，本機 commit，沒推送，還沒套用到任何資料庫。Edge 程式還沒有地方呼叫 v3 RPC（第 2 片才接）；第 2 片推 main 前要先照 `docs/shared-agent-rules.md` 套這份 migration、核對 ledger 與 schema。
