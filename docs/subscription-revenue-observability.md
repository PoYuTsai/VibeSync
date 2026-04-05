# Subscription / Revenue Observability

## 購買是跟哪個平台扣款

- iOS: 走 Apple App Store / Apple ID 訂閱扣款
- Android: 走 Google Play / Google 帳號訂閱扣款
- App 內不直接刷卡，真正的扣款與續訂都由商店處理
- VibeSync 透過 RevenueCat 統一接收商店訂閱狀態，再同步回 Supabase

## 方案 tier 看哪裡

主要來源是 `subscriptions` table。

```sql
select
  user_id,
  tier,
  started_at,
  expires_at,
  monthly_messages_used,
  daily_messages_used,
  updated_at
from public.subscriptions
order by updated_at desc
limit 50;
```

單一使用者：

```sql
select
  user_id,
  tier,
  started_at,
  expires_at,
  monthly_messages_used,
  daily_messages_used,
  updated_at
from public.subscriptions
where user_id = 'USER_ID_HERE';
```

## RevenueCat webhook / 商店事件看哪裡

原始 webhook 事件可看 `webhook_logs`。

```sql
select
  created_at,
  source,
  event_type,
  status,
  payload
from public.webhook_logs
where source = 'revenuecat'
order by created_at desc
limit 50;
```

## 收益看哪裡

交易事件記在 `revenue_events`。

```sql
select
  created_at,
  user_id,
  event_type,
  product_id,
  price_usd,
  currency,
  transaction_id
from public.revenue_events
order by created_at desc
limit 50;
```

月份收益 summary：

```sql
select *
from public.monthly_revenue
order by month desc;
```

月份毛利 summary：

```sql
select *
from public.monthly_profit
order by month desc;
```

## 活躍訂閱使用者看哪裡

`real_subscriptions` view 會比直接看 raw table 更適合後台。

```sql
select *
from public.real_subscriptions
order by updated_at desc
limit 50;
```

## Admin Dashboard 現成頁面

- `/subscriptions`
- `/revenue`
- `/costs`
- `/users`

## 目前判讀邏輯

- 購買成功: 先看商店交易是否成功，再看 RevenueCat entitlements 是否生效
- App 內方案顯示: 以 Supabase `subscriptions.tier` + RevenueCat sync 結果為主
- `同步已買過的訂閱`: 不是再次扣款，而是把商店裡已存在的訂閱重新同步回 app
