-- Persist RevenueCat product details so admin can distinguish monthly vs
-- quarterly Starter / Essential subscriptions.

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS active_product_id TEXT;

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS billing_period TEXT CHECK (
    billing_period IS NULL OR billing_period IN ('monthly', 'quarterly', 'unknown')
  );

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS store TEXT;

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS revenuecat_environment TEXT;

CREATE INDEX IF NOT EXISTS idx_subscriptions_active_product_id
  ON public.subscriptions(active_product_id);

CREATE INDEX IF NOT EXISTS idx_subscriptions_billing_period
  ON public.subscriptions(billing_period);

CREATE OR REPLACE FUNCTION public.infer_subscription_billing_period(
  product_id TEXT
)
RETURNS TEXT AS $$
BEGIN
  IF product_id IS NULL OR length(trim(product_id)) = 0 THEN
    RETURN NULL;
  END IF;

  IF lower(product_id) LIKE '%quarter%' OR lower(product_id) LIKE '%p3m%' THEN
    RETURN 'quarterly';
  END IF;

  IF lower(product_id) LIKE '%monthly%' OR lower(product_id) LIKE '%p1m%' THEN
    RETURN 'monthly';
  END IF;

  RETURN 'unknown';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

WITH latest_product AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    product_id,
    occurred_at
  FROM (
    SELECT
      re.user_id,
      re.product_id,
      re.event_timestamp AS occurred_at
    FROM public.revenue_events re
    WHERE re.product_id IS NOT NULL

    UNION ALL

    SELECT
      wl.user_id::UUID AS user_id,
      COALESCE(
        wl.payload->>'new_product_id',
        wl.payload->>'product_id'
      ) AS product_id,
      wl.created_at AS occurred_at
    FROM public.webhook_logs wl
    WHERE wl.source = 'revenuecat'
      AND wl.user_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      AND COALESCE(wl.payload->>'new_product_id', wl.payload->>'product_id') IS NOT NULL
  ) source_rows
  ORDER BY user_id, occurred_at DESC
)
UPDATE public.subscriptions s
SET
  active_product_id = COALESCE(s.active_product_id, lp.product_id),
  billing_period = COALESCE(
    s.billing_period,
    public.infer_subscription_billing_period(lp.product_id)
  )
FROM latest_product lp
WHERE s.user_id = lp.user_id;

NOTIFY pgrst, 'reload schema';
