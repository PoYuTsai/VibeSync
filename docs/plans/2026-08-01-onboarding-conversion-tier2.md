# Onboarding 轉化 Tier 2＋埋點 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 完成 onboarding 轉化診斷（docs 外部報告 2026-07-31）Tier 2 的三個真項目＋埋點前置債：首頁額度露出與 Coach/Opener 入口、去識別化漏斗埋點、onboarding 輕量問卷與首頁起步清單。

**Architecture:** 三批依序執行，批間有 gate。批 1 純 client UI（零後端）；批 1.5 埋點走案 1 批 3 的既有通道（submit-feedback Edge＋新表，**有 migration，走高風險流程＋跨模型審查**）；批 2 純 client（問卷餵既有 `UserProfileController`、清單讀既有訊號 provider）。

**Tech Stack:** Flutter/Riverpod、Supabase Edge Functions（Deno）、Postgres targeted migration、Hive（間接）。

**拍板紀錄（Eric 2026-08-01，全依 CC 建議）：**
- Coach 入口＝導航版 (a)：有對象進最近互動對象的 coach 跟進區，沒對象導建卡。全域教練 (b) 另案。
- 額度露出＝只給免費用戶、一行小條、剩 ≤3 變醒目色、點擊開說明 sheet。
- 問卷＝一頁（互動風格單選＋練習目標最多選 2），可略過。
- 起步清單四項＝關於我／第一次分析**或**第一局練習（二擇一即勾）／開跟進提醒／設定鍵盤（僅 iOS）。全完成卡片消失。
- **T2-7（OCR 相片權限預熱）撤案**：主線 `image_picker ^1.0.7` 在 iOS 走 PHPickerViewController，根本不跳權限框，「預熱」無問題可解。**別再開案**；鍵盤支線要全相簿權限是另一回事，其雙重預熱維持不動。
- 埋點插在批 1 與批 2 之間：沒有它，所有轉化改動都無法量測。

**已驗證的既有材料（2026-08-01 於 main `eb9bf41b` 查證）：**
- `SubscriptionState.isFreeUser` / `.monthlyRemaining` / `.monthlyLimit`（`subscription_providers.dart:154-161`）；refresh seam＝`subscriptionScreenRefreshProvider`（`:1621`）。
- `/opener` 路由無必要參數；Coach 導航用現成 `followUpDeepLink(partnerId)`（`routes.dart:80`）。
- `partnerListProvider` 已按最後互動時間降冪排序（`partner_providers.dart:29-35`）→ `partners.first`＝最近互動對象。
- 埋點通道範本：client `CoachingOutcomeUploader`（best-effort／白名單／絕不 throw）＋ Edge `submit-feedback` 的 `kind:"outcome"` 分支（`index.ts:187`）＋`outcome_events` 表。
- 問卷 chips 可重用 `ProfileChipSection<T>`（`profile_chip_section.dart`）；不合身就在 onboarding 內做輕量版，**不改共用元件**。
- 清單訊號全現成：profile＝`userProfileControllerProvider`；分析＝`analysisHistoryEventsProvider`；練習＝`practiceTemperatureTrendProvider`；跟進提醒＝`FollowUpOptInStore.read()`；鍵盤＝`OnboardingService.isKeyboardCompletedSync`。
- T1 批已種 notes：`_seedProfileFromBranchAnswer`（`onboarding_screen.dart`）**只在 profile 全空時種**——批 2 問卷會先建 profile，必須改成合併式種子（見 Task 10），否則 notes 永遠種不進去。

---

## 批 1｜首頁額度小條＋Opener/Coach 入口（純 UI）

### Task 1: HomeQuotaStrip widget

**Files:**
- Create: `lib/features/subscription/presentation/widgets/home_quota_strip.dart`
- Test: `test/widget/features/subscription/home_quota_strip_test.dart`

**Step 1: 寫失敗測試**（用 `subscriptionProvider.overrideWith` 塞 seeded notifier，同 `my_report_screen_test` 的 `_SeededSubscriptionNotifier` 慣例）：

```dart
testWidgets('免費用戶顯示剩餘次數', (tester) async { /* tier: free, used 7/30 → 找「本月分析還剩 23 次」 */ });
testWidgets('付費用戶整條隱藏', (tester) async { /* tier: starter → findsNothing */ });
testWidgets('剩 3 次以下換醒目色', (tester) async { /* used 27/30 → 驗色票 key */ });
testWidgets('點擊開說明 sheet，內含看訂閱方案', (tester) async { /* tap → 找說明文字＋按鈕 */ });
```

**Step 2: 跑測試確認紅**：`flutter test test/widget/features/subscription/home_quota_strip_test.dart`

**Step 3: 最小實作**：`ConsumerStatefulWidget`；`initState` 內 best-effort 呼叫 `ref.read(subscriptionScreenRefreshProvider)()`（吞錯誤）；build 讀 `subscriptionProvider`，`!isFreeUser → SizedBox.shrink()`；一行文字＋`monthlyRemaining <= 3` 換 `AppColors.ctaStart` 系醒目色；`onTap → showModalBottomSheet`（額度說明＋`BrandPrimaryButton('看訂閱方案') → context.push('/paywall')`）。

**Step 4: 跑綠。Step 5: Commit**：`首頁：免費額度小條（剩餘次數＋說明 sheet）`

**注意**：測試帳號（TEST_EMAILS，vibesync.test）免扣額度，dogfood 時剩餘數不動是預期，別誤判 bug。

### Task 2: 首頁功能入口列（Opener＋Coach 導航版）

**Files:**
- Create: `lib/features/partner/presentation/widgets/home_feature_entries.dart`
- Test: `test/widget/features/partner/home_feature_entries_test.dart`

**Step 1: 失敗測試**：stub GoRouter（慣例照 `onboarding_branching_page_test._stubRouter`）＋`partnerListProvider.overrideWithValue`：

```dart
testWidgets('開場救援 → /opener', ...);
testWidgets('問教練＋有對象 → 最近對象的 coach 跟進 deep link', ...); // partners=[老的,新的] 驗導向 partners.first
testWidgets('問教練＋沒對象 → /partner/new', ...);
```

**Step 3: 實作**：兩顆並排小卡（BrandKit 暗面卡樣式，對齊首頁現有視覺）；Coach onTap：`final partners = ref.read(partnerListProvider); partners.isEmpty ? context.push('/partner/new') : context.push(followUpDeepLink(partners.first.id));`

**Step 5: Commit**：`首頁：Opener 與問教練入口（導航版）`

### Task 3: 掛進 partner_list_screen（空／非空兩態都掛）

**Files:**
- Modify: `lib/features/partner/presentation/screens/partner_list_screen.dart`（兩個 ListView 的頂部各插 `HomeQuotaStrip()`＋`HomeFeatureEntries()`；非空態注意 `listItemCount`／banner index 位移，跟著 `bannerCount` 的既有算法改）
- Test: 擴充 `test/widget/features/partner/` 既有 partner_list 測試（若無則新建）：空態與非空態都找得到兩個新 widget；banner 測試不因 index 位移而破。

**Step 5: Commit**：`首頁：掛上額度小條與功能入口列`

### Task 4: 批 1 收尾

1. `flutter analyze`（**全 repo**，release gate 標準；記取 `defaultTargetPlatform` 教訓——本機綠不等於 CI 綠，import 全部顯式寫）。
2. `flutter test test/widget/features/subscription/ test/widget/features/partner/`。
3. 視覺 proof：仿 `onboarding_conversion_proof_test.dart` 拍首頁兩態（**字型要載 msjh 雙路徑，翻頁／切態後先斷言目標文字再截圖，比對 md5 防假圖**），傳 Eric 目檢。
4. Push main → 盯 exact-SHA Build & Distribute＋Vercel 兩條到綠。

---

## 批 1.5｜漏斗埋點（Edge＋migration，高風險流程）

> **Gate：本批動 Edge 與 migration＝R2。push 前必須跨模型審查（codex:rescue 對抗式單審起跳），executor 不自審。**
> **順序鐵律：先完成並驗證 targeted migration，才准 push 依賴它的 Edge 代碼**（AGENTS.md：Never push migration-dependent Edge code to `main` before its required migration is verified）。**絕不 `supabase db push`**，照 `docs/shared-agent-rules.md` 的目標式 migration 程序，版本號寫進帳本。

### Task 5: 事件字典 v1（先落檔再寫碼）

**Files:** Create: `docs/integrations/funnel-events-v1.md`

白名單事件（server 端 enum 硬擋，字典外的 event 一律 400）：

| event | properties（白名單鍵） | 打點位置 |
|---|---|---|
| `onboarding_page_view` | `page_index` | OnboardingScreen.onPageChanged |
| `onboarding_skip` | `page_index` | _skipOnboarding |
| `onboarding_branch_answer` | `has_partner` | _completeOnboardingTo |
| `onboarding_questionnaire_submit` | `style_set`(bool), `goals_count` | 批 2 問卷頁 |
| `quota_strip_tap` | — | HomeQuotaStrip |
| `opener_entry_tap` / `coach_entry_tap` | `has_partner`(coach) | HomeFeatureEntries |
| `first_analysis_completed` | — | 分析完成 hook（本機 once-flag 去重） |
| `first_practice_completed` | — | endPractice hook（本機 once-flag 去重） |
| `keyboard_setup_shown` / `keyboard_setup_completed` | — | app.dart push 點／markKeyboardCompleted |
| `checklist_item_done` | `item` | 批 2 清單 |

**隱私鐵則（照案 1 批 3）**：payload 只有 event 名＋上表白名單鍵；**絕不**帶對話內容、對象名、自由文字。client＋server 雙層白名單。

**Step: Commit**：`docs：漏斗事件字典 v1`

### Task 6: `funnel_events` 表 targeted migration

**Files:** Create: `supabase/migrations/<照帳本規則取版本號>_funnel_events.sql`

```sql
create table public.funnel_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  event text not null,
  properties jsonb not null default '{}'::jsonb,
  client_ts timestamptz,
  created_at timestamptz not null default now()
);
alter table public.funnel_events enable row level security;
-- 無任何 client policy：只有 service role（Edge）可寫，查詢走 Management API。
create index funnel_events_user_event_idx on public.funnel_events (user_id, event, created_at);
```

**Steps:** 寫檔 → 本機 PG smoke（照 shared-agent-rules 的 smoke 慣例）→ 用 targeted 程序 apply 到 prod → **回讀驗證表存在** → migration 帳本記版本 → Commit。載入 `supabase:supabase-postgres-best-practices` skill 後再動筆。

### Task 7: Edge `submit-feedback` 加 `kind:"funnel"` 分支

**Files:**
- Create: `supabase/functions/submit-feedback/funnel_utils.ts`（`buildFunnelRow(userId, event)`：事件名 enum 白名單＋properties 鍵白名單＋長度上限，違規丟 null → 400）
- Modify: `supabase/functions/submit-feedback/index.ts`（照 `kind:"outcome"` 分支的形狀，`:186` 附近加分支，insert `funnel_events`）
- Test: `supabase/functions/tests/submit_feedback_funnel_test.ts`（Deno：合法事件 200／字典外事件 400／白名單外鍵被剝除／超長截斷）

**Steps:** Deno 測試先紅後綠 → Commit。**記住 AI 鍵盤案教訓：Deno 綠只驗 TS 層——本案 SQL 層無 validator trigger，但任何 server 端白名單都要跟 Task 5 字典逐字對齊，改字典必同批改兩層。**

### Task 8: client `FunnelTracker`

**Files:**
- Create: `lib/core/services/funnel_tracker.dart`＋provider（照抄 `CoachingOutcomeUploader` 的 seam 設計：invoker 可注入、fire-and-forget、吞一切錯誤、絕不 block UI）
- Test: `test/unit/core/funnel_tracker_test.dart`（wire payload 白名單、非 2xx 不 throw、invoker 炸掉不 throw）

**Step 5: Commit**：`埋點：FunnelTracker best-effort 上傳封裝`

### Task 9: 打點＋隱私揭露＋收尾

1. 依 Task 5 字典在各位置打點（onboarding／首頁入口／app.dart 鍵盤／分析與練習完成 hook，once-flag 用 SharedPreferences key `funnel_once_<event>`）。widget 測試各補一條「動作觸發 tracker 一次」。
2. **隱私揭露**：設定頁 AI 隱私頁補「去識別化使用事件」一行；`docs/` 對應文件同 commit 更新（policy change 必帶 docs）。
3. `flutter analyze`＋全部相關測試綠。
4. **跨模型審查 gate**：codex:rescue 對抗式審（重點：白名單雙層一致性、RLS、migration 可回滾、絕不 block UI）。APPROVED 才進 5。
5. **先驗 migration 已在 prod**（Task 6 已做，回讀再確認一次）→ push main → Edge 自動部署 → 用 Supabase Management API 抽查 `funnel_events` 有新 row 進來（自己走一次 onboarding 流程或打一發測試事件）。

---

## 批 2｜onboarding 一頁問卷＋首頁起步清單（純 client）

### Task 10: 種子邏輯改合併式（先修地基）

**Files:**
- Modify: `lib/features/onboarding/presentation/screens/onboarding_screen.dart`
- Test: `test/widget/features/onboarding/onboarding_profile_seed_test.dart`（擴充）

現況 `_seedProfileFromBranchAnswer` 在 profile 非空時整個跳過。改成單一合併種子：`_completeOnboardingTo` 收攏問卷選擇＋分流答案，**一次** `UserProfile.create(interactionStyle: 問卷, practiceGoals: 問卷, notes: 分流轉寫, ...)`，仍然只在既有 profile `isEmpty` 時寫入、失敗靜默、略過不寫。

**Step 1 失敗測試**：問卷有選＋答「有」→ 一筆 save 同時帶 style/goals/notes；問卷略過 → 只帶 notes；既有非空 profile → 零 save（原測試保留）。

**Step 5: Commit**：`onboarding：種子改單次合併寫入`

### Task 11: 問卷頁（新第 4 頁，分流頁前）

**Files:**
- Create: `lib/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart`
- Modify: `onboarding_screen.dart`（頁序：welcome / analyze-demo / styles-demo / **問卷** / privacy / 分流；`itemCount`、指示點、既有測試的頁序常數全部跟著 +1）
- Test: `test/widget/features/onboarding/onboarding_questionnaire_test.dart`

**設計**：標題「30 秒，讓建議更像你」；互動風格 5 chip 單選＋練習目標 chip 最多選 2（第 3 顆點了換掉最舊的或直接不給選，選後者——簡單）；不選任何東西也能按「下一步」＝略過。選擇存在 `_OnboardingScreenState` 欄位，**本頁不寫 Hive**，統一由 Task 10 的合併種子寫。chips 先試 `ProfileChipSection<T>`，佈局不合身就頁內自建輕量 chip，**不改共用元件**。

**Step 1 失敗測試**：頁面渲染 5+5 chips；目標選第 3 顆無效；選擇後翻到分流頁答題 → save payload 帶對應 enum。**既有 5 頁測試（branching/ai_privacy/demo_preview/proof）頁序全部更新，跑綠。**

**Step 5: Commit**：`onboarding：新增一頁輕量問卷（風格＋目標，可略過）`

### Task 12: 起步清單卡

**Files:**
- Create: `lib/features/partner/presentation/widgets/getting_started_checklist.dart`
- Modify: `partner_list_screen.dart`（掛在 QuotaStrip 之下、入口列之上；空態兩顆 CTA 保留不動——CTA 是路、清單是進度）
- Test: `test/widget/features/partner/getting_started_checklist_test.dart`

**四項與訊號**：
1. 填 30 秒關於我 → `userProfileControllerProvider` 非 null 且 `!isEmpty`；未完成點擊 → `context.push('/profile/about-me')`
2. 完成第一次分析或第一局練習 → `analysisHistoryEventsProvider.isNotEmpty || practiceTemperatureTrendProvider 非空`（二擇一即勾）
3. 開啟跟進提醒 → `FollowUpOptInStore.read()` granted（經 provider seam 讀，不直接 new）
4. 設定鍵盤 → `OnboardingService.isKeyboardCompletedSync`；**`defaultTargetPlatform != iOS` 時整項不顯示**（foundation 顯式 import！）

全四項（iOS）或前三項（非 iOS）完成 → 整卡 `SizedBox.shrink()`，不留殘骸。每項打勾態變化打 `checklist_item_done`。

**Step 1 失敗測試**：四種完成度組合的渲染；Android 隱藏鍵盤項；全完成消失；未完成項點擊導航正確。

**Step 5: Commit**：`首頁：起步清單卡（四項訊號驅動，完成即消失）`

### Task 13: 批 2 收尾

1. 全 repo `flutter analyze`＋onboarding/partner/user_profile 測試全綠。
2. 視覺 proof：onboarding 六頁重拍（沿用 `onboarding_conversion_proof_test.dart`，頁序改掉）＋首頁含清單卡兩態，傳 Eric。
3. 批 2 純 client、低風險：單審即可（要不要 codex 過一眼由當時判斷，預設不用）。
4. Push main → 盯 CI 兩條到綠。

### Task 14: 全案收尾

- 回報格式照 AGENTS.md（commit/push 態、Edge/migration 態、exact-SHA build 結果、Eric 真機要驗清單、刻意不做清單）。
- Eric 真機驗：額度小條（免費帳號）、兩入口導航、問卷→關於我回讀、清單逐項打勾與消失、funnel_events 有資料（我用 Management API 抽查後附證據）。
- 埋點跑滿一週後才回頭看漏斗數字，別隔天就下結論。

---

## 邊界與不做

- 全域教練 (b)、訪客模式、Tier 3 三項（報告分頁上鎖／付費牆感官／Splash）：**不在本計畫**，等 Eric 拍板另案。
- T2-7 撤案（理由見拍板紀錄）。
- 不引入第三方 analytics SDK；埋點只走自建通道，不動 `PrivacyInfo.xcprivacy` 的第三方清單（自家 server 上傳的揭露照案 1 批 3 前例處理）。
