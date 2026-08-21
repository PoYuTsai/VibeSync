# Android 首次公開上架需求規格（Frozen Spec v1）

> 日期：2026-08-21（Asia/Taipei）
> 狀態：**需求已由 Eric 於 2026-08-21 明確凍結；仍禁止依本文件直接開始實作**
> Roundtable：Eric（產品／外部決策）＋ CC / Fable 5（code owner）＋ Codex（協調者、main reviewer）
> 工作編號：`w-969031a5-dd4a-486d-a1f9-d28d765c794e`
> 後續執行更新（2026-08-22）：Eric 已在獨立指示中授權分段實作與 Play onboarding；本文件本身仍不構成未來 runtime、Console、付費、push、部署或送審的持續授權。
> iOS 基線：iOS 1.0.1 仍在開發新功能，尚未宣告 submission candidate，因此 `BASE-01` 尚未釘住；候選版形成時只對新增差異做一次受控對帳，material 變更才更新受影響規格／計畫。

## 1. 本輪邊界

本輪只做：

- 盤點現有 iOS 1.0.1 與 Android 狀態。
- 定義 Android 首次公開版的共同基線、平台差異、上架條件與測試閘門。
- 切分未來實作、外部設定、驗收與審查任務。
- 一次只請 Eric 決定一個會改變方向的問題。

本輪在 2026-08-21 進行 roundtable 時沒有授權：

- 修改 Flutter、Android、Supabase、CI/CD 或網站執行碼。
- 建立／修改 Play Console、RevenueCat、Google Cloud 或 GitHub Secrets。
- 產生或上傳簽名金鑰、AAB、APK。
- 購買測試服務、推送、部署或送審。

Eric 後續明確放行的任務可依其當次範圍執行；這不改變 Frozen Spec 的產品基線，也不會把單次授權擴張成其餘切片或外部動作的 blanket authorization。

## 2. 發布目標與「同步」定義

Android 首次公開版應與 **iOS 1.0.1 最終送審 build** 共用同一套產品承諾，而不是要求兩個平台每個 OS 細節完全相同。

### 2.1 共同產品承諾

- 相同帳號可跨平台取回 server 端資料與付費權益。
- Coach 1:1、開場救星／新話題、對話分析、Practice、學習專區、作戰板等共同功能，行為與額度規則一致。
- Starter／Essential 的方案能力、quota 與資料刪除語意一致。
- Android 與 iOS 採同一價格策略：台灣目標售價、方案價值與季繳折扣邏輯一致；海外只容許商店匯率、稅金與合法價格級距造成的正常差異，不做平台歧視定價。
- 同一 Supabase／RevenueCat App User ID 的有效付費權益跨平台生效；某商店已有有效訂閱時，另一商店不得再引導重複購買。
- 訂閱來源只在實際相關時顯示：新 Android／免費用戶只看到 Google Play；App Store 訂閱者在 Android 先看到「權益已啟用」，只有訂閱詳情／管理操作才標示原購買商店。
- Android 測試發現的共用 bug，修在 shared code 並同時回歸 Android 與 iOS。
- Android 測試提出的 UI/UX 想法，只有 Eric 接受且屬於首發必要範圍時才納入；否則進下一版 backlog，避免測試期無限長大。

### 2.2 基線凍結規則

目前 iOS 1.0.1 還在 dogfood，所以 Android 可以先規格化與開發準備，但共同基線不能永遠指向移動中的 `main`。

1. Eric 認定 iOS 1.0.1 submission candidate 後，以該 exact SHA／tag 作為 Android 功能基線。
2. iOS 送審前發現的 shared P0/P1：兩邊一起修、一起回歸，再更新基線。
3. iOS 已送審後，Android 才發現 shared P0/P1：另做 release 決策；不能偷偷改掉已送審 binary。必要時撤回 iOS 重送，否則 Android 先修並排入 iOS 1.0.2。
4. 非阻斷性的 feature／UI/UX 優化：預設延後到下一個雙平台共同版本。

2026-08-22 執行註記：iOS 1.0.1 仍在向前開發，因此現在不為每個 iOS commit 反覆改寫本規格。Eric 宣告 submission candidate 後，才以 exact SHA／tag 執行一次 delta review：shared 首發功能與 P0／P1 納入 Android；iOS-only 差異明記平台例外；非必要優化預設留到下一個共同版本。

Eric 已決定 iOS 1.0.1 在送審前就納入共同的 18+ 年齡閘門，以及隱私政策／商店文字由 17+ → 18+ 的對齊；因此 submission candidate 必須包含這組 shared 變更，不能先用舊的 17+ 契約送審。

因此，「同步」代表同一個產品契約與 shared 修正回流，不代表兩個 Store 必須同一天、同 build number 上線。

## 3. 功能 parity 矩陣

| 能力 | 分類 | Android 首發要求 |
|---|---|---|
| Email 登入／註冊、帳號資料 | shared | 必須可用，資料與 iOS 同帳號一致 |
| 18+ 存取限制 | shared＋Store gate | **全平台只服務 18+。** Android 啟用 Play Restrict Minor Access，App 內另有中立年齡閘門；未滿 18 歲不得建立／使用核心帳號 |
| Google 登入 | shared | Android 必須顯示且 callback 可完成；iOS 建立的 Google 帳號要能登入 |
| Apple 登入帳號可攜性 | shared＋Android 平台流程 | **首發支援。** Android 主要登入仍是 Google／Email；另提供「已有 iPhone VibeSync 帳號」的次要 Apple web-flow 入口，讓 Apple-only／Hide My Email 使用者回到同一 Supabase user |
| Coach 1:1 | shared | 主要路徑、串流、quota、錯誤處理一致 |
| 開場救星／新話題 | shared | 產出、收藏／紀錄與額度一致 |
| 對話分析＋OCR／圖片匯入 | shared＋平台適配 | 分析結果一致；Android photo picker、權限、低記憶體情境另驗 |
| Practice／抽卡／音效 | shared | 核心玩法一致；返回鍵、音效焦點另驗 |
| 學習專區／測驗 | shared | 內容與進度一致 |
| 作戰板／分析紀錄 | shared | server 資料一致；本機 cache 行為安全 |
| 48h 跟進通知 | shared outcome＋平台適配 | Android 通知權限、排程與實際顯示要真機驗證 |
| Starter／Essential 訂閱 | shared entitlement＋不同商店 | 權益相同；iOS 走 App Store、Android 走 Google Play Billing；任一商店有效訂閱都解鎖同一帳號的跨平台權益，且不得重複購買 |
| 管理／恢復訂閱 | shared outcome＋來源感知 | 新 Android／Google Play 訂閱者不出現 Apple 文案；只有實際 `APP_STORE` 訂閱者才顯示 App Store 來源並導向原商店管理，反方向同理 |
| AI 內容回報 | shared | 所有生成式輸出提供站內「回報不當內容」；iOS 同步受益 |
| 帳號刪除 | shared＋外部網頁 | App 內刪除保留；另提供 Play Console 可填的外部刪除入口 |
| AI 鍵盤 | shared product outcome＋平台原生實作 | **首發必做。** 第一目標與 iOS 相同：VibeSync 鍵盤顯示期間截圖，鍵盤自動偵測、裁切並分析；須先通過 Android API／Play 權限可行性閘門。只有該閘門以證據確認不可行時，才啟用 Eric 已核可的手動 Photo Picker／Sharesheet fallback，AI 鍵盤與 Android 上架仍保留 |

## 4. 現況盤點

### 4.1 已有且可保留

- Android scaffold 已存在，`applicationId`／Firebase package 目前是 `com.vibesync.app`。
- Flutter 3.47.0 目前對應 `minSdk 24`、`targetSdk 36`；可安裝下限約 Android 7，且已符合 2026-08-31 起新送件需 target API 36 的規則。
- exact SHA `875b1d08e81e1ddf8dc2021e855b1a0eaf6cee01` 的 GitHub `Build & Distribute` 已成功編出 release APK 並上傳 Firebase App Distribution：<https://github.com/PoYuTsai/VibeSync/actions/runs/32391986794>。
- 共用 Flutter 功能大多沒有硬鎖 iOS；iOS 鍵盤在 onboarding、settings、getting-started 等入口已有平台 guard。
- `flutter_local_notifications 18.0.1` 的 library manifest 已宣告 `POST_NOTIFICATIONS`。這不是目前已證實的缺碼，但仍要在 Android 13+ 真機驗證合併 manifest 與實際授權。
- RevenueCat webhook 的 tier 判斷目前以 product ID 內的 `starter`／`essential` 判斷，概念上可跨 Store；但只有 App Store 測試資料，不能直接視為 Play 已完成。

### 4.2 已證實的 P0 blocker

1. **App 可能編得過但啟動不了**
   `AndroidManifest.xml` 用 `.MainActivity`，會依 namespace 尋找 `com.vibesync.app.MainActivity`；實際 Kotlin package 是 `com.vibesync.vibesync`。必須先對齊並用安裝／啟動 smoke 證明。

2. **Play release signing 沒接通**
   release workflow 會產生 `key.properties`，但 `android/app/build.gradle.kts` 沒讀它，release build 仍指定 debug signing。現有 APK 編譯成功不等於 Play 可接受的簽名 AAB。

3. **Android 訂閱目前被停用，且 key fallback 會跨平台誤用**
   `RevenueCatService` 在 Android 直接 return；環境 key 驗證只接受 `appl_`，最後還有 Apple key fallback；Android workflow 也注入 iOS key。Android paywall、購買、restore 與管理訂閱尚未成立。啟用 Android 後必須改為 iOS 僅接受 `appl_`、Android 僅接受 `goog_`，缺值或 prefix 錯誤一律 fail closed。

4. **Play 商品契約未定義**
   client 只有 iOS 商品 ID 清單，fallback 又會依 title／description 做模糊搜尋；Google Play 的 subscription／base plan 識別方式尚未鎖定。建立 Play 商品前必須先凍結 product ID、base plan ID、RevenueCat package 與 server tier mapping。

5. **社群登入在 Android 被隱藏／callback 契約不完整**
   login UI 只在 iOS 顯示 Google／Apple。Manifest 已有 `com.poyutsai.vibesync://login-callback` 的 MainActivity deep link，但仍缺 `flutter_web_auth_2` 要求的 `CallbackActivity`，且既有 scheme、CallbackActivity 與 Supabase redirect allowlist 尚未三方對齊。Apple Android web flow 也尚未配置。

6. **訂閱 UX 與管理入口仍是無條件 Apple 專用**
   paywall、restore、刪除帳號提醒、管理訂閱 URL 有大量 Apple ID／App Store 文案。Android 預設必須是 Google Play 語意，但跨平台帳號若確有 App Store 訂閱，仍要條件式顯示正確來源與管理方式；shared 文案不能只依目前 OS 猜購買商店。

7. **AI 內容回報未覆蓋所有生成面**
   現有 thumbs feedback 不等於清楚的「回報冒犯／不當 AI 內容」。Google 要求能在 App 內回報，不可只導去 email。Coach、分析、Opener／新話題、Practice 等所有生成輸出都要覆蓋。

8. **Play 政策資料與 18+ enforcement 不完整**
   尚缺可填入 Play Console 的外部帳號刪除 URL、Android Data safety 對照、App access reviewer 說明、內容分級／目標年齡、AI 內容聲明與 Store 素材包。Eric 已決定全平台 18+，但目前隱私政策仍寫 17+，App 內也未找到實際年齡閘門；只填高年齡分級不等於阻擋未成年。

9. **Android backup 邊界未定義**
   manifest 尚未明確限制 Android Auto Backup／data extraction。VibeSync 有加密 Hive、secure storage、對話與圖片等敏感資料；需先定義哪些資料禁止備份／轉機，以及無法解密時不得 crash 或殘留半套資料。

10. **release workflow 有 iOS 假設耦合**
    Android release 路徑仍使用 iOS RevenueCat key，production preflight 也包含 iOS／keyboard 假設。Android AAB 的必要條件必須獨立且可驗證。

11. **Android AI 鍵盤的自動截圖路徑尚未證明可行／可上架**
   Eric 已決定首發第一目標要求與 iOS 相同的自動截圖體驗。Android IME 必須另寫 `InputMethodService`；Android 14 的標準截圖 callback 屬於 Activity，而 VibeSync 鍵盤是 Service。若改以 MediaStore／相簿監聽取得別的 App 截圖，可能需要 Google Play 限制的廣泛圖片權限。這不是預先取消需求，而是實作前必須完成的硬 feasibility／policy gate；若證明不可行，已決定降級為手動選圖／分享而不取消 AI 鍵盤或 Android 上架。

12. **目前單列訂閱資料無法安全承載 App Store＋Play 並存**
   `subscriptions.user_id` 是唯一列；RevenueCat webhook 會用新事件覆寫同列的 `store`／`tier`／`expires_at`，而 `sync-subscription` 又不可靠寫入購買來源。若同帳號歷史上有兩店訂閱，較短的 Play 到期事件可能把仍有效的 App Store 權益降成 Free，反方向亦然。`BILL-07` 的 per-store 狀態與 migration 是跨店共享、來源感知文案及雙訂防護的硬前置。

### 4.3 P1 品質缺口

- App label 目前是小寫 `vibesync`。
- Android 專屬測試很少；目前只有少數測試覆蓋「Android 不顯示鍵盤入口」。
- 尚未證明 API 24 低階裝置、API 33+ 通知／圖片、API 36 edge-to-edge／返回行為。
- 尚未證明相機／相簿 OCR、大字體、深色模式、窄螢幕、背景恢復、網路切換與低記憶體。
- CI 有 Android APK build 證據，但沒有「已安裝且成功啟動」與 Play Billing sandbox 證據。

### 4.4 GitHub Actions secrets 唯讀盤點

2026-08-21 只以 GitHub 回傳的 **secret 名稱與 `updatedAt`** 對帳；GitHub 不會回傳既有 secret 的內容，本輪也沒有修改、下載、重建或輪替任何 secret。

| 用途 | 現存名稱 | 唯讀證據與判定 |
|---|---|---|
| Android upload signing | `ANDROID_KEYSTORE`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` | 四組皆存在，最後更新於 2026-02-27 UTC。**只證明已設定，不證明 keystore、alias 與密碼仍互相匹配**；先走 `SEC-01` 驗證，不因 Eric 忘記內容就直接重建 |
| Google Play API／Fastlane | `PLAY_STORE_CONFIG_JSON` | 存在，最後更新於 2026-02-27 UTC。尚未證明 service account 仍有效、權限最小且已綁定預定的 `com.vibesync.app` |
| Firebase Android distribution | `FIREBASE_ANDROID_APP_ID`、`FIREBASE_SERVICE_ACCOUNT` | 皆存在；exact-SHA workflow 已在 2026-08-21 前成功上傳 Android APK，是當時可用的實際證據，正式 Play 路徑仍要另驗 |
| 共用 production build | `SUPABASE_PROD_URL`、`SUPABASE_PROD_ANON_KEY`、`SENTRY_DSN` | 皆存在，且目前 workflow 有引用；不在規格階段讀值或重設 |
| Android RevenueCat | 未見明確的 `REVENUECAT_ANDROID_API_KEY`；另有用途未確認的 `REVENUECAT_PROD_KEY` | **不能把泛用舊名稱猜成 Android public SDK key。** 現有 Android workflow 仍注入 `REVENUECAT_IOS_API_KEY`，須在 `BILL-02` 定義平台別設定並核對 RevenueCat dashboard 後再決定 secret 名稱／輪替 |

結論：現階段不需要 Eric 回想或交出任何密碼。保留現有 secrets；到實作階段先用不洩密的 fingerprint、CI signing gate 與 API 權限檢查驗證，只有確認失效或來源不明到無法安全採用時，才另行請 Eric 授權重建／輪替。

## 5. Google Play 外部前置（Eric 執行，Codex 白話逐步帶）

任何付費或 Console mutation 都要再次取得 Eric 明確授權；以下只是未來順序。

1. **已決定：使用 Personal 個人開發者帳號**
   Eric 目前沒有可用的公司／商號，因此不為規避測試門檻臨時建立 Organization 帳號。依 2023-11-13 後新個人帳號規則，規劃 12 人連續 14 天封閉測試；4 位台灣朋友可計入 12 人，付費測試社群只作穩定 build 之後的補人備援。Google 現行文件允許 Personal 日後在完成公司、網站、D-U-N-S 與新 payment profile 驗證後轉 Organization。
2. **🟡 Google Play 開發者帳號已建立，身分審核中（2026-08-22）**
   `VibeSync AI Studio` Personal 帳戶已建立並完成約 US$25 的一次性註冊付款；正式文件已提交 Google 驗證。身分審核完成後再驗證聯絡電話，期間不重複送件。
3. **✅ 裝置驗證已完成（2026-08-22）**
   已使用非 root、Android 15、僅連 Wi-Fi 的實體手機完成 Play Console device verification；SIM 卡不是這項驗證的必要條件。
4. **已決定：保留 package ID `com.vibesync.app`**
   Firebase Android app 與既有 CI 也使用此 ID；建立 Play App、簽名與商品時都以此為唯一識別。第一次上傳後不再更換同一 App 的 package name。
5. **建立 upload key 與備份方案**
   本機產生 upload keystore，密碼進密碼管理器，keystore 至少兩處受控備份；只把必要 secret 放 GitHub，不把 keystore／密碼 commit。啟用 Play App Signing。
6. **建立 App 並先走 Internal testing**
   上傳第一個可啟動、正確簽名、package 已凍結的 AAB。不要直接開封閉 14 天計時。
7. **先凍結商品契約，再建 Play 商品**
   Android 採與 iOS 相同價格策略：台灣 Starter 月繳目標 NT$590、Essential 月繳目標 NT$1,290；季繳在建立商品當下以 App Store live price 對齊，不能抄舊文件。完成 `BILL-01` 後才建立 subscription／base plan；再把 Play app、service credentials、商品與 Android public SDK key 接入同一 RevenueCat project／entitlement 契約。海外價格可由商店依匯率、稅金與當地 price pattern 產生，但發布前要檢查異常價差；首發另依 `DEC-09` 在 Monetization setup 明確停用 subscription pause。
8. **Internal track 驗證 Billing**
   加 license testers，以 Play 安裝來源測試購買、restore、升級、降級、取消、退款／billing issue。Sideload APK 或單純 emulator 假資料不能取代這關。
9. **完成政策、18+ 限制與商店資料**
   Target audience 只選 18+ 並啟用 Restrict Minor Access；Data safety、IARC 內容分級、AI 內容、App access、廣告聲明、隱私政策、外部刪除 URL、icon、feature graphic、手機截圖、短／長描述都與實際 App 一致；若 Android 鍵盤採廣泛圖片權限，另需完成 Photo and Video Permissions declaration 並通過 Google 審查。
10. **先找真實台灣朋友，再補人數**
    4 位朋友可算在 12 人內；穩定 build 完成後才啟動封閉測試。Testers Community Pro 只作補門檻備援，不保證 Google 核准、不交帳密，也不能取代真實回饋與持續使用證據。
11. **封閉測試 12 人 × 連續 14 天**
    僅適用新的 Personal 帳號；以 Play Console 當時顯示為準。期間允許修 bug，但維持功能凍結並保存版本、回饋、修正與測試紀錄。
12. **申請 Production access，通過後才安排公開送審**。

官方依據：

- [新個人帳號的 12 人／14 天規則](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Personal 與 Organization 帳號型態、D-U-N-S](https://support.google.com/googleplay/android-developer/answer/13634885)
- [Personal 轉 Organization 的現行流程](https://support.google.com/googleplay/android-developer/answer/16260648)
- [Android 實體裝置驗證](https://support.google.com/googleplay/android-developer/answer/14316361)
- [target API 規則](https://developer.android.com/google/play/requirements/target-sdk)

## 6. 未來任務切分

標籤：`shared`＝兩平台共同；`android-only`＝Android 平台；`backend`＝Supabase／資料；`external`＝Eric 的 Console／憑證／網站動作；`legal`＝須做官方政策／法律適用性查核，不代表本規格提供法律意見。

### 6.1 需求凍結前

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| DEC-01 ✅ | P0 | 帳號型態：**Personal**（Eric 目前無可用公司／商號） | Eric | 無 | 已接受新個人帳號的 12 人連續 14 天封閉測試路徑 |
| DEC-02 ✅ | P0 | Android 首發**必做 AI 鍵盤**，目標包含與 iOS 相同的自動截圖偵測／分析 | Eric | 無 | 不以手動 Photo Picker／Sharesheet 當作需求等價替代 |
| DEC-02F ✅ | P0 | 若 OS／Play 證明 exact 自動截圖不可行：改用手動 Photo Picker／Sharesheet，保留 AI 鍵盤並繼續 Android 上架 | Eric | KEY-00 證據 | fallback 已預先核可，但只有 KEY-00 以可重現證據失敗後才能啟用；不得為省工預先降級 |
| DEC-03 ✅ | P0 | 凍結 package ID：**保留 `com.vibesync.app`** | Eric | DEC-01 | 已書面決定；Play、Firebase、簽名與 RevenueCat 後續設定都以此 ID 對齊 |
| DEC-04 ✅ | P0 | Apple-only 帳號首發可登入 Android；Apple 為既有 iPhone 帳號的次要入口 | Eric | 無 | Google／Email 是 Android 主要選項；Apple web flow 必須回到同一 Supabase user，不建立重複帳號 |
| DEC-05 ✅ | P0 | **全平台僅限 18+**；未成年不得使用核心服務 | Eric | 官方政策盤點 | Android Play 限制、App 內 gate、iOS／Android Store、隱私政策與條款全部一致 |
| DEC-06 ✅ | P0 | 跨商店共享付費權益並阻止重複訂閱；管理入口依實際購買來源顯示 | Eric | DEC-04 | Android-only／免費用戶完全不見 Apple；有效 App Store 訂閱者在 Android 直接取得權益，只有詳情／管理才標示原商店；反方向同理 |
| DEC-07 ✅ | P0 | Android 與 iOS 採相同價格策略 | Eric | DEC-06 | 台灣目標售價與季繳折扣語意一致；海外僅容許匯率、稅金與商店 price pattern 的合理差異，不另做 Android 高低價 |
| DEC-08 ✅ | P0 | iOS 1.0.1 送審前就完成 shared 18+ gate 與 17+ → 18+ 文字對齊 | Eric | DEC-05 | 不接受先送舊契約再等 iOS 1.0.2；submission candidate 含 AGE-01 的 iOS 路徑與隱私／Store 對齊 |
| DEC-09 ✅ | P0 | Android 首發停用 Google Play subscription pause | Eric | DEC-06 | Play Console 的 Pause 明確設為 Disabled；取消、續訂、升降級照常；grace period／account hold 是付款失敗恢復機制，與自願暫停不同，仍須正確處理 |
| DEC-10 ✅ | P0 | KEY-00 feasibility prototype 最多投入 3 個實際工作日 | Eric | DEC-02、DEC-02F | 「工作日」只計實際投入，不計等待裝置／帳號／審查；到期停止無限探索並交 Codex 審證據。達門檻才通過；有失敗證據才啟用 KEY-FB；若仍不確定，回 Eric 決定，不以逾時假裝技術不可行。只有一項具體且接近完成的驗證時，Codex 可提議一次至多 1 個工作日延長，仍需 Eric 同意 |
| DEC-11 ✅ | P0 | 正式凍結 Android 首發需求與驗收契約 | Eric | DEC-01～DEC-10 | Frozen Spec v1 成為後續 implementation plan 的唯一需求基線；任何 material scope 變更須由 Eric 明確 reopen／replan；凍結本身不授權寫碼、prototype、Console、付費、push、部署或送審 |
| BASE-01 | P0 | 釘住 iOS 1.0.1 submission exact SHA／tag | Eric＋CC | iOS dogfood 收斂、AGE-01、SAFE-04 | Android baseline 可重現，且已包含 DEC-08；後續變更有分類規則 |
| BILL-01 | P0 | 凍結 Play product／base-plan／RC package／tier mapping | CC，Codex review | DEC-03、DEC-06、DEC-07 | 四方案 exact mapping、台灣 live price 對帳、regional price review、升降級 replacement mode、跨店策略與 server exact mapping 都有表格與測試案例；dashboard 實值核對前不得猜 entitlement／key |

### 6.1A Play／RevenueCat 技術契約提案

以下 ID 是 CC 第二輪提案、經 Codex 依 Google／RevenueCat 現行規則修正後的**首選契約**。本輪不會建立商品；`BILL-01` 必須先以 RevenueCat dashboard 與 App Store live 商品做唯讀核對，確認沒有既有衝突後才凍結。特別是 code 目前使用的 entitlement `premium` 只是候選值，不代表 dashboard 已證實存在。

| 方案 | Play subscription ID | Base plan ID | RevenueCat product identifier | offering／RC package | Entitlement 候選 | Server tier |
|---|---|---|---|---|---|---|
| Starter 月繳 | `vibesync_starter` | `monthly` | `vibesync_starter:monthly` | `default`／`starter_monthly` | `premium`（待核） | `starter` |
| Starter 季繳 | `vibesync_starter` | `quarterly` | `vibesync_starter:quarterly` | `default`／`starter_quarterly` | `premium`（待核） | `starter` |
| Essential 月繳 | `vibesync_essential` | `monthly` | `vibesync_essential:monthly` | `default`／`essential_monthly` | `premium`（待核） | `essential` |
| Essential 季繳 | `vibesync_essential` | `quarterly` | `vibesync_essential:quarterly` | `default`／`essential_quarterly` | `premium`（待核） | `essential` |

Replacement mode 的預設契約：

- Starter → Essential：`CHARGE_PRORATED_PRICE`，立即升級並按剩餘期間補差價。
- Essential → Starter：`DEFERRED`，到下次續訂才降級，避免已付低價但 server 仍保留高權益。
- 同一 tier 的 monthly ↔ quarterly：`WITHOUT_PRORATION`，權益等級不變，新價格在下次帳單日收取。這裡不採 CC 原提案的 `DEFERRED`，因為 Google 對同一 subscription 內 base plan 切換目前只支援 `CHARGE_FULL_PRICE` 或 `WITHOUT_PRORATION`。
- UI 必須在確認前顯示「何時生效、何時扣多少」；實際收費以 Play purchase sheet 為準。
- Google Play subscription pause：首發明確設為 `Disabled`。這只移除使用者自願暫停一至三個月的選項，不等於關閉付款失敗後的 grace period／account hold；後兩者仍列入 webhook 與 sandbox 驗收。

### 6.1B 外部 Console／憑證任務

這些任務只是把 §5 的外部步驟變成可追蹤依賴；仍需 Eric 在執行當下另行授權任何付費、Console mutation、credential 建立或上傳。

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| EXT-01 | P0 | Play Personal 帳號註冊、身分與實體裝置驗證 `[external]` | Eric，Codex 白話引導 | DEC-01 | 帳號可用；Android 10+ 非 root 實機驗證完成；未把帳密交給第三方 |
| EXT-02 | P0 | 建立 Play App、凍結 package、啟用 App Signing 並驗證 upload credentials `[external]` | Eric＋CC，Codex review | EXT-01、DEC-03、SEC-01 | Play app 為 `com.vibesync.app`；upload certificate fingerprint 可核；signed AAB 可被 internal track 接受 |
| EXT-03 | P0 | 同一 RevenueCat project 新增 Android app 並綁 Play service credentials `[external]` | Eric＋CC，Codex review | EXT-02、BILL-01 | package、public SDK key、entitlement 與最小權限 service credentials 均核對；不猜用舊 key |
| EXT-04 | P0 | 建立四組 Play subscription／base plan、價格、pause 設定與 RevenueCat package mapping `[external]` | Eric＋CC，Codex review | EXT-03、BILL-01、DEC-09 | exact ID 與 §6.1A 一致；台灣 live price 對齊 iOS；海外異常價差已檢查；Monetization setup 的 Pause 明確為 Disabled 並留存非敏感設定證據；商品未誤公開 |
| EXT-05 | P0 | 建立 license testers、Internal track 與測試帳號 `[external]` | Eric＋CC | EXT-02、EXT-04、CI-01 | 測試者由 Play 安裝；sandbox 買／restore／換約／取消可重現，正式卡不被誤扣 |
| EXT-06 | P0 | 完成 Play App content、18+、Data safety、App access 與 listing `[external]` | Eric，Codex 白話引導 | SAFE-02、SAFE-03、SAFE-04、SAFE-05、STORE-01、STORE-02 | 每項 Console 答案與實際 App／政策文件一致；未經 REL-01 不送 Production review |

### 6.2 Android 可啟動、可簽名、可登入

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| AND-01 | P0 | 對齊 MainActivity namespace／package `[android-only]` | CC | DEC-03 | API 24、API 36 emulator 安裝後可從 launcher 冷啟動，無 ClassNotFound |
| SEC-01 | P0 | 既有 Android CI secrets 的來源與有效性驗證 `[external]` | Eric＋CC，Codex review | DEC-03 | 不讀出明文；確認現存 upload keystore 四件組、Play service account 與 Firebase credentials 對應 `com.vibesync.app`；以 fingerprint／最小權限與實際 CI gate 驗證；失效才另行取得 Eric 授權重建或輪替 |
| AND-02 | P0 | release signing 接通 `[android-only][external]` | CC＋Eric | DEC-03、SEC-01 | Gradle 在 CI 消費受控 secrets；產物為 Play 接受的 signed AAB；debug key 不得進 release |
| AND-03 | P0 | manifest／label／OAuth CallbackActivity `[android-only]` | CC | AND-01 | brand label 正確；既有 `com.poyutsai.vibesync://login-callback` scheme、`flutter_web_auth_2` CallbackActivity 與 Supabase redirect allowlist 三方對齊並凍結；Google OAuth 可回 App；merged manifest 稽核通過 |
| AND-04 | P0 | 敏感資料 backup／data extraction 規則 `[android-only]` | CC，Codex review | 無 | 對話、圖片、token／key 不被不當備份；重裝／轉機失敗不 crash、不暴露資料 |
| AUTH-01 | P0 | Android 顯示 Google＋Email 並完成 Supabase OAuth `[shared]` | CC | AND-03 | iOS 既有 Google 帳號可登入 Android；取消／失敗／重試都有清楚狀態 |
| AUTH-02 | P0 | 既有 Apple 帳號的 Android web flow `[shared][external]` | CC＋Eric | DEC-04 | 入口文案明示供既有 iPhone 帳號使用；iOS Apple 帳號（含 Hide My Email）登入後維持同一 Supabase user ID；Services ID 與 primary App ID 正確關聯、Supabase client ID 順序與 return URL 可驗證；Apple OAuth secret 有不洩密保存與最長六個月輪替流程 |
| CI-01 | P0 | Android build／install smoke 與 release workflow 解耦 `[android-only]` | CC | AND-01、AND-02 | required gate 能證明 APK/AAB 編譯，至少一條自動或可重現流程證明安裝＋啟動；Android 不依賴 iOS keyboard／key 前置 |

### 6.2A Android AI 鍵盤（首發硬需求）

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| KEY-00 | P0 Gate | 自動截圖偵測／讀取的技術與 Play 政策 feasibility proof `[android-only]` | CC，Codex review | DEC-02、DEC-10 | 先做可獨立於主 App／AND-01 的最小 prototype；最多 3 個實際工作日；emulator 覆蓋 API 34／35／36，實機至少一台 stock Android 14+ 與一台 Samsung One UI 6+，每類 ≥40 次，IME 顯示後跨 App 截圖在 3 秒內成功率 ≥95%，session-bound 且去重；權限白名單逐項對映 Play 政策；不得用 AccessibilityService 規避；若需反覆讓使用者重選「部分照片存取」，即視為 manual fallback，不算 exact flow；到期由 Codex 依證據判定 pass／proven fail／inconclusive，只有 proven fail 才啟用 KEY-FB，inconclusive 回 Eric 決定；至多 1 個工作日的單次延長須有接近完成的具體驗證且另得 Eric 同意 |
| KEY-01 | P0 | Android `InputMethodService`、啟用／設定引導與輸入連線 `[android-only]` | CC | KEY-00 通過 | 使用者可啟用／切換 VibeSync IME；password／PIN／敏感 input type 禁用 AI；候選文字可正確 `commitText`，可切回一般鍵盤 |
| KEY-02 | P0 | IME 認證、owner-bound context、consent 與 privacy purge `[android-only][shared]` | CC，Codex review | KEY-01 | 登入／登出／換帳號不串資料；token、對象快照、同意 receipt 與清除流程可驗證；log 不含聊天內容／token |
| KEY-03 | P0 | 截圖 session floor、MediaStore 監聽、裁切、hash／dedupe 與上傳 `[android-only]` | CC，Codex review | KEY-00、KEY-02 | 只有鍵盤本次顯示後的新截圖會觸發；只取預期圖片；裁掉自家 IME；同張圖／observer 抖動不重複扣費 |
| KEY-04 | P0 | iOS 鍵盤產品契約 parity `[shared]` | CC | KEY-03 | 截圖後自動分析；cue／turnState／uncertainty、三候選、why／effect、voice、換一批、插入、retry／pending replay 與 quota 語意一致 |
| KEY-05 | P0 | Android IME 相容性與 dogfood matrix `[android-only]` | Eric＋CC | KEY-04 | 至少 LINE、Instagram、Messenger／WhatsApp 類文字欄位；API／OEM／直橫向／記憶體回收／網路切換通過；密碼欄永不送 AI |
| KEY-FB | P0 Contingency | 手動 Photo Picker／Sharesheet 截圖入口 `[android-only]` | CC | KEY-00 經 Codex review 判定 exact flow 不可行 | 使用者可明確選擇／分享單張截圖；後續裁切、分析、三候選、quota 與隱私契約維持；Android AI 鍵盤及公開上架不因此取消 |

### 6.3 Play Billing 與跨平台權益

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| BILL-02 | P0 | Android RevenueCat platform key/config `[android-only]` | CC | BILL-01、EXT-03 | iOS 只接受 `appl_`、Android 只接受 `goog_`；缺值／錯 prefix 拒絕初始化並讓 paywall 顯示可理解錯誤，不得 fallback 到另一平台或硬編碼 key；secret 不進 client/log；dashboard 實際 entitlement ID 已核對 |
| BILL-03 | P0 | Play offerings／四方案顯示 `[android-only][external]` | CC＋Eric | BILL-01、BILL-02、EXT-04 | Free／Starter／Essential × 月／季都以 §6.1A exact ID 對到正確本地價格；台灣與 iOS live price／折扣語意對齊，海外價差有審核；Android 停用 title／description 模糊搜尋與繞過 Offerings 的 `purchaseStoreProduct` fallback；缺商品 fail closed |
| BILL-04 | P0 | 購買、restore、升降級、取消／管理訂閱 `[android-only]` | CC | BILL-03、EXT-05、DEC-09 | Internal track sandbox 五條主路徑正確；Starter→Essential 用 `CHARGE_PRORATED_PRICE`、Essential→Starter 用 `DEFERRED`、同 tier 月↔季用 `WITHOUT_PRORATION`；確認畫面清楚顯示生效／扣款時間；管理與取消回原商店；首發 UX 不宣傳或假設 pause 可用 |
| BILL-05 | P0 | webhook／sync-subscription 的 `PLAY_STORE` 與 base plan 測試 `[backend]` | CC，Codex review | BILL-01、DEC-09 | sandbox event 能更新正確的 per-store tier／period／store；fixture 含 product ID 帶／不帶 `:basePlanId`、BILLING_ISSUE／grace、account hold、取消、退款／revocation、各種 expiration reason；雖然首發停用 pause，仍保留 `SUBSCRIPTION_PAUSED`／resume 防禦性 fixture，避免歷史事件或 Console 漂移造成誤授權；pause 中不提前撤權，到期／退款時不延遲撤權；空 snapshot、重播與 stale event 不誤降權 |
| BILL-07 | P0 | per-store 訂閱狀態 schema／migration 與 aggregate entitlement `[backend]` | CC，Codex review | BILL-01、DEC-06 | App Store 與 Play 狀態可同時保存（或有等價的 store-aware authoritative design）；每店事件只更新該店，idempotent／stale 防護成立；aggregate 取所有有效來源中仍應享有的最高權益／最晚有效狀態；既有單列資料有可驗證 backfill／migration；`sync-subscription` 不再遺失或猜購買來源；任一店到期不得覆蓋另一店仍有效權益 |
| BILL-06 | P0 | 跨店 entitlement 與雙訂防護 `[shared]` | CC，Codex review | BILL-04、BILL-05、BILL-07、DEC-06 | 相同 App User ID 跨平台取得有效權益；另一 Store 的購買入口停用並說明已啟用；管理／取消回原商店；原訂閱到期後才開放目前商店購買；若歷史上已雙訂，明示兩筆來源並引導處理，不靜默降權或假裝可代取消 |
| COPY-01 | P0 | 來源感知的訂閱／刪除帳號文案與 URL `[shared]` | CC | BILL-04、BILL-06、BILL-07、SAFE-02 | Android-only／Google Play 狀態無 Apple 誤導；來源只讀 authoritative per-store state；只有 `APP_STORE` 來源才顯示 Apple，只有 `PLAY_STORE` 來源才顯示 Google Play；主要訊息先講權益狀態，商店細節留在訂閱詳情／管理動作 |

### 6.4 政策、資料與 Store 準備

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| SAFE-01 | P0 | 全生成面站內「回報不當內容」 `[shared][backend]` | CC，Codex review | 無 | Coach、分析、Opener／新話題、Practice 等可在 App 內回報；後端可追蹤處理，且資料最小化 |
| SAFE-02 | P0 | 外部帳號刪除入口 `[external][backend]` | Eric＋CC | 現有 delete contract | 公開 URL 可用並填入 Play；能驗證本人、刪除相應資料，不要求交出密碼 |
| SAFE-03 | P0 | Android Data safety／dating／UGC 聲明對照 `[external]` | Eric＋Codex | 資料流盤點 | email／ID、文字／圖片、購買、usage、diagnostics、AI providers、Sentry 與刪除／保留期答案一致；dating／社交與 AI 內容是否觸發額外申報、回報／封鎖能力已有逐題證據 |
| AGE-01 | P0 | 全平台 18+ 中立年齡閘門與 server enforcement `[shared][backend]` | CC，Codex review | DEC-05、DEC-08 | 首次進入核心服務前完成不誘導造假的中立年齡流程；未滿 18 歲 fail closed；登入／登出、換機、重裝、離線與既有帳號不繞過；只保存執行政策所需的最小年齡／receipt 資料，不把完整生日默認當行銷資料；iOS 1.0.1 submission candidate 已包含此路徑 |
| SAFE-04 | P0 | 內容分級、18+／未成年與 AI 聲明 `[external][shared]` | Eric＋CC | DEC-05、DEC-08、AGE-01 | Play target audience 僅 18+ 並啟用 Restrict Minor Access；IARC、iOS／Android listing、onboarding、條款與隱私政策由 17+ 統一為 18+，且 iOS 1.0.1 送審前已與實際 App 行為一致 |
| SAFE-05 | P0 | 發布地區年齡法／Play Age Signals 適用性書面查核 `[external][legal]` | Eric＋Codex | DEC-05、目標發布地區清單 | 依 2026 當時官方資料逐區記錄是否適用、需要哪些 signal／consent／家長流程；Google 明示適用性由 developer 判定，無法可靠判斷時取得合格法律意見；本任務不預先宣稱某州法律必然適用或不適用 |
| STORE-01 | P0 | App access reviewer 帳號與操作說明 `[external]` | Eric | AUTH-01、AUTH-02、AGE-01、BILL-04 | 可重複、跨地區、不靠 OTP；Reviewer 能通過 18+ gate、進核心功能與需要審查的付費狀態 |
| STORE-02 | P1 | Play listing 素材與文案 `[external]` | Eric | KEY-04、BASE-01 | title、短／長描述、icon、feature graphic、手機截圖與實際 Android 鍵盤功能一致；只有 Gate K 通過後才宣傳自動截圖 |

### 6.5 測試與放行

| ID | P | 任務 | Owner | 依賴 | 驗收標準 |
|---|---:|---|---|---|---|
| QA-01 | P0 | Android regression checklist `[shared]` | CC，Codex review | parity 凍結 | 每個共同核心、平台差異、付費、刪除、AI 回報都有 expected result |
| QA-02 | P0 | Emulator matrix | CC | AND／AUTH 基礎完成 | API 24、API 33+、API 36；冷啟動、返回、IME 切換、字體、旋轉／恢復、核心 smoke 通過；自動截圖真實性不以 emulator 單獨放行 |
| QA-03 | P0 | 實體裝置 matrix | Eric＋CC | QA-02、KEY-04 | 舊 Wi-Fi 機跑低階／效能；至少一台 stock Android 14+ 與一台 Samsung One UI 6+ 跑自動截圖、通知與權限；Android 10+ 非 root 機完成帳號驗證；朋友機型開測前先盤點 |
| QA-04 | P0 | Internal Play track／Billing sandbox | Eric＋CC | BILL-04、BILL-05、BILL-06、BILL-07、EXT-05、STORE-01 | Google Play 安裝來源；買／restore／升／降／取消／退款／billing issue 及 per-store aggregate entitlement 證據齊全 |
| QA-05 | P0 | 台灣朋友 dogfood | Eric | QA-04 | 4 位朋友完成核心任務；bug 有 shared／Android-only／idea 分類與處理結果 |
| QA-06 | P0（Personal） | 12 人連續 14 天 closed test | Eric | 穩定 release candidate、EXT-06 | Play Console 門檻達成；測試紀錄可回答 Production access 問卷 |
| REV-01 | P0 | CC code-owner 完整交付包 | CC | 所有 code tasks | exact SHA、變更、測試、已知風險、外部待辦齊全 |
| REV-02 | P0 | Codex independent main review（最多兩輪） | Codex | REV-01 | R2 finding 收斂；未解重大風險交 Eric，不以投票掩蓋 |
| REL-01 | P0 | 公開上架前 Eric go/no-go | Eric | QA、REV、Production access | Eric 明確授權後才可做 Release to App Stores／Play submission |

## 7. 測試梯

1. **Gate 0 — 規格凍結**：本文件的決策題完成；iOS 1.0.1 已納入 18+ shared 對齊，baseline exact SHA／tag 已釘住。
2. **Gate K — Android 自動截圖可行性／政策證明**：KEY-00 standalone prototype 最多投入 3 個實際工作日；API／OEM 實驗矩陣與 Play permission path 經 Codex review，3 秒內成功率與試驗次數達門檻、且不用 AccessibilityService 才算通過。反覆照片重選歸 manual fallback；有可重現的技術／政策失敗才啟用已核可的 KEY-FB。若到期仍 inconclusive，停止探索並回 Eric 決定；只有具體且接近完成的單一驗證，才可另請 Eric 核可一次至多 1 個工作日延長。最終 Play 審查結果仍是 REL-01 殘餘風險，Gate K 不得宣稱保證獲准。
3. **Gate 1 — 可啟動／可簽名**：signed release artifact 可安裝冷啟動，package、backup、OAuth callback 與 CI 正確。
4. **Gate 2 — 模擬器＋自有舊機**：共同核心、18+ gate 與 Android UI 行為通過；Wi-Fi-only 沒問題。
5. **Gate 3 — Play Internal track**：真實 Play 安裝來源、RevenueCat／Billing sandbox、per-store entitlement、Google／Apple 帳號可攜性通過。
6. **Gate 4 — 台灣朋友 dogfood**：重點驗品質；配合 QA-03 至少涵蓋 stock Android 14+、Samsung One UI 6+ 與不同螢幕尺寸，並實測各聊天 App 的 IME 自動截圖流程。
7. **Gate 5 — Personal closed test**：如適用，12 人連續 14 天；功能凍結，只收 release blocker 與必要文案修正。
8. **Gate 6 — 雙審與 Production access**：CC 交付，Codex main review，Eric go/no-go。

舊、無 SIM、只連 Wi-Fi 的 Android 手機可以測：

- Android 7+：可驗基本安裝、效能與核心功能。
- Android 10+、非 root：可用於新個人帳號的 Play 裝置驗證。
- Android 13+：才足以覆蓋較新的通知權限／photo picker 行為。

因此舊手機值得保留，但不能成為唯一實體測試機；可以由 4 位朋友中的新機補齊，不一定立刻買手機。

## 8. Roundtable 對帳結果

CC / Fable 5 與 Codex 一致認定的主 blocker：Android RevenueCat 停用、social login 被 iOS gate 擋住、release signing 未接、Apple-only 訂閱文案、AI 內容回報、外部刪除 URL／Data safety。

Eric 在第二輪需求收斂中推翻「Android v1 不做鍵盤」的建議，選擇首發第一目標為完整自動截圖體驗。此決定優先於 CC／Codex 的原建議；技術與政策不確定性由 KEY-00 提前驗證，不得被包裝成已證實可行。Eric 同時決定：只有 KEY-00 證明 exact flow 不可行時，才降級為手動選圖／分享；AI 鍵盤及 Android 上架繼續。

Eric 已決定保留既有 package ID `com.vibesync.app`。Codex 隨後以唯讀方式確認：Android upload signing 四件組、`PLAY_STORE_CONFIG_JSON`、Firebase Android 與共用 production build secrets 都已存在；這些 metadata 不能證明內容有效，因此採「保留、先驗證、失效才經授權重建」策略。Android 專用 RevenueCat public SDK key 仍未證實存在。

Eric 已接受 Android 首發保留 Apple 帳號可攜性，但不把 Apple 當 Android 新用戶的主要登入方式：Google／Email 為主，Apple 以「已有 iPhone VibeSync 帳號」次要入口提供。這是跨平台帳號 continuity，不是 Google Play 要求；必須驗證 native iOS App ID 與 web Services ID 的關聯能回到同一 Supabase user，並納入 Apple OAuth secret 最長六個月輪替維護。

Eric 已選擇全平台統一 18+。Android 不只填 IARC 高年齡分級，還要把 target audience 設為僅 18+、啟用 Play Restrict Minor Access，並以 App 內中立年齡 gate 補足既有安裝／非 Play 路徑；現行隱私政策的 17+ 必須同步修正。具體驗證方式與最小資料保存由 `AGE-01` 設計，不能以容易繞過的單一「我已滿 18 歲」勾選預先宣告完成。

Eric 已選擇跨商店共享權益並防止雙重訂閱。此決定不是讓所有 Android 用戶看到 Apple：新 Android／免費用戶只看到 Google Play；只有相同帳號確有 App Store 有效訂閱時，Android 才先顯示已啟用權益，並在詳情／管理操作條件式標示 App Store。取消、變更仍由原購買商店處理；原訂閱到期後才開放在目前商店重新訂閱。原規格的「Android 全路徑不得出現 App Store」已修正為來源感知規則。

Eric 已選擇 Android 與 iOS 採同一價格策略。台灣月繳目標沿用 Starter NT$590／Essential NT$1,290；季繳不得依賴目前缺少 exact live price 的舊文件，建立 Play 商品時再與 App Store 當下售價核對。海外由各 Store 依匯率、稅金與當地價格型態產生的合理差異可接受，但不能刻意做平台高低價。

Codex 核對後修正兩點：

- CC 原先把 `POST_NOTIFICATIONS` 列為缺失；鎖定的 `flutter_local_notifications 18.0.1` 已在 library manifest 宣告，故撤銷「一定要補 permission」這個實作需求，保留 merged manifest 與 Android 13+ 真機驗證。
- CC 把帳號型態說成完全不可逆；Google 2026 現行文件已提供 Personal → Organization 流程，但需公司網站、D-U-N-S、新 payment profile／身分驗證並等待同步。仍建議註冊前先選對。

Codex 額外補入：

- `MainActivity` namespace／Kotlin package 不一致，是比「APK 編譯成功」更前面的啟動 blocker。
- Android Auto Backup／data extraction 對敏感本機資料的邊界尚未定義。
- Server 端雖有 store-agnostic 的 tier 雛形，但 `REVENUECAT_IOS_API_KEY` 命名／取數策略與 `PLAY_STORE` fixture 都需要 integration proof，不能只靠 substring 判斷宣告完成。

### 8.1 CC / Fable 5 第二輪 challenge 與 Codex 對帳

CC 第二輪以唯讀方式檢查 Draft R9 與 RevenueCat client、webhook、`sync-subscription`、paywall、manifest，輸出 SHA-256 為 `641e28a198c5f95879c0e902fe34610eabc855b3b63a3d005ce69e49ddea18bc`，未修改專案。Codex 逐項對照現行 source 與官方契約後，接受並落入 R10 的 blocker：

- 現有 `subscriptions` 一人一列會讓不同商店事件互相覆寫；新增 `BILL-07`，並把它列為 BILL-06／COPY-01 硬前置。
- `sync-subscription` 沒有可靠維護購買來源；來源感知 UI 必須讀 per-store authoritative state，不能由目前 OS 或過期欄位猜。
- Android RevenueCat key 要求 `goog_`、iOS 要求 `appl_`；錯值／缺值 fail closed，不能讓 Android 落到 Apple fallback。
- Android 商品只准 exact mapping；停用 title／description 模糊搜尋及繞過 Offerings 的 direct-purchase fallback。
- Play lifecycle fixture 擴充 pause、resume、grace、account hold、refund／revocation、expiration reason、stale／replay，且每個事件只影響原商店狀態。
- OAuth 現況修正為「已有 MainActivity deep link、缺 CallbackActivity 與 redirect allowlist 三方契約」，不是完全沒有 deep link。
- §5 外部步驟新增 EXT-01～EXT-06，避免商品、憑證與 Internal track 成為隱藏依賴。

Codex 沒有照單接受的部分：CC 建議同 tier 月↔季使用 `DEFERRED`；Google 現行文件對同一 subscription 內 base plan 切換只允許 `CHARGE_FULL_PRICE` 或 `WITHOUT_PRORATION`，因此 R10 改採 `WITHOUT_PRORATION`。跨 tier 仍採 Starter→Essential `CHARGE_PRORATED_PRICE`、Essential→Starter `DEFERRED`。

KEY-00 的「部分照片存取＋反覆重選」不再列為 Eric 新分歧：DEC-02 已把 exact flow 定義為自動偵測，反覆手選依定義就是 KEY-FB。Gate K 以可量測門檻收斂，但 prototype 的工作量 timebox 尚待 Eric 決定。

Eric 本輪選擇 DEC-08：iOS 1.0.1 在送審前完成 AGE-01 與 17+ → 18+ 的政策／文字對齊。這會擴大 1.0.1 的送審範圍，但消除一段雙平台契約矛盾；目前仍在 dogfood，尚未送審，是風險最低的納入時點。

Eric 選擇 DEC-09：Android 首發在 Play Console 停用 subscription pause，以縮小第一版 Billing 狀態機與跨店誤授權面。取消、續訂、升降級不受影響；付款失敗的 grace period／account hold 不是「自願暫停」，仍保留並完整測試。即使 Console 設為 Disabled，server 仍要保留 paused／resume 防禦性 fixture，不能把外部設定當成唯一安全邊界。

Eric 選擇 DEC-10：KEY-00 feasibility prototype 最多投入 3 個實際工作日，避免 Android 自動截圖的不確定性無限拖住整條上架 DAG。這個 timebox 不是把「逾時」當成「不可能」：Codex 到期只依證據判定 pass、proven fail 或 inconclusive；inconclusive 必須回 Eric，不得自行降級。若只剩一項明確且接近完成的驗證，Codex 可提議一次至多 1 個工作日延長，但不能自行授權。

Eric 選擇 DEC-11：以上需求、非目標、fallback、任務依賴與驗收標準正式凍結為 **Frozen Spec v1**。`BASE-01` 的 iOS 1.0.1 exact SHA 只能在 submission candidate 形成後補入，它是執行前證據，不會讓凍結狀態失效。若後續出現 material 新需求或改變 DEC-01～DEC-10，必須由 Eric 明確 reopen requirements 並重做受影響的 plan／review；不得在實作中靜默擴張。

## 9. 已凍結決策與後續證據

決策順序：

1. ✅ Play 開發者帳號使用 Personal；規劃 12 人連續 14 天封閉測試。
2. ✅ Android 首發必做 AI 鍵盤，目標含與 iOS 相同的「鍵盤顯示期間截圖 → 自動偵測／分析」，不以手動選圖作等價替代。
3. ✅ 若 KEY-00 證明 exact 自動截圖不可行，降級為手動選圖／分享，但保留 AI 鍵盤並繼續 Android 上架。
4. ✅ 保留 package ID `com.vibesync.app`；既有 Android release secrets 保留並先驗證，不預先重建。
5. ✅ Apple-only 帳號可在 Android 首發登入同一帳號；Google／Email 為主要入口，Apple 為既有 iPhone 用戶的次要入口。
6. ✅ 全平台僅限 18+；Android 啟用 Play Restrict Minor Access 並實作 App 內中立年齡 gate，政策與 Store 全部統一。
7. ✅ iOS 1.0.1 在送審前納入 shared 18+ gate 與 17+ → 18+ 對齊；不延到 iOS 1.0.2。
8. iOS 1.0.1 submission baseline 的 exact SHA／tag（等 Eric 認定 submission candidate 時才能釘住）。
9. ✅ 相同帳號跨商店共享有效付費權益並阻止重複訂閱；管理資訊依真實購買來源條件式顯示。
10. ✅ Android 與 iOS 採同一價格策略；台灣目標售價／折扣語意一致，海外僅接受商店造成的合理差異。
11. ✅ Play／RevenueCat exact ID 與 replacement mode 已有 §6.1A 技術提案；實作前仍須以 dashboard／live product 唯讀核對後由 BILL-01 凍結，不把候選 entitlement 當成已知事實。
12. ✅ Android 首發停用 Google Play subscription pause；取消／續訂／升降級保留，grace period／account hold 照常處理，server 保留 paused／resume 防禦性 fixture。
13. ✅ KEY-00 feasibility prototype 最多 3 個實際工作日；到期由 Codex 依證據判定，inconclusive 回 Eric；一次至多 1 個工作日延長須有具體近完成驗證且另得 Eric 同意。
14. ✅ Eric 已明確凍結 Android 首發需求規格為 Frozen Spec v1；凍結不等於授權 implementation plan、實作、Console 操作、付費、push、部署或送審。

尚待補入但不影響需求凍結的證據：`BASE-01` iOS 1.0.1 submission exact SHA／tag、Dashboard live product／entitlement 核對，以及各 Gate 的執行證據。

後續狀態（2026-08-22）：Eric 已授權 CC 依 Frozen Spec v1 製作 implementation plan，Codex 已完成主審，並另行放行部分實作與 Play onboarding。Personal 帳戶已建立、註冊付款與 Android 實體裝置驗證已完成；身分審核與聯絡電話仍待完成，Play App 尚未建立。未來各 slice、Console mutation、額外付費、push、部署與送審仍保留各自的明確授權閘門。

## 10. 其他官方參考

- [Google Play Billing 政策](https://support.google.com/googleplay/android-developer/answer/9858738)
- [App 內與外部帳號刪除要求](https://support.google.com/googleplay/android-developer/answer/13327111)
- [AI-generated content 政策](https://support.google.com/googleplay/android-developer/answer/13985936)
- [App access／Reviewer credentials](https://support.google.com/googleplay/android-developer/answer/15748846)
- [App content／Data safety 等聲明](https://support.google.com/googleplay/android-developer/answer/9859455)
- [Google Play：Age-Restricted Content and Functionality](https://support.google.com/googleplay/android-developer/answer/16302250)
- [Google Play：18+ target audience／Restrict Minor Access](https://support.google.com/googleplay/android-developer/answer/9867159)
- [Google Play：subscription base plan 與 regional pricing](https://support.google.com/googleplay/android-developer/answer/12124625)
- [Apple：其他平台提供 Sign in with Apple](https://developer.apple.com/sign-in-with-apple/usage-guidelines-for-websites-and-other-platforms/)
- [Supabase：Apple OAuth、Services ID 與 secret 輪替](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [RevenueCat SDK 使用平台別 public key](https://www.revenuecat.com/docs/getting-started/configuring-sdk)
- [RevenueCat：相同 App User ID 的跨平台權益與原商店管理](https://www.revenuecat.com/docs/customers/identifying-customers)
- [RevenueCat Google Play subscription／base plan](https://www.revenuecat.com/docs/getting-started/entitlements/android-products)
- [RevenueCat webhook event types／fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields)
- [RevenueCat：管理升降級與 replacement mode](https://www.revenuecat.com/docs/subscription-guidance/managing-subscriptions)
- [Android Developers：subscription replacement mode 與 lifecycle](https://developer.android.com/google/play/billing/subscriptions)
- [Google Play Console：啟用／停用 subscription pause](https://support.google.com/googleplay/android-developer/answer/140504)
- [Google Play：年齡驗證法與 Age Signals API 說明](https://support.google.com/googleplay/android-developer/answer/16569691)
