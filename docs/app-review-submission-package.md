# App Review Submission Package

最後更新：2026-05-23

這份文件是送審前的「主控台」：App Store Connect 審核說明、Reviewer 測試步驟、Privacy Label 對照、Go/No-Go gate 都先放這裡。密碼、API key、Apple sandbox 帳密不要 commit，請只填在 App Store Connect 的 App Review Information。

---

## 0. 2026-05-23 送審狀態摘要

目前 repo 端的送審包已整理到「文件與技術 gate 可交叉檢查」狀態；真正送出前仍要在 App Store Connect、RevenueCat、Supabase Dashboard、真機 TestFlight 做最後人工確認。

已完成的穩定化證據：

- Legal / support：Privacy、Terms、Support URL、Settings / Paywall / Login legal links 已核對。
- Backend：live OPTIONS probe 已確認 7 個 Edge Functions 有 CORS；`analyze-chat` 未被平台 JWT 擋住；RevenueCat webhook health 可回應。
- Edge validation：Deno Edge tests 307 passed；7 個主要 Edge Function `deno check` passed。
- Core flow targeted tests：quota、OCR、analyze 分段回覆、coach context、opener draft、partner memory、UX guide 等階段已補測或補 review。
- Privacy label 草稿：已依 app 與第三方服務的資料處理列出 Email、User ID、Purchase History、User Content、Photos/Videos、Usage Data、Diagnostics；目前不勾 Tracking、Location、Contacts。

送出前仍需人工 gate：

- App Store Connect：填入 reviewer account password、build number、App Review contact、Privacy Label、IAP 審核資訊。
- IAP / RevenueCat：確認 4 個產品同一 subscription group、entitlement `premium` 綁定、sandbox purchase / restore / upgrade / downgrade matrix。
- Supabase Dashboard：確認 live secrets 包含 `CLAUDE_API_KEY`、`REVENUECAT_IOS_API_KEY`、`REVENUECAT_WEBHOOK_SECRET`，並抽查 `ai_logs`。
- TestFlight 真機：跑 Phase 13 smoke，含登入、手動分析、截圖 OCR、Coach、Paywall、Restore、刪帳入口。

## 1. App Review Information 草稿

可貼到 App Store Connect 的 Review Notes，送審前請補上測試帳號密碼與當前 build number。

```text
VibeSync is a communication coaching app that helps users review private chat context, understand conversation signals, and receive AI-assisted reply suggestions.

The app is not a social network, does not provide public posting or user-to-user messaging, does not automate messages to third parties, and does not guarantee dating or relationship outcomes.

Privacy and AI processing:
- Conversation content is local-first and stored on the user's device by default.
- When the user explicitly requests analysis, screenshot recognition, opener help, draft polishing, or AI coaching, only the minimum required content for that request is sent through our backend processing service and Anthropic Claude API to generate the response.
- Before an AI request is sent, the app explains what data may be sent, identifies VibeSync backend processing and Anthropic Claude API as recipients, and asks the user to agree. If the user declines, the request is not sent.
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
| Category | Primary 建議 Lifestyle；若 App Store Connect 需要 secondary，可再考慮 Productivity |
| Age Rating | 建議 17+，因使用者可能輸入成人/曖昧/關係內容 |
| Privacy Policy URL | `https://vibesyncai.app/privacy` |
| Support URL | `https://vibesyncai.app/support` |

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
- Partner-aware conversation context and personal style memory
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
| User content: typed chat | 使用者主動分析時會處理 | AI 分析、回覆建議、Coach | local-first；請求期間傳 VibeSync 後端與 Anthropic Claude API |
| User content: screenshots | 使用者主動上傳時會處理 | OCR、分析 | 不主動讀相簿；請求期間傳 VibeSync 後端與 Anthropic Claude API |
| Diagnostics | 是 | crash/error/debug、服務穩定 | app version、error code、部分遮罩 metadata |
| Usage data | 是 | 額度、成本、濫用防護、產品穩定 | token/model/latency/status |
| Contact info in feedback | 使用者主動提交時可能有 | 客服與問題排查 | feedback context 應最小化 |
| Tracking across apps/websites | 不應有 | 無 | 若未使用廣告追蹤，ATT 不應啟用 |

核對原則：

- [ ] Privacy Policy、App Store Connect Privacy Label、Review Notes 三者一致
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：`https://vibesyncai.app/support`，不要填 `mailto:`
- [ ] 不宣稱「資料永不離開裝置」
- [ ] 清楚揭露 Anthropic Claude API 會處理使用者主動送出的內容，且 App 內送出前會先取得同意
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
| Auth | Apple / Google / Email / 登出登入 / 刪帳主流程無 P1 | Targeted review passed；TestFlight 真機 round-trip / delete-account smoke 待 Phase 13 |
| Subscription | 購買、restore、升降級、quota refresh 無 P1 | Code review / targeted tests passed；RevenueCat sandbox matrix 與 ASC IAP 狀態待人工 |
| OCR | 清楚單圖、長圖、多圖、fallback 無 P1 | Targeted tests passed；真機截圖集 smoke 待 Phase 13 |
| Core AI | 分析、5 種回覆、Coach 1:1 無 P1 | Analyze / Coach / Opener targeted tests passed；Eric 最後 dogfood 待 Phase 14 |
| Privacy | URL、policy、ASC privacy label、Review Notes 一致 | Repo 端已對齊；ASC Privacy Label / support email manual check 待人工 |
| Backend | Edge deploy 綠、`analyze-chat --no-verify-jwt` 維持、webhook 正常 | Live probes + Deno tests passed；Supabase secrets / live logs / RevenueCat delivery 待 dashboard |
| Review Notes | 測試帳號、測試步驟、IAP 說明已填 ASC | 草稿 ready；password、build number、ASC contact 只填 App Store Connect |

### 6.1 最後人工確認清單

這些項目無法只靠 repo 端驗證，送出前逐項打勾：

- [ ] App Store Connect Privacy Label 按 3.1 填完並 Publish / attach to version。
- [ ] App Review Information 填入不會過期的 demo account、contact phone / email、build number。
- [ ] 4 個 auto-renewable subscriptions 已可供審核，且在同一 subscription group。
- [ ] RevenueCat Dashboard entitlement / offering / package 對應 4 個 Apple product id。
- [ ] RevenueCat sandbox：purchase、restore、upgrade、downgrade、cancel / expiration webhook delivery。
- [ ] Supabase Dashboard secrets：`CLAUDE_API_KEY`、`REVENUECAT_IOS_API_KEY`、`REVENUECAT_WEBHOOK_SECRET`。
- [ ] Supabase `ai_logs` 最近紀錄可查 timeout、429、schema error、OCR failure。
- [ ] `vibesyncaiapp@gmail.com` 可收信；Support URL 頁面有可聯絡資訊。
- [ ] TestFlight build 完成 Phase 13 smoke，再由 Eric 做 Phase 14 final dogfood。

### 6.2 Phase 14 Final Submit Gate - 2026-05-23

目前判定：`Repo GO / Submit HOLD`。

Repo 端已達送審候選狀態：

- Latest pushed commit：`b515cad`
- Working tree：clean
- `flutter analyze`：PASS
- Phase 13 targeted Flutter tests：PASS，103 tests
- Edge validation：live probes + Deno tests/checks 已在 Phase 12 PASS
- Submission package：Review Notes、metadata、privacy label draft、manual gate 都已整理在本文件

送出前仍不可跳過：

- Eric 或 CC 需在最新 TestFlight build 勾完 `docs/testflight-regression-checklist.md` 的 Phase 13 最小 smoke。
- RevenueCat / App Store sandbox 需確認 purchase、restore、upgrade、downgrade、cancel / expiration webhook delivery。
- App Store Connect 需填完 Privacy Label、IAP review info、reviewer account password、build number、contact phone/email。
- Supabase Dashboard 需確認 live secrets 與 `ai_logs` 可查。

只有上述人工 gate 全部完成，且沒有 P1 / No-Go 條件，才把 `Submit HOLD` 改成 `Submit GO`。

---

## 7. 參考來源

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Store Connect App Review Information: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- App Store Connect Submit an App: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- App Store Connect Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- App Store Connect App Privacy Reference: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy
