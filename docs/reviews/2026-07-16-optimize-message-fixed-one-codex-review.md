# 「我幫你修」固定扣 1 與安全重播 — Codex 終審證據

- 日期：2026-07-16
- 程式 commit：`4b624617`
- 審查範圍：`b09b6dd1..4b624617`
- 結論：APPROVED；P0 0／P1 0／P2 0／P3 2

## 已驗證的不變條件

| 不變條件 | 結果 |
|---|---|
| 只有通過 schema、可被 App 使用的成功結果才固定扣 1；失敗扣 0 | 通過 |
| 同一 owner、requestId 與 input hash 可重播既有結果且不重扣 | 通過 |
| result persist 與扣額度在同一資料庫交易完成 | 通過 |
| App 先把 owner-scoped request UUID 寫入既有 AES-256 Hive，再送 HTTP | 通過 |
| Hive 身分資料損壞時 fail closed，不自行刪除並換新 UUID | 通過 |
| 使用者降級後仍可恢復已付結果；新的非 Essential 請求仍被擋下 | 通過 |
| preflight replay 查詢失敗會回 retryable 503，不會先呼叫模型或扣額度 | 通過 |
| quick／full／stream 等錯誤 optimize mode 在模型與 quota 前被拒絕 | 通過 |
| NULL quota counters 已回填、設為 NOT NULL，回應採 server authoritative counters | 通過 |
| ledger 只另存生成後的 optimized text 與 reason，不另存原始草稿或完整對話欄位 | 通過 |
| live ledger 約保留 7 天，pg_cron 每小時清理過期資料 | 通過 |
| App 同意文案與 repo 隱私政策誠實說明生成結果可能反映使用者輸入 | 通過 |

## 驗證

- `analyze-chat` 全套 Deno tests：597/597 passed。
- 最終 billing／quota targeted Deno tests：48/48 passed。
- analysis widgets Flutter tests：67/67 passed。
- 最終 session／contract／privacy focused Flutter tests：28/28 passed。
- `deno check index.ts`、`flutter analyze`、格式檢查與 `git diff --check`：通過。
- 獨立 Codex review：APPROVED，沒有 P0／P1／P2 finding。

## P3 與已知邊界

1. 本機 Docker engine 不可用，因此未能執行真 PostgreSQL concurrency、RLS、RPC 與 cron integration test。部署後必須直接核對 `cron.job`／`cron.job_run_details`，並測 fresh request、同 request 並行 replay、quota rollback。
2. 舊版 App 不會傳 `requestId`；server 仍固定扣 1，但 legacy request 無法保證 exactly-once。新版 App 才具備 durable request identity 與安全重播。

## 上線閘門

這個 commit 尚未部署。正式啟用前必須依序完成：

1. 先發布新版線上隱私政策，並同步 App Store Connect 的資料使用揭露。
2. 精準套用 `20260716170000_optimize_message_fixed_charge.sql`，不得用無差別 `supabase db push`。
3. 驗證 RPC、grants、RLS 與 pg_cron 首次執行。
4. 以專案既定的 `--no-verify-jwt` 部署 `analyze-chat`。
5. 發佈包含 durable requestId 的新版 App／TestFlight，完成真機 fresh、retry、downgrade recovery 與 quota smoke。
