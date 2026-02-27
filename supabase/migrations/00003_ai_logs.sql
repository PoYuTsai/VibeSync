-- supabase/migrations/00003_ai_logs.sql
-- AI 呼叫日誌表

CREATE TABLE ai_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,

  -- 請求資訊
  model TEXT NOT NULL,
  request_type TEXT NOT NULL DEFAULT 'analyze',

  -- Token 使用
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cost_usd DECIMAL(10, 6),

  -- 效能
  latency_ms INTEGER NOT NULL,

  -- 狀態
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'filtered')),
  error_code TEXT,

  -- 失敗時才記錄的完整內容 (成功時不記錄以節省空間)
  request_body JSONB,
  response_body JSONB,
  error_message TEXT,

  -- Fallback 資訊
  fallback_used BOOLEAN DEFAULT FALSE,
  retry_count INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_ai_logs_user_id ON ai_logs(user_id);
CREATE INDEX idx_ai_logs_created_at ON ai_logs(created_at);
CREATE INDEX idx_ai_logs_status ON ai_logs(status);
CREATE INDEX idx_ai_logs_model ON ai_logs(model);

-- RLS
ALTER TABLE ai_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own logs" ON ai_logs
  FOR SELECT USING (auth.uid() = user_id);

-- Service role can insert logs
CREATE POLICY "Service role can insert logs" ON ai_logs
  FOR INSERT WITH CHECK (TRUE);

-- 清理函數 (30 天)
CREATE OR REPLACE FUNCTION cleanup_old_ai_logs()
RETURNS void AS $$
BEGIN
  DELETE FROM ai_logs WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- 每日成本報表 View
CREATE VIEW daily_cost_report AS
SELECT
  DATE(created_at) as date,
  model,
  COUNT(*) as request_count,
  SUM(input_tokens) as total_input_tokens,
  SUM(output_tokens) as total_output_tokens,
  SUM(cost_usd) as total_cost_usd,
  AVG(latency_ms) as avg_latency_ms,
  COUNT(*) FILTER (WHERE status = 'success') as success_count,
  COUNT(*) FILTER (WHERE status = 'failed') as failed_count,
  COUNT(*) FILTER (WHERE status = 'filtered') as filtered_count
FROM ai_logs
GROUP BY DATE(created_at), model
ORDER BY date DESC, model;

-- 用戶月度 Token 使用 View
CREATE VIEW user_monthly_token_summary AS
SELECT
  user_id,
  DATE_TRUNC('month', created_at) as month,
  COUNT(*) as request_count,
  SUM(input_tokens) as total_input_tokens,
  SUM(output_tokens) as total_output_tokens,
  SUM(cost_usd) as total_cost_usd
FROM ai_logs
WHERE status = 'success'
GROUP BY user_id, DATE_TRUNC('month', created_at)
ORDER BY month DESC, total_cost_usd DESC;
