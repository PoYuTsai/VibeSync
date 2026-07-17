# Launch Readiness Checklist

最後更新：2026-07-17
目前目標：iOS / TestFlight / App Review 上線前最後收尾

送審主控台、App Review Notes 草稿、Privacy Label 對照見：

- `docs/app-review-submission-package.md`

## 0. Phase 14 目前判定

目前判定：`Repo GO / Submit HOLD`。

可繼續進入最後人工 gate；不要直接送出，直到最新 TestFlight 真機 smoke、RevenueCat / App Store sandbox、App Store Connect privacy/IAP/reviewer 資訊、Supabase secrets/logs dashboard 都完成。

2026-07-17 新增 AI 鍵盤發布硬閘：production migration、HMAC secret、matching JWT-verified Edge v5 與 live contract 已完成；下一個 build 仍須通過 signed keyboard extension、非測試 quota／HTTP 並行與 lost-response、真機矩陣與新隱私揭露。

## 1. 核心功能

### Auth / Session

- [ ] Apple Sign In 真機 round-trip 正常
- [ ] Google Sign In 真機 round-trip 正常
- [ ] Email sign up / verify / forgot password 正常
- [ ] 登出 / 重新登入後 session 不混亂

### Subscription / Tier

- [ ] Starter 購買與 tier 刷新正確
- [ ] Essential 購買與 tier 刷新正確
- [ ] Restore Purchases 正常
- [ ] 同 Apple ID / 不同 Apple ID 邊界情境已驗證
- [ ] recognize-only 不扣額度

### OCR / Analysis

- [ ] 單張截圖識別正常
- [ ] 截圖匯入後分析正常
- [ ] iOS 首次選取聊天截圖時，Photo Library 權限彈窗文案正常
- [ ] LINE 引用回覆、長圖、多圖 overlap 已驗證
- [ ] media bubble / sticker / video bubble 不會破壞 speaker 判斷
- [ ] 同一批真實截圖抽測仍維持穩定

### AI 鍵盤

- [x] Live contract 回 `keyboard-reply-exactly-once-v1`
- [x] Production 測試帳號 fresh／replay／mismatch、DB pending／settlement／rollback、RLS／grant／cron 通過且 smoke rows 清為 0
- [ ] Fresh request、lost-response replay、pending、mismatch、quota、model-rate 行為正確且不重複扣額
- [ ] Signed Archive / IPA 包含 `VibeSyncKeyboard.appex`
- [ ] LINE、Instagram、Messages 在 Full Access 開／關時都能正確成功或安全失敗

## 2. 法務與對外資訊

- [ ] [https://vibesyncai.app/privacy](https://vibesyncai.app/privacy) 內容與目前資料流一致
- [ ] [https://vibesyncai.app/terms](https://vibesyncai.app/terms) 內容與目前方案一致
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：[https://vibesyncai.app/support](https://vibesyncai.app/support)
- [ ] `vibesyncaiapp@gmail.com` 可收信
- [ ] App Store Connect privacy disclosure 已完成
- [ ] Privacy Label 已揭露使用者主動上傳的聊天截圖、文字對話、訂閱、使用量與診斷資料
- [ ] App Review 說明文已更新

## 3. 後端與部署

- [ ] 最新 Edge Function deploy 綠燈
- [ ] 最新 iOS release workflow 綠燈
- [x] 精準套用 `20260717120000_keyboard_reply_exactly_once.sql` 並核對 migration history
- [x] 依 DB → `KEYBOARD_REPLAY_HMAC_KEY` → JWT-verified `keyboard-reply` v5 順序部署
- [ ] RevenueCat webhook 正常同步 tier
- [ ] `sync-subscription` 不再使用 hard-coded fallback key
- [ ] `revenuecat-webhook` 只保留最小必要 webhook log payload
- [ ] `analyze-chat` 暫時維持 `--no-verify-jwt`，直到未來專案單獨調查完成

## 4. 觀測與營運

- [ ] `ai_logs` 能看成功 / 失敗 / timeout / latency 分布
- [ ] restore / transfer 問題有文件可查
- [ ] support 流程可接住帳號、支付、OCR 失敗問題

## 5. Go / No-Go

只有以下都成立才算 Go：

- [ ] OCR 主流程穩定
- [ ] Auth / subscription / restore 無 P1 blocker
- [ ] 對外法務與 support 資訊一致
- [ ] 最新部署沒有重新引入 regression
- [ ] 已完成最後一輪真人 regression
- [ ] AI 鍵盤 production / signed iOS / privacy gates 全部完成
