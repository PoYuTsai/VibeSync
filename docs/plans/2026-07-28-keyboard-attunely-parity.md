# AI 鍵盤進階化實作計畫 — 2026-07-28

狀態：**SHIPPED，待 Eric 出 build 真機 dogfood**

## 背景

參考對手 Attunely 的鍵盤（唯一做得好的功能），把 VibeSync 鍵盤從「複製貼上 →
五種風格 → 插入」提升到「截圖即分析 → 帶理由的三張候選 → 可連續對話」，同時保留
第一版的貼上文字流，並補上我們獨有的教練屬性。

前置修復：`fe2e2206` 修好 `textDocumentProxy.documentIdentifier` 的 nil 橋接
trap（extension 啟動即死、鍵盤從地球儀消失）。本計畫建立在該修復之上。

## 影片證據（對手行為）

- 使用者在聊天輸入框、**鍵盤開著**的狀態下按截圖。
- 面板縮圖的最後一列正好是聊天 App 的輸入列，**沒有鍵盤、沒有他們自己的工具列**
  → 他們把自己鍵盤佔的區塊裁掉才送出。
- 偵測到截圖後**沒有預覽確認步驟**，直接進入生成。
- 結果面板：可捲動分析卡（摘要／意圖／好感度／張力／建議怎麼回）＋三張候選
  （左「回的不好？」、中風格標籤、右藍氣泡）＋底部「換一批」。
- 提示「對方回覆後再截圖，可以繼續對話」「系統會記住對話脈絡」。

## 我們已經有、但沒用到的材料

`keyboard-assist` ready result 已回傳 `cue`(≤120)、`turnState`、`uncertainty`、
`options[3]`（`strategy`/`text`/`why`≤80/`effect`≤60）、`source.*`；request 已支援
`voice.primary/secondary`（五型）。`KeyboardContextEnvelope.partners[]` 含
`effectiveVoice` 已經在 extension 內。compiler 每次產 **6** 個候選，judge 只挑 3 個，
另外 3 個目前直接丟棄。

刻意不做：**好感度分數**。compiler prompt 明文禁止「好感百分比／心理診斷」，
且 Eric 拍板不需要。我們用 `turnState`（該不該回）取代它作為差異化。

## 批次

### B1 截圖裁掉自家鍵盤區（純 Swift）

`KeyboardImagePreprocessor` 目前完全不裁切，會把「聊天＋我們自己的鍵盤」整張送出。

- 問題一：約 45% 像素是自家 UI，浪費 token。
- 問題二：縮到 960/768/640 寬後，聊天文字的有效解析度被稀釋，OCR 品質受害。
- 問題三（正確性）：第二張截圖的下半是**我們自己剛產生的三句候選**，compiler
  可能把它們轉錄成聊天訊息。連續對話一旦啟用必然發生。

作法：`LatestScreenshot` 帶上 `creationDate`（已有）。extension 記錄
`keyboardAppearedAt`；`creationDate >= keyboardAppearedAt` 表示截圖當下鍵盤在畫面上
→ 依 `view.bounds.height / screen.bounds.height` 的比例裁掉圖片底部。否則不裁。

裁切必須在 hash 之前（`KeyboardPreparedImage.sha256` 綁的是實際上傳的 bytes），
縮圖也改顯示裁切後版本。

### B2 拿掉預覽確認，截圖即跑（Swift + Dart + plist + docs）

Eric 拍板：截圖後直接跑，不要預覽與確認。

實作採**最小風險**路徑：不動狀態機的狀態與轉移，只在 `screenshotFound` 成功後由
coordinator 自動連續送出 `previewRequested` 與 `confirmPreviewAndGenerate()`。
`confirmPreviewAndGenerate()` 內既有的「重新讀取最新截圖、比對 assetIdentifier
與 creationDate」競態防護原封保留。

隱私契約同步變更（缺一不可）：

- `ios/Runner/Info.plist`、`ios/VibeSyncKeyboard/Info.plist` 的
  `NSPhotoLibraryUsageDescription`
- `AiDataSharingConsent` 的 `keyboardScreenshotDataDescription` /
  `keyboardScreenshotPurposeText`
- `lib/core/constants/ai_privacy_disclosure.dart`
- `KeyboardSetupScreen` 與 `_PrivacyNotice` 文案
- 受影響的 Dart source test 與 widget test

新的隱私敘述基準：**一次性同意 + 永遠看得到用了哪張圖**，取代原本的逐次確認。

### B3 相簿監聽自動重跑（純 Swift）

現況：extension 沒有 `PHPhotoLibraryChangeObserver`；`detectLatestScreenshot()`
只從 `start()`（`viewWillAppear`）與重試鍵進入，而重試鍵在 `.resultsPreview`
狀態是隱藏的。使用者截第二張時**面板毫無反應**。

作法：註冊 change observer，只在 `.idle` / `.resultsPreview` / `.inserted` /
`.recognitionRejected` 狀態接受重跑，且必須滿足：新的 `assetIdentifier`、
`creationDate` 在 `screenshotRecencyWindow`(180s) 內、且晚於目前這筆。

**扣費風險**：每張新截圖 = 新 requestId = 再扣一次
（`chargeQuota: result.status === "ready" && quota.chargeQuota`）。自動重跑必須
嚴格去重，任何抖動重觸發都是重複扣費。

### B4 priorTurn 連續對話 + 候選禁止清單（Edge + Swift）

同一份資料的兩種用途：連續對話的燃料，以及誤判的防線。

- request 加 `priorTurn: { insertedText: string, cue: string } | null` 與
  `excludedTexts: string[]`（上一輪的三個候選）。
- 只有**同 `documentIdentifier` 且同 owner** 才帶（binding 既有，直接沿用）。
- server 在 normalize 之後比對：任何 `messages[].text` 與 `excludedTexts` 高度相似
  → `recognition_rejected`，**不扣費**。
- 陷阱：使用者可能真的採用了建議並送出，那句話會**合法**出現在我方訊息泡泡。
  B1 裁乾淨後，殘留只可能來自裁切邊界誤差，故比對僅作為保險網；命中時整份作廢
  而非只刪那一則，避免半殘輸入。

### B5 換一批不扣第二次費（Edge + Swift）

judge 目前從 6 個候選挑 3 個，另外 3 個丟棄。改為挑 6 個、分兩批各 3 個且批內
strategy 互異。client 先顯示第一批，「換一批」切第二批，**不再打 API、不再扣費**。

代價：judge 輸出多約 250 tokens；相對於重跑整條含影像的 pipeline 省 90% 以上。
這是相對於對手的明確差異點。

### B6 鍵盤面板改版（純 Swift）

單一面板、兩個輸入來源、不做模式切換。

```
💜 VibeSync   [風格▾] [對象▾]                    ABC
─────────────────────────────────────────────
💡 <cue>
● 輪到你回 · 讀到 7 則        ⚠︎ <uncertainty>
─────────────────────────────────────────────
[順著聊]  晚點跟你說
          這樣不會太急 · 保持節奏
[深化連結] …
[往前推]  …
─────────────────────────────────────────────
 🔄        [ 換一批 ]      都不合用      ⌫
```

空狀態（尚無結果）：`截圖聊天畫面就會自動分析` ／ `或` ／ `[貼上複製的訊息]`
—— 第一版的文字流原封保留，沒截圖也能用（對手沒有這個）。

- 分析卡：`cue` + `turnState`（`reply_due`→「輪到你回」／`optional_follow_up`→
  「她沒在等你回」）+ `uncertainty`（有值才顯示）。`confidence` 類數字一律不露出。
- 候選卡：左 strategy 色票（順著聊／深化連結／往前推一步／先確認／降溫）、
  中 text 氣泡、下 `why · effect` 小灰字。取代現在把四個欄位塞進一顆按鈕 title。
- 風格 chip：吃既有的 `voice` 五型（穩定／直接／幽默／溫柔／俏皮），預設值取
  對象的 `effectiveVoice` → 鍵盤與 App 同一個人格。
- 對象：**只做切換，不做新增**。`partners[]` 已在加密快照內，屬純 UI；新增要寫回
  App 資料層與同意契約，成本高，本期不做。
- 「都不合用」：換一批 + 靜默記一筆 outcome，接既有 `submit-feedback` outcome 分支。

## 差異化總結

1. 每張候選說明「為什麼這樣回、會有什麼效果」（對手只有形容詞標籤）
2. `turnState` 該不該回，取代編造的好感度分數
3. `uncertainty` 誠實揭露「這張圖我不確定什麼」
4. 換一批不扣第二次費
5. 鍵盤與 App 同一個人格（對象 `effectiveVoice` 直接生效）
6. 保留貼上文字流，沒截圖也能用

## 驗收

- `flutter analyze lib test` 0 issue、全套 Dart 測試綠
- `deno test supabase/functions/keyboard-assist` 綠
- 每批 push 後 `Build & Distribute` 的 `build-ios` 綠（macos-26 上真的
  `flutter build ipa --release` 並簽章，這是唯一的 Swift 編譯閘）
- 真機 dogfood 由 Eric 執行：需手動跑 `Release to App Stores` 出 TestFlight build

## 已知不做

- 好感度分數（prompt 明文禁止、Eric 拍板不需要）
- 鍵盤內「新增對象」（要寫回 App 資料層與同意契約）
- 圖中圖／引用預覽的 `origin` 標記硬擋（contract 變更，待另外拍板；現況靠 compiler
  prompt 的「引用預覽不可當成新訊息」與 `conversationType` 四分類擋）


## 交付結果 — 2026-07-28

| 批次 | commit | 內容 |
|---|---|---|
| 前置修復 | `fe2e2206` | `documentIdentifier` nil 橋接 trap，extension 啟動即死 |
| B1 | `f2303b14` | 上傳前裁掉自家鍵盤區 |
| B2 | `d36d2da3` | 截圖即分析，移除逐次預覽確認；同意版本升 v2 |
| B3 | `61c6feed` | 相簿監聽自動重跑＋重複扣費守門 |
| B4 | `50f739c0` | priorTurn 連續對話與候選禁止清單 |
| B5 | `ee0bad72` | 換一批不扣第二次費 |
| B6 | `0fd12a1e` | 分析卡＋三段式候選卡＋風格 chip |
| 交付路徑 | `3123bade` | `Deploy Keyboard Assist` 定向部署工作流程 |

驗證：`flutter analyze lib test` 0 issue、Dart 全套 2635 passed / 0 failed、
`deno test supabase/functions/keyboard-assist` 68 passed / 0 failed、
每一批的 `Build & Distribute` 都在 macos-26 上完成 `flutter build ipa --release` 與簽章。

Edge：`Deploy Keyboard Assist` run `30299835205` 部署 `keyboard-assist` 至 version 5、
`ACTIVE`；其餘 12 個函式版本未變動；未授權 capability 探測回 `401`；未套用任何 migration。

## 執行中改變的決定

- **`priorTurn` 不注入事實。** 原本設想把「上一輪的 cue 與已送出的句子」當脈絡餵給
  compiler，但 grounding 要求每個事實 token 都追得回這張截圖的可見訊息，注入會讓
  合法輸出被自己的守門判死。實際連續性由截圖本身承載——使用者若採用了建議並送出，
  那句話下一張截圖就看得到。`priorTurn` 因此只做兩件事：避免重複、偵測自家輸出外洩。
- **`priorTurn` 不進 replay 雜湊。** same-payload 重試是從已儲存的 pending metadata
  重建的，沒辦法重現這個提示；納入雜湊會把安全重試變成 409。

## 本期明確不做（不是遺漏）

- **鍵盤內切換對象。** v1 request 契約完全沒有 partner 欄位，且 server 強制
  `source.partnerId` 與 `contextRevision` 為 null。做出來只能改語氣，會讓使用者
  以為對象脈絡真的送進去了。要做必須先擴 contract，另案。
- **「都不合用」負向回饋 telemetry。** 從 extension 上報 outcome 需要另一條
  認證、端點與同意路徑；本期只保留「換一批」與「重新分析」兩個真的有效果的動作，
  不放一顆假的回饋鈕。
- **圖中圖／引用預覽的 `origin` 硬擋。** 現況靠 compiler prompt 的「引用預覽不可
  當成新訊息」與 `conversationType` 四分類；硬擋需要 contract 變更，待拍板。
