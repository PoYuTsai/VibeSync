# Phase A - Launch Stabilization

> 狀態：進行中
> 最後更新：2026-04-03

## 這個 Phase 在做什麼

這是 VibeSync 上架前最後穩定化階段。

目標不是再擴新功能，而是把目前已做出的產品收斂到可送審、可營運、可持續 debug 的狀態。

## 目標

- 穩定 iOS / TestFlight 主流程
- 收斂 OCR 邊界
- 收斂 RevenueCat / restore / transfer 行為
- 補齊後台手冊、送審 checklist、handoff
- 讓夥伴可以直接依文件操作，不必依賴聊天紀錄

## 目前已確認完成

- Auth 主流程：
  - 註冊
  - 驗證信
  - 忘記密碼
  - 回 App 重設
  - 刪帳後重註冊
- Subscription 主流程：
  - Free -> Essential
  - 完整回覆刷新
  - 同 Apple ID restore / transfer 行為釐清
- OCR 主案例：
  - LINE 引用回覆
  - `only_left / only_right / mixed`
  - quoted context
- 營運文件：
  - `docs/supabase-ops-guide.md`
  - `docs/revenuecat-ops-guide.md`
  - `docs/gstack-usage-sop.md`

## 仍在收斂中的重點

- OCR 邊界：
  - 長截圖
  - 多張連續截圖
  - 短句續句
  - 名字錯字
  - 圖片 / 貼圖 / 影片 bubble
- RevenueCat：
  - Starter 升降級
  - 不同 Apple ID restore
- App Review：
  - privacy / terms / support email / App Store Connect privacy disclosure

## 非本 Phase 重點

- 不再做大功能擴張
- 不在這階段做新的成長自動化產品
- Android / Google Play 正式驗收延後

## 核心文件

- `docs/current-test-status-2026-04-03.md`
- `docs/app-review-final-checklist.md`
- `docs/testflight-regression-checklist.md`
- `docs/launch-readiness-checklist.md`
- `docs/ocr-analysis-maturity-benchmark.md`
- `docs/supabase-ops-guide.md`
- `docs/revenuecat-ops-guide.md`

## 完成標準

- 沒有新的 P1 / P2
- Auth / Subscription / OCR 主流程穩定
- 夥伴可依文件自行排查基本營運問題
- 可進 App Review
