# VibeSync AI 鍵盤 TestFlight 發布檢查

更新：2026-07-17

## 發布契約

- 每次有效生成固定消耗 1 點；只有通過輸出驗證並完成原子結算才扣額。
- App 與鍵盤 extension 以共享 Keychain 保存同一 user／文字／風格的 durable request ID，成功插入回覆後才刪除。
- Client request ID 可重試約 23 小時；Server replay ledger 保存最多 24 小時並每小時清理。這個時間差保留時鐘與排程安全邊界。
- Server 必須先取得 claim／lease 才可呼叫模型；同 request ID 的並行請求只能由一個 owner 生成，其餘回 409 pending 並保留原 request ID。
- Free 15／30、Starter 50／300、Essential 120／800；模型限流不得誤開 paywall。

## 必須依序完成：DB → Secret → Edge → App

1. 先確認 CLI 已 link 到 `fcmwrmwdoqiqdnbisdpg`，再用 `supabase migration list --linked` 核對 production migration history：
   - 若 `20260717120000` 尚未 applied，套用 `supabase/migrations/20260717120000_keyboard_reply_exactly_once.sql`。
   - 若 production 已記錄同版號，代表舊內容可能已套用；不可只修改原 migration，必須建立新時間戳 corrective migration，再依正常流程套用。
2. 建立 Base64 編碼、解碼後至少 32 random bytes 的 HMAC key；值不可進 repo：

   ```powershell
   openssl rand -base64 32
   npx.cmd --yes supabase secrets set KEYBOARD_REPLAY_HMAC_KEY="<generated-value>" --project-ref fcmwrmwdoqiqdnbisdpg
   ```

3. 驗證必要 secrets 名稱：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/preflight/check-supabase-secrets.ps1 -ProjectRef fcmwrmwdoqiqdnbisdpg
   ```

4. 部署 JWT 驗證的 `keyboard-reply`；不可使用 `--no-verify-jwt`：

   ```powershell
   supabase functions deploy keyboard-reply --project-ref fcmwrmwdoqiqdnbisdpg
   ```

5. 用 production anon key 驗證 Edge 與 DB 共同宣告的 capability：

   ```powershell
   $env:SUPABASE_PROD_ANON_KEY = "<production-anon-key>"
   powershell -ExecutionPolicy Bypass -File tools/preflight/check-keyboard-contract.ps1
   ```

   必須回報 `keyboard-reply-exactly-once-v1`。Migration、RPC、HMAC secret 或 Edge 任一缺失都必須失敗。

6. HMAC key 不可在 24 小時 replay window 內直接輪替。要輪替時先暫停鍵盤流量並等待至少 24 小時，或先實作 versioned-key migration。

### Production 完成證據（2026-07-17）

- [x] `20260717120000` 精準套用，migration ledger local／remote version 對齊。
- [x] 32-byte random Base64 `KEYBOARD_REPLAY_HMAC_KEY` 已設定，必要 secret preflight 通過。
- [x] `keyboard-reply` v5 已部署，`verify_jwt=true`。
- [x] Live health 回 `keyboard-reply-exactly-once-v1`。
- [x] 真實 PostgreSQL claim／pending／owner release／settlement／replay／mismatch transaction smoke 通過並 rollback；RLS／grant／cron 正確。
- [x] Production 測試帳號 fresh／replay／mismatch 通過、quota 不變、smoke rows 清為 0。
- [ ] 非測試 quota +1／429、HTTP 並行 pending／lost-response 與 iPhone Full Access 仍待真機矩陣。

## Apple／Build

1. Runner `com.poyutsai.vibesync` 與 Keyboard `com.poyutsai.vibesync.keyboard` 都啟用：
   - App Group `group.com.poyutsai.vibesync`
   - Keychain Sharing `TTQHTVG8CC.group.com.poyutsai.vibesync`
2. 重新產生 Development、Ad Hoc、App Store provisioning profiles。
3. CI 的 macOS `flutter build ios --simulator --debug` 必須成功編譯 App 與 extension。
4. Archive／Validate／TestFlight build 必須包含 `VibeSyncKeyboard.appex`。

## Production smoke（缺一不可）

1. Fresh：新 request ID 產生有效回覆，usage 恰好 +1。
2. Lost response：模擬 client 未收到結果，以相同 ID 重試；回放相同回覆且 usage 不再增加。
3. Concurrent：A 尚在生成時 B 使用相同 ID；B 得到 pending，不能產生第二次模型呼叫或新 ID。
4. Mismatch：相同 ID 搭配不同文字或風格；回 409 mismatch、不扣額。
5. 429：只在明確 `QUOTA_EXCEEDED` 時開 paywall；明確 quota／model-rate gate 都在 terminal 或 pre-claim 邊界並釋放 client slot。未知 429、408、425、5xx 必須保留 ID 並提供稍後重試。
6. A/B 同時輸入不同文字；各自保留獨立 request ID，不互相覆蓋。
7. LINE、Instagram、Messages 各完成一次 Full Access 貼上、生成、插入與回到 VibeSync 更新登入的流程。

## 隱私／App Review

- App 內揭露：使用者主動載入的文字會送至 Anthropic。
- Keychain 保存 request ID／user ID／fingerprint metadata，重試資格約 23 小時，不保存原文；成功、刪帳或下次 extension 啟用時清理。一般登出保留 pending metadata 以保護在途結算；App 未刪帳即移除時，iOS Keychain 實體資料可能延後至重裝後的下次清理。
- Server 保存生成回覆、風格與 keyed HMAC 最多 24 小時，每小時排程清理；backup／PITR 有獨立週期。
- 發布前必須更新 `https://vibesyncai.app/privacy` 與 App Store Connect App Privacy。Repo 文件更新不等於公開頁面已發布。

## 判定

Windows 的 Deno／Flutter 測試只能證明程式與契約；在 production migration history 核對、真實 PostgreSQL migration／併發測試、macOS signed build、production capability、fresh／replay／pending／mismatch、quota／paywall、Full Access 及公開隱私頁完成前，不得宣稱 dogfood safe 或 App Review ready。
