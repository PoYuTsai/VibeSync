-- Simplify partner settlement modes to the two modes shown in the dashboard.

UPDATE public.monthly_settlements
SET settlement_mode = 'contribution_split'
WHERE settlement_mode = 'no_distribution';

ALTER TABLE public.monthly_settlements
  DROP CONSTRAINT IF EXISTS monthly_settlements_settlement_mode_check;

ALTER TABLE public.monthly_settlements
  ADD CONSTRAINT monthly_settlements_settlement_mode_check
  CHECK (settlement_mode IN ('contribution_split', 'net_profit_split'));

NOTIFY pgrst, 'reload schema';
