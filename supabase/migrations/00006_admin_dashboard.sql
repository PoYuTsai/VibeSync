-- supabase/migrations/00006_admin_dashboard.sql

-- Admin 用戶白名單
CREATE TABLE admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 營收事件 (RevenueCat Webhook)
CREATE TABLE revenue_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  event_type TEXT NOT NULL CHECK (event_type IN (
    'INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION',
    'BILLING_ISSUE', 'PRODUCT_CHANGE'
  )),
  product_id TEXT NOT NULL,
  price_usd DECIMAL(10, 2) NOT NULL,
  currency TEXT DEFAULT 'TWD',
  transaction_id TEXT,
  event_timestamp TIMESTAMPTZ NOT NULL,
  raw_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_revenue_events_user_id ON revenue_events(user_id);
CREATE INDEX idx_revenue_events_timestamp ON revenue_events(event_timestamp);
CREATE INDEX idx_revenue_events_type ON revenue_events(event_type);

-- RLS (Admin 專用)
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_events ENABLE ROW LEVEL SECURITY;

-- Admin 可以讀取所有資料
CREATE POLICY "Admin can read admin_users" ON admin_users
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM admin_users WHERE email = auth.jwt()->>'email')
  );

CREATE POLICY "Admin can read revenue_events" ON revenue_events
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM admin_users WHERE email = auth.jwt()->>'email')
  );

-- Service role can manage admin_users
CREATE POLICY "Service role can manage admin_users" ON admin_users
  FOR ALL USING (true);

-- Service role can insert revenue_events (for webhooks)
CREATE POLICY "Service role can insert revenue_events" ON revenue_events
  FOR INSERT WITH CHECK (true);

-- 月度營收彙總 View
CREATE OR REPLACE VIEW monthly_revenue AS
SELECT
  DATE_TRUNC('month', event_timestamp) AS month,
  SUM(CASE WHEN event_type IN ('INITIAL_PURCHASE', 'RENEWAL') THEN price_usd ELSE 0 END) AS revenue,
  SUM(CASE WHEN event_type = 'INITIAL_PURCHASE' THEN 1 ELSE 0 END) AS new_subscriptions,
  SUM(CASE WHEN event_type = 'RENEWAL' THEN 1 ELSE 0 END) AS renewals,
  SUM(CASE WHEN event_type = 'CANCELLATION' THEN 1 ELSE 0 END) AS cancellations,
  COUNT(DISTINCT user_id) AS paying_users
FROM revenue_events
GROUP BY DATE_TRUNC('month', event_timestamp)
ORDER BY month DESC;

-- 月度利潤 View
CREATE OR REPLACE VIEW monthly_profit AS
SELECT
  r.month,
  r.revenue,
  COALESCE(t.total_cost_usd, 0) AS cost,
  r.revenue - COALESCE(t.total_cost_usd, 0) AS profit,
  CASE WHEN r.revenue > 0
    THEN ROUND(((r.revenue - COALESCE(t.total_cost_usd, 0)) / r.revenue * 100)::DECIMAL, 2)
    ELSE 0
  END AS margin_percent,
  r.paying_users,
  CASE WHEN r.paying_users > 0
    THEN ROUND((COALESCE(t.total_cost_usd, 0) / r.paying_users)::DECIMAL, 4)
    ELSE 0
  END AS cost_per_user
FROM monthly_revenue r
LEFT JOIN (
  SELECT DATE_TRUNC('month', created_at) AS month, SUM(cost_usd) AS total_cost_usd
  FROM token_usage
  GROUP BY DATE_TRUNC('month', created_at)
) t ON r.month = t.month;

-- AI 成功率 View
CREATE OR REPLACE VIEW ai_success_rate AS
SELECT
  DATE_TRUNC('day', created_at) AS date,
  COUNT(*) AS total_requests,
  SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
  SUM(CASE WHEN status = 'filtered' THEN 1 ELSE 0 END) AS filtered_count,
  ROUND((SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END)::DECIMAL / COUNT(*) * 100), 2) AS success_rate
FROM ai_logs
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY date DESC;

-- 用戶活躍度 View (DAU)
CREATE OR REPLACE VIEW user_activity AS
SELECT
  DATE_TRUNC('day', created_at) AS date,
  COUNT(DISTINCT user_id) AS dau
FROM ai_logs
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY date DESC;

-- 測試用戶表 (用於排除測試資料)
CREATE TABLE test_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_test_users_user_id ON test_users(user_id);

ALTER TABLE test_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage test_users" ON test_users
  FOR ALL USING (true);

-- 真實用戶 View (排除測試帳號)
CREATE OR REPLACE VIEW real_users AS
SELECT u.*
FROM users u
WHERE NOT EXISTS (
  SELECT 1 FROM test_users t WHERE t.user_id = u.id
);

-- 真實訂閱 View (排除測試帳號)
CREATE OR REPLACE VIEW real_subscriptions AS
SELECT s.*
FROM subscriptions s
WHERE NOT EXISTS (
  SELECT 1 FROM test_users t WHERE t.user_id = s.user_id
);
