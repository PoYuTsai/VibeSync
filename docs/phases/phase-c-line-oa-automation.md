# Phase C - LINE OA Automation

> 狀態：規劃中
> 最後更新：2026-04-03

## 這個 Phase 在做什麼

這個 Phase 是把 LINE Official Account 串 webhook，做成自動化 AI 客服 / 分流 / lead 接待系統。

## 初步目標

- 串 LINE OA webhook
- 收到訊息後自動判斷意圖
- 提供 AI 客服式回覆
- 能做 FAQ、導流、分流、人工接手
- 能把對話轉成可追蹤的客戶流程

## 目前想到的子題

- LINE webhook 驗證與簽名驗證
- 使用者識別與 session
- FAQ / knowledge base
- 自動回覆與限制規則
- lead capture
- 人工接手與 escalation
- 客服工作台 / 查詢頁

## 之後要先討論清楚的規格問題

- 這是客服型 bot、銷售型 bot，還是混合型？
- 什麼情況一定要轉人工？
- 能不能讓 AI 直接回所有訊息？
- 資料要不要進 CRM？
- 要不要有黑名單、敏感詞、防濫用？
- 回覆語氣是品牌官方、客服、還是顧問式？

## 與目前 VibeSync App 的關係

- 這是新產品 phase，不是目前聊天分析 app 的小功能
- 可以共用：
  - Supabase
  - AI prompt / logging 經驗
  - 後台營運概念
- 但應該視為一條獨立產品線來規劃

## Android / Google Play 備註

Android / Google Play 正式驗收目前還沒展開。

建議做法：

- 先完成 Phase A 的 iOS / TestFlight / App Review
- Android / Google Play 之後再獨立開 spec / implementation plan
- 不要在當前 launch stabilization 階段一起混進來

## 下一步建議

- 先和夥伴討論商業目標：
  - 客服
  - 銷售
  - 導流
  - lead 蒐集
- 再開一份正式 spec：
  - webhook flow
  - session flow
  - reply policy
  - escalation policy
  - 後台需求
- 然後再拆 implementation plan
