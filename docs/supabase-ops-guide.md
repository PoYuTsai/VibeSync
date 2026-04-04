# Supabase Ops Guide

> VibeSync 上線後的日常營運、查詢、除錯指引
> 最後更新：2026-04-03
> 本文件 SQL 已對照目前 repo 內 migration/schema 校正

## 先講結論

日常後台主要看 `Supabase`，但不是只有 Supabase：

- `Supabase`：使用者、tier、分析紀錄、Auth 診斷、Webhook 原始事件、SQL 查詢
- `RevenueCat`：訂閱 entitlement、restore/transfer、商店訂閱真實狀態
- `App Store Connect`：iOS 商品、subscription group、升降級週期、App Store 端狀態

所以：

- 日常營運與除錯，主要看 `Supabase`
- 遇到訂閱同步、restore、transfer 問題，再去看 `RevenueCat`
- 遇到 iOS 訂閱週期或產品配置問題，再看 `App Store Connect`

## 後台分工總結

- `Supabase`
  - 主後台
  - 看日常營運、查人、查 tier、查分析、查 Auth、跑 SQL

- `RevenueCat`
  - 看訂閱 entitlement、restore、transfer、同 Apple ID 行為

- `App Store Connect`
  - 看 iOS 商品、subscription group、升降級週期、商店端規則

一句話：

- 主後台是 `Supabase`
- 訂閱真相要搭配 `RevenueCat`
- iOS 商店規則要看 `App Store Connect`

## 後台常用頁面

| 頁面 | 路徑 | 用途 |
|------|------|------|
| `Authentication -> Users` | Supabase Dashboard | 查註冊帳號、驗證狀態、最後登入時間 |
| `Table Editor` | Supabase Dashboard | 快速看 `subscriptions`、`ai_logs`、`feedback` 等資料表 |
| `SQL Editor` | Supabase Dashboard | 跑自訂 SQL 查詢 |
| `Edge Functions` | Supabase Dashboard | 看 function 部署狀態 |
| `Logs -> Edge Functions` | Supabase Dashboard | 查 function runtime error |
| `Customers / Entitlements` | RevenueCat Dashboard | 查訂閱是否真的有效、是否 transfer |
| `Products / Subscriptions` | App Store Connect | 查 iOS 商品與 subscription group |

## 重要資料表 / View

| 名稱 | 類型 | 用途 |
|------|------|------|
| `public.users` | table | App 內用戶資料 |
| `public.subscriptions` | table | 用戶目前 tier 與額度使用 |
| `public.ai_logs` | table | AI 分析紀錄、tokens、cost、latency、status |
| `public.feedback` | table | 用戶 👍👎 反饋 |
| `public.webhook_logs` | table | RevenueCat webhook 原始事件 |
| `public.revenue_events` | table | 已整理過的營收事件 |
| `public.rate_limits` | table | 每分鐘 throttle 狀態，不是每日/月額度 |
| `public.token_usage` | table | token 使用明細 |
| `public.auth_diagnostics` | table | 註冊、驗證信、忘記密碼、deep link 診斷 |
| `public.real_subscriptions` | view | 排除測試帳號後的訂閱狀態 |
| `public.monthly_revenue` | view | 月營收 summary |
| `public.monthly_profit` | view | 月毛利 summary |

補充：

- `webhook_logs` 現在保存的是「精簡過的 RevenueCat payload 摘要」，不是完整 raw payload。
- `monthly_profit` 目前是 `收入 - token/AI 成本` 的營運毛利近似值，不是最終財務淨利。

## 日常監控 SQL

### 1. 用戶總覽

```sql
-- 總註冊用戶數
select count(*) as total_users
from auth.users;

-- 各 tier 分佈
select tier, count(*) as users
from public.subscriptions
group by tier
order by tier;

-- 近 30 天每日新用戶
select
  date(created_at) as date,
  count(*) as new_users
from auth.users
group by date(created_at)
order by date desc
limit 30;
```

### 2. 活躍度

```sql
-- 今日有做分析的活躍用戶
select count(distinct user_id) as dau_today
from public.ai_logs
where created_at >= current_date;

-- 本週活躍用戶
select count(distinct user_id) as wau
from public.ai_logs
where created_at >= date_trunc('week', now());

-- 近 30 天每日活躍用戶
select
  date(created_at) as date,
  count(distinct user_id) as dau
from public.ai_logs
group by date(created_at)
order by date desc
limit 30;
```

### 3. AI 成本 / 請求狀態

```sql
-- 今日 AI 成本與呼叫數
select
  coalesce(sum(cost_usd), 0) as total_cost_usd,
  count(*) as total_calls
from public.ai_logs
where created_at >= current_date;

-- 本月 AI 成本與呼叫數
select
  coalesce(sum(cost_usd), 0) as monthly_cost_usd,
  count(*) as monthly_calls
from public.ai_logs
where created_at >= date_trunc('month', now());

-- 近 30 天每日成本趨勢
select
  date(created_at) as date,
  coalesce(sum(cost_usd), 0) as daily_cost_usd,
  count(*) as calls
from public.ai_logs
group by date(created_at)
order by date desc
limit 30;

-- 各模型本月成本分佈
select
  model,
  count(*) as calls,
  coalesce(sum(cost_usd), 0) as total_cost_usd
from public.ai_logs
where created_at >= date_trunc('month', now())
group by model
order by total_cost_usd desc;

-- AI 狀態分佈
select
  status,
  count(*) as requests
from public.ai_logs
group by status
order by requests desc;
```

## 訂閱 / 收益 SQL

### 0. 先懂訂閱資料流

- iOS：實際扣款走 `Apple ID / App Store`
- Android：實際扣款走 `Google 帳號 / Google Play`
- App 內不直接刷卡，商店才是真正扣款來源
- `RevenueCat` 負責統一接收商店訂閱狀態
- `Supabase.public.subscriptions` 是 app 內 tier 同步結果，不是商店真相唯一來源

### 訂閱判讀邏輯

- `購買成功`
  - 先看商店交易有沒有成功
  - 再看 RevenueCat entitlement 是否生效
  - 最後看 `public.subscriptions.tier` 是否同步正確

- `同步已買過的訂閱`
  - 不是再次扣款
  - 是把此 Apple ID / Google 帳號底下已存在的有效訂閱同步回 app

- `同 Apple ID`
  - 若目前 RevenueCat restore behavior 是 `Transfer to new App User ID`
  - 那同一個 Apple ID 下，切到另一個 VibeSync 帳號後按 restore/sync，方案同步過去屬於預期行為

- `不同 Apple ID`
  - 如果該 Apple ID / Google 帳號從沒買過
  - 按 sync/restore 預期仍應維持 `Free`

### 1. 目前 tier 與付費用戶

```sql
-- 付費用戶列表
select
  u.email,
  s.tier,
  s.status,
  s.started_at,
  s.expires_at,
  s.monthly_messages_used,
  s.daily_messages_used
from auth.users u
join public.subscriptions s on u.id = s.user_id
where s.tier != 'free'
order by s.started_at desc;

-- 各 tier 付費人數
select
  tier,
  count(*) as users
from public.subscriptions
where tier != 'free'
group by tier
order by users desc;

-- 真實付費訂閱（排除 test_users）
select
  user_id,
  tier,
  status,
  started_at,
  expires_at,
  monthly_messages_used,
  daily_messages_used
from public.real_subscriptions
where tier != 'free'
order by started_at desc;

-- 付費轉換率
select
  (select count(*) from public.subscriptions where tier != 'free') as paying_users,
  (select count(*) from public.subscriptions) as total_users,
  round(
    (
      (select count(*) from public.subscriptions where tier != 'free')::numeric
      / nullif((select count(*) from public.subscriptions), 0)
    ) * 100,
    1
  ) as conversion_rate_pct;
```

### 2. RevenueCat / 商店事件

```sql
-- 最近 RevenueCat webhook 原始事件
select
  created_at,
  source,
  event_type,
  user_id,
  payload
from public.webhook_logs
where source = 'revenuecat'
order by created_at desc
limit 50;

-- 查某個 user_id 最近的 RevenueCat webhook
select
  created_at,
  event_type,
  user_id,
  payload
from public.webhook_logs
where source = 'revenuecat'
  and user_id = 'USER_ID_HERE'
order by created_at desc
limit 50;

-- 最近營收事件（整理後）
select
  event_timestamp,
  created_at,
  user_id,
  event_type,
  product_id,
  price_usd,
  currency,
  transaction_id
from public.revenue_events
order by event_timestamp desc
limit 50;

-- 月營收
select *
from public.monthly_revenue
order by month desc;

-- 月毛利
select *
from public.monthly_profit
order by month desc;
```

## Auth / 註冊 / 深連結 SQL

```sql
-- 查某個 email 的 auth 狀態
select
  id,
  email,
  created_at,
  last_sign_in_at,
  email_confirmed_at
from auth.users
where email = 'xxx@xxx.com';

-- 查最近 Auth 診斷事件
select
  created_at,
  event,
  status,
  email_redacted,
  platform,
  app_version,
  build_number,
  error_code,
  message,
  metadata
from public.auth_diagnostics
order by created_at desc
limit 100;

-- 查特定 email 的 Auth 診斷事件
select
  created_at,
  event,
  status,
  error_code,
  message,
  metadata
from public.auth_diagnostics
where email_redacted = 'er***04@yahoo.com.tw'
order by created_at desc;
```

## 常用除錯 SQL

### 1. 查單一用戶的完整狀態

```sql
select
  u.id as user_id,
  u.email,
  s.tier,
  s.status,
  s.started_at,
  s.expires_at,
  s.monthly_messages_used,
  s.daily_messages_used,
  s.monthly_reset_at,
  s.daily_reset_at
from auth.users u
left join public.subscriptions s on u.id = s.user_id
where u.email = 'xxx@xxx.com';
```

### 2. 查單一用戶最近分析紀錄

```sql
select
  created_at,
  model,
  request_type,
  input_tokens,
  output_tokens,
  cost_usd,
  latency_ms,
  status,
  error_code,
  fallback_used,
  retry_count
from public.ai_logs
where user_id = (
  select id from auth.users where email = 'xxx@xxx.com'
)
order by created_at desc
limit 20;
```

### 3. 查最近 AI 失敗/被擋請求

```sql
select
  created_at,
  user_id,
  model,
  request_type,
  status,
  error_code,
  error_message
from public.ai_logs
where status in ('failed', 'filtered')
order by created_at desc
limit 50;
```

### 4. 查負面反饋

```sql
select
  created_at,
  user_id,
  rating,
  category,
  comment,
  user_tier,
  model_used
from public.feedback
where rating = 'negative'
order by created_at desc
limit 50;
```

## 常用手動修正 SQL

> 只在真的需要救火時用，跑之前先 double check email / user_id。

```sql
-- 手動改 tier（緊急用）
update public.subscriptions
set
  tier = 'essential',
  status = 'active'
where user_id = (
  select id from auth.users where email = 'xxx@xxx.com'
);

-- 重設每日額度（注意：daily quota 在 subscriptions，不在 rate_limits）
update public.subscriptions
set
  daily_messages_used = 0,
  daily_reset_at = now()
where user_id = (
  select id from auth.users where email = 'xxx@xxx.com'
);

-- 重設每月額度
update public.subscriptions
set
  monthly_messages_used = 0,
  monthly_reset_at = now()
where user_id = (
  select id from auth.users where email = 'xxx@xxx.com'
);

-- 同時重設每日 + 每月額度
update public.subscriptions
set
  daily_messages_used = 0,
  monthly_messages_used = 0,
  daily_reset_at = now(),
  monthly_reset_at = now()
where user_id = (
  select id from auth.users where email = 'xxx@xxx.com'
);
```

## 常見誤區

- `rate_limits` 不是每日/月額度表  
  它只是在做每分鐘 throttle。

- `webhook_logs` 沒有 `status` 欄位  
  如果要查 webhook 失敗，優先看 `Logs -> Edge Functions` 的 `revenuecat-webhook` runtime logs。

- `subscriptions.tier` 不是商店扣款真相本身  
  它是 app 目前同步到 Supabase 的 tier 狀態；訂閱真實來源仍要搭配 RevenueCat / App Store Connect 一起看。

- `restore / sync` 的真實來源是 `RevenueCat + 商店`  
  `Supabase.subscriptions` 是 app 內 tier 的同步結果，不是商店扣款真相來源。

- 同 Apple ID 下按 `同步已買過的訂閱` 讓另一個 VibeSync 帳號變 premium  
  在目前 RevenueCat 預設 `Transfer to new App User ID` 規則下，這是預期行為，不一定是 bug。

## 每日營運 Checklist

- [ ] 看新用戶數
- [ ] 看 tier 分佈有沒有異常變動
- [ ] 看今日 / 本月 AI 成本
- [ ] 看 `ai_logs` 失敗率
- [ ] 看負面反饋
- [ ] 看 `auth_diagnostics` 是否有異常集中事件
- [ ] 看 RevenueCat webhook 是否有異常事件或 transfer 爭議

## 補充文件

- [app-review-final-checklist.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/app-review-final-checklist.md)
- [current-test-status-2026-04-03.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/current-test-status-2026-04-03.md)
