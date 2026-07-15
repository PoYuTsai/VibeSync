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

1. 審查當下本機 Docker engine 不可用，因此沒有本地 PostgreSQL integration test。部署時已改以遠端真 PostgreSQL 驗證 migration、RLS、grants、RPC、原子 charge/replay、quota rollback、同 request 並行 first-writer-wins 與 cron 設定；測試列與額度變化均已清除／rollback。
2. 舊版 App 不會傳 `requestId`；server 仍固定扣 1，但 legacy request 無法保證 exactly-once。新版 App 才具備 durable request identity 與安全重播。

## 2026-07-16 部署與 smoke 證據

- 線上政策：`vibesync-web` `9929d5b`；GitHub Pages run `29450492357` 成功，live URL 已驗新版揭露。
- DB：只用 `supabase migration up --linked` 套用唯一待辦 `20260716170000`，沒有執行 `db push`；local／remote migration ledger 對齊。
- Schema：兩個 usage counter 為 `NOT NULL DEFAULT 0`；ledger RLS 已開；anon／authenticated 無 table、settlement、cleanup 權限；service role 權限正確。
- Cron：job id 1 於 2026-07-15 21:17:00 UTC 首次自然觸發，約 34ms 完成，`status=succeeded`、`return_message=1 row`。
- PostgreSQL transaction smoke：fresh 固定 +1、同 request replay +0、hash mismatch fail、quota failure 連 ledger 一起 rollback；整段測試 transaction 最後 rollback，測試帳號維持 0／0。
- 並行 smoke：兩個同 owner／requestId／hash 的請求只留下單一 first-writer result，兩邊取得相同結果；測試 row 已刪除。
- Edge：GitHub Actions run `29450067262` 成功；`analyze-chat` v269 保持 `verify_jwt=false`，`coach-chat` v52 保持 JWT 驗證。
- Live API：fresh 200 且有可用結果；同 ID／同 payload replay 200、回同一結果與 `optimize_message_idempotent_replay`；同 ID／不同 payload 回 400 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`。測試 ledger 已刪除，測試帳號仍為 0／0。
- Build：`cdafa244` 的 staging iOS IPA 與 Android APK 均成功，GitHub run `29450067276` 已上傳 Firebase App Distribution。

剩餘 release gate 是實機 dogfood：用新版 App 測 fresh、連線重試、背景／前景、降級後恢復已付結果與最後一格 quota；正式再次送審前仍須人工核對 App Store Connect／Review Notes。
