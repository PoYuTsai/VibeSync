-- supabase/migrations/00005_token_usage.sql
-- Token 精確追蹤表 (用於計費和用量分析)

CREATE TABLE token_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,

  model TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  total_tokens INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,
  cost_usd DECIMAL(10, 6) NOT NULL,

  conversation_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_token_usage_user_id ON token_usage(user_id);
CREATE INDEX idx_token_usage_created_at ON token_usage(created_at);
CREATE INDEX idx_token_usage_conversation_id ON token_usage(conversation_id);
-- Note: Removed DATE_TRUNC index (not immutable in PostgreSQL)
-- Use idx_token_usage_user_id + idx_token_usage_created_at for monthly queries

-- RLS
ALTER TABLE token_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own token usage" ON token_usage
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Service role can insert token usage" ON token_usage
  FOR INSERT WITH CHECK (TRUE);

-- 對話成本彙總 View
CREATE VIEW conversation_cost_summary AS
SELECT
  user_id,
  conversation_id,
  COUNT(*) AS analysis_count,
  SUM(input_tokens) AS total_input_tokens,
  SUM(output_tokens) AS total_output_tokens,
  SUM(total_tokens) AS total_tokens,
  SUM(cost_usd) AS total_cost_usd,
  MIN(created_at) AS first_analysis,
  MAX(created_at) AS last_analysis
FROM token_usage
WHERE conversation_id IS NOT NULL
GROUP BY user_id, conversation_id
ORDER BY last_analysis DESC;

-- 模型使用分佈 View (管理用)
CREATE VIEW model_usage_distribution AS
SELECT
  DATE(created_at) AS date,
  model,
  COUNT(*) AS request_count,
  SUM(total_tokens) AS total_tokens,
  SUM(cost_usd) AS total_cost_usd,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY DATE(created_at)), 2) AS percentage
FROM token_usage
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at), model
ORDER BY date DESC, request_count DESC;
