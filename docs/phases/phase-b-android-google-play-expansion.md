# Phase B - Android / Google Play Expansion

> 狀態：規劃中
> 最後更新：2026-04-03

## 這個 Phase 在做什麼

這個 Phase 是把目前以 iOS 為主的 VibeSync，正式擴張到 Android / Google Play。

它不是小修，而是一條獨立平台線：

- Android 真機驗收
- Google Play 訂閱 / 發布
- Android 特有 deep link / auth callback / browser 行為
- Android 平台 UI / UX / OCR / 支付流程驗證

## 初步目標

- Android 真機完成主要流程驗收
- Google Play / RevenueCat 行為穩定
- Android 版 auth / OCR / subscription 主流程打通
- 可建立 Android internal testing / staged rollout 流程

## 目前想到的子題

### 核心功能驗收

- Email / Google 登入
- 忘記密碼 / deep link 回 App
- 截圖上傳與 OCR
- 手動輸入與重新分析
- Free / Starter / Essential 權限行為

### 平台與商店

- Google Play 商品與 subscription group 設定
- RevenueCat Android entitlement 對齊
- Play Console 版本、測試軌道、審核要求
- Restore / transfer / 新 Google 帳號情境

### Android 特有差異

- Chrome / WebView / Custom Tabs 行為
- intent filter / callback scheme
- 權限、檔案選取、圖片格式差異
- UI 在不同 Android 螢幕尺寸與系統版本的差異

## 之後要先討論清楚的規格問題

- Android 要和 iOS 完全同功能同步，還是先做核心功能版？
- Google Play 訂閱方案是否和 iOS 完全一致？
- Android launch 是與 iOS 同步，還是延後一波？
- 要不要先做 internal testing，再決定正式上架時間？

## 非本 Phase 重點

- 不處理 iOS 送審前最後穩定化
- 不處理 IG / Threads 成長自動化
- 不處理 LINE OA 客服自動化

## 下一步建議

- 等 Phase A iOS launch stabilization 進入收尾
- 再開一份 Android / Google Play spec：
  - 用戶流程
  - 平台差異
  - 訂閱與 restore 行為
  - 發布策略
- 然後拆 implementation plan
