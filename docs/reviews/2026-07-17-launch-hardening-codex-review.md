# 2026-07-17 發布硬化 Codex Review

狀態：`CODE_REVIEW_APPROVED_WITH_EXTERNAL_GATES`

## Scope

- Base：`origin/main`
- Branch：`codex/launch-hardening-20260717`
- Intent：評估 TestFlight／App Review 前的產品成熟度，修正會造成假綠燈、錯誤計費、成本失真或資料清理遺漏的缺陷。
- Scope check：`CLEAN`。變更集中在 CI／發布閘門、AI 成本真相、admin 相依安全，以及 AI 鍵盤恰一次結算。
- Greptile：目前沒有 PR，無外部留言可分類。

## 已修正 findings

1. `[P1]` Firebase Distribution 失敗可被 `continue-on-error` 吞掉，staging 選項實際仍指向 production backend。已移除假環境與非阻斷上傳，release notes 明示 production backend。
2. `[P1]` `analyze-chat` streaming 路徑把成功請求 token 記為 0，Free Sonnet 5 成本監控會假綠。已解析 Anthropic `message_start`／`message_delta` usage，補齊 input、output、cache write/read token。
3. `[P1]` Admin 成本頁讀取沒有 writer 的 `token_usage`。已改以 `ai_logs.cost_usd` 為唯一成本來源，並用 1,000-row 分頁讀完整資料，不再靜默截斷 5,000 筆。
4. `[P1]` 鍵盤 durable request ID 原本不足以序列化並行模型呼叫，429／timeout／lost response 可能清錯 identity 或重複扣額。已加入 user-bound keyed HMAC、owner-bound claim／renew／release／settlement、45 秒 lease、24 小時 replay、原子 result＋quota transaction 與 fail-closed client semantics。
5. `[P1]` 刪除帳號時 session redirect 可能早於鍵盤 Keychain purge，留下帳號 metadata。已把清理順序固定為 local storage → keyboard Keychain → local session。
6. `[P2]` Admin runtime 與 `@types/node` 未跟 Supabase SDK 的 Node 需求同步，且相依套件有已知漏洞。已固定 Node 22、同步 types、升級受影響套件；production audit 為 0 vulnerabilities。
7. `[P2]` 成本計算忽略 Anthropic prompt cache，未知 model ID 還可能套用最便宜價格。已加入 cache write 1.25x、read 0.1x，未知 model 改用 Sonnet 4.6 保守費率，並加入 Sonnet 5 launch price 2026-08-31 到期測試。
8. `[P2]` 通用 Edge auto-deploy 可能在 migration 前先上新版 keyboard function。已排除 `keyboard-reply`，release／distribution 改以 DB-owned live contract 阻擋不相容版本。
9. `[P2]` 非串流 quick／full／legacy log 只把 cache token 放進 response metadata，沒有傳入成本函式。已讓 7 個 metered log call 全部傳遞 cache write/read token，並加 source contract test。
10. `[P2]` Admin 成本 API 全歷史 offset 分頁會無界成長，且同 timestamp／並行刪除可能漏算或重算。已限制為近 12 個 UTC 月並改用 `(timestamp, id)` keyset pagination；空狀態也同步為 `ai_logs`。
11. `[P2]` reply style 測試只確認字串曾在 SQL 出現，無法抓 table CHECK 與 settlement allowlist 漂移。已分別解析兩個 allowlist，逐項與 canonical TS contract 做 exact equality。

最終獨立安全複審沒有發現剩餘 P0／P1 程式碼問題。

## Verification

- `flutter test --concurrency=1`：2,252 passed、4 skipped。
- `flutter analyze`：no issues。
- CI Edge contracts 原樣執行：177 passed、0 failed。
- `deno check supabase/functions/keyboard-reply/*.ts supabase/functions/analyze-chat/index.ts`：passed。
- Targeted `deno fmt --check`、Dart format、`git diff --check`：passed。
- Admin Node `v22.16.0`：ESLint passed、Next.js 16.2.10 production build passed、`npm audit` 0 vulnerabilities。
- 變更後的所有 GitHub Actions workflow YAML：parse passed。
- 兩支 PowerShell preflight script：syntax passed。
- `AGENTS.md`／`CLAUDE.md` SHA-256：一致。

## 尚未完成的外部硬閘門

以下不是可用 Windows 單元測試取代的證據。完成前不得宣稱 dogfood safe 或 App Review ready：

1. 用 `supabase migration list --linked` 核對 production migration history。若 `20260717120000` 已 applied，必須新增 corrective migration，不可只修改原檔。
2. 在真實 PostgreSQL／Supabase 驗證 migration、RLS／權限、concurrent claim、settlement rollback、replay 與 cleanup。
3. 設定 `KEYBOARD_REPLAY_HMAC_KEY`，依 DB → Secret → Edge 順序部署，live contract 必須回 `keyboard-reply-exactly-once-v1`。
4. macOS signed build／Archive 必須包含 `VibeSyncKeyboard.appex`。
5. 真機完成 fresh、lost response replay、pending、mismatch、quota、model-rate、LINE／Instagram／Messages Full Access 測試。
6. 更新公開隱私頁與 App Store Connect App Privacy；repo 內政策更新不等於已對外發布。

## Verdict

`APPROVED FOR MERGE`，但 `NOT YET DOGFOOD SAFE`。程式碼層阻斷問題已收斂，正式安全結論必須等上述 production／Apple／privacy gates 全數完成。
