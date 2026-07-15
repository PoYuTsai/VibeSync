# App Review Final Checklist

最後更新：2026-07-04

這份清單是送審前最後核對用，不是功能願望清單。

送審主控台與 App Review Notes 草稿見：

- `docs/app-review-submission-package.md`

## 0. Phase 14 目前判定

目前判定：`Repo GO / Submit GO`——**2026-07-04 已送審（build 305）**，現行判定與 H batch 完成紀錄以 `app-review-submission-package.md` §6.3 為準。

Repo 端已完成：`b515cad` 已 push、`flutter analyze` PASS、Phase 13 targeted tests 103 tests PASS、Edge live probes / Deno tests 已在 Phase 12 PASS。

送出前仍需人工完成：最新 TestFlight 真機 smoke、RevenueCat / App Store sandbox 訂閱矩陣、App Store Connect Privacy Label / IAP / reviewer account、Supabase live secrets / `ai_logs` dashboard 抽查。

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

- [ ] `https://vibesyncai.app/privacy` 可正常開啟
- [ ] `https://vibesyncai.app/terms` 可正常開啟
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：`https://vibesyncai.app/support`，不使用 `mailto:`
- [ ] `vibesyncaiapp@gmail.com` 可收信
- [ ] App Store Connect 的 privacy disclosure 已依目前資料流填寫
- [ ] Privacy Label 已揭露 Email / User ID / Purchase History / User Content / Photos / Usage Data / Diagnostics
- [ ] App 內 AI 隱私頁、線上 Privacy Policy 與 App Store Connect 已揭露「我幫你修」暫存 AI 生成潤飾句／理由、生成文字可能反映輸入、不另存原始草稿／完整對話輸入（重播 7 天、每小時清除逾期 live row，備份依 Supabase 週期）
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
- [ ] 最新 Edge Function deploy workflow 綠燈
- [ ] TestFlight build 可在 App Store Connect / TestFlight 看到
- [ ] `analyze-chat` 目前維持 `--no-verify-jwt`，未被誤改

## 6. Release Gate

只有以下條件都成立，才算可送審：

- [ ] Auth 沒有 P1 blocker
- [ ] Subscription / restore 沒有 P1 blocker
- [ ] OCR 主流程用同一批真實截圖再測仍穩定
- [ ] Privacy / Terms / support / disclosure 都已對齊
- [ ] 沒有新的 deploy-only regression
