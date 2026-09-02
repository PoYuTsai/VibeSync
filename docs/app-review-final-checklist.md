# App Review Final Checklist

最後更新：2026-09-03（程式端／黑箱可驗項目由 Claude 逐項補證據；真機與 App Store Connect 項目仍待 Eric）

這份清單是送審前最後核對用，不是功能願望清單。

送審主控台與 App Review Notes 草稿見：

- `docs/app-review-submission-package.md`

## 0. Phase 14 目前判定

目前判定：`Repo GO / Next Build HOLD`。2026-07-04 的 build 305 已送審是歷史紀錄；2026-07-17 新增的 AI 鍵盤恰一次計費與隱私資料流，其 production backend gate 已完成，仍須完成 signed iOS、真機與 App Store Connect 新一輪 gate。

Repo 端目前證據：發布硬化 PR #17 已建立；`flutter analyze` PASS、Flutter 2,251 passed / 4 skipped、Edge contracts 177 passed / 0 failed、admin production build / lint / audit PASS。最終 code review 無剩餘 P0/P1/P2。

送出下一個 build 前仍需完成：signed keyboard extension、非測試 quota／HTTP 並行與 lost-response 真機 smoke、公開隱私頁與 App Store Connect Privacy Label 對齊，以及既有 RevenueCat / reviewer / logs gate。Keyboard migration → HMAC secret → JWT-verified Edge → live contract 已完成。

## 1. 帳號與登入

- [ ] Apple Sign In 在 TestFlight 真機 round-trip 正常
- [ ] Google Sign In 在 TestFlight 真機 round-trip 正常
- [ ] Email sign up / verify / resend / forgot password 可正常完成
- [ ] 登出後重新登入，tier / session / 本地狀態一致
- [ ] 刪除帳號流程可完成，且重新登入不會吃到舊 session

## 2. 訂閱與 restore

- [ ] 4 個 IAP 產品都在 App Store Connect 可供審核
- [ ] 4 個 IAP 產品都在同一 subscription group，避免誤訂兩份同類訂閱
- [ ] Starter 購買可完成
- [ ] Essential 購買可完成
- [ ] Restore Purchases 可完成
- [ ] Free -> Starter 後權限刷新正確
- [ ] Starter -> Essential 後權限刷新正確
- [ ] Essential -> Starter 或降級情境顯示正確
- [ ] 同 Apple ID restore 情境與預期一致
- [ ] 不同 Apple ID restore 情境已驗證

## 3. OCR / 截圖主流程

- [ ] 單張聊天截圖的純識別可成功
- [ ] 單張聊天截圖識別後匯入對話可成功
- [ ] 截圖後直接分析可成功
- [ ] LINE 引用回覆：外層 bubble speaker 判斷正確，引用卡只當 quoted context（2026-09-03 黑箱 65 張三輪：修 OCR prompt 前 Sonnet 5 在 2 張暗色 LINE 圖完全不標引用卡→鬼訊息 4、側邊判反；補上暗色主題「表頭列／↳ 貼圖回覆」兩種樣式描述（`2c81345a`）後全套重跑：側邊 99.4%（＝7 月基線）、召回 93.7%、逐字 98.6%、鬼訊息 0、dark_candy_2 回到全對；殘餘：單側長圖 S__5480452 仍有 3/6 側邊錯（模型判成雙側），匯入前可滑動改側邊）
- [ ] 長截圖可成功（2026-09-03 黑箱：唯一長圖單元 S__5480452 修正後鬼訊息歸零但側邊仍 3/6；其餘 standard 46 張側邊 100%）
- [ ] 多張截圖 overlap 情境可成功（2026-09-03 黑箱 overlap 2 組側邊 100%、召回 85%）
- [ ] 名字小字、錯字、模糊邊界案例已抽測（2026-09-03 黑箱 typo 8 張側邊 100%、逐字 98.9%）
- [ ] 圖片 / 貼圖 / 影片 bubble 不會把 speaker 判斷帶歪（2026-09-03 黑箱 sticker_media 20 張側邊 98.2%、召回 89.7%）
- [x] OCR 失敗時不顯示 raw internal error 給使用者（2026-09-03 程式端驗：`mapAnalysisHttpError` 只放行繁中 server 訊息；模型英文摘要改由 `recognitionFailureMessage` 換固定文案）

## 4. 送審與對外資訊

- [x] `https://vibesyncai.app/privacy` 可正常開啟（2026-09-03 HTTP 200，最後更新 2026-09-02；已含 AI 鍵盤 24 小時 server replay、輸入 HMAC、共享 Keychain 約 23 小時、不保存原文，與 4.3 保留期限 30 天）
- [x] `https://vibesyncai.app/terms` 可正常開啟（2026-09-03 HTTP 200，最後更新 2026-09-02，Free／Starter／Essential 與自動續約條款在列）
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：`https://vibesyncai.app/support`，不使用 `mailto:`（2026-09-03 頁面 HTTP 200 已驗；ASC 欄位仍需人工核對）
- [ ] `vibesyncaiapp@gmail.com` 可收信
- [ ] App Store Connect 的 privacy disclosure 已依目前資料流填寫
- [ ] Privacy Label 已揭露 Email / User ID / Purchase History / User Content / Photos / Usage Data / Diagnostics
- [ ] App 內 AI 隱私頁、線上 Privacy Policy 與 App Store Connect 已揭露「我幫你修」暫存 AI 生成潤飾句／理由、生成文字可能反映輸入、不另存原始草稿／完整對話輸入（重播 7 天、每小時清除逾期 live row，備份依 Supabase 週期）（2026-09-03 App 內頁與線上頁已驗齊全；ASC 待人工）
- [ ] App 內 AI 隱私頁、線上 Privacy Policy 與 App Store Connect 已揭露 AI 鍵盤 request identity／input HMAC、只保存 AI 回覆與風格、24 小時 server replay／每小時清理，以及共享 Keychain 最多約 23 小時的 retry identity（2026-09-03 線上頁已齊；App 內頁補上 HMAC 與「只保存回覆與風格」字句；ASC 待人工）
- [ ] Privacy Label 未勾 tracking、location、contacts 等未使用資料類型
- [ ] App Review 說明文已更新成目前實際功能與資料流
- [ ] App Review Information 已填測試帳號、測試步驟、IAP/AI/OCR 說明
- [ ] App Store metadata 不使用「把妹、操控、約砲、保證成功」等高風險定位
- [x] iOS `NSPhotoLibraryUsageDescription` 已存在，且說明只用於聊天截圖 OCR/分析（2026-09-03 驗 `ios/Runner/Info.plist`：選取聊天截圖＋鍵盤「最近截圖」輔助，可隨時撤回）

## 4.5 AI / 內容安全

- [ ] AI 不鼓勵騷擾、跟蹤、威脅、操控或違反同意的行為（2026-09-03 程式端：`SAFETY_RULES`＋`BLOCKED_PATTERNS`＋外送脅迫句型守門；黑箱 42 案 150 張回覆卡與決策文字守門掃描 0 命中，含邊界／婉拒案全部判不傳；成人曖昧情境尚無黑箱）
- [ ] 成人/曖昧情境能成熟回覆，但包含尊重、界線、安全提醒
- [x] AI 失敗、額度不足、OCR 失敗時都不顯示 raw internal error（2026-09-03 全路徑掃描：分析／開場／新話題／教練／鍵盤／額度 429 皆固定繁中；唯一漏洞＝付費失敗 SnackBar 會露原始例外文字，已修 `purchaseErrorMessageFor`）
- [x] Free 用戶可在額度內完成核心分析體驗，用完才導 Paywall（2026-09-03 程式端驗：`used >= limit` 才 429 且先刷新 RevenueCat；模型／OCR 限流 429 刻意不帶額度欄位不會誤導 Paywall；鎖定測試 `analysis_service_model_rate_limit_test`、`index_test` I4）

## 5. Release / Workflow

- [x] 最新 iOS release workflow 綠燈（2026-08-31 run 33428088300 success；Build & Distribute 2026-09-02 run 33648963212 success）
- [x] 最新 Edge Function deploy workflow 綠燈（`cdafa244`，run `29450067262`）
- [ ] TestFlight build 可在 App Store Connect / TestFlight 看到
- [x] `analyze-chat` 目前維持 `--no-verify-jwt`，未被誤改（v274）
- [x] Production 已精準套用 `20260717120000_keyboard_reply_exactly_once.sql`，且 migration 帳本 version 對齊
- [x] Supabase 已設定 `KEYBOARD_REPLAY_HMAC_KEY`，再部署 JWT-verified `keyboard-reply` v5
- [x] Live keyboard health 回 `keyboard-reply-exactly-once-v1`
- [x] Signed Archive / IPA 包含 `VibeSyncKeyboard.appex`（2026-09-03 下載 Build & Distribute run 33648963212 的 ios-ipa：`Payload/Runner.app/PlugIns/VibeSyncKeyboard.appex/` 含 embedded.mobileprovision、keyboard-service extension point）
- [ ] 真機 fresh / lost-response replay / pending / mismatch / quota / model-rate 與 LINE／Instagram／Messages Full Access 全過

## 6. Release Gate

只有以下條件都成立，才算可送審：

- [ ] Auth 沒有 P1 blocker
- [ ] Subscription / restore 沒有 P1 blocker
- [ ] OCR 主流程用同一批真實截圖再測仍穩定
- [ ] Privacy / Terms / support / disclosure 都已對齊
- [ ] 沒有新的 deploy-only regression
- [ ] AI 鍵盤 production contract、signed build 與真機矩陣全部綠燈
