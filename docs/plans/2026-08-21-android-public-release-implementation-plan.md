# Android 首次公開上架實作計畫（Reviewed Plan v1）

> 日期：2026-08-21（Asia/Taipei）
> 狀態：**PLAN REVIEWED；Eric 已於後續指示授權分段實作，但本文件不是整份計畫的持續授權**
> Frozen Spec：docs/plans/2026-08-21-android-public-release-roundtable-spec.md
> Frozen Spec SHA-256：1aed17f5e058f64948a418209d1a843dc2f2f9e271817aa070ba51145285134f
> CC / Fable 5 完整草案 SHA-256：d4db99532ce95d2ed0d71410e28a2da52154e20f351452eb37c9ee4cd5fbf238
> 工作編號：w-969031a5-dd4a-486d-a1f9-d28d765c794e
> 角色：Eric＝產品決策與外部動作；CC / Fable 5＝code owner；Codex＝main reviewer

## 0. 這份計畫現在代表什麼

這份文件把 Frozen Spec v1 轉成可執行的工程切片，並已由 Codex 對 CC / Fable 5 草案完成主審修正。

目前只代表：

- 需求、相依、驗收、停止條件與外部閘門已經切清楚。
- 可由 CC 依 Eric 後續放行的切片實作，Codex 依證據 review。
- Eric 可讓 iOS 1.0.1 dogfood 與 Android 準備工作並行，不必等待 iOS 先上架。

本文件本身仍不代表、也不會自動授權：

- 未被 Eric 後續明確放行的 runtime code、prototype、migration、CI 或網站工作。
- 把已完成的單次 Play onboarding 授權擴張成任意修改 Play Console、RevenueCat、Supabase、Apple、Google Cloud 或 GitHub Secrets。
- 未另行放行的建立商品、上傳 AAB／APK、push、部署、production access 或送審。
- 直接以本計畫開始所有切片。每個外部／R3 gate 仍須另有 Eric 明確授權。

若本計畫與 Frozen Spec 衝突，以 Frozen Spec 為準。material scope 變更必須由 Eric 明確 reopen requirements。

### 0.1 執行進度更新（2026-08-22）

- Eric 已於後續指示確認 CC / Fable 5 為 code owner、Codex 為 main reviewer，並採一次交付一個可驗收小 milestone 的節奏。
- Android 工作保留在獨立 worktree／`codex/android-foundation-20260821`；本計畫描述目標與 gate，不取代 branch、exact SHA、測試與 review 證據。
- Slice 2 branch 已推送至 exact SHA `a2a9553132e88d85b3dae555dac0c8f1e5f4ede6`。該 SHA 的 Flutter gate、analyze 與完整測試通過，但 [Android Build & Distribute](https://github.com/PoYuTsai/VibeSync/actions/runs/32495993539) 在 release signing setup 因既有 `ANDROID_KEYSTORE` 不是有效 Base64 而停止，尚未產出 signed APK／AAB、merged manifest 或 API 24／36 install-smoke 證據；因此 Slice 2 仍是 **partial implementation candidate，verification-blocked**，不能稱完成。重新建置前也必須先安全同步較新的 `main` workflow。
- 主審另發現 branch 的自訂 `AuthCallbackDispatcherActivity` 與 Frozen Spec 指定的 `flutter_web_auth_2` `CallbackActivity` 不一致，且連帶加入原屬 Slice 3 的 Email recovery；必須先由 Eric 決定要回到凍結規格，或正式 reopen AND-03／AUTH scope，才可把 AND-03 視為完成。
- standards review 尚有兩個 milestone gate：部分修補 commit 混合多個 concern，需要重整邊界；backup fail-closed 政策必須回寫 `docs/decisions.md`，驗證步驟則應併入既有 launch checklist 或由 ADR 連結。workflow 簽名步驟重複、Android contract test 過度集中與 callback raw strings 散落，列為合併前的可維護性整理項。
- `VibeSync AI Studio` Personal 開發者帳戶已建立並完成註冊付款；身分文件正在由 Google 審核，Android 15 實體裝置驗證已完成，聯絡電話仍待身分核准後驗證，Play App 尚未建立。
- iOS 1.0.1 仍在開發新功能，Eric 尚未宣告 submission candidate，故 `BASE-01` 仍未釘住。候選版形成時只做一次受控 delta review，再更新受影響的 spec／plan 與 Android 基線。

## 1. Codex 主審後的必要修正

以下修正已併入本版，取代 CC 草案中的對應內容：

1. 決策 ID 已按 Frozen Spec 的真實語意重新對映；package、Apple continuity、18+、跨店權益、價格、iOS 時點、KEY-00 時限與凍結決策不再錯位。
2. iOS baseline 正確順序是：完成 AGE-01 與 SAFE-04 → iOS dogfood → Eric 宣告 submission candidate → 釘住 BASE-01 exact SHA／tag → Eric 手動送審。不能送審後才補 SHA。
3. SAFE-01 與 SAFE-02 是首發共同安全工作，但不是 Frozen Spec 指定的 iOS 1.0.1 baseline 硬阻擋；除非實作時發現與 AGE-01／SAFE-04 有不可分割的 code coupling。
4. KEY-00 不依賴 Play 帳號 EXT-01；它依賴的是實際可用的兩類真機。Gate K emulator 固定 API 34／35／36，不用 API 24／33 取代。
5. MainActivity 必須成為 com.vibesync.app.MainActivity；不能只改 Manifest 去配合目前錯置的 com.vibesync.vibesync package。
6. BILL-07 不得把「最高 tier」與「最晚 expiry」分別取最大後拼成一筆權益；這會憑空延長 Essential。每個商店來源、tier 與 expiry 必須獨立保存，再以指定時間點的有效來源計算權益。
7. dual-write 期間的 legacy subscriptions row 必須由 aggregate 結果重算，不能讓最新單一商店事件直接覆寫，否則舊 client 仍會被跨店事件誤降權。
8. 來源不明的 legacy row 不得猜成 App Store 或 Play。優先以 authoritative RevenueCat snapshot 對帳；仍無法確認時，保留安全的 legacy aggregate，標記待人工驗證。
9. Play lifecycle fixtures 已補齊 base plan ID 帶／不帶冒號、pause／resume、防禦性狀態、grace、account hold、refund／revocation、expiration reason、stale、replay 與 empty snapshot。
10. closed test 更新 build 本身不會自動重算 14 天；真正要守住的是符合資格的 tester 持續 opted-in 與 Console 當下規則。只有人數／持續資格中斷或 Console 明示時，才按實際狀態重算。
11. Android backup 驗證不依賴已淘汰的 adb backup；以 merged manifest、data extraction／backup rules 與受支援的重裝／還原／轉機實機路徑驗證。
12. EXT-01～EXT-06、credential、production migration、push、deploy、Build & Distribute、付費與送審都保持獨立授權。

## 2. 執行模型與關鍵路徑

### 2.1 可以並行的第一批

在 Eric 另行授權實作後，以下三條可並行，但各自獨立交付與 review：

- 路徑 A：Slice 1 的 iOS 18+ submission baseline。
- 路徑 B：Slice 2 的 Android foundation。
- 路徑 K：Slice 0 的 Android screenshot feasibility proof；前提是兩類真機可借到。

EXT-01 已由 Eric 另行啟動：帳戶建立與裝置驗證已完成，身分／聯絡電話仍在流程中；它不是 Gate K 的硬前置，剩餘外部步驟也不能由本計畫自動啟動。

### 2.2 四條 critical path

**Critical Path A — iOS 1.0.1 baseline**

AGE-01＋SAFE-04 → iOS dogfood → Eric 宣告 submission candidate → BASE-01 exact SHA／tag → Eric 手動 App Store submission

**Critical Path K — Android AI 鍵盤**

KEY-00 evidence → Codex 判定 pass／proven fail／inconclusive → pass 才做 KEY-01～KEY-05；proven fail 才做 KEY-FB；inconclusive 回 Eric

**Critical Path B — 跨店訂閱**

BILL-01＋唯讀證據 → BILL-07 expand／backfill／dual-write／cutover → BILL-02～BILL-05 → BILL-06＋COPY-01 → QA-04

**Critical Path R — Google Play**

foundation＋auth＋billing＋keyboard＋policy → Internal track → 4 位朋友 dogfood → 12 人連續 14 天 closed test → Codex final review → Eric go／no-go

## 3. 實作切片

### Slice 0 — Gate K：自動截圖 feasibility／Play policy proof

- Frozen IDs：KEY-00。
- 約束決策：DEC-02、DEC-02F、DEC-10。
- Owner／review：CC 實驗與整理證據；Codex 判定結果；Eric 只處理延長或 inconclusive。
- 前置：可使用一台 stock Android 14+ 與一台 Samsung One UI 6+；不要求先完成 EXT-01 或 AND-01。
- 隔離方式：使用 throwaway worktree／獨立 prototype module；不合併到正式 branch，不依賴主 App 可啟動。
- 實驗內容：
  1. 最小 InputMethodService 顯示期間，在其他 App 觸發 screenshot。
  2. 驗證候選 API／MediaStore 路徑、讀取時機、權限、session floor、hash 與 dedupe。
  3. 明確列出需要的每一項 Android permission，逐項對照當時 Play 官方政策。
  4. 禁止 AccessibilityService；不得用它繞過 screenshot／圖片權限限制。
  5. 若每次或反覆需要使用者重選「部分照片存取」，歸類為 manual fallback，不算 exact flow。
- 測試矩陣：
  - emulator：API 34、35、36。
  - physical：stock Android 14+、Samsung One UI 6+。
  - 每一類至少 40 次。
  - IME 顯示後跨 App screenshot 在 3 秒內偵測成功率至少 95%。
  - 只接受本次 IME session 之後的新 screenshot，同圖不得重複觸發／扣費。
- 證據包：逐日實際投入帳、裝置／OS、成功與失敗原始計數、p50／p95 latency、錄影、權限畫面、政策連結、失敗可重現步驟、隱私風險與三選一建議。
- 時限：最多 3 個實際工作日；等待裝置／帳號／外部回覆不計入。只有一項具體且接近完成的驗證，Codex 才可提議一次最多 1 日延長，且仍須 Eric 另行同意。
- Exit：
  - pass：全部量化門檻與 policy path 通過，開放 Slice 7。
  - proven fail：有可重現技術或政策阻擋，開放 KEY-FB。
  - inconclusive：停止探索，交 Eric 決定，不得自行視為失敗或改 scope。
- Stop／rollback：第 3 個實際工作日到期即停；prototype 永不合流；任何敏感資料或廣泛權限風險未釐清即不得 pass。
- Eric gate：借用／安排兩類真機；延長 1 日；inconclusive 裁決。三者都要另行授權。

### Slice 1 — iOS 1.0.1 shared 18+ baseline 與共同安全工作

- Frozen IDs：AGE-01、SAFE-04、BASE-01；SAFE-01、SAFE-02 可平行完成。
- 約束決策：DEC-05、DEC-08。
- Owner／review：CC code owner；Codex review；Eric dogfood 與 submission candidate 決定。
- iOS baseline 硬路徑：
  1. AGE-01：中立 18+ gate、最小化 receipt、登入／登出／換機／重裝／離線／既有帳號 bypass 防護。
  2. server enforcement：直接呼叫核心 API 也不能繞過；client／server rollout 必須有舊版本相容與停止方案。
  3. SAFE-04：App、onboarding、隱私、條款、iOS／Android listing 契約由 17+ 統一為 18+。
  4. iOS regression＋dogfood 通過。
  5. Eric 宣告 submission candidate 後，才記錄 BASE-01 exact SHA／tag。
  6. App Store submission 始終由 Eric 手動執行。
- 平行但非 BASE-01 硬阻擋：
  - SAFE-01：Coach、分析、Opener／新話題、Practice 全部生成面提供站內不當內容回報，後端可追蹤且資料最小化。
  - SAFE-02：App 內連結到公開帳號刪除入口；外部頁面與 Play Console 填寫另有 Eric gate。
- Likely modules：onboarding／auth routing、age receipt model、核心 Edge authorization、policy resources、各 AI output widget、report endpoint、settings。
- Atomic commits：age schema／server compatibility、client gate、enforcement activation、18+ 文案、AI report、delete link 分離；不得把 migration、Edge、UI 混成一個 concern。
- Tests／evidence：
  - 新舊帳號、deep link、換機、重裝、offline、API 直呼 bypass matrix。
  - server 與 widget tests；完整 iOS regression，尤其 keyboard contract。
  - 17+ 殘留文字掃描；隱私／條款 URL 與 App 顯示對照。
  - exact SHA dogfood build 與 Eric submission-candidate 紀錄。
- Stop／rollback：任何合法成年既有用戶被誤鎖、未成年可繞過、舊版 client 被意外全面破壞，均停止 candidate 並修正；不得以永久關閉 server enforcement 假裝完成。
- Eric gate：dogfood 驗收、submission candidate 宣告、App Store listing 更新與手動 submission；SAFE-02 公開 URL。

### Slice 2 — Android foundation：啟動、簽名、manifest、backup、CI

- Frozen IDs：AND-01、SEC-01、AND-02、AND-03、AND-04、CI-01。
- 約束決策：DEC-03；保留現有 secrets、先驗證、失效才重建。
- Owner／review：CC code owner；Codex review；Eric 只處理失效 secret／Console gate。
- 前置：可在 feature branch 先做；最終 release candidate 必須錨定 BASE-01。SEC-01 先於 AND-02；EXT-02 只在 Play 接受 signed AAB 時需要。
- Atomic work：
  1. AND-01：移動／改正 Kotlin package，使實際 launcher class 為 com.vibesync.app.MainActivity；Manifest 保持對應。
  2. SEC-01：只輸出遮蔽結果與 fingerprint，驗證既有 upload keystore 四件組、Play service account、Firebase credential 的身分與最小權限；不讀回或記錄明文。
  3. AND-02：Gradle release signing 真正讀取 CI 產生的 key.properties；release 禁止 debug certificate；輸出 Play 可接受的 signed AAB。
  4. AND-03：修正品牌 label；凍結 app scheme、flutter_web_auth_2 CallbackActivity、Supabase redirect allowlist 三方契約。
  5. AND-04：定義 allowBackup、dataExtractionRules／backup rules；排除 token、secure storage、加密 Hive key、聊天與圖片等敏感資料。
  6. CI-01：Android build／install-smoke 與 iOS keyboard／iOS RevenueCat key 前置解耦。
- Likely files：android/app/build.gradle.kts、AndroidManifest.xml、android/app/src/main/kotlin/com/vibesync/app/MainActivity.kt、android/app/src/main/res/xml、workflow 與 preflight scripts。
- Tests／evidence：
  - API 24 與 API 36 安裝、launcher cold start、ClassNotFound＝0。
  - merged manifest 檢查；deep link callback 可重現。
  - apksigner certificate 證據確認非 debug；AAB 簽名與 package 對帳。
  - backup rules 靜態檢查，加上受支援的重裝／還原／轉機路徑；解密失敗不得 crash 或暴露殘留。
  - exact-SHA CI run、artifact 與 install smoke 證據。
- Stop／rollback：任何 existing secret 驗證失敗即停在該 gate，不自行建立／輪替；cold start 或 signing 失敗時只回退相關 atomic commit。
- Eric gate：EXT-02、失效 credential 的重建／輪替、任何 secret mutation。

### Slice 3 — Android Auth：Google／Email 主登入、Apple continuity

- Frozen IDs：AUTH-01、AUTH-02。
- 約束決策：DEC-04。
- 前置：AND-03；Supabase／Google／Apple 設定只能在另行授權後變更。
- Atomic work：
  1. AUTH-01：Android 顯示 Email 與 Google 主登入；完成成功、取消、錯誤、重試與 callback。
  2. AUTH-02：新增次要入口「已有 iPhone VibeSync 帳號」，走 Apple web flow。
  3. 驗證 native iOS App ID、Apple Services ID、Supabase provider client ID 順序、return URL 與 app callback。
  4. Apple client secret 以不洩密方式保存，建立最長六個月輪替 runbook。
- Likely files：environment config、login screen、social auth service、Android callback manifest、auth tests 與整合文件。
- Tests／evidence：
  - iOS 既有 Google 帳號登入 Android，取得同一 auth.users.id。
  - iOS Apple 原生登入與 Android Apple web flow 取得同一 auth.users.id。
  - Hide My Email 實例、取消、拒絕、callback timeout、重試。
  - 入口排序：Android 新用戶只把 Google／Email 視為主選項。
- Stop／rollback：若 Apple web flow 產生第二個 user，立即隱藏 Android Apple 入口並回 Eric；禁止自動合併帳號或資料。
- Eric gate：Supabase Auth provider、redirect allowlist、Apple／Google Console 變更。

### Slice 4 — BILL-07 per-store subscription migration

- Frozen IDs：BILL-07。
- 約束決策：DEC-06、DEC-09。
- 風險：material R2／production migration R3；production 操作前必須完成 opposite-frontier main review 與 GLM challenge，且需 Eric 對 targeted migration 明確授權。
- 前置證據：現行 subscriptions schema、constraints、indexes、RLS、所有讀寫者、RevenueCat App User ID 契約與 legacy store 欄位可靠度。
- Target design：
  1. additive 新 per-store state，每個 user＋store 可獨立保存 product、base plan、tier、status、expiry、event time／id、verification source。
  2. 任一 webhook 事件只更新它所屬的 store，並有 idempotent、stale、out-of-order 防護。
  3. effective entitlement at time t：只看 t 當下仍有效的各來源，再選最高 tier；每個來源 expiry 獨立保留。Essential 到期後，較晚到期的 Starter 可繼續，但不能把 Starter 的較晚 expiry 套到 Essential。
  4. source-aware UI 讀 per-store authoritative state，不由目前 OS 猜來源。
- Migration sequence：
  1. Expand：加新表／欄位、RLS、indexes，不破壞舊 client。
  2. Backfill：可重跑；來源可驗證的 row 才寫入對應 store。
  3. Ambiguous legacy：先以 authoritative RevenueCat snapshot 對帳；仍不明者保留安全 legacy aggregate 並標記未驗證，不捏造來源。
  4. Dual-write：新 per-store row 與 legacy row 同步；legacy row由 aggregate 重算，不由單一最新事件直寫。
  5. Cutover：讀端切到 per-store aggregate，保留短期相容寫入。
  6. Verify：跨店、stale、replay、backfill reconciliation 全綠。
  7. Contract：移除 legacy write 另立 concern、另 review，不與第一次 migration 綁在一起。
  8. Recover：可把讀端切回仍持續由 aggregate 更新的 legacy row；資料修復採 forward-fix，不能假設 destructive rollback。
- Likely files：新 targeted migration、revenuecat-webhook、sync-subscription、subscription repository／providers、migration runbook。
- Tests／evidence：
  - App Store Essential 到期較早＋Play Starter 到期較晚。
  - App Store Starter 到期較晚＋Play Essential 到期較早。
  - 單店到期不得撤掉另一店有效權益。
  - stale、亂序、重播、相同 event id、empty snapshot。
  - backfill 前後計數、未驗證來源清單、RLS 與 legacy／new aggregate 差異查詢。
- Branch／delivery：
  - non-main：只驗證、commit、push branch 與 exact-SHA build；production migration／Edge 保持 pending。
  - main：先完成 reviewed targeted migration 並驗證，再 push 依賴它的 Edge code；永遠禁止 supabase db push。
- Stop／rollback：schema／RLS／舊 client compatibility 未證明就不進 production；aggregate fixture 任一失敗即不 cutover。
- Eric gate：production targeted migration、任何 production Edge／credential 動作。

### Slice 5 — Billing client 與商品契約

- Frozen IDs：BILL-01、BILL-02、BILL-03、BILL-04。
- 約束決策：DEC-03、DEC-07、DEC-09；secrets 的平台 prefix 規則。
- 前置：EXT-03／EXT-04 的 dashboard 唯讀證據；offering 與 entitlement 名稱未核實前不得猜。
- Frozen technical mapping：
  - vibesync_starter:monthly → starter_monthly → Starter。
  - vibesync_starter:quarterly → starter_quarterly → Starter。
  - vibesync_essential:monthly → essential_monthly → Essential。
  - vibesync_essential:quarterly → essential_quarterly → Essential。
  - offering 候選 default、entitlement 候選 premium；兩者必須以 RevenueCat dashboard 實值為準。
- Atomic work：
  1. BILL-02：iOS 只接受 appl_ public SDK key；Android 只接受 goog_。缺值／錯 prefix fail closed；generic REVENUECAT_PROD_KEY 不可猜成 Android key。
  2. BILL-03：Android 只做 exact product／base-plan／package mapping；移除 title／description fuzzy search 與繞過 Offerings 的 direct purchase fallback；缺任一商品 fail closed。
  3. BILL-04：purchase、restore、manage、cancel 與 replacement mode。
  4. Starter→Essential＝CHARGE_PRORATED_PRICE；Essential→Starter＝DEFERRED；同 tier 月↔季＝WITHOUT_PRORATION。
  5. 台灣月價目標 Starter NT$590、Essential NT$1,290；季價以建立當下 App Store live price 對齊；海外只接受 Store 正常匯率／稅／price pattern 差異。
- Likely files：environment config、RevenueCat service、subscription providers、paywall、settings、workflow env injection 與 tests。
- Tests／evidence：
  - key selector 的 iOS／Android／缺值／錯 prefix 矩陣。
  - 四商品逐列 exact mapping；任一缺失時購買入口 fail closed。
  - replacement mode 參數斷言與確認畫面的扣款／生效時間。
  - manage／cancel 必須回原購買商店。
  - dashboard screenshot／export 與 code 常數對表。
- Stop／rollback：dashboard 實值與候選不同時，以 dashboard 為準做單獨變更；四商品不齊或 key 來源不明時不得開 paywall。
- Eric gate：EXT-03、EXT-04、RevenueCat／Play 商品或 secret mutation。

### Slice 6 — Play events、跨店權益、雙訂防護、來源文案

- Frozen IDs：BILL-05、BILL-06、COPY-01。
- 約束決策：DEC-06、DEC-09。
- 前置：BILL-07 cutover 可用；Slice 5 client contract 完成。
- Atomic work：
  1. BILL-05：RevenueCat Play webhook 與 sync-subscription 可靠寫入原始 store／product／base plan，不猜來源。
  2. BILL-06：相同 App User ID 共享有效 entitlement；另一商店已有有效權益時關閉新購買入口並指向原商店管理。
  3. 歷史雙訂時顯示兩筆來源，不靜默降權、不假裝可代取消；原來源到期後才開放目前商店購買。
  4. COPY-01：主要文案先講「權益已啟用」；只有詳情／管理才按 authoritative source 顯示 App Store 或 Google Play。
- Required fixtures：
  - product ID 帶與不帶 :basePlanId。
  - initial purchase、renewal、cancellation、product change。
  - BILLING_ISSUE／grace period、account hold。
  - SUBSCRIPTION_PAUSED、resume 防禦；即使 Console 首發 Pause Disabled 也保留。
  - refund／revocation、所有實際支援的 expiration reasons。
  - stale、out-of-order、replay、duplicate event、empty snapshot。
  - App Store／Play 兩店各 tier／expiry 組合與另一店事件隔離。
- UI tests：免費／僅 Play／僅 App Store／同時兩店／歷史已雙訂；Android 免費用戶不得看到 Apple 文案，反方向同理。
- Stop／rollback：任一跨店 fixture 失敗即不得進 QA-04；若 BILL-07 暫時回切 legacy，Slice 6 讀端同步回到已由 aggregate 維護的 legacy view。
- Eric gate：production Edge delivery 仍依 branch 與 migration 狀態另行處理；本計畫不授權。

### Slice 7 — Android AI keyboard 正式實作

- Frozen IDs：KEY-01、KEY-02、KEY-03、KEY-04、KEY-05；KEY-FB 僅條件分支。
- 約束決策：DEC-02、DEC-02F、DEC-10。
- 前置：KEY-00 必須由 Codex 判定 pass；在 pass 前不得開正式 KEY-01～KEY-05 runtime work。AUTH 與 foundation 必須可提供 owner-bound session。
- Atomic work：
  1. KEY-01：InputMethodService、啟用／設定引導、切換鍵盤、commitText；password／PIN／敏感 input type 禁止 AI。
  2. KEY-02：auth、owner context、consent receipt、換帳號／登出 purge；log 不含聊天、圖片或 token。
  3. KEY-03：session floor、Gate K 證實的 screenshot observer、裁除自家 IME、hash／dedupe、上傳與 quota exactly-once。
  4. KEY-04：與 iOS 的 cue、turnState、uncertainty、三候選、why／effect、voice、換一批、插入、retry／pending replay、quota 契約對表。
  5. KEY-05：LINE、Instagram、Messenger／WhatsApp 類、直橫向、多視窗、記憶體回收、網路切換與 OEM dogfood。
- KEY-FB：只有 KEY-00 proven fail 才可另立 Photo Picker／Sharesheet commits；後段分析、三候選、quota、隱私與 AI keyboard 本體仍保留。inconclusive 不得啟用。
- Likely files：android/app/src/main/kotlin/com/vibesync/app/ime、IME resources／Manifest、shared keyboard contract、必要的 Edge schema adapters 與 tests。
- Tests／evidence：
  - 零 AccessibilityService；零原始全螢幕 screenshot 持久保存。
  - 登出／換帳號／cache purge；backup 排除覆蓋 IME。
  - password／敏感欄位永不送 AI。
  - screenshot→crop→dedupe→analyze→insert E2E 錄影與 quota 證據。
  - iOS keyboard regression 與 shared contract diff＝0。
- Stop／rollback：privacy、owner isolation、quota exactly-once 任一不過就關閉 dogfood gate；正式實作若遇到 Gate K 未涵蓋的 material 技術／政策障礙，回 Gate K 重判，不私下切 fallback。
- Eric gate：KEY-FB 只受既定 proven-fail 條件開啟；真機 dogfood 協調與任何新增廣泛權限申報另行授權。

### Slice 8 — Store／政策資料與 QA

- Frozen IDs：SAFE-03、SAFE-05、STORE-01、STORE-02、QA-01、QA-02、QA-03、QA-04；SAFE-02／SAFE-04 的外部申報在此收斂。
- 約束決策：DEC-01、DEC-05、DEC-07、DEC-09。
- 前置：相對應 runtime slices 已完成；EXT-05 才能做 QA-04；EXT-06 尚不能送 production review。
- Atomic work：
  1. SAFE-03：Data safety／dating／UGC／AI 資料流逐題對照實作、第三方、保留與刪除。
  2. SAFE-05：依目標發布地區與 2026 當時官方資料查核年齡法／Play Age Signals；無法可靠判斷時標示需法律意見。
  3. STORE-01：建立可重複、跨地區、不靠 OTP 的 reviewer 路徑與操作說明；帳號由 Eric 建。
  4. STORE-02：18+、實際 Android 功能、價格與鍵盤能力一致的 listing 素材；Gate K 未 pass 前不得宣傳自動 screenshot。
  5. QA-01：核心功能、平台差異、18+、auth、billing、刪除、AI 回報與 keyboard expected results。
  6. QA-02：一般回歸 emulator API 24、33+、36；Gate K 的 API 34／35／36 證據另計。
  7. QA-03：舊 Wi-Fi 手機做低階／效能；stock Android 14+ 與 Samsung One UI 6+ 做 screenshot、通知、權限與 IME。
  8. QA-04：只能用 Google Play Internal track 安裝來源做 billing sandbox；sideload／mock 不算。
- QA-04 必測：四方案顯示、買、restore、升級、降級、同 tier 週期切換、取消、billing issue、grace、account hold、refund／revocation、兩店 aggregate 與 manage-original-store。
- Evidence：每項 pass／fail、裝置與 build exact SHA、錄影／截圖、Play order→RevenueCat event→webhook state→client entitlement 對照。
- Stop／rollback：申報與實作不一致時，修實作或修申報後重驗，禁止虛報；billing 任一路徑失敗退回 Slice 4～6。
- Eric gate：EXT-05、EXT-06、reviewer account、Console App content／listing、可能的測試裝置安排。

### Slice 9 — Dogfood、closed test、雙審與上架決策

- Frozen IDs：QA-05、QA-06、REV-01、REV-02、REL-01。
- 約束決策：DEC-01、DEC-11。
- 前置：stable release candidate；Slice 8 blockers＝0；EXT-06 的必填資料已備妥。
- Sequence：
  1. QA-05：4 位台灣朋友完成核心任務；回饋分 shared bug／Android-only bug／idea。
  2. blocker 修好並重驗後，才啟動 QA-06。
  3. QA-06：Personal 帳號依 Play Console 當時規則維持至少 12 位 tester 連續 opted-in 14 天；4 位朋友可計入。
  4. paid tester community 只在 stable build 後補缺口；不交帳密、不視為核准保證，也不能取代真實回饋。
  5. 測試期間可以更新 build；更新本身不自動重算 14 天。持續資格、人數與 Console 顯示才是判定來源。
  6. REV-01：CC 交 exact SHA、變更摘要、測試索引、外部狀態、已知風險與 rollback。
  7. REV-02：Codex independent main review，最多兩輪；重大未解 finding 交 Eric。
  8. REL-01：只有 Eric 明確 go／no-go 後，才可申請 production access 或進行手動 Play submission。
- Stop／rollback：tester count／eligibility 中斷時依 Console 實際狀態處理；shared P0／P1 依 Frozen Spec baseline 規則決定 iOS 回流；nonblocking idea 預設進下一共同版本。
- Eric gate：tester 邀請、任何付費 tester 服務、production access、Release to App Stores／Play submission 全部另行授權。

## 4. 外部工作包（不因本計畫落檔而啟動）

2026-08-22 進度：EXT-01 部分完成——Personal 帳戶已建立、註冊付款與 Android 實體裝置驗證已完成；身分審核與聯絡電話待完成。EXT-02～EXT-06 尚未因這份計畫而自動啟動。

| ID | 最早可並行時點 | 完成證據 | 授權邊界 |
|---|---|---|---|
| EXT-01 | 可與 Slice 0～2 平行；不是 Gate K 前置 | Personal 帳號可用、Android 10+ 非 root 實機驗證 | 註冊、付費與 Console 操作須 Eric 另授權 |
| EXT-02 | SEC-01 後 | Play App＝com.vibesync.app、App Signing、upload fingerprint、AAB 被 Internal track 接受 | 建 App／App Signing／credential mutation 須另授權 |
| EXT-03 | EXT-02＋BILL-01 後 | 同一 RC project 的 Android app、Play credential、goog_ public key、entitlement 對帳 | RevenueCat／Play Console 操作須另授權 |
| EXT-04 | EXT-03 後 | 四組 product／base plan、台灣價格、regional review、Pause Disabled、RC package 對映 | 建商品／價格／pause 設定須另授權 |
| EXT-05 | CI-01＋EXT-04 後 | license testers、Internal track、測試帳號與 sandbox 安裝 | tester／track／帳號 mutation 須另授權 |
| EXT-06 | SAFE／STORE tasks 完成後 | 18+、Data safety、App access、listing 與實作一致 | 不含 production review；送審仍由 REL-01 控制 |

## 5. Delivery 與 review 規則

- 所有 Git index、Flutter build／test 與 artifacts 走 WSL；先用 .agent/environment.json 的 versioned resolver／doctor。
- 一個 commit 只處理一個 concern，繁中 commit message，不 blanket-stage Eric 的其他變更。
- 實作、驗證、commit、review、push、migration、Edge delivery、Build & Distribute、dogfood、Console 與送審是不同狀態。
- material R2 由獨立 reviewer 審；production migration／其他 R3 仍需 Eric 當下授權。
- BILL-07 production migration 前必須有 opposite-frontier review＋GLM challenge；最多兩輪 reconcile，不用投票掩蓋 finding。
- 非 main task branch：可驗證、commit、push該 branch、跑 exact-SHA Build & Distribute；不做 production migration／Edge。
- main：migration-dependent Edge push 前，先依 targeted migration procedure 完成並驗證 migration；永遠不用 supabase db push。
- Release to App Stores 與 App Store／Play submission 由 Eric 手動；任何一般「ship」字樣都不等於授權。

## 6. Frozen ID coverage

| Frozen IDs | 實作位置 | Exit evidence |
|---|---|---|
| DEC-01 | Slice 8～9 | Personal 12×14 路徑與 Console 證據 |
| DEC-02、DEC-02F | Slice 0、7 | exact flow Gate K；fallback 僅 proven fail |
| DEC-03 | Slice 2、5 | com.vibesync.app、簽名、Play／RC 對帳 |
| DEC-04 | Slice 3 | Apple continuity 回同一 Supabase user |
| DEC-05 | Slice 1、8 | 18+ gate、server enforcement、Store／政策一致 |
| DEC-06 | Slice 4、6 | per-store authoritative state、共享權益與防雙訂 |
| DEC-07 | Slice 5、8 | 台灣價格與 live-price／regional 對帳 |
| DEC-08 | Slice 1 | AGE-01＋SAFE-04 先於 BASE-01 與 iOS submission |
| DEC-09 | Slice 5、6、8 | Pause Disabled＋pause／resume 防禦 fixtures |
| DEC-10 | Slice 0 | 3 個實際工作日、量化 evidence、單次延長 gate |
| DEC-11 | 全計畫、Slice 9 | Frozen Spec 唯一基線；scope change 必須 reopen |
| BASE-01 | Slice 1 | Eric 宣告 candidate 後的 exact SHA／tag |
| BILL-01 | Slice 5 | exact product／base plan／package／tier／replacement mapping |
| EXT-01～EXT-06 | §4、各 slice gate | 每個外部工作包的 Console／credential evidence |
| AND-01、SEC-01、AND-02、AND-03、AND-04、CI-01 | Slice 2 | cold start、masked secret validation、signed AAB、manifest、backup、CI |
| AUTH-01、AUTH-02 | Slice 3 | Google／Email E2E 與 Apple same-user continuity |
| KEY-00 | Slice 0 | Gate K evidence packet＋Codex verdict |
| KEY-01、KEY-02、KEY-03、KEY-04、KEY-05、KEY-FB | Slice 7 | IME／privacy／exact screenshot／parity／dogfood；conditional fallback |
| BILL-02、BILL-03、BILL-04 | Slice 5 | prefix fail-closed、exact offering、sandbox replacement modes |
| BILL-05、BILL-06、BILL-07、COPY-01 | Slice 4、6 | lifecycle fixtures、aggregate、double-sub guard、source-aware UI |
| SAFE-01、SAFE-02 | Slice 1、8 | in-app AI report、公開 deletion URL／連結 |
| SAFE-03、AGE-01、SAFE-04、SAFE-05 | Slice 1、8 | Data safety、18+ enforcement、Store text、legal applicability memo |
| STORE-01、STORE-02 | Slice 8 | reviewer path 與真實 listing 素材 |
| QA-01、QA-02、QA-03、QA-04 | Slice 8 | checklist、emulator、physical device、Internal billing |
| QA-05、QA-06 | Slice 9 | 4 友 dogfood、12 人連續 14 天證據 |
| REV-01、REV-02、REL-01 | Slice 9 | CC packet、Codex 最多兩輪 review、Eric go／no-go |

## 7. 只差證據、不差產品決策的三個 open questions

1. **RevenueCat／Play dashboard**：實際 offering、entitlement、Android public SDK key identity、四商品／base plan、價格與 Pause Disabled 證據。候選值不能當成事實。
2. **現行 subscription 資料面**：完整 schema／RLS／index／讀寫者、legacy store 可靠度，以及可用來校正 ambiguous rows 的 authoritative RevenueCat snapshot。
3. **外部 identity／policy 面**：Apple Services ID 與 iOS App ID／Hide My Email continuity 設定、公開 deletion URL，以及目標發布地區的 age-law／Age Signals 適用性證據。

這三項都是執行前證據包，不會改變 Frozen Spec。若證據顯示既定需求不可安全成立，CC 停止該 slice，由 Codex整理衝突後回 Eric；不得自行改 scope。

## 8. Plan readiness

**判定：PLAN-READY；已獲後續分段執行授權，但不是整份計畫的 blanket authorization。**

- 59 個 Frozen task IDs 已全部映射到 owner、依賴、atomic work、驗收、停止條件與 Eric gate。
- CC / Fable 5 為 code owner；Codex 為 main reviewer。
- 第一批可並行的工程路徑已切清楚；只有 Eric 後續明確放行的 tranche 可啟動，不因本文件存在而自動擴張。
- 建議未來採「一次授權一個可驗收 tranche」，避免 Android、iOS 1.0.1 與 Console 工作互相綁死。
