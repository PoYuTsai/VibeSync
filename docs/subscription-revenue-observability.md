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

原始 webhook 事件可看 `webhook_logs`。這張表沒有 `status` 欄；處理結果在 `payload` 裡：`processed_tier`（這次有改方案才有值）與 `ignored_reason`（例如 `user_not_found`：帳號已經刪除）。

```sql
select
  created_at,
  source,
  event_type,
  user_id,
  payload ->> 'environment' as environment,
  payload ->> 'processed_tier' as processed_tier,
  payload ->> 'ignored_reason' as ignored_reason,
  payload
from public.webhook_logs
where source = 'revenuecat'
order by created_at desc
limit 50;
```

## 退款怎麼查

RevenueCat 把「使用者關掉自動續訂」和「退款」都送成 `CANCELLATION`，要看 `cancel_reason` 才分得出來。webhook 從 Onboarding 第 7 步部署後，把它存進 `webhook_logs.payload` 與 `revenue_events.raw_payload`；`EXPIRATION` 的到期原因存成 `expiration_reason`，只存在 `webhook_logs`（`revenue_events` 不收 `EXPIRATION`）。部署後寫進去的每一列都有這兩個鍵（RevenueCat 沒送就是 `null`），部署前的舊列沒有這兩個鍵。

值的意思以 RevenueCat 文件為準。實作規格列的三個：

| `cancel_reason` | 意思 |
| --- | --- |
| `UNSUBSCRIBE` | 使用者關掉自動續訂 |
| `CUSTOMER_SUPPORT` | 退款（以 RevenueCat 文件為準） |
| `BILLING_ERROR` | 帳單問題 |

其他值照 RevenueCat 送來的原字串存，查之前先對 RevenueCat 文件。TestFlight 的交易是 `SANDBOX`，算正式數字只看 `environment = 'PRODUCTION'`。

正式環境的退款：

```sql
select
  event_timestamp,
  user_id,
  product_id,
  raw_payload ->> 'store' as store,
  raw_payload ->> 'cancel_reason' as cancel_reason
from public.revenue_events
where event_type = 'CANCELLATION'
  and raw_payload ->> 'environment' = 'PRODUCTION'
  and raw_payload ->> 'cancel_reason' = 'CUSTOMER_SUPPORT'
order by event_timestamp desc
limit 50;
```

取消與到期原因的分布（只算部署後、有這兩個鍵的列）：

```sql
select
  event_type,
  payload ->> 'environment' as environment,
  coalesce(payload ->> 'cancel_reason', payload ->> 'expiration_reason') as reason,
  count(*) as events
from public.webhook_logs
where source = 'revenuecat'
  and event_type in ('CANCELLATION', 'EXPIRATION')
  and payload ? 'cancel_reason'
group by 1, 2, 3
order by 1, 2, 4 desc;
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
- App 內方案顯示: 以 Supabase `subscriptions` + RevenueCat `sync-subscription` 結果為主
- `恢復購買`: 不是再次扣款，而是把商店裡已存在的訂閱重新同步回 app
