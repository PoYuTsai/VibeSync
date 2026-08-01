# 批 B｜訪客模式 實作計畫

> **For Claude:** 依 task 順序執行；每 task 一個 concern 一個 commit（繁中訊息）。
> 設計真相源：`docs/plans/2026-08-01-splash-global-coach-guest-mode-design.md` 批 B 節（Eric 已拍板）。
> R3：全部做完後跨模型雙審（Codex 額度空窗至 8/5 → Grok 4.5 主審＋GLM 5.2 證偽），審過才 push main。

**Goal**：登入頁一鍵「先逛逛，不用註冊」→ Supabase 匿名帳號真用核心功能（訪客額度 3 則總量、不重置）→ 三處觸發導 `/register` → identity linking 轉正（uid 不變、資料零搬移）。

**架構決定（盤點後定案）**：
- **一條 migration**（實作中發現，取代原「免 migration」估計）：TS 側重置（`applyResetsIfNeeded`＋CAS 寫回）匿名一律跳過＋限額 `{monthly: 3, daily: 3}`；但 practice 路徑的重置在 SQL `prepare_practice_subscription_usage` 內（且被 `settle_prefetched_practice_hint` SQL 內部再呼叫），TS 跳過蓋不到 → `20260801120000_practice_prepare_guest_skip_reset.sql` 讓該 RPC 查 `auth.users.is_anonymous` 匿名跳過歸零，簽名零改動。並發防護沿用 `increment_usage` 4-arg RAISE。
- 訪客判定單源：JWT/user `is_anonymous`（server `user.is_anonymous`、client `User.isAnonymous`，gotrue 2.18.0 已支援）。
- 「點訂閱付費 → 導註冊」**在 redirect matrix 集中攔截**（訪客 `/paywall` → `/register`），30+ 個 paywall push 點零散改動全免。
- 轉正三路：Apple＝`linkIdentityWithIdToken`（原生 idToken，鏡射現有 signInWithApple）；Google＝`getLinkIdentityUrl`＋FlutterWebAuth2＋`getSessionFromUrl`（鏡射現有 signInWithGoogle）；email＝`updateUser(email+password)` 寄確認信，點連結前仍是訪客（介面明講）。
- 需開兩個 auth 設定：`enable_anonymous_sign_ins`＋`enable_manual_linking`（config.toml 同批 commit；prod 以 Management API PATCH `external_anonymous_users_enabled`/`security_manual_linking_enabled`，deploy 時做）。

**驗證主命令**：`deno test`（各 function 目錄）、`flutter analyze`、`flutter test <相關檔>`；收尾全套 `flutter test`。

---

## Server（Edge）

### Task 1：`_shared/quota.ts` 訪客原語＋單元測試

**Files**：Modify `supabase/functions/_shared/quota.ts`、`supabase/functions/_shared/quota_test.ts`

1. 先寫失敗測試（quota_test.ts）：
   - `resolveLimits("free", { anonymous: true })` → `{ monthly: 3, daily: 3 }`；任何 tier＋anonymous 都是 3/3（訪客不可能有付費 tier，防禦性一致）。
   - `resolveLimits("free")`／`resolveLimits("starter")` 既有行為不變（回歸鎖）。
   - `noResetResult(sub)` → `{ sub 原樣, dailyReset: false, monthlyReset: false, previous*: 原值 }`。
   - `buildQuotaExceededPayload({..., anonymous: true })` → 既有鍵全保留＋`guest: true`＋message＝訪客文案；`anonymous: false`/缺席 → 無 `guest` 鍵、payload 與現版逐鍵相等（回歸鎖）。
2. 實作：
   ```ts
   export const GUEST_TOTAL_LIMIT = 3;
   export function isAnonymousAuthUser(user: { is_anonymous?: boolean | null } | null | undefined): boolean {
     return user?.is_anonymous === true;
   }
   // resolveLimits 加第二參數 opts?: { anonymous?: boolean }：anonymous → { monthly: GUEST_TOTAL_LIMIT, daily: GUEST_TOTAL_LIMIT }
   // noResetResult(sub): ResetResult — 訪客跳過重置用（monthly counter＝終身計數）
   // quotaExceededMessage / buildQuotaExceededPayload 加 anonymous?: boolean：
   //   訪客 message＝「訪客額度已用完，免費註冊即可解鎖每月 30 則額度。」＋ payload.guest = true
   ```
   `checkQuota` 純函式**不改**（訪客靠 limits 3/3 生效）；`classifyQuotaRpcError` 不改（RAISE 沿用 MONTHLY/DAILY）。
3. `cd supabase/functions/_shared && deno test quota_test.ts` 全綠。
4. Commit：`Edge：quota 共用層加訪客原語（3 則總量、免重置、guest 429）`

### Task 2：coach-chat 訪客接線＋測試

**Files**：Modify `supabase/functions/coach-chat/index.ts`（auth L317-322、reset L459、limits L468/486、429 L578/608、increment L730）＋既有測試檔

1. 失敗測試：`is_anonymous: true` 的 user →（a）用完 3 則後 429 且 payload 含 `guest: true`；（b）不寫回 reset（stale `monthly_reset_at` 也不歸零）；（c）非匿名行為不變（回歸鎖）。
2. 實作 pattern（各 function 通用）：
   ```ts
   const anonymous = isAnonymousAuthUser(user);
   const resetResult = anonymous ? noResetResult(sub) : applyResetsIfNeeded(sub, new Date());
   let limits = resolveLimits(sub.tier, { anonymous });
   // RC tier refresh 分支內的第二次 resolveLimits 同樣帶 { anonymous }
   // 429 payload 帶 anonymous；increment_usage RPC 的 p_monthly_limit/p_daily_limit 用訪客 limits
   ```
   注意：RC refresh（升 tier 救回）對匿名無意義，維持呼叫無害，但 limits 仍鎖 3/3。
3. `deno test` 綠。Commit：`Edge：coach-chat 訪客額度 3 則總量（免重置＋guest 429）`

### Task 3：coach-follow-up＋keyboard-assist＋keyboard-reply 同 pattern

**Files**：`coach-follow-up/index.ts`（L365/373/394/421/440/477）、`keyboard-assist/index.ts`（L213/220/232）＋`handler.ts` 429 點、`keyboard-reply/index.ts`（L320/325/338/594）＋`generation.ts` 429 點；各自測試檔

同 Task 2 pattern 逐一接線；每個 function 至少一條 guest 測試＋一條非匿名回歸鎖。keyboard 429 的 QUOTA_EXCEEDED signal shape（keyboard-reply L635）鍵不動、只多 `guest`。三 function 各自一個 commit（或合一 commit 若改動極小且同型）。

### Task 4：practice-chat（handler＋draw_handler）

**Files**：`practice-chat/handler.ts`（L1652 getUser、L1760 limits、429 L1935/1996）、`draw_handler.ts`（L149 limits、429 L326-341）、`quota_decision.ts`/`draw_decision.ts` 視 grep 結果；測試檔

先 grep practice-chat 的 sub 取得與 reset 寫回位置（它不 import `applyResetsIfNeeded`，可能有自己的流程——**先讀懂再改**，不確定就照實際結構把「匿名→limits 3/3＋跳過任何 reset 寫回」塞進單一 seam）。測試同上。Commit。

### Task 5：analyze-chat（核心計費面）

**Files**：`supabase/functions/analyze-chat/index.ts`（auth L4641；checkQuota ×10：L5523/6029/7264/7407/7603/7840/7939/8428/8491/9575；429 payload ×5：L6470/6477、L7160/7167、L7193/7200、L9420/9427、L9524/9531；increment L9508）、`opener_charge.ts`、`new_topic_billing.ts`；測試檔

1. 先 grep：analyze-chat 內部怎麼算 limits（不 import `resolveLimits`）＋reset 寫回在哪（自有 `new Date(0)` fallback 契約）。找到單一（或少數）seam 後套同 pattern：匿名 → limits 3/3、跳過 reset 寫回、429 帶 guest、RPC limit 參數帶 3。
2. OCR `ocr_rate_limit.ts` **不動**（429 不帶 quota 鍵的鐵則維持；訪客照吃 6/分 60/天 rate limit）。
3. 測試：至少 opener 或 analysis 主路徑一條 guest 超限測試＋非匿名回歸鎖。
4. Commit：`Edge：analyze-chat 訪客額度接線（含 opener/new-topic 計費路徑）`

## Client（Flutter）

### Task 6：匿名登入＋登入頁訪客入口＋funnel

**Files**：Modify `lib/core/services/supabase_service.dart`、`lib/features/auth/presentation/screens/login_screen.dart`（L895 後插入）、`lib/core/services/funnel_tracker.dart`（L26-39 白名單）、`supabase/functions/submit-feedback/index.ts`（Edge 白名單）＋鍵級鎖測試三處（**鐵則：改字典必同批改三處**）

1. `SupabaseService` 加：
   ```dart
   static bool get isGuestUser => currentUser?.isAnonymous ?? false;
   static Future<AuthResponse> signInAnonymously() async =>
       await client.auth.signInAnonymously();
   ```
2. 登入頁「先逛逛，不用註冊」文字按鈕（sign-up toggle 之下、legal disclaimer 之上；只在登入模式顯示、密碼恢復模式不顯示）→ `signInAnonymously()` → 走既有 `_handleSuccessfulLogin(user)`（ensureSubscriptionExists＋invalidate providers＋go('/')）。失敗走既有錯誤顯示。
3. funnel 字典加 `guest_mode_enter`（登入頁點擊時 track）、`guest_register_view`（屬性 `source`）、`guest_register_success`（屬性 `method`）——Edge/client/鍵級鎖測試三處同批。
4. Widget test：訪客按鈕存在＋點擊呼叫 signInAnonymously（mock seam 視 login_screen 既有測試慣例）。
5. Commit：`訪客：匿名登入＋登入頁先逛逛入口＋funnel 三事件（字典三處同批）`

### Task 7：redirect matrix 加 isAnonymous 軸＋`/register` 路由

**Files**：Modify `lib/app/routes.dart`（`resolveAppRedirect` L45-77、路由表）、`test/unit/app/redirect_matrix_test.dart`；Create `lib/features/auth/presentation/screens/register_screen.dart`（本 task 先立殼）

1. 失敗測試（matrix 新 group）：
   - 訪客（loggedIn＋anonymous）：`/paywall` → `/register`；`/register` → null（可達）；其餘路由行為與一般登入者相同。
   - 一般登入者：`/register` → `/`；`/paywall` → null（回歸鎖）。
   - 未登入：`/register` → `/login`（既有通則自動涵蓋，仍入測）。
2. `resolveAppRedirect` 加 `required bool isAnonymous`；live router 餵 `SupabaseService.isGuestUser`。規則插在「登入＋onboarding 完成」段。
3. 路由表加 `/register` → `RegisterScreen`（殼：AppBar＋placeholder）。
4. 測試綠（含 `onboarding_gate_router_test.dart` 不破）。Commit：`訪客：redirect matrix 加匿名軸（paywall→register 集中攔截）＋/register 路由`

### Task 8：identity linking 服務層

**Files**：Modify `lib/core/services/social_auth/social_auth_interface.dart`、`social_auth_native.dart`、`social_auth_web.dart`（stub throw）、`lib/core/services/supabase_service.dart`

1. `SocialAuthService` 加 `linkWithApple()`／`linkWithGoogle()`：
   - Apple：鏡射 `signInWithApple`（nonce＋getAppleIDCredential）→ `auth.linkIdentityWithIdToken(provider: OAuthProvider.apple, idToken:, nonce: rawNonce)`。
   - Google：`auth.getLinkIdentityUrl(OAuthProvider.google, redirectTo: AppConfig.authRedirectUri)` → FlutterWebAuth2（同 scheme/host 檢查）→ `auth.getSessionFromUrl(callbackUri)`。
2. `SupabaseService` 加 `linkWithApple()`／`linkWithGoogle()`／
   `registerGuestWithEmail({email, password})` → `client.auth.updateUser(UserAttributes(email:, password:), emailRedirectTo: AppConfig.authRedirectUri)`。
3. 錯誤語意：identity 已屬他人帳號（AuthException，訊息含 `identity_already_exists`／`already linked`）→ 原樣拋出，由 UI 判別顯示「這個帳號已註冊過，請改用登入」。
4. 純接線無獨立單元測（服務層薄殼），行為由 Task 9 widget test＋雙審覆蓋。Commit：`訪客：identity linking 服務層（Apple idToken／Google web-flow／email updateUser）`

### Task 9：RegisterScreen 完整 UI＋流程

**Files**：Modify `lib/features/auth/presentation/screens/register_screen.dart`；Create `test/widget/auth/register_screen_test.dart`

1. UI：權益文案（「註冊解鎖每月 30 則免費額度，訪客期間的紀錄全部保留」）＋ Apple/Google 按鈕（iOS block，鏡射登入頁）＋ email+password 表單（沿用登入頁驗證規則、`minimum_password_length 8`＋字母數字）＋「已有帳號？登入」。
2. 流程：
   - 進頁 track `guest_register_view`（source 由 route extra 傳入，預設 `unknown`）。
   - Apple/Google 成功（uid 不變）→ track `guest_register_success{method}` → invalidate session-scoped providers（鏡射 login_screen L72-76）→ `context.go('/')`＋成功 snackbar。
   - email 提交成功 → track `guest_register_success{method: email}` → 頁內狀態切「確認信已寄出，點擊信中連結完成註冊」（明講點連結前仍是訪客額度）。
   - identity 已存在錯誤 → 顯示「這個 Apple/Google 帳號已經註冊過。要改用它登入嗎？（訪客紀錄不會帶過去）」＋確認後 `SupabaseService.signOut()`（router 自動回 /login）。
   - 「已有帳號？登入」→ 同上警告 dialog → signOut。
   - 非訪客誤入由 Task 7 matrix 擋（`/register` → `/`），頁內不再重複防。
3. Widget test：權益文案與表單渲染、email 提交呼叫 service（mock）、寄出狀態切換、登入警告 dialog 出現。
4. Commit：`訪客：註冊頁三路轉正（Apple/Google 即時、email 確認信）＋警告動線`

### Task 10：client 訂閱狀態訪客額度（3/3）

**Files**：Modify `lib/features/subscription/data/providers/subscription_providers.dart`（`SubscriptionState` L121-160）、`lib/features/subscription/domain/services/subscription_tier_helper.dart`（`limitsFor` L42）、相關測試

1. 失敗測試：guest 狀態 `monthlyLimit == 3`＋`monthlyRemaining` clamp ≥ 0；非 guest 回歸鎖（free 30/15）。
2. `SubscriptionState` 加 `isGuest`（單源 `SupabaseService.isGuestUser`，由 notifier build 時讀入）；guest 時 limits 覆寫 3/3（tier helper 加 guest-aware helper，不動既有 `limitsFor(tier)` 簽名）。
3. 測試綠。Commit：`訪客：client 訂閱狀態鏡射訪客額度 3 則（單源 isAnonymous）`

### Task 11：額度 UI 訪客變體（首頁小條＋超限卡）

**Files**：Modify `lib/features/subscription/presentation/widgets/home_quota_strip.dart`（L94-129＋explain sheet L42-87）、`lib/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart`（`QuotaExceededUpgradeCard` L214-239）、`lib/features/analysis/presentation/screens/analysis_screen.dart`（render L7569-7588、`_handleCoachChatQuotaExceeded` L371-375）；對應 widget test（**pump PartnerListScreen 必用 `homeScreenSignalOverrides()` 鐵則**）

1. HomeQuotaStrip：guest → 「訪客額度剩 N 則」；explain sheet guest 文案＋CTA「免費註冊」→ `push('/register')`（帶 source: `quota_strip`）。非 guest 文案與 CTA 回歸鎖。
2. `QuotaExceededUpgradeCard`：加 guest 變體（標題「訪客額度已用完」、內文「免費註冊解鎖每月 30 則額度」、CTA「免費註冊」）；render site 依 `isGuest` 分流 CTA → `/register`（source: `quota_exhausted`）。
3. `_handleCoachChatQuotaExceeded`：guest → snackbar 文案改註冊版＋push `/register`（非 `/paywall`；不依賴 matrix 兜底、文案才一致）。其餘零散 paywall push 點不逐一改——matrix 兜底。
4. Widget test：guest/非 guest 兩態文案與導向。Commit：`訪客：額度 UI 訪客變體（小條＋超限卡＋教練 429 導註冊）`

### Task 12：跟進提醒訪客閘＋設定頁訪客帳號區

**Files**：Modify `lib/features/subscription/presentation/screens/settings_screen.dart`（`_onFollowUpReminderToggled` L182-205、帳號區、登出確認 L817-842）、`lib/features/analysis/presentation/screens/analysis_screen.dart`（`_maybeScheduleFollowUpNotification` L2274-2303）；對應測試

1. 設定頁提醒 toggle：guest → 不改 opt-in、push `/register`（source: `follow_up`）。
2. 分析完成後 soft opt-in 卡：guest 直接不彈（v1 決定：訪客唯一提醒入口＝設定頁 toggle → 導註冊）。
3. 設定頁帳號區：guest 顯示「訪客帳號」＋「註冊帳號」入口（→ `/register`，source: `settings`）；登出確認文案 guest 變體：「訪客帳號登出後無法找回，紀錄將永久遺失」。
4. Widget test：toggle 導向、soft card 不彈、帳號區兩態。Commit：`訪客：跟進提醒閘＋設定頁訪客帳號區與登出警告`

## 收尾

### Task 13：auth 設定＋文件＋全套驗證

1. `supabase/config.toml`：`enable_anonymous_sign_ins = true`、`enable_manual_linking = true`。
2. 設計檔補批 B 狀態註記；`docs/snapshot.md` 若有 stage 行順手對齊（不展開重寫）。
3. 全套：`flutter analyze`（0 warning 鐵則）＋`flutter test` 全綠＋各 Edge function `deno test` 全綠。
4. Commit：`訪客：auth 設定開匿名與手動 linking＋批 B 收尾文件`

### Task 14：R3 跨模型雙審 → 審修 → 交付

1. 雙審（**在 repo 外 cwd 跑 grok-codex、prompt 引數傳**——盤點 memory 鐵則）：Grok 4.5 主審全 diff；GLM 5.2 證偽包（聚焦：額度繞過、reset 漏跳、redirect 迴圈、linking 錯誤態、429 shape 相容）。至多兩輪。
2. 審修後：Edge pre-push audit → push main（自動帶上本地既有 docs commit acd7c2a8）→ 盯 push-triggered Edge deploy＋`Build & Distribute`（Android）。
3. Prod auth 設定（Supabase Management API＋PAT，ref=fcmwrmwdoqiqdnbisdpg）：
   `PATCH /v1/projects/{ref}/config/auth` body `{"external_anonymous_users_enabled": true, "security_manual_linking_enabled": true}`，PATCH 後 GET 回讀驗證。
4. **Migration 交付**：`20260801120000_practice_prepare_guest_skip_reset.sql` 走定向套用（Management API＋PAT，絕不 `supabase db push`），套用後核對遠端帳本版本＝檔名、驗 RPC 行為，**先於 push main**（規則：migration-dependent Edge code 不得先上）。
5. **不做**：iOS build dispatch（Eric 手動）、App Store 送審、`supabase db push`。
6. **審計註記（雙審後補）**：`opener_charge.ts`／`new_topic_billing.ts` grep 證實無獨立 429/limits 建構（全由 index.ts 傳入，已鎖訪客值），故無 diff；`_handleSuccessfulLogin` 只用 `user.id`，email-null 安全；keyboard-assist 429 維持自有 shape（`quota_exhausted`＋message，不帶 `guest` 鍵）＝刻意例外，client 鍵盤訊號 keys 不動。

**Dogfood 腳本（Eric/Bruce，批 A＋B 一顆 build）**：刪 app 裝新版 → 先逛逛 → onboarding → 用核心功能到 3 則用完 → 撞註冊卡（非付費牆）→ 註冊（Apple 或 email）→ 確認訪客期間對象卡／分析／關於我都在、額度變 30/月。

## 邊界（不做）

- 訪客資料合併進既有帳號（登入路徑）：v1 不做，介面明講。
- 30+ paywall push 點逐一改文案：不做，matrix 集中攔截兜底；只改三個主要接觸面（小條/超限卡/教練 snackbar）。
- SQL/migration：零改動。`check_and_reset_usage` legacy 函式不動。
- OCR rate limit、TEST_EMAILS bypass、RevenueCat 接線：全部不動（訪客 RC login 用匿名 uid 無害，轉正 uid 不變歸屬延續）。
