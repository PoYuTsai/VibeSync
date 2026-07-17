# 2026-07-17 AI 鍵盤 Production 部署證據

狀態：`PRODUCTION_BACKEND_GATE_COMPLETE`

## Scope

- Project：`fcmwrmwdoqiqdnbisdpg`（linked project：`vibesync-sandbox`，`ACTIVE_HEALTHY`）
- 只處理 AI 鍵盤 exactly-once backend gate；沒有部署 `analyze-chat` 或其他 Edge Function。
- 順序固定為 DB → Secret → JWT-verified Edge → Live contract。
- 全程沒有使用 `supabase db push`，也沒有把 secret 值寫入 repo、終端輸出或文件。

## Deployment

1. `supabase migration list --linked` 顯示 local／remote 原本完整對齊，唯一 pending 為 `20260717120000`。
2. 以 `supabase migration up --linked --yes` 精準套用 `20260717120000_keyboard_reply_exactly_once.sql`；重查 migration ledger，local／remote version 均為 `20260717120000`。
3. 在記憶體產生 Base64 編碼的 32 random bytes，設定為 `KEYBOARD_REPLAY_HMAC_KEY`；必要 secret preflight 通過。
4. 只部署 `keyboard-reply`，未使用 `--no-verify-jwt`。遠端由 v4 升為 v5，狀態 `ACTIVE`、`verify_jwt=true`。
5. Production GET health 通過，Edge 與 DB 共同回報 `keyboard-reply-exactly-once-v1`。

## Database verification

- `keyboard_reply_contract_version()`：`keyboard-reply-exactly-once-v1`。
- Migration ledger：`20260717120000` 恰一筆。
- `keyboard_reply_requests`：RLS enabled；anon／authenticated 無 table SELECT；service role 有 SELECT。
- claim RPC：anon／authenticated 無 EXECUTE；service role 的 claim／release／settle 均可執行。
- `cleanup-expired-keyboard-reply-requests` cron：恰一筆，排程 `31 * * * *`。
- Transaction smoke：fresh claim、第二 owner pending、錯 owner 不可 release、正 owner release、reclaim、無扣額 settlement、replay、hash mismatch 全通過；最後 rollback，殘留 0 row。

## Live API smoke

以既有免扣額測試帳號驗證並清理測試資料：

- Fresh request：HTTP 200，reply 與 style 合法。
- 同 request ID／同 payload：HTTP 200，回放相同 reply／style。
- 同 request ID／不同 style：HTTP 409，`KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH`。
- 測試帳號 monthly／daily usage 前後不變，符合免扣額契約。
- Ledger 為 `done`、`quota_charged=false`、HMAC 64 hex、result 只有 `reply`／`style`；smoke rows 清理後為 0。

## Remaining external gates

Backend 四步已完成，但以下仍需 signed iPhone／非測試 quota 情境，不能由這次 Windows smoke 代替：

1. 非測試帳號 fresh 成功恰好 +1、quota 429 與 model-rate 429。
2. HTTP 層真正並行 pending 與 lost-response retry；DB pending／replay contract 已驗證。
3. Signed Archive／IPA 包含 `VibeSyncKeyboard.appex`。
4. LINE／Instagram／Messages Full Access 與 App 返回同步。
5. 公開 Privacy Policy、App Store Connect App Privacy／Review Notes 對齊鍵盤 24 小時 replay 與 Keychain identity。
