# Android M6 Gate K：IME screenshot 官方政策與 API 證據

> 研究日期：2026-08-28（Asia/Taipei）
> 範圍：Android API 34／35／36、第三方 `InputMethodService`、跨 App 新 screenshot 的偵測與讀取
> 來源邊界：只採 Android Developers、AOSP／Android 官方規格與 Google Play 官方政策；不採部落格、社群回答或二手摘要
> 狀態：**preliminary evidence only**。這不是 Google Play 預審，也不保證最終上架結果；Gate K 的 `pass`／`proven fail`／`inconclusive` 最終裁決仍由 Codex 在 prototype、exact-SHA 主審與獨立隱私審查完成後作成。

## Preliminary 結論

**`inconclusive`（preliminary）**。

官方文件已足以排除三個看似直接、實際不符合 exact flow 的方案：

1. Android 14 的 screenshot detection callback 只觀察「本 App 的可見 Activity」被截圖，且 callback **不含 screenshot 影像**；它不是第三方 IME 觀察底層 App screenshot 的 API。[Android screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection)、[`Activity.registerScreenCaptureCallback`](https://developer.android.com/reference/android/app/Activity#registerScreenCaptureCallback(java.util.concurrent.Executor,%20android.app.Activity.ScreenCaptureCallback))
2. Photo Picker 與 Android 14 Selected Photos Access 只授權使用者選到的項目；Android 15 的 `QUERY_ARG_LATEST_SELECTION_ONLY` 也只回傳「最近一次選擇中已授權」的項目，不會把日後新產生的 screenshot 自動加入。[Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker)、[Selected Photos Access](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)、[`QUERY_ARG_LATEST_SELECTION_ONLY`](https://developer.android.com/reference/android/provider/MediaStore#QUERY_ARG_LATEST_SELECTION_ONLY)
3. `MediaProjection` 是螢幕內容擷取串流，不是讀取剛保存的 screenshot；target API 34+ 每個 capture session 都必須重新取得使用者同意，因此不能當成無反覆介入的 screenshot-file 觀察器。[Android 14 MediaProjection consent](https://developer.android.com/about/versions/14/behavior-changes-14#media-projection)、[`MediaProjection`](https://developer.android.com/reference/android/media/projection/MediaProjection)

官方文件同時留下兩條**需要 prototype 才能證明**的候選路徑：

- **候選 A：完整圖片庫授權。** 使用者先授予 `READ_MEDIA_IMAGES` 完整存取後，`MediaStore.Images` 會包含 screenshots；`ContentObserver` 可接收 content URI 變更，再查詢並開啟候選 URI。這是 API 層可組合出的技術路徑，但 Google 並未保證 screenshot 專屬事件、一次一個 callback、callback URI 完整性或 3 秒內 OEM propagation；而且 `READ_MEDIA_IMAGES` 受 Play broad-photo 核心功能與 declaration 審查。[MediaStore screenshots 與跨 App 圖片存取](https://developer.android.com/training/data-storage/shared/media)、[`ContentResolver.registerContentObserver`](https://developer.android.com/reference/android/content/ContentResolver#registerContentObserver(android.net.Uri,%20boolean,%20android.database.ContentObserver))、[Play Photo and Video Permissions policy](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)
- **候選 B：一次性、目錄級 SAF 授權。** `ACTION_OPEN_DOCUMENT_TREE` 可讓使用者只授權一個目錄及其子目錄，並可保存 URI grant 跨重開機使用；因此「設定時選一次 Screenshots 目錄，之後只在 IME session 內觀察新檔」在 API 權限模型上是合理候選，而且不需要 `READ_MEDIA_IMAGES`。但官方文件沒有保證 API 34／35／36 各 OEM picker 都會暴露正確 screenshot 目錄，也沒有保證 tree provider 的 change notification 或 3 秒內可讀性；此外，是否符合本專案禁止廣泛檔案存取／背景爬圖的 frozen boundary，仍要由 Gate owner 判定。[SAF directory grant 與限制](https://developer.android.com/training/data-storage/shared/documents-files#grant-access-directory)、[persistable URI grant](https://developer.android.com/training/data-storage/shared/documents-files#persist-permissions)、[Play 允許其他 system picker](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en)

因此，目前既不能判 `pass`（兩條候選都缺 OEM／真機／政策閉環），也不能判 `proven fail`（官方 API 明確留下至少一條完整授權路徑，另有一條最小範圍目錄 grant 候選）。

## 一、API 技術能力

### 1. 路徑對照

| 路徑 | 能否自動看見「之後新產生」的 screenshot | 使用者介入 | API 硬限制 | Gate K preliminary 狀態 |
|---|---|---|---|---|
| `READ_MEDIA_IMAGES` 完整存取 + `MediaStore.Images` + `ContentObserver` | **技術上可能**。Android 把 screenshots 加入 `MediaStore.Images`，完整授權可讀其他來源建立的圖片；observer 可通知 URI 資料改變。[官方依據](https://developer.android.com/training/data-storage/shared/media) | 初次／重新授權時需要 runtime permission；使用者可選完整、部分或拒絕。[官方依據](https://developer.android.com/about/versions/14/changes/partial-photo-video-access) | 沒有 screenshot-only observer；通知旗標是 optional，不能從文件推定一事件一 callback 或固定 latency。[官方依據](https://developer.android.com/reference/android/content/ContentResolver#NOTIFY_INSERT) | 候選；需量測，而且有 Play broad-photo declaration 風險。 |
| `ACTION_OPEN_DOCUMENT_TREE` 指定 screenshot 目錄 + persistable URI | **技術上可能，但未證。** Tree grant 僅涵蓋使用者選定目錄／子目錄，可保存 grant。[官方依據](https://developer.android.com/training/data-storage/shared/documents-files#grant-access-directory) | 理論上設定時選一次目錄；目錄移動、刪除或 grant 被撤銷後需重新授權。[官方依據](https://developer.android.com/training/data-storage/shared/documents-files#persist-permissions) | Android 11+ 禁止選 storage root、SD root、`Download`、`Android/data`、`Android/obb`；官方未保證 OEM screenshot 目錄可選、未保證 provider change event。[官方依據](https://developer.android.com/training/data-storage/shared/documents-files#access-restrictions) | 候選；先由 Gate owner 確認 frozen boundary，再做實機證明。 |
| Photo Picker (`ACTION_PICK_IMAGES`／Activity contract) | **不能自動取得未來新 screenshot。** Picker 只把使用者選定的 URI 授予呼叫 App。[官方依據](https://developer.android.com/training/data-storage/shared/photo-picker) | 每個未授權項目都需使用者選取；可保存已選 URI，但不擴張到日後新檔。[官方依據](https://developer.android.com/training/data-storage/shared/photo-picker#persist-media-file-access) | 預設存取在裝置重啟或 App 停止後結束；persist 也只針對已選 URI。 | 不符合 exact flow；只能是 manual fallback。 |
| `READ_MEDIA_VISUAL_USER_SELECTED` 部分照片存取 | **不能自動取得未來未選 screenshot。** 權限文字明確限定 permission-prompt picker 中使用者選過的圖片／影片。[官方依據](https://developer.android.com/reference/android/Manifest.permission#READ_MEDIA_VISUAL_USER_SELECTED) | 新項目必須重新開 selection UI；官方要求由使用者按 UI 元素才 re-request，避免驚訝。[官方依據](https://developer.android.com/about/versions/14/changes/partial-photo-video-access#reselection) | 宣告 broad media／location permission 時系統會自動把本權限加進 manifest；若 App 未主動 request/處理，`READ_MEDIA_IMAGES` 仍可能暫時回 `PERMISSION_GRANTED`，實際卻只有 selected subset（官方稱 false grant），直到 App 進背景。[官方依據](https://developer.android.com/reference/android/Manifest.permission#READ_MEDIA_VISUAL_USER_SELECTED) | 不符合 exact flow。 |
| Android 14 `Activity.ScreenCaptureCallback` | **不能。** 只在該 App Activity 可見且被截圖時回呼，且不交付圖片。[官方依據](https://developer.android.com/about/versions/14/features/screenshot-detection) | 不需 runtime dialog；`DETECT_SCREEN_CAPTURE` 是 normal permission。[官方依據](https://developer.android.com/reference/android/Manifest.permission#DETECT_SCREEN_CAPTURE) | API 定義在 `Activity`；IME 核心是 `InputMethodService`，底層可見 Activity 屬於另一個 App。[IME 官方架構](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method) | 已由官方 API 契約排除。 |
| Android 15 screen-recording detection | **不能。** 它只通知註冊 UID 自己的 Activity 是否正在 screen recording，既不是 screenshot 事件，也不提供影像。[官方依據](https://developer.android.com/about/versions/15/features#screen-recording-detection) | 無助於讀 screenshot。 | 觀察範圍仍是註冊 process UID 所擁有的 activities。 | 已排除。 |
| `MediaProjection` | **不是相同資料路徑。** 它擷取螢幕串流，不是觀察／讀取使用者保存的 screenshot。[官方依據](https://developer.android.com/reference/android/media/projection/MediaProjection) | target API 34+ 每個 capture session 都要同意，一個 token／instance 只可用一次。[官方依據](https://developer.android.com/about/versions/14/behavior-changes-14#media-projection) | 還需 media-projection foreground service；使用者可撤回，且受 `FLAG_SECURE` 保護內容限制。[官方依據](https://developer.android.com/media/platform/av-capture) | 不符合目前 exact flow；不應拿來繞過 screenshot／圖片權限。 |
| `AccessibilityService` | **技術上能另行擷取 display/window bitmap，但不是 IME 身分附帶的能力。** `takeScreenshot()` 需一個已啟用且宣告 `canTakeScreenshot` 的 AccessibilityService；API 34 的 window 版本遇 secure content 會回明確錯誤。[官方 API](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService#takeScreenshot(int,%20java.util.concurrent.Executor,%20android.accessibilityservice.AccessibilityService.TakeScreenshotCallback)) | 需使用者另行啟用特殊服務與額外 disclosure／declaration。 | Play 禁止用 Accessibility API 繞過 Android 隱私控制，並要求可用時改採窄範圍 API。[官方政策](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en#accessibility) | frozen spec 禁止。 |
| `MANAGE_EXTERNAL_STORAGE` | 不需要，也不應用。 | 特殊 App Access。 | Play 明確要求只在 critical core use case 使用，且對 media-file access／個別檔案選取應用 SAF 或 MediaStore，而不是 All files access。[官方政策](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en) | 禁止。 |

### 2. API 34／35／36 差異

| OS/API | 與本題直接相關的正式行為 | 對 exact flow 的影響 |
|---|---|---|
| Android 14 / API 34 | 新增 Selected Photos Access；target 34+ 的使用者可在 media permission dialog 選「部分照片」。另新增 Activity-scoped screenshot detection，但 callback 不含影像。[Selected Photos Access](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)、[screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection) | 部分授權不能自動讀未來 screenshot；screenshot callback 不能觀察另一 App。完整 `READ_MEDIA_IMAGES` 或一個可用的 SAF tree grant 才仍是候選。 |
| Android 15 / API 35 | 新增 `QUERY_ARG_LATEST_SELECTION_ONLY`，只列最近一次 permission-prompt photo picker 已授權項目；Android 14 搭配 U extension 12 也可能支援。[API reference](https://developer.android.com/reference/android/provider/MediaStore#QUERY_ARG_LATEST_SELECTION_ONLY)、[Android 15 feature](https://developer.android.com/about/versions/15/features#selected-photos-access) | 這是「已選項目」查詢輔助，不是 future screenshot grant；不改變 partial-access 的手動選取硬限制。 |
| Android 16 / API 36 | target 36+ 在 partial-access picker 中會預選「本 App 擁有」的照片，使用者仍可取消；Android 16 另把 `MediaStore.getVersion()` 變成 per-app 值。[target 36 behavior](https://developer.android.com/about/versions/16/behavior-changes-16#app-owned-photos)、[MediaStore version lockdown](https://developer.android.com/about/versions/16/behavior-changes-16#mediastore-version-lockdown) API 36 的 `QUERY_ARG_MEDIA_STANDARD_SORT_ORDER` 可按 `INFERRED_DATE` 排列「已有權限看到」的媒體，但沒有建立新 grant 或 screenshot-specific event。[API 36 `MediaStore` 差異](https://developer.android.com/sdk/api_diff/36/changes/android.provider.MediaStore) | 系統 screenshot 並非 VibeSync 建立，故「app-owned 預選」不會自動授權該 screenshot（這是依 ownership 規則作出的推論）；新排序也只幫助排列已可讀候選。完整授權／SAF 候選仍需 API 36 實測。 |

補充：自 **2026-08-31** 起，Google Play 新 App 與更新需 target API 36（可依官方機制申請延至 2026-11-01）；本研究日是 2026-08-28，因此 API 34／35 是相容性矩陣，production policy baseline 應按 API 36 評估。[Play target API policy](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)

### 3. `MediaStore` 路徑能證明與不能證明的事

官方可證明：

- Android 會掃描 `DCIM/`、`Pictures/` 中的照片與 screenshots，並放進 `MediaStore.Images`。[Android shared media](https://developer.android.com/training/data-storage/shared/media)
- 對 VibeSync 而言，系統建立的 screenshot 不是 VibeSync 自有媒體；讀取其他來源建立的圖片需要相應的 storage permission，API 33+ 是 `READ_MEDIA_IMAGES`。[Android shared media](https://developer.android.com/training/data-storage/shared/media#storage-permission)
- `ContentResolver` 可註冊 observer 接收指定 content URI 的變更，並能以 `openInputStream()` 開啟有權限的 URI。[`ContentResolver`](https://developer.android.com/reference/android/content/ContentResolver)

官方不能證明：

- 沒有公開的「全系統 screenshot saved」專屬 callback／broadcast 契約。
- `ContentObserver` 的 insert／update flags 是 optional；文件不保證 callback 數量、順序、URI 粒度、SystemUI 寫入完成時機或 3 秒 latency。[`NOTIFY_INSERT`](https://developer.android.com/reference/android/content/ContentResolver#NOTIFY_INSERT)
- 公開 [`MediaStore.Images.ImageColumns`](https://developer.android.com/reference/android/provider/MediaStore.Images.ImageColumns) 沒有 `IS_SCREENSHOT` 或等價的 screenshot classifier；API 36 的 [`MediaStore` 公開差異](https://developer.android.com/sdk/api_diff/36/changes/android.provider.MediaStore) 也沒有新增 screenshot event/type。因此 screenshot folder name、`DISPLAY_NAME`、`RELATIVE_PATH`、OEM 手勢來源或多螢幕行為都不是官方定義的跨廠牌 identity；候選辨識必須 fail closed，不能只靠檔名包含 `Screenshot` 就宣稱完成。

### 4. SAF tree notification 能證明與不能證明的事

- `DocumentsProvider` 可以讓 child-directory query 的 cursor 設 notification URI，並在資料改變時以 `notifyChange()` 觸發重新查詢；這是 provider 可支援的泛用機制，不是 screenshot API。[`DocumentsProvider.queryChildDocuments`](https://developer.android.com/reference/android/provider/DocumentsProvider#queryChildDocuments(java.lang.String,%20java.lang.String[],%20android.os.Bundle))
- AOSP 的 `FileSystemProvider` 參考實作確實用 `FileObserver` 監看 `CREATE`、`CLOSE_WRITE`、move、delete 等事件，並對 directory cursor 的 URI 發變更通知；cursor 關閉時 observer 也停止。[AOSP `FileSystemProvider`](https://android.googlesource.com/platform/frameworks/base.git/+/master/core/java/com/android/internal/content/FileSystemProvider.java)
- 上一點是 AOSP 實作證據，不是 API 34／35／36 對所有 OEM `DocumentsProvider` 的相容性承諾。事件可能泛用、重複、早於檔案可安全讀取，且不一定附新 screenshot URI；因此仍需重查 tree、確認檔案完成、去重並量測延遲，不能從官方資料推定可靠即時偵測。[`DocumentsProvider` change-notification contract](https://developer.android.com/reference/android/provider/DocumentsProvider#queryChildDocuments(java.lang.String,%20java.lang.String[],%20android.os.Bundle))

## 二、Google Play 政策

### 1. Photo and Video Permissions

- 所有使用者照片都是 personal and sensitive data。target API 33+ 只有在 system picker 不足以提供 App 的 **core functionality** 時，才可要求 `READ_MEDIA_IMAGES`／`READ_MEDIA_VIDEO`；繼續要求者必須向 Play Console 提交 declaration，證明 broad access 必要性與 picker 為何不足。[Permissions and APIs that access sensitive information](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)
- Play 說明進一步指出：核心功能圍繞 broad photo/video access 的 App 才可使用；自製 picker 並不自動合格；若不符合支援的核心 use case，必須移除 broad media permissions。Google 允許 Android Photo Picker 以外的其他 system picker。[Restricted Permissions minimum-scope guidance](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en)
- 對 VibeSync 的含義：`READ_MEDIA_IMAGES` 路徑**不是政策上已通過**。自動匯入 screenshot 是否屬於整個 App 的核心功能、SAF／picker 是否確實不足、以及審查者是否接受證據，都不是公開文件能預先裁定的；不可把「API 可讀」寫成「Play 會核准」。
- `ACTION_OPEN_DOCUMENT_TREE` 若只授權 screenshot 目錄，避開的是 `READ_MEDIA_IMAGES` 這一項 broad-photo declaration gate；它仍須符合 User Data、透明揭露、最小化與資料安全政策，也不等於 Google Play 預先核可。[Play User Data](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)

### 2. 敏感資料、背景存取與 IME 隱私

- Play 要求 personal/sensitive data 的 access、collection、use、sharing 必須限於使用者合理預期的政策合規功能，使用 runtime permission，安全處理，且不得蒐集超過必要範圍。[Play User Data](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en#personal-sensitive)
- 若資料存取超出合理預期，例如使用者未在主 App UI 中而是在其他 App 使用 IME 時存取，必須在 permission／consent 前提供正常流程內、清楚描述資料種類、用途與分享方式的 prominent disclosure，並取得明確 affirmative consent；隱私政策或商店文案不能取代此揭露。[Prominent Disclosure & Consent](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en#prominent-disclosure)
- Play 把未擁有的相片／SD-card 檔案在使用者未合理預期下傳出列為 spyware 風險示例；因此 prototype 的「不呼叫 AI、不上傳、不保存聊天內容」是必要隔離，但日後若加入 OCR／AI，上傳、留存、刪除與 Data safety 聲明必須另開 R2 隱私審查，不能沿用本 Gate 證據直接放行。[Spyware policy](https://support.google.com/googleplay/android-developer/answer/14745000?hl=en)
- IME 本身能讀取游標附近文字；Android 官方特別要求密碼欄位不可在 IME UI 顯示密碼，也不可把密碼存到裝置。[Create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method#handle-different-input-types)
- 任何 screenshot／screen capture 路徑都必須尊重其他 App 的 `FLAG_SECURE`，不得製造繞道；受保護畫面可能禁止截圖或產生空白影像。[Play Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)、[Android `FLAG_SECURE`](https://developer.android.com/security/fraud-prevention/activities#flag_secure)

### 3. Accessibility API

- 本 Gate 已禁止 `AccessibilityService`；政策上也不能把它當成繞過 media permission／privacy control 的替代品。Play 明文禁止 Accessibility API 繞過 Android 內建安全、隱私控制或通知，並要求可行時使用更窄範圍 API。[Play Accessibility policy](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en#accessibility)
- 非 disability-first 的 App 不能冒稱 `isAccessibilityTool=true`；若仍使用 AccessibilityService，還需 Play declaration、獨立 prominent disclosure、affirmative consent 與 demo video，且是否核准仍由審查決定。[Use of AccessibilityService API](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en)
- API 層要精確分開：`AccessibilityService.takeScreenshot()` 確實能回傳 display bitmap，API 34 另有 window screenshot；但需獨立 AccessibilityService 能力與使用者啟用，不是 `InputMethodService` 自帶權限，且 secure window 會回 `ERROR_TAKE_SCREENSHOT_SECURE_WINDOW`。[Accessibility screenshot API](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService#takeScreenshot(int,%20java.util.concurrent.Executor,%20android.accessibilityservice.AccessibilityService.TakeScreenshotCallback))

## 三、仍需實機證明的未知

1. **完整權限分支：** API 34／35／36 在 full／partial／deny／由 Settings 降級／permission auto-reset 各狀態下，IME 顯示時能否查到並 `openInputStream()` 讀取新 screenshot；partial 狀態應證明 fail closed，而不是誤判 `PERMISSION_GRANTED` compatibility state。[permission compatibility mode](https://developer.android.com/about/versions/14/changes/partial-photo-video-access#compatibility-mode)
2. **MediaStore event 品質：** AOSP emulator、stock Android 14+、Samsung One UI 6+ 的 callback 次數、URI、flags、首次可查詢時間、首次可開啟時間、p50／p95，以及是否在 3 秒內達到 kickoff 的 95% 門檻。官方只保證一般 content change callback，不保證 screenshot SLA。[`ContentResolver`](https://developer.android.com/reference/android/content/ContentResolver)
3. **Screenshot identity：** hardware keys、Quick Settings、OEM 手勢、長截圖／scroll capture、多螢幕、編輯後另存的 metadata 差異；須量測而不能把某個 OEM 的資料夾或檔名當跨平台契約。
4. **SAF tree 可行性：** 各測試裝置能否在 system picker 選到真正承接新 screenshot 的最小目錄；persist grant 在 process death／reboot 後是否仍有效；目錄被移動、刪除、重新建立或 OEM 改路徑時是否安全失敗。[SAF persisted access limitation](https://developer.android.com/training/data-storage/shared/documents-files#persist-permissions)
5. **SAF change detection：** tree provider 是否送可靠 notification；若只能輪詢，限定在可見 IME session、只查 session floor 後的候選是否仍符合 frozen boundary，需 Gate owner 明確裁決。官方沒有給 tree notification SLA。
6. **IME lifecycle：** observer 在 `onStartInputView`／`onFinishInputView` 對應範圍內的存活、process reclaim、旋轉、切換輸入框、切換 IME、螢幕鎖定及 permission UI 往返；不可因 service process 長存而變成背景爬圖。[IME lifecycle](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method#lifecycle)
7. **False positive／dedupe：** session 前舊圖、相機新照片、下載圖片、同一 screenshot 多次 observer 通知、同名／同尺寸圖片、跨 session 重送都必須拒絕或去重；官方沒有 screenshot-specific identity 可直接依賴。
8. **`FLAG_SECURE`：** 在受保護 App 上應沒有可用 screenshot 或只得到空白內容，prototype 必須 fail closed，且不得嘗試替代擷取。[Play `FLAG_SECURE` requirement](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)
9. **Play eligibility：** broad-photo declaration 的核心功能敘述、picker／SAF 不足證據與 reviewer 結果目前都不存在；在不操作 Play Console 的本輪中，這項只能維持 unknown，不能用法律／政策文字自行宣告獲准。

## 四、Prototype 必須產出的具體證據

以下只定義要證明的觀察結果，不是正式產品實作處方：

1. **兩條候選分開量測：**
   - A：`READ_MEDIA_IMAGES` full grant + `MediaStore.Images` observation。
   - B：一次性最小 screenshot-directory SAF tree grant；若 Gate owner 判 frozen boundary 不接受，記錄為 policy/scope rejection，不偷偷改成 background directory crawler。
2. **每個 OS 分支覆蓋：** API 34、35、36 emulator 各至少 40 次；stock Android 14+ 與 Samsung One UI 6+ 各至少 40 次，保留每次原始成功／失敗、裝置／OS、permission state、callback 數、query/open latency、p50／p95。
3. **權限狀態矩陣：** full、partial、deny、partial→full、full→partial、Settings revoke、process death、reboot；任何沒有有效 grant 的狀態都不得讀圖。
4. **事件與內容分開記錄：** observer 收到事件不算成功；只有 session floor 後的正確 screenshot URI 可查、可開、內容 hash 成功且 3 秒內完成才算成功。
5. **負向案例：** session 前 screenshot、IME 隱藏後 screenshot、一般相機照片、下載圖片、同圖重送、同名不同圖、錯目錄、`FLAG_SECURE` 目標 App，全部保留 raw outcome 並 fail closed。
6. **事件來源覆蓋：** hardware key、Quick Settings／系統 UI、Samsung 手勢（若裝置支援）、長截圖；另證明 Android screenshot callback 不會替 IME 取得底層 App 的影像或可用跨 App event。
7. **SAF 特有證據：** picker 畫面與最小所選目錄、grant flags、persist 後重啟、目錄變更、provider notification／無 notification、受控 session-only fallback query 的成本與 false positives。
8. **隱私隔離證據：** manifest permission allowlist；不存在 `AccessibilityService`、`MANAGE_EXTERNAL_STORAGE`；prototype 不含 AI／OCR 網路呼叫、圖片上傳、quota、聊天內容 log 或永久圖片副本；session 結束即釋放內容與 observer。
9. **政策包但不送審：** 保存 permission／disclosure 畫面、使用者明確同意流程、資料最小化與刪除行為、為何 Photo Picker／Selected Photos Access 無法支援 future screenshot 的官方連結；若候選 A 通過技術門檻，再由 Eric 決定是否另行授權 Play Console declaration／正式預審。

## 五、Gate 判定邊界

- **可進入 `pass` 評估**：至少一條候選同時滿足 exact-flow 量化門檻、session／dedupe／fail-closed、frozen permission boundary，且沒有未解的 Play broad-photo／User Data／`FLAG_SECURE` 風險。技術成功本身不等於政策成功。
- **可進入 `proven fail` 評估**：所有允許範圍內候選都出現可重現平台阻擋／未達門檻，或取得明確適用的政策阻擋；不能只因 Play 結果未知就自行視為失敗。
- **維持 `inconclusive`**：技術路徑只有 emulator 成功、SAF scope 未裁決、缺 stock／Samsung 實機、或 broad-photo eligibility 未閉環時，都不得放行 `KEY-01`～`KEY-05`，也不得聲稱 Google Play 會核准。

## 官方來源索引

- Android：[MediaStore shared media](https://developer.android.com/training/data-storage/shared/media)、[Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker)、[Selected Photos Access](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)、[SAF documents/tree access](https://developer.android.com/training/data-storage/shared/documents-files)、[screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection)、[Android 15 features](https://developer.android.com/about/versions/15/features)、[Android 16 target behavior](https://developer.android.com/about/versions/16/behavior-changes-16)、[MediaProjection](https://developer.android.com/about/versions/14/behavior-changes-14#media-projection)、[Accessibility screenshot API](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService#takeScreenshot(int,%20java.util.concurrent.Executor,%20android.accessibilityservice.AccessibilityService.TakeScreenshotCallback))、[IME guide](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)
- AOSP 輔證：[SystemUI screenshot exporter](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/packages/SystemUI/src/com/android/systemui/screenshot/ImageExporter.java)、[`FileSystemProvider` directory observation](https://android.googlesource.com/platform/frameworks/base.git/+/master/core/java/com/android/internal/content/FileSystemProvider.java)
- Google Play：[Permissions and APIs that access sensitive information](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)、[Restricted Permissions minimum-scope guidance](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en)、[User Data](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)、[AccessibilityService API](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en)、[Device and Network Abuse／FLAG_SECURE](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)、[Spyware policy](https://support.google.com/googleplay/android-developer/answer/14745000?hl=en)、[Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
