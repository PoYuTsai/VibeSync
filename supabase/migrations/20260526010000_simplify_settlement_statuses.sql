-- Simplify monthly settlement statuses to Eric/Bruce-facing actions.

UPDATE public.monthly_settlements
SET status = CASE
  WHEN status IN ('locked', 'transfer_pending') THEN 'transfer_pending'
  WHEN status IN ('paid', 'completed') THEN 'completed'
  ELSE 'open'
END;

ALTER TABLE public.monthly_settlements
  ALTER COLUMN status SET DEFAULT 'open';

ALTER TABLE public.monthly_settlements
  DROP CONSTRAINT IF EXISTS monthly_settlements_status_check;

ALTER TABLE public.monthly_settlements
  ADD CONSTRAINT monthly_settlements_status_check
  CHECK (status IN ('open', 'transfer_pending', 'completed'));

NOTIFY pgrst, 'reload schema';
