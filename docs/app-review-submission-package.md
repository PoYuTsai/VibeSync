# App Review Submission Package

最後更新：2026-05-09

這份文件是送審前的「主控台」：App Store Connect 審核說明、Reviewer 測試步驟、Privacy Label 對照、Go/No-Go gate 都先放這裡。密碼、API key、Apple sandbox 帳密不要 commit，請只填在 App Store Connect 的 App Review Information。

---

## 1. App Review Information 草稿

可貼到 App Store Connect 的 Review Notes，送審前請補上測試帳號密碼與當前 build number。

```text
VibeSync is a communication coaching app that helps users review private chat context, understand conversation signals, and receive AI-assisted reply suggestions.

The app is not a social network, does not provide public posting or user-to-user messaging, does not automate messages to third parties, and does not guarantee dating or relationship outcomes.

Privacy and AI processing:
- Conversation content is local-first and stored on the user's device by default.
- When the user explicitly requests analysis, screenshot recognition, or AI coaching, only the minimum required content for that request is sent through our backend processing service and AI providers to generate the response.
- We do not use users' raw conversations to train our own model.
- Users can delete conversations locally and can delete their account in the app.
- The app requests Photo Library access only when the user chooses to upload a chat screenshot for OCR/analysis. It does not access photos in the background.

Subscriptions:
- Paid plans are Apple auto-renewable subscriptions managed through App Store in-app purchase.
- The app includes Restore Purchases and subscription management entry points.
- Free users can try the core analysis flow within quota limits.

Reviewer demo flow:
1. Sign in using the provided reviewer account.
2. Open the home screen and create or select a conversation.
3. Paste a short sample chat, or upload a chat screenshot.
4. Tap analysis to view heat score, conversation stage, and reply suggestions.
5. Tap "Ask Coach" to test the 1:1 coaching flow.
6. Open Settings / Subscription to verify plan, quota, Restore Purchases, Terms, Privacy, and account deletion entry points.

Reviewer account:
- Email: [fill in App Store Connect only]
- Password: [fill in App Store Connect only]

Notes:
- If a screenshot is unreadable or unsupported, the app may ask the user to retry or enter text manually.
- Some AI responses vary slightly because they are generated dynamically.
```

---

## 1.1 App Store Metadata 草稿

這段是給 App Store Connect 商品頁與審核 metadata 的安全版本。避免使用「把妹、操控、約砲、保證成功」等高風險詞。

| 欄位 | 建議草稿 |
|------|----------|
| App Name | VibeSync |
| Subtitle | AI 對話分析與社交回覆教練 |
| Category | Lifestyle 或 Productivity，送審前依 App Store Connect 可選項擇一 |
| Age Rating | 建議 17+，因使用者可能輸入成人/曖昧/關係內容 |
| Privacy Policy URL | `https://vibesyncai.app/privacy` |
| Support URL | 暫用 `https://vibesyncai.app/privacy`（頁面底部含客服信箱）；`/support` 正式上線後再改 |

### 簡短描述

```text
VibeSync 是一款 AI 對話教練，幫助你整理聊天脈絡、理解互動訊號，並產生更自然、有邊界感的回覆草稿。
```

### 完整描述草稿

```text
VibeSync helps you reflect on private chat context and prepare better replies with AI-assisted conversation coaching.

You can paste chat messages or upload chat screenshots, then receive conversation signals, reply suggestions, and follow-up coaching. VibeSync is designed for people who want to communicate with more clarity, confidence, and emotional awareness.

Key features:
- Chat context analysis and heat score
- AI reply suggestions with multiple tones
- Screenshot recognition for chat screenshots
- 1:1 coach follow-up for deeper context
- Conversation memory and personal notes
- Learning articles for communication practice

Privacy-first:
- Your conversations are local-first by default.
- AI processing happens only when you explicitly request analysis or coaching.
- VibeSync does not send messages on your behalf and does not guarantee any dating, relationship, or social outcome.

Subscriptions:
VibeSync offers Free, Starter, and Essential plans. Paid plans are auto-renewable subscriptions managed by Apple App Store in-app purchase.
```

### 關鍵字草稿

```text
聊天,社交,溝通,對話,AI教練,回覆建議,情感,約會,聊天分析,自我提升
```

---

## 2. Reviewer 測試路徑

### A. 不付費也能看到的核心價值

- [ ] 新帳號登入後可建立第一個對話
- [ ] 手動貼上 2-5 則聊天訊息可分析
- [ ] Free 額度內可看到熱度、階段、延展回覆與基礎建議
- [ ] Free 額度用完時導到 Paywall，不顯示 raw error
- [ ] 學習專區可打開文章，免費文章限制與 Paywall 導流正常

### B. 付費功能審核路徑

- [ ] Paywall 顯示 Starter / Essential 的額度、價格、週期、方案差異
- [ ] Restore Purchases 可見且可操作
- [ ] 訂閱管理入口可打開 App Store 訂閱管理
- [ ] Starter 顯示 Sonnet 權限、完整 5 種回覆、報告功能
- [ ] Essential 顯示更高額度與完整功能

### C. AI / OCR 主流程

- [ ] 單張清楚聊天截圖可 OCR
- [ ] OCR 後可匯入對話
- [ ] OCR 後可直接分析
- [ ] 手動輸入 fallback 可用
- [ ] AI 失敗或 timeout 時給使用者可理解的重試訊息

### D. Coach 1:1 / Session flow

- [ ] 分析完成頁可點「問教練」
- [ ] Coach 能根據目前對話與用戶問題產生建議
- [ ] Coach loading 狀態明確，不會讓使用者以為沒送出
- [ ] 多輪深挖後，最近 10 輪完整保留
- [ ] 超過 10 輪後，更早內容會以摘要保留且可展開

### E. 帳號 / 刪除

- [ ] Apple Sign In 可完成
- [ ] Google Sign In 可完成
- [ ] Email sign up / verify / resend / forgot password 可完成
- [ ] 登出後 session 不殘留
- [ ] 刪除帳號入口可找到
- [ ] 刪除帳號前提醒 Apple 訂閱需要另外到 App Store 管理
- [ ] 刪除帳號後重新登入不會吃到舊本地 session

---

## 3. Privacy Label 對照

送審前在 App Store Connect 逐項核對，不要寫得比實際資料流更少。

| 類別 | 是否可能收集 | 用途 | 備註 |
|------|--------------|------|------|
| Email / User ID | 是 | Auth、帳號管理、客服、刪帳 | Supabase Auth / Apple / Google |
| Purchase history / Subscription info | 是 | 訂閱驗證、restore、額度同步 | Apple / RevenueCat / Supabase |
| User content: typed chat | 使用者主動分析時會處理 | AI 分析、回覆建議、Coach | local-first；請求期間傳後端與 AI provider |
| User content: screenshots | 使用者主動上傳時會處理 | OCR、分析 | 不主動讀相簿 |
| Diagnostics | 是 | crash/error/debug、服務穩定 | app version、error code、部分遮罩 metadata |
| Usage data | 是 | 額度、成本、濫用防護、產品穩定 | token/model/latency/status |
| Contact info in feedback | 使用者主動提交時可能有 | 客服與問題排查 | feedback context 應最小化 |
| Tracking across apps/websites | 不應有 | 無 | 若未使用廣告追蹤，ATT 不應啟用 |

核對原則：

- [ ] Privacy Policy、App Store Connect Privacy Label、Review Notes 三者一致
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面，不要填 `mailto:`；`/support` 未上線前暫用 `https://vibesyncai.app/privacy`
- [ ] 不宣稱「資料永不離開裝置」
- [ ] 清楚揭露 AI provider 會處理使用者主動送出的內容
- [ ] 若新增 analytics / crash SDK，要回頭更新此表

### 3.1 App Store Connect Privacy Label 建議填法

Apple 要求 privacy label 同時涵蓋 app 與第三方 SDK/服務的資料處理。官方說明也提醒：只要 app 或第三方 partner 會收集資料，就算用途不是廣告或分析，也要揭露；若 app 提供照片上傳類功能，也要揭露對應媒體資料類型。

以下是送審前建議答案草稿，實際填寫時仍以 App Store Connect 畫面為準：

| ASC Data Type | 建議是否揭露 | Linked to User | Tracking | Purposes |
|---------------|--------------|----------------|----------|----------|
| Contact Info - Email Address | 是 | 是 | 否 | App Functionality、Customer Support |
| Identifiers - User ID | 是 | 是 | 否 | App Functionality、Analytics、Fraud Prevention/Security |
| Purchases - Purchase History | 是 | 是 | 否 | App Functionality |
| User Content - Other User Content | 是 | 是 | 否 | App Functionality、Product Personalization |
| User Content - Photos or Videos | 是，使用者主動上傳聊天截圖時 | 是 | 否 | App Functionality、Product Personalization |
| User Content - Customer Support | 可能，使用者主動提交 feedback/support 時 | 是 | 否 | Customer Support、App Functionality |
| Usage Data - Product Interaction / Other Usage Data | 是 | 是 | 否 | Analytics、App Functionality |
| Diagnostics - Crash / Performance / Other Diagnostic Data | 是 | 可能 | 否 | Analytics、App Functionality |

建議不要勾：

- Location：目前沒有定位功能
- Contacts：目前不讀取通訊錄
- Browsing/Search History：目前沒有收集跨網站瀏覽或搜尋紀錄
- Sensitive Info：除非未來主動要求使用者填寫更敏感的個資
- Tracking：目前沒有廣告追蹤、跨 app/web tracking 或 ATT

### 3.2 iOS 權限文案核對

目前 iOS 權限宣告：

| Permission | 用途 | Info.plist key |
|------------|------|----------------|
| Photo Library | 使用者點選圖時，選取聊天截圖做 OCR/分析 | `NSPhotoLibraryUsageDescription` |

目前不需要：

- Camera：app 只從相簿選圖，沒有拍照入口
- Microphone：沒有錄音/錄影功能
- Location / Contacts / Calendar：沒有使用
- App Tracking Transparency：沒有 tracking 用途

---

## 4. 訂閱 / IAP Gate

Apple 會特別看 subscription 資訊是否清楚、購買是否順、使用者是否會誤訂兩份同類商品。

- [ ] 4 個產品都在 App Store Connect 建好且可供審核
- [ ] 4 個產品都在同一 subscription group
- [ ] RevenueCat entitlement `premium` 正確綁定 4 個產品
- [ ] App 內顯示的名稱、週期、價格與 App Store Connect 一致
- [ ] Free -> Starter 購買後 tier 和額度立即刷新
- [ ] Free -> Essential 購買後 tier 和額度立即刷新
- [ ] Starter -> Essential 升級流程不會誤導使用者
- [ ] Essential -> Starter 降級流程不會再次要求購買同類訂閱
- [ ] 已排程降級時，app 顯示仍可用目前方案到續訂日
- [ ] 取消降級 / 管理訂閱導到 Apple 訂閱管理
- [ ] Restore Purchases 在無訂閱 Apple ID 下維持 Free
- [ ] Restore Purchases 在有效訂閱 Apple ID 下恢復正確 tier

---

## 5. 內容安全與定位 Gate

送審 metadata 與截圖不要把產品包成操控、騷擾或成人內容工具。

可用定位：

- 社交溝通教練
- 對話品質輔助
- 私人聊天分析與回覆草稿
- 溝通表達訓練

避免用語：

- 把妹神器
- 約砲教學
- 操控、套路、征服
- 保證邀約成功
- 自動代傳訊息

App 內 AI 邊界：

- [ ] 不鼓勵騷擾、威脅、跟蹤、操控或違反同意的行為
- [ ] 成人情境可以成熟處理，但要提醒尊重、同意、界線與安全
- [ ] 不輸出明顯色情化、物化、暴力或脅迫式建議
- [ ] 不承諾戀愛或邀約結果

---

## 6. Go / No-Go

送審前只要有任一項是 No-Go，就先不送。

| Gate | Go 條件 | 狀態 |
|------|---------|------|
| Auth | Apple / Google / Email / 登出登入 / 刪帳主流程無 P1 | 未驗 |
| Subscription | 購買、restore、升降級、quota refresh 無 P1 | 未驗 |
| OCR | 清楚單圖、長圖、多圖、fallback 無 P1 | 未驗 |
| Core AI | 分析、5 種回覆、Coach 1:1 無 P1 | dogfood 中 |
| Privacy | URL、policy、ASC privacy label、Review Notes 一致 | 未完成 |
| Backend | Edge deploy 綠、`analyze-chat --no-verify-jwt` 維持、webhook 正常 | 未驗 |
| Review Notes | 測試帳號、測試步驟、IAP 說明已填 ASC | 未完成 |

---

## 7. 參考來源

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- App Store Connect App Privacy Reference: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy
