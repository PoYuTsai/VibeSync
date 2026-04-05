-- Round 6 security hardening:
-- 1. allow a second alert sink (`webhook`) in addition to Telegram
-- 2. keep historical alert-event rows valid after the channel expansion

DO $$
DECLARE
  existing_constraint_name text;
BEGIN
  SELECT c.conname
  INTO existing_constraint_name
  FROM pg_constraint c
  WHERE c.conrelid = 'public.security_alert_events'::regclass
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%channel%telegram%';

  IF existing_constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.security_alert_events DROP CONSTRAINT %I',
      existing_constraint_name
    );
  END IF;
END;
$$;

ALTER TABLE public.security_alert_events
  ADD CONSTRAINT security_alert_events_channel_check
  CHECK (channel IN ('telegram', 'webhook'));
