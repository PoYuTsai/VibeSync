-- webhook_logs 表：追蹤 RevenueCat webhook 事件
CREATE TABLE IF NOT EXISTS public.webhook_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL,
  event_type TEXT,
  user_id TEXT,
  payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 建立索引方便查詢
CREATE INDEX idx_webhook_logs_source ON public.webhook_logs(source);
CREATE INDEX idx_webhook_logs_created_at ON public.webhook_logs(created_at DESC);
CREATE INDEX idx_webhook_logs_user_id ON public.webhook_logs(user_id);

-- RLS 設定：只有 service role 能寫入
ALTER TABLE public.webhook_logs ENABLE ROW LEVEL SECURITY;

-- Service role 可以 insert
CREATE POLICY "Service role can insert webhook logs" ON public.webhook_logs
  FOR INSERT TO service_role
  WITH CHECK (true);

-- Service role 可以 select（用於查詢）
CREATE POLICY "Service role can select webhook logs" ON public.webhook_logs
  FOR SELECT TO service_role
  USING (true);

COMMENT ON TABLE public.webhook_logs IS 'RevenueCat webhook 事件記錄，用於追蹤訂閱狀態變更';
