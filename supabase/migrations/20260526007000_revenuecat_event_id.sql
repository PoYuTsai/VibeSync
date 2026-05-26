-- Store RevenueCat's webhook event id so revenue event ingestion is idempotent.

ALTER TABLE public.revenue_events
  ADD COLUMN IF NOT EXISTS revenuecat_event_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_revenue_events_revenuecat_event_id
  ON public.revenue_events(revenuecat_event_id)
  WHERE revenuecat_event_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
