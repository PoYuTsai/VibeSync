# RevenueCat Ops Guide

> VibeSync 的 RevenueCat 營運與排查手冊
> 最後更新：2026-04-03

## 先講結論

RevenueCat 不是你們的主後台。

- `Supabase`
  - 主後台
  - 查用戶、查 tier、查 Auth、查分析、查 SQL、查收益與成本
- `RevenueCat`
  - 查訂閱真相
  - 查 entitlement、restore、transfer、同 Apple ID 行為
- `App Store Connect`
  - 查 iOS 商品、subscription group、升降級週期、商店規則

一句話：

- 日常營運先看 `Supabase`
- 訂閱真相看 `RevenueCat`
- iOS 商店規則看 `App Store Connect`

## 這份文件是給誰看的

這份主要是給你和夥伴在這些情境下用的：

- 想看某個用戶到底有沒有有效訂閱
- 想知道 restore 為什麼把方案同步到另一個帳號
- 想查同 Apple ID 為什麼按同步後變 Essential
- 想看 product、offering、entitlement 是否設對

## 白話名詞

### entitlement

白話意思：

- `這個人現在實際有沒有付費權限`

你可以把它理解成：

- 這個帳號現在到底是不是 premium
- 現在能不能用 Starter / Essential 的功能

一句話：

- `entitlement = 目前生效中的付費資格`

### restore

白話意思：

- `把以前買過的訂閱，重新同步回現在這支 App`

常見情境：

- 換手機
- 重裝 App
- App 一時沒同步到已買方案
- 重新登入後 tier 不見了

在 VibeSync 裡：

- `同步已買過的訂閱` 就是在做 restore

一句話：

- `restore = 把以前買過的東西找回來`

### transfer

白話意思：

- `同一個 Apple ID 買過的訂閱，被同步到另一個 App 帳號`

例如：

- 原本用 Google 帳號買了 Essential
- 後來改登入 Yahoo 帳號
- 按了 restore / 同步已買過的訂閱
- Essential 跑到 Yahoo 帳號身上

這個從 A 帳號轉到 B 帳號的動作，就是 transfer。

一句話：

- `transfer = 訂閱從一個 App 帳號轉到另一個 App 帳號`

## 目前 VibeSync 的 collaborator 現況

你和夥伴現在都已經是 `Administrator`。

所以這份文件不再展開一堆角色權限比較，重點放在：

- RevenueCat 哪些頁面要看
- 各種訂閱情境要怎麼判讀

## RevenueCat 後台最常看的地方

### 1. Collaborators

用途很單純：

- 看目前誰有進專案
- 新增或移除協作者

你們現在這塊已經處理好，之後除非要加新成員，不然不用常看。

### 2. General / Project Settings

這裡最重要的是：

- `Restore Behavior`

它會直接影響：

- 同 Apple ID 按 `同步已買過的訂閱` 之後會怎樣
- 訂閱會不會轉到另一個 VibeSync 帳號

VibeSync 目前的理解是：

- 維持 RevenueCat 預設的 `Transfer to new App User ID`

所以：

- 同一個 Apple ID 底下
- 換另一個 VibeSync 帳號
- 按 `同步已買過的訂閱`
- 方案可能會同步過去

這是預期行為，不是 bug。

### 3. Customers

這是最常用的排查頁。

在這裡主要看：

- 這個 App User ID 目前有沒有 active entitlement
- 現在是 Starter 還是 Essential
- 最近有沒有 purchase / renew / cancel / restore / transfer
- customer timeline 是否合理

最常見用途：

- 用戶說「我明明買了，App 還是 free」
- 用戶說「我按了 restore 還是沒回來」
- 用戶說「我換帳號後怎麼變 premium 了」

### 4. Entitlements / Products / Offerings / Paywalls

這幾塊是設定層，不是日常排查第一站。

要看的是：

- `Entitlements`
  - Starter / Essential 是否都有正確綁到 premium entitlement
- `Products`
  - App Store / Play Store product id 是否正確
- `Offerings`
  - paywall 用的 packages 是否正確
- `Paywalls`
  - 如果之後真的使用 RevenueCat Paywalls，再回來看這裡

### 5. Charts / Overview

這裡主要看：

- 總收入趨勢
- 訂閱變化趨勢
- 取消率

但如果你要排查某個用戶或某次事件，優先還是：

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
  - 比較像購買根本沒完成，或商店狀態還沒進來

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
- 那個 Apple ID 從沒買過 Starter / Essential

要看：

1. `RevenueCat -> Customers`
2. `Supabase -> public.subscriptions`
3. `Supabase -> public.webhook_logs`

### 情境 4：restore 沒作用

先看：

1. `RevenueCat -> Customers`
2. `Supabase -> public.subscriptions`
3. `Supabase -> public.webhook_logs`

### 情境 5：想知道某個月收入和利潤

這題不要只看 RevenueCat。

正確做法：

- 看 RevenueCat 的趨勢圖，理解訂閱變化
- 真正查營運數字，回 Supabase 看：
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

這題最後還是要一起看：

- `RevenueCat`
- `App Store Connect`

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

- [supabase-ops-guide.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/supabase-ops-guide.md)

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
