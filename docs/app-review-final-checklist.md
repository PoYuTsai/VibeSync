# App Review Final Checklist

最後更新：2026-07-17

這份清單是送審前最後核對用，不是功能願望清單。

送審主控台與 App Review Notes 草稿見：

- `docs/app-review-submission-package.md`

## 0. Phase 14 目前判定

目前判定：`Repo GO / Next Build HOLD`。2026-07-04 的 build 305 已送審是歷史紀錄；2026-07-17 新增的 AI 鍵盤恰一次計費與隱私資料流，必須先完成 production、signed iOS、真機與 App Store Connect 新一輪 gate。

Repo 端目前證據：發布硬化 PR #17 已建立；`flutter analyze` PASS、Flutter 2,252 passed / 4 skipped、Edge contracts 177 passed / 0 failed、admin production build / lint / audit PASS。最終 code review 無剩餘 P0/P1/P2。

送出下一個 build 前仍需完成：keyboard migration → HMAC secret → Edge 的 production 順序部署、live contract、signed keyboard extension、真機 smoke、公開隱私頁與 App Store Connect Privacy Label 對齊，以及既有 RevenueCat / reviewer / logs gate。

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
- [ ] LINE 引用回覆：外層 bubble speaker 判斷正確，引用卡只當 quoted context
- [ ] 長截圖可成功
- [ ] 多張截圖 overlap 情境可成功
- [ ] 名字小字、錯字、模糊邊界案例已抽測
- [ ] 圖片 / 貼圖 / 影片 bubble 不會把 speaker 判斷帶歪
- [ ] OCR 失敗時不顯示 raw internal error 給使用者

## 4. 送審與對外資訊

- [ ] `https://vibesyncai.app/privacy` 可正常開啟，但仍須發佈 AI 鍵盤 24 小時 server replay、共享 Keychain request identity 與不保存原始複製文字的揭露
- [ ] `https://vibesyncai.app/terms` 可正常開啟
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：`https://vibesyncai.app/support`，不使用 `mailto:`
- [ ] `vibesyncaiapp@gmail.com` 可收信
- [ ] App Store Connect 的 privacy disclosure 已依目前資料流填寫
- [ ] Privacy Label 已揭露 Email / User ID / Purchase History / User Content / Photos / Usage Data / Diagnostics
- [ ] App 內 AI 隱私頁、線上 Privacy Policy 與 App Store Connect 已揭露「我幫你修」暫存 AI 生成潤飾句／理由、生成文字可能反映輸入、不另存原始草稿／完整對話輸入（重播 7 天、每小時清除逾期 live row，備份依 Supabase 週期）
- [ ] App 內 AI 隱私頁、線上 Privacy Policy 與 App Store Connect 已揭露 AI 鍵盤 request identity／input HMAC、只保存 AI 回覆與風格、24 小時 server replay／每小時清理，以及共享 Keychain 最多約 23 小時的 retry identity
- [ ] Privacy Label 未勾 tracking、location、contacts 等未使用資料類型
- [ ] App Review 說明文已更新成目前實際功能與資料流
- [ ] App Review Information 已填測試帳號、測試步驟、IAP/AI/OCR 說明
- [ ] App Store metadata 不使用「把妹、操控、約砲、保證成功」等高風險定位
- [ ] iOS `NSPhotoLibraryUsageDescription` 已存在，且說明只用於聊天截圖 OCR/分析

## 4.5 AI / 內容安全

- [ ] AI 不鼓勵騷擾、跟蹤、威脅、操控或違反同意的行為
- [ ] 成人/曖昧情境能成熟回覆，但包含尊重、界線、安全提醒
- [ ] AI 失敗、額度不足、OCR 失敗時都不顯示 raw internal error
- [ ] Free 用戶可在額度內完成核心分析體驗，用完才導 Paywall

## 5. Release / Workflow

- [ ] 最新 iOS release workflow 綠燈
- [x] 最新 Edge Function deploy workflow 綠燈（`cdafa244`，run `29450067262`）
- [ ] TestFlight build 可在 App Store Connect / TestFlight 看到
- [x] `analyze-chat` 目前維持 `--no-verify-jwt`，未被誤改（v269）
- [ ] Production 已精準套用 `20260717120000_keyboard_reply_exactly_once.sql`，且 migration 帳本 version 對齊
- [ ] Supabase 已設定 `KEYBOARD_REPLAY_HMAC_KEY`，再部署 JWT-verified `keyboard-reply`
- [ ] Live keyboard health 回 `keyboard-reply-exactly-once-v1`
- [ ] Signed Archive / IPA 包含 `VibeSyncKeyboard.appex`
- [ ] 真機 fresh / lost-response replay / pending / mismatch / quota / model-rate 與 LINE／Instagram／Messages Full Access 全過

## 6. Release Gate

只有以下條件都成立，才算可送審：

- [ ] Auth 沒有 P1 blocker
- [ ] Subscription / restore 沒有 P1 blocker
- [ ] OCR 主流程用同一批真實截圖再測仍穩定
- [ ] Privacy / Terms / support / disclosure 都已對齊
- [ ] 沒有新的 deploy-only regression
- [ ] AI 鍵盤 production contract、signed build 與真機矩陣全部綠燈
