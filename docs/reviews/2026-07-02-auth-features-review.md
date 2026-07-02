# 2026-07-02 登入 / 登出 / 刪帳號 Read-Only Review

> 範圍：`lib/features/auth/`、`lib/core/services/supabase_service.dart`、`social_auth/`、
> `lib/features/subscription/presentation/screens/settings_screen.dart`、
> `supabase/functions/delete-account/index.ts`、相關 migrations 與測試。
> 結論：**無 P0/P1；1 個 P2、3 個 P3**。純檢查，未改任何程式碼。

## 結論總表

| 級別 | 問題 | 位置 |
|------|------|------|
| P2 | 刪帳成功但本機清理失敗時，顯示「刪除帳號失敗」誤導使用者 | `settings_screen.dart` `_confirmDeleteAccount` catch |
| P3 | `deleteAccount` 的非 2xx 錯誤解析是死碼（invoke 直接丟 `FunctionException`） | `supabase_service.dart:157-181` |
| P3 | 刪帳硬刪 `revenue_events`，營收史料隨帳號消失 | `delete-account/index.ts` cleanupTargets |
| P3 | 離線時登出會整體失敗、留在登入狀態 | `SupabaseService.signOut` |

## P2 — 刪帳成功、本機清理失敗的錯誤訊息

`_confirmDeleteAccount` 中 `deleteAccount()` 成功後，`clearLocalStorage()` 若丟例外會落入同一個
catch，顯示 `_mapDeleteError` 的「刪除帳號失敗，請稍後再試。」。但此時**遠端帳號已刪除**：

- 使用者重試 → Edge 回 Invalid token → 顯示「登入狀態已失效，請重新登入。」，仍無法完成本機清理。
- 本機 session 與 Hive 資料留在裝置上，直到 token 過期才會被踢出。

行為本身符合 invariant（remote 成功不得謊報全部完成），現有測試
`delete account local cleanup failure does not finish deletion` 也鎖住呼叫次序；問題只在**文案與後續引導**。
建議：deleteAccount 成功後的清理失敗改走獨立分支，明講「帳號已刪除，但本機資料清理未完成，請重新開啟 App」，
並仍執行 `clearLocalSessionAfterDeletion()` 的 best-effort 清 session。

## P3 — deleteAccount 錯誤解析死碼

supabase_flutter v2 的 `functions.invoke` 對非 2xx 直接丟 `FunctionException`，所以
`supabase_service.dart` 中 `response.status` 檢查後解析 `data['error']` 的分支跑不到；
`_mapDeleteError` 靠字串比對（`confirmation` / `unauthorized`）對 `FunctionException` 也無效，
實際上一律 fallback 到通用訊息。建議 catch `FunctionException` 讀 `details` 再映射。

## P3 — revenue_events 硬刪

`revenue_events.user_id REFERENCES users(id)` 無 ON DELETE 規則，會擋住 `public.users` 的級聯刪除，
所以 Edge 把它列為 `required: true` 先刪——順序正確，但代價是 admin dashboard 的歷史營收統計
（MRR/退款紀錄）隨帳號消失。可考慮 migration 改 `ON DELETE SET NULL` 保留匿名化營收列。
**產品/財務決策，需 Eric 拍板，不建議逕改。**

## P3 — 離線登出

`client.auth.signOut()` 網路失敗且 local session 未清時，UI 顯示網路錯誤並留在登入狀態。
有 auth-gone fallback（session 已失效時仍清本機並導回 /login），但純離線登不出。dogfood 時知悉即可。

## 已驗證 OK 的事項

- **登入**：email/密碼、註冊驗證與重寄、忘記密碼、密碼重設（recovery deep link 冷啟 + 事件雙路徑）；
  Apple nonce 為 raw/sha256 正確配對；Google 走 ASWebAuthenticationSession 且驗 callback scheme/host；
  auth 錯誤映射成繁中含 429；`auth_diagnostics` 寫入前有 email 遮蔽與 metadata 消毒。
- **Router guard**：未登入僅 /login 可達；recovery 保持在 /login；完成 onboarding 後不可回 /login/onboarding；
  `resolveAppRedirect` 為純函數可單測。
- **登出**：清 usage snapshot + 練習室狀態；RevenueCat SDK logout 有意 no-op（登入時 `Purchases.logIn(user.id)` 切身份）；
  本機對話/Partner/Profile **刻意保留**（AES 加密），且 conversation/partner/user_profile repo 都以
  `ownerUserId` 過濾——換帳號登入不會看到前一使用者資料，符合 shared-agent-rules invariant。
- **刪帳號**：DELETE 確認閘（client + server 雙驗）；Edge 驗 JWT；cleanup 清單與 FK 現況一致
  （`analysis_runs` / `analysis_stream_runs` / `practice_profile_draw_events` 靠 auth.users CASCADE 自動清；
  `practice_chat_sessions` 無 FK、已列入手動清單）；先清資料再 `auth.admin.deleteUser` 的順序正確，
  deleteUser 失敗時資料已清但帳號可自我修復（下次登入 `ensureSubscriptionExists` 重建 free row）。
  成功後 `clearAll()` 覆蓋全部 Hive box + 清 session + invalidate providers。
- **測試**：`settings_screen_test` 覆蓋登出 3 情境、刪帳 5 情境；`storage_service_clear_all_test` 鎖 clearAll 全 box 覆蓋。
  本次 review 環境無 Flutter SDK，未執行 `flutter test`（需本機跑）。

## Next

- P2 文案分流：小 scope client fix，改後需補 widget test 鎖住「帳號已刪除但清理未完成」訊息。
- P3 x3：低急迫，排 backlog；revenue_events 保留策略先問 Eric。
