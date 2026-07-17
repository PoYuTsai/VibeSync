# App Review Submission Package

最後更新：2026-07-04（**已送審**：build 305，§6.3 判定 Submit GO；H batch 完成紀錄見 §6.3）

這份文件是送審前的「主控台」：App Store Connect 審核說明、Reviewer 測試步驟、Privacy Label 對照、Go/No-Go gate 都先放這裡。密碼、API key、Apple sandbox 帳密不要 commit，請只填在 App Store Connect 的 App Review Information。

---

## 0. 送審狀態摘要（2026-07-04 更新）

### 送審歷史

- 2026-05-23 首次送審 → 2026-05-27 Apple 拒審（審核機＝iPad Air 11 M3）：3.1.2(c)×2（帳單金額不醒目＋必要資訊）、2.1(b)（購買鈕無限轉圈）、5.1.1(i)/5.1.2(i)（AI 資料同意揭露不足）。
- 2026-07-03 起依 `docs/plans/2026-07-03-app-review-readiness-plan.md` 全面補修（Batch R1/R2/F1/F2/F3/F5＋V-2 對抗式總驗證），全部 client 修復已進 V-3 TestFlight build。

### 拒審點修復對照

| 拒審 Guideline | 修復內容 | 驗證 |
|---|---|---|
| 2.1(b) 購買鈕無限轉圈 | 所有掛 blocking UI 的訂閱/同步 await 全部加時限：StoreKit 類 45s、狀態同步類 20s；失敗一律變可重試狀態；購買成功呈現不依賴後續 refresh 成敗 | 7 條 hang widget 測試；V-2 Codex 四輪對抗審 R4 APPROVED |
| 3.1.2(c) 帳單金額 | priceString 為 paywall 最大價格元素；「省 X%」徽章改 App Store 實價動態計算（floor 絕不高報、抓不到價或幣別不符不顯示） | R2-1，TDD 9 新測 |
| 3.1.2(c) 必要資訊 | app 內名稱/訂閱長度/價格/Terms/Privacy 可點連結齊全；`vibesyncai.app/terms` 六項 EULA 要素查核齊全 | R2-2；metadata 側 EULA/Privacy 連結歸 H-2 人工 |
| 5.1.1(i)/5.1.2(i) AI 同意 | 同意閘 v2 帳號級化（consent key 綁 userId，換帳號不沿用）；onboarding 第 4 頁靜態「AI 與隱私」揭露頁；設定頁常駐「AI 與你的隱私」入口；練習室 DeepSeek 獨立同意；privacy policy／Review Notes 點名 Anthropic＋DeepSeek | R1-1 Codex 雙審 APPROVED；R1-4／F5 A7 |

### 拒審點以外的加固（同期落地）

- per-user 模型呼叫限流七 scope；429 顯示稍後再試訊息，絕不誤導到 paywall。
- opener 扣費 idempotency（request-id＋ledger）；opener 等待改 staged 進度文案（非只有轉圈）。
- 刪帳「遠端成功/本機清理失敗」分流；清理未完成擋在不可跳過的重試 dialog，絕不放行 login 見前用戶資料。
- 全 app 文案總審（F5）：拿掉高風險用語與「未扣額度」假承諾，22 檔純文案批改。

### 驗證證據（2026-07-04）

- Edge 層 deno 全套 1176 passed / 0 failed。
- V-2 對抗式總驗證：Codex 攻擊四個拒審 guideline 四輪（R1–R3 各抓一破口→修），R4 APPROVED 全過。
- V-3 TestFlight build：Eric 全動線 dogfood 通過（2026-07-04），清單含訂閱按鈕逾時行為、onboarding AI 揭露頁、opener staged 文案、練習室導覽/圖鑑。

送出前仍需人工 gate（Eric 側 Batch H）：見 §6.3。

## 1. App Review Information 草稿

可貼到 App Store Connect 的 Review Notes，送審前請補上測試帳號密碼與當前 build number。

```text
VibeSync is a communication coaching app that helps users review private chat context, understand conversation signals, and receive AI-assisted reply suggestions.

The app is not a social network, does not provide public posting or user-to-user messaging, does not automate messages to third parties, and does not guarantee dating or relationship outcomes.

Response to the previous review (rejected 2026-05-27):
- Guideline 2.1: Purchase, restore, and plan-refresh flows now have explicit timeouts (45s for App Store operations, 20s for state sync). Any failure resolves to a visible, retryable state; the purchase button can no longer spin indefinitely.
- Guideline 3.1.2(c): The billed price is the most prominent price element on the paywall. The savings badge is computed from actual App Store prices. App name, subscription length, billed price, and tappable links to the Terms of Use (EULA) and Privacy Policy are all shown before purchase. A screen recording of the full subscription purchase flow is attached.
- Guideline 5.1.1 / 5.1.2: Onboarding now includes an AI & privacy disclosure page that names our third-party AI providers (Anthropic Claude API; DeepSeek API for practice chat). Consent is stored per account, each AI feature asks for consent before any data is sent, and a persistent "AI and your privacy" entry is available in Settings.

Privacy and AI processing:
- Conversation content is local-first and stored on the user's device by default.
- When the user explicitly requests analysis, screenshot recognition, opener help, draft polishing, AI coaching, or practice chat, only the minimum required content for that request is sent through our backend processing service and the corresponding third-party AI provider (Anthropic Claude API for analysis/coaching/OCR; DeepSeek API for the practice chat feature) to generate the response.
- Before an AI request is sent, the app explains what data may be sent, identifies VibeSync backend processing and the specific third-party AI provider (Anthropic Claude API, or DeepSeek API for practice chat) as recipients, and asks the user to agree. Practice chat has its own separate consent. If the user declines, the request is not sent.
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
7. Optional: from the new-conversation sheet, try the opener generator (staged progress text is shown while generating).
8. Optional: in the Learn tab, open the practice chat. It asks for its own separate AI consent (DeepSeek) before starting.

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
- [ ] Free 額度內可看到投入度、階段、延展＋調情兩種回覆與基礎建議
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

### F. Opener / 練習室 / 限流（2026-07 新增動線）

- [ ] 新增對話 sheet 可產生開場白；等待期間顯示 staged 進度文案，不是只有轉圈
- [ ] Free 用戶 opener 付費型卡顯示鎖卡與升級導流，不顯示 raw error
- [ ] 練習室首次使用出現獨立 AI 同意（點名 DeepSeek）；拒絕則不送出任何內容
- [ ] 翻牌／圖鑑收藏動線正常
- [ ] 觸發 per-user 限流時顯示「稍後再試」類訊息，不落 paywall、不顯示 raw error

---

## 3. Privacy Label 對照

送審前在 App Store Connect 逐項核對，不要寫得比實際資料流更少。

| 類別 | 是否可能收集 | 用途 | 備註 |
|------|--------------|------|------|
| Email / User ID | 是 | Auth、帳號管理、客服、刪帳 | Supabase Auth / Apple / Google |
| Purchase history / Subscription info | 是 | 訂閱驗證、restore、額度同步 | Apple / RevenueCat / Supabase |
| User content: typed chat | 使用者主動分析時會處理 | AI 分析、回覆建議、Coach | local-first；請求期間傳 VibeSync 後端與 Anthropic Claude API |
| User content: screenshots | 使用者主動上傳時會處理 | OCR、分析 | 不主動讀相簿；請求期間傳 VibeSync 後端與 Anthropic Claude API |
| User content: practice chat | 使用者主動使用練習室時會處理 | AI 模擬對話練習 | 請求期間傳 VibeSync 後端與 DeepSeek API；獨立同意閘 |
| Diagnostics | 是 | crash/error/debug、服務穩定 | app version、error code、部分遮罩 metadata |
| Usage data | 是 | 額度、成本、濫用防護、產品穩定 | token/model/latency/status |
| Contact info in feedback | 使用者主動提交時可能有 | 客服與問題排查 | feedback context 應最小化 |
| Tracking across apps/websites | 不應有 | 無 | 若未使用廣告追蹤，ATT 不應啟用 |

核對原則：

- [ ] Privacy Policy、App Store Connect Privacy Label、Review Notes 三者一致
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：`https://vibesyncai.app/support`，不要填 `mailto:`
- [ ] 不宣稱「資料永不離開裝置」
- [ ] 清楚揭露 Anthropic Claude API（分析/Coach/OCR）與 DeepSeek API（練習室）會處理使用者主動送出的內容，且 App 內送出前會先取得同意（練習室為獨立同意項）
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

| Gate | Go 條件 | 狀態（2026-07-04） |
|------|---------|------|
| Auth | Apple / Google / Email / 登出登入 / 刪帳主流程無 P1 | F2 刪帳分流 Codex R4 APPROVED；V-3 dogfood 通過 |
| Subscription | 購買、restore、升降級、quota refresh 無 P1、無無限轉圈 | V-2 時限加固 Codex R4 APPROVED＋7 hang 測試綠；V-3 dogfood 通過；**iPad sandbox 矩陣（H-5）待人工** |
| OCR | 清楚單圖、長圖、多圖、fallback 無 P1 | Targeted tests passed；recognizeOnly 限流 6/分 60/天已上 prod |
| Core AI | 分析、5 種回覆、Coach 1:1、opener 無 P1 | Edge deno 1176 綠；opener idempotency＋限流七 scope 上 prod；V-3 dogfood 通過 |
| Privacy | URL、policy、ASC privacy label、Review Notes 一致（含 Anthropic＋DeepSeek） | Repo 端已對齊含 DeepSeek；**ASC Privacy Label（H-3）＋live privacy 頁重部署（H-6）待人工** |
| Backend | Edge deploy 綠、`analyze-chat --no-verify-jwt` 維持、webhook 正常 | Edge deno 全套 1176 passed / 0 failed；Supabase secrets / live logs / RevenueCat delivery 待 dashboard 抽查 |
| Review Notes | 測試帳號、測試步驟、IAP 說明、拒審回應已填 ASC | 草稿 ready（§1 已含拒審回應段）；password、build number、錄屏附件（H-4）只在 App Store Connect 補 |

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

### 6.2 Phase 14 Final Submit Gate - 2026-05-23（歷史紀錄，已被 §6.3 取代）

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

### 6.3 V-4 Submit Gate - 2026-07-04（現行判定）

目前判定：**`Repo GO / Submit GO`**——**已於 2026-07-04 送審（Version 1.0, build 305）**，並在 5/27 拒審 thread 回覆四 guideline 修復摘要＋附訂閱流程錄屏。

Repo/code 端已達送審候選狀態：

- 2026-05-27 四個拒審 guideline 全部修復（§0 對照表），V-2 Codex 四輪對抗審 R4 APPROVED。
- Edge deno 全套 1176 passed / 0 failed（2026-07-04）。
- V-3 TestFlight build 出爐，Eric 全動線 dogfood 通過（2026-07-04）。
- 送審包本文件已全文對齊現況（Review Notes 含拒審回應段、Privacy Label 含 DeepSeek）。

H batch 完成紀錄（2026-07-04 送審前全數處理）：

- [x] H-1 Paid Apps Agreement 生效；4 訂閱 Waiting for Review＝已綁送審佇列，Product ID 與 `lib/subscription_providers.dart` 逐字核對一致。
- [x] H-2 metadata：App 描述補 EULA/Privacy/Support 三連結＋opener/練習室兩行。
- [x] H-3 Privacy Label 實填並 Publish：貼上的聊天內容歸 Other User Content、Tracking 全 No、含 Anthropic＋DeepSeek 揭露。
- [x] H-4 Review Notes 整格換新草稿（含拒審回應三段）；訂閱流程錄屏（同意 dialog→分析→paywall→降級購買→設定頁排程狀態，117s）已傳 Attachment＋拒審 thread 回覆再附一次。
- [x] H-5 iPad 矩陣：**風險承擔跳過**（Eric 無 iPad/Mac 可用）。依據：轉圈根因＝無界 await 屬裝置無關、修復已 Codex R4 雙審、iPhone 真機 sandbox 全矩陣錄屏驗證通過、上輪 iPad 審核無任何佈局類 finding。殘餘風險＝再吃一次拒審循環（可承受）。
- [x] H-6 live `vibesyncai.app/privacy` 重新部署（vibesync-web `5fdc46b`），6 處 DeepSeek 揭露已驗；年齡分級 Apple 新制 18+（=舊 17+）免動。
- [x] Supabase secrets 抽查 OK；`ai_logs` 最後一筆停 2026-07-02（telemetry 疑斷，非送審 blocker，另案追）。

### 6.4 AI Keyboard Next-Build Gate - 2026-07-17（現行判定）

目前判定：**`Repo GO / Next Build HOLD`**。§6.3 只代表 build 305 在 2026-07-04 的送審狀態；PR #17 新增 AI 鍵盤恰一次計費與新的短期保存／Keychain 資料流，不能沿用舊 build 的 Submit GO。

Repo 端已完成完整 Flutter／Edge／admin 驗證與獨立 code review；下一個 TestFlight／App Review build 仍須逐項完成：

- [ ] 精準套用 `20260717120000_keyboard_reply_exactly_once.sql`，在真實 PostgreSQL 驗證 claim、settlement rollback、replay、cleanup、RLS／grant，並對齊 migration 帳本。
- [ ] 設定 `KEYBOARD_REPLAY_HMAC_KEY`，再部署 JWT-verified `keyboard-reply`；live health 必須回 `keyboard-reply-exactly-once-v1`。
- [ ] macOS signed Archive / IPA 包含 `VibeSyncKeyboard.appex`，TestFlight 真機完成 fresh、lost-response replay、pending、mismatch、quota、model-rate 與 Full Access 矩陣。
- [ ] 公開 Privacy Policy、App 內 AI 隱私頁、App Store Connect App Privacy 與 Review Notes 同步 AI 鍵盤 24 小時 replay／每小時清理、共享 Keychain retry identity、input HMAC 與不保存原始複製文字的資料流。

---

## 7. 參考來源

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Store Connect App Review Information: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- App Store Connect Submit an App: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- App Store Connect Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- App Store Connect App Privacy Reference: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy
