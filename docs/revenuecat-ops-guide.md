# RevenueCat Ops Guide

> VibeSync 的 RevenueCat 營運與排查手冊
> 最後更新：2026-04-03

## 先講結論

RevenueCat 不是你們的主後台。

- `Supabase`
  - 主後台
  - 看日常營運、查人、查 tier、查分析、查 Auth、跑 SQL
- `RevenueCat`
  - 看訂閱真相
  - 看 entitlement、restore、transfer、同 Apple ID 行為
- `App Store Connect`
  - 看 iOS 商品、subscription group、升降級週期、商店規則

一句話：

- 日常營運先看 `Supabase`
- 訂閱真相看 `RevenueCat`
- iOS 商店規則看 `App Store Connect`

## 這份文件在做什麼

這份是給你和夥伴在這些情境下用的：

- 想看某個用戶到底有沒有有效訂閱
- 想知道 restore 為什麼把方案同步到另一個帳號
- 想查同 Apple ID 為什麼按同步後變 Essential
- 想看產品、offering、entitlement 是否設對
- 想決定夥伴該給什麼 collaborator 權限

## RevenueCat 後台最常看的地方

### 1. Collaborators

頁面用途：

- 邀請夥伴進 RevenueCat project
- 控制對方能不能看、能不能改

你們最常用的角色建議：

- `Administrator`
  - 你自己
  - 可管理整個 project、設定、產品、paywalls、API keys
- `View Only`
  - 只需要看數據、看 customer、看 entitlement 狀態的人
- `Support`
  - 需要看 customer timeline、restore、transfer、entitlement 變化，但不需要改設定的人
- `Growth`
  - 需要調整 offerings、paywalls、產品展示的人

目前對 VibeSync 的建議：

- 你：`Administrator`
- 夥伴：
  - 如果主要是看資料與排查，用 `View Only` 或 `Support`
  - 如果之後要動 paywall / offerings，再升到 `Growth`

### 2. General / Project Settings

這裡最重要的是：

- `Restore Behavior`

這個設定會直接影響：

- 同 Apple ID 按 `同步已買過的訂閱` 之後會怎樣
- 訂閱會不會轉到另一個 VibeSync 帳號

VibeSync 目前建議採用的理解：

- 維持 RevenueCat 預設的 `Transfer to new App User ID`
- 這代表同一個 Apple ID 底下，使用者在另一個 VibeSync 帳號按 restore / sync 時，訂閱可能會被同步過去

這不是 bug，而是 restore policy。

### 3. Customers

這是最常用的排查頁。

在這裡主要看：

- 這個 App User ID 目前有沒有 active entitlement
- 是 Starter 還是 Essential
- 最近有沒有 purchase / renew / cancel / restore / transfer
- customer timeline 是否合理

常見用途：

- 用戶說「我明明買了，App 還是 free」
- 用戶說「我按了 restore 還是沒回來」
- 用戶說「我換帳號後怎麼變 premium 了」

### 4. Entitlements / Products / Offerings / Paywalls

這幾塊主要是設定層，不是日常排查第一站。

要看的是：

- `Entitlements`
  - Starter / Essential 是否都有正確綁到 premium entitlement
- `Products`
  - App Store / Play Store product id 是否正確
- `Offerings`
  - paywall 用的 packages 是否正確
- `Paywalls`
  - 如果你們之後要用 RevenueCat Paywalls，再來這裡看

### 5. Charts / Overview

這裡主要看：

- 總收入趨勢
- 訂閱變化趨勢
- 取消率

但如果你要對單一用戶或單次事件做排查，優先還是去：

- `Customers`
- `Supabase webhook_logs`
- `Supabase revenue_events`

## 最常見的排查情境

### 情境 1：用戶說「我買了，但 App 還是 free」

先看：

1. `RevenueCat -> Customers`
   - 有沒有 active entitlement
2. `Supabase -> public.subscriptions`
   - tier 是否已同步
3. `Supabase -> public.webhook_logs`
4. `Supabase -> public.revenue_events`

判讀：

- RevenueCat 有 entitlement，但 Supabase 還是 free
  - 比較像 webhook / sync 問題
- RevenueCat 也沒有 entitlement
  - 比較像購買根本沒完成，或 App Store 狀態還沒進來

### 情境 2：同 Apple ID，另一個帳號按了同步後變 Essential

先看：

1. `RevenueCat -> Project Settings -> Restore Behavior`
2. `RevenueCat -> Customers`
3. `Supabase -> public.subscriptions`

判讀：

- 如果 Restore Behavior 是 `Transfer to new App User ID`
  - 這是預期行為，不是 bug

### 情境 3：真的沒買過，按同步後卻變 premium

這題才是潛在 bug，但前提是：

- 真的換了另一個 Apple ID / Sandbox Apple ID
- 這個 Apple ID 從沒買過 Starter / Essential

要看：

1. `RevenueCat -> Customers`
2. `Supabase -> public.subscriptions`
3. `Supabase -> public.webhook_logs`

### 情境 4：restore 沒作用

先看：

1. `RevenueCat -> Customers`
2. `Supabase -> public.subscriptions`
3. `Supabase -> public.webhook_logs`

### 情境 5：想知道某個月營收和收益

先看：

- RevenueCat Dashboard 的趨勢圖
- Supabase 的：
  - `public.revenue_events`
  - `public.monthly_revenue`
  - `public.monthly_profit`

## VibeSync 目前的訂閱規則理解

### 同 Apple ID

目前預期：

- 不按同步、不購買
  - `Free` 維持 `Free`
- 同 Apple ID 下，另一個 VibeSync 帳號按 `同步已買過的訂閱`
  - 可能變成 `Essential`
  - 這是預期行為

### 不同 Apple ID

目前預期：

- 如果這個 Apple ID 從沒買過
- 按 `同步已買過的訂閱`
- 應該維持 `Free`

這一題之後若有新的 Sandbox Apple ID，再實機補測。

### 升降級週期

正常預期：

- `Free -> Starter`
  - 立即生效
- `Free -> Essential`
  - 立即生效
- `Starter -> Essential`
  - 立即升級
- `Essential -> Starter`
  - 通常不是立刻降
  - 會維持 Essential 到下一個 renewal date，下一期才變 Starter

這題的商店規則，最後還是要以：

- `RevenueCat`
- `App Store Connect`

一起看。

## RevenueCat 搜尋上的注意事項

RevenueCat 後台找 customer，最穩的是：

- `App User ID`
- `Transaction ID`
- `Order ID`

不要預設一定能直接用 email 找到。

因為 RevenueCat 是否能用 email 搜，取決於：

- 你有沒有把 email 明確傳成 customer attributes

## 你和夥伴平常怎麼分工看

### 先看 Supabase 的情境

- 查用戶有沒有註冊
- 查 Auth 狀態
- 查 tier
- 查額度
- 查 AI 成本
- 跑 SQL

看：

- [docs/supabase-ops-guide.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/supabase-ops-guide.md)

### 先看 RevenueCat 的情境

- 查 entitlement
- 查 restore
- 查 transfer
- 查同 Apple ID 行為
- 查 customer timeline

看：

- 這份文件

### 先看 App Store Connect 的情境

- 查 iOS 商品
- 查 subscription group
- 查升降級週期
- 查商店端設定

看：

- App Store Connect

## 官方文件

- RevenueCat Collaborators:
  - [Collaborators](https://www.revenuecat.com/docs/projects/collaborators)
- RevenueCat Projects / Overview:
  - [Projects Overview](https://www.revenuecat.com/docs/projects/overview)
- RevenueCat Project Settings:
  - [Project Settings](https://www.revenuecat.com/docs/projects/project-settings-index)
- RevenueCat Supporting Customers:
  - [Supporting Your Customers](https://www.revenuecat.com/docs/dashboard-and-metrics/supporting-your-customers)
