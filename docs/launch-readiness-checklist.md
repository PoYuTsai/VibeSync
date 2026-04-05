# Launch Readiness Checklist

最後更新：2026-04-05
目前目標：iOS / TestFlight / App Review 上線前最後收尾

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
- [ ] LINE 引用回覆、長圖、多圖 overlap 已驗證
- [ ] media bubble / sticker / video bubble 不會破壞 speaker 判斷
- [ ] 同一批真實截圖抽測仍維持穩定

## 2. 法務與對外資訊

- [ ] [https://vibesyncai.app/privacy](https://vibesyncai.app/privacy) 內容與目前資料流一致
- [ ] [https://vibesyncai.app/terms](https://vibesyncai.app/terms) 內容與目前方案一致
- [ ] `support@vibesyncai.app` 可收信
- [ ] App Store Connect privacy disclosure 已完成
- [ ] App Review 說明文已更新

## 3. 後端與部署

- [ ] 最新 Edge Function deploy 綠燈
- [ ] 最新 iOS release workflow 綠燈
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
