-- Round 6 business observability hardening:
-- 1. make revenue_events dedupe-friendly
-- 2. tolerate missing price fields without poisoning monthly summaries

ALTER TABLE public.revenue_events
  ADD COLUMN IF NOT EXISTS source_event_id TEXT,
  ADD COLUMN IF NOT EXISTS price_in_purchased_currency DECIMAL(10, 2),
  ADD COLUMN IF NOT EXISTS store TEXT;

ALTER TABLE public.revenue_events
  ALTER COLUMN price_usd DROP NOT NULL;

DROP POLICY IF EXISTS "Service role can update revenue_events"
  ON public.revenue_events;

CREATE POLICY "Service role can update revenue_events"
  ON public.revenue_events
  FOR UPDATE TO service_role
  USING (true)
  WITH CHECK (true);

CREATE UNIQUE INDEX IF NOT EXISTS idx_revenue_events_source_event_id_unique
  ON public.revenue_events(source_event_id)
  WHERE source_event_id IS NOT NULL;

CREATE OR REPLACE VIEW monthly_revenue AS
SELECT
  DATE_TRUNC('month', event_timestamp) AS month,
  SUM(
    CASE
      WHEN event_type IN ('INITIAL_PURCHASE', 'RENEWAL')
        THEN COALESCE(price_usd, 0)
      ELSE 0
    END
  ) AS revenue,
  SUM(CASE WHEN event_type = 'INITIAL_PURCHASE' THEN 1 ELSE 0 END) AS new_subscriptions,
  SUM(CASE WHEN event_type = 'RENEWAL' THEN 1 ELSE 0 END) AS renewals,
  SUM(CASE WHEN event_type = 'CANCELLATION' THEN 1 ELSE 0 END) AS cancellations,
  COUNT(DISTINCT user_id) AS paying_users
FROM revenue_events
GROUP BY DATE_TRUNC('month', event_timestamp)
ORDER BY month DESC;
