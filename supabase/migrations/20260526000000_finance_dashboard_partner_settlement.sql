-- Finance Dashboard + Partner Settlement V1
-- Shared Eric/Bruce operating ledger and monthly settlement tables.

CREATE TABLE IF NOT EXISTS public.finance_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
  paid_at DATE,
  settlement_month DATE NOT NULL,
  store_report_month DATE,
  store_fiscal_period_start DATE,
  store_fiscal_period_end DATE,
  type TEXT NOT NULL CHECK (type IN ('revenue', 'expense')),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  category TEXT NOT NULL DEFAULT 'other' CHECK (category IN (
    'app_store_proceeds',
    'google_play_proceeds',
    'claude',
    'apple_developer',
    'domain',
    'hosting',
    'revenuecat',
    'marketing',
    'tooling',
    'refund_adjustment',
    'other'
  )),
  amount NUMERIC(14, 2) NOT NULL CHECK (amount <> 0),
  currency TEXT NOT NULL DEFAULT 'TWD' CHECK (char_length(currency) BETWEEN 3 AND 8),
  amount_twd NUMERIC(14, 2),
  fx_rate_to_twd NUMERIC(14, 6),
  bank_received_amount NUMERIC(14, 2),
  bank_received_currency TEXT CHECK (bank_received_currency IS NULL OR char_length(bank_received_currency) BETWEEN 3 AND 8),
  bank_fee_amount NUMERIC(14, 2),
  deposit_status TEXT NOT NULL DEFAULT 'not_applicable' CHECK (deposit_status IN (
    'not_applicable',
    'pending',
    'received',
    'returned',
    'held_below_threshold'
  )),
  paid_by TEXT NOT NULL DEFAULT 'none' CHECK (paid_by IN ('eric', 'bruce', 'platform', 'none')),
  received_by TEXT NOT NULL DEFAULT 'none' CHECK (received_by IN ('eric', 'bruce', 'platform', 'none')),
  billing_cycle TEXT NOT NULL DEFAULT 'one_time' CHECK (billing_cycle IN (
    'monthly',
    'annual',
    'one_time',
    'usage_based',
    'campaign_based'
  )),
  recognition_method TEXT NOT NULL DEFAULT 'cash_basis' CHECK (recognition_method IN (
    'cash_basis',
    'amortize_evenly',
    'usage_based',
    'manual_schedule'
  )),
  cost_role TEXT NOT NULL DEFAULT 'fixed_overhead' CHECK (cost_role IN (
    'direct_variable_cost',
    'fixed_overhead',
    'growth_investment',
    'personal',
    'other'
  )),
  include_before_profit_split BOOLEAN NOT NULL DEFAULT FALSE,
  settlement_treatment TEXT NOT NULL DEFAULT 'excluded_for_now' CHECK (settlement_treatment IN (
    'included_before_profit_split',
    'excluded_for_now',
    'pending_agreement'
  )),
  service_period_start DATE,
  service_period_end DATE,
  amortization_months INTEGER CHECK (amortization_months IS NULL OR amortization_months > 0),
  amortization_start_month DATE,
  next_renewal_date DATE,
  receipt_url TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN (
    'manual',
    'apple_report',
    'google_report',
    'revenuecat_observation',
    'system_estimate'
  )),
  external_reference TEXT,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_finance_entries_month ON public.finance_entries(settlement_month);
CREATE INDEX IF NOT EXISTS idx_finance_entries_type ON public.finance_entries(type);
CREATE INDEX IF NOT EXISTS idx_finance_entries_treatment ON public.finance_entries(settlement_treatment);
CREATE INDEX IF NOT EXISTS idx_finance_entries_paid_by ON public.finance_entries(paid_by);
CREATE INDEX IF NOT EXISTS idx_finance_entries_received_by ON public.finance_entries(received_by);

CREATE TABLE IF NOT EXISTS public.cost_recognition_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  finance_entry_id UUID NOT NULL REFERENCES public.finance_entries(id) ON DELETE CASCADE,
  recognition_month DATE NOT NULL,
  amount NUMERIC(14, 2) NOT NULL,
  amount_twd NUMERIC(14, 2),
  include_before_profit_split BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(finance_entry_id, recognition_month)
);

CREATE INDEX IF NOT EXISTS idx_cost_recognition_month ON public.cost_recognition_schedule(recognition_month);

CREATE TABLE IF NOT EXISTS public.monthly_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_month DATE NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'review', 'locked', 'paid')),
  settlement_mode TEXT NOT NULL DEFAULT 'contribution_split' CHECK (settlement_mode IN (
    'contribution_split',
    'net_profit_split',
    'no_distribution'
  )),
  revenue_total_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  refund_adjustment_total_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  recorded_expense_total_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  deducted_expense_total_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  direct_variable_cost_total_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  operating_profit_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  settlement_profit_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  reserve_amount_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  reserve_reason TEXT,
  distributable_amount_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  eric_actual_cash_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  bruce_actual_cash_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  eric_entitlement_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  bruce_entitlement_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  carry_in_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  amount_eric_should_transfer_to_bruce_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  amount_bruce_should_transfer_to_eric_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  carry_out_twd NUMERIC(14, 2) NOT NULL DEFAULT 0,
  locked_by UUID REFERENCES auth.users(id),
  locked_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_monthly_settlements_month ON public.monthly_settlements(settlement_month);
CREATE INDEX IF NOT EXISTS idx_monthly_settlements_status ON public.monthly_settlements(status);

CREATE TABLE IF NOT EXISTS public.settlement_line_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id UUID NOT NULL REFERENCES public.monthly_settlements(id) ON DELETE CASCADE,
  finance_entry_id UUID REFERENCES public.finance_entries(id) ON DELETE SET NULL,
  snapshot JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_settlement_line_items_settlement ON public.settlement_line_items(settlement_id);

CREATE TABLE IF NOT EXISTS public.finance_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id UUID,
  old_values JSONB,
  new_values JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_finance_audit_logs_created ON public.finance_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_finance_audit_logs_record ON public.finance_audit_logs(table_name, record_id);

CREATE TABLE IF NOT EXISTS public.bank_deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deposit_date DATE NOT NULL,
  bank_account_label TEXT NOT NULL,
  amount NUMERIC(14, 2) NOT NULL,
  currency TEXT NOT NULL CHECK (char_length(currency) BETWEEN 3 AND 8),
  fx_rate_to_twd NUMERIC(14, 6),
  bank_fee_amount NUMERIC(14, 2),
  related_finance_entry_id UUID REFERENCES public.finance_entries(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'received' CHECK (status IN ('received', 'returned', 'unmatched')),
  statement_url TEXT,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bank_deposits_date ON public.bank_deposits(deposit_date DESC);
CREATE INDEX IF NOT EXISTS idx_bank_deposits_related_entry ON public.bank_deposits(related_finance_entry_id);

CREATE OR REPLACE FUNCTION public.update_finance_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS finance_entries_updated_at ON public.finance_entries;
CREATE TRIGGER finance_entries_updated_at
  BEFORE UPDATE ON public.finance_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.update_finance_updated_at();

DROP TRIGGER IF EXISTS monthly_settlements_updated_at ON public.monthly_settlements;
CREATE TRIGGER monthly_settlements_updated_at
  BEFORE UPDATE ON public.monthly_settlements
  FOR EACH ROW
  EXECUTE FUNCTION public.update_finance_updated_at();

DROP TRIGGER IF EXISTS bank_deposits_updated_at ON public.bank_deposits;
CREATE TRIGGER bank_deposits_updated_at
  BEFORE UPDATE ON public.bank_deposits
  FOR EACH ROW
  EXECUTE FUNCTION public.update_finance_updated_at();

CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.admin_users
    WHERE lower(email) = lower(auth.jwt()->>'email')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

ALTER TABLE public.finance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cost_recognition_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_deposits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage finance_entries" ON public.finance_entries
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

CREATE POLICY "Admins can manage cost_recognition_schedule" ON public.cost_recognition_schedule
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

CREATE POLICY "Admins can manage monthly_settlements" ON public.monthly_settlements
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

CREATE POLICY "Admins can manage settlement_line_items" ON public.settlement_line_items
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

CREATE POLICY "Admins can read finance_audit_logs" ON public.finance_audit_logs
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

CREATE POLICY "Admins can insert finance_audit_logs" ON public.finance_audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_user());

CREATE POLICY "Admins can manage bank_deposits" ON public.bank_deposits
  FOR ALL TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

-- Bruce admin whitelist. Passwords must stay in Supabase Auth only, never in repo.
INSERT INTO public.admin_users (email, name)
VALUES ('chiang688041@gmail.com', 'Bruce')
ON CONFLICT (email) DO UPDATE
SET name = COALESCE(public.admin_users.name, EXCLUDED.name);
