export type FinanceParty = "eric" | "bruce" | "platform" | "none";
export type FinanceEntryType = "revenue" | "expense";
export type SettlementMode = "contribution_split" | "net_profit_split";
export type SettlementStatus = "draft" | "review" | "locked" | "paid";

export type FinanceCategory =
  | "app_store_proceeds"
  | "google_play_proceeds"
  | "claude"
  | "apple_developer"
  | "domain"
  | "hosting"
  | "revenuecat"
  | "marketing"
  | "tooling"
  | "refund_adjustment"
  | "other";

export type BillingCycle =
  | "monthly"
  | "annual"
  | "one_time"
  | "usage_based"
  | "campaign_based";

export type RecognitionMethod =
  | "cash_basis"
  | "amortize_evenly"
  | "usage_based"
  | "manual_schedule";

export type CostRole =
  | "direct_variable_cost"
  | "fixed_overhead"
  | "growth_investment"
  | "personal"
  | "other";

export type SettlementTreatment =
  | "included_before_profit_split"
  | "excluded_for_now"
  | "pending_agreement";

export interface FinanceEntry {
  id: string;
  entry_date: string;
  paid_at: string | null;
  settlement_month: string;
  type: FinanceEntryType;
  title: string;
  category: FinanceCategory;
  amount: number | string;
  currency: string;
  amount_twd: number | string | null;
  fx_rate_to_twd: number | string | null;
  paid_by: FinanceParty;
  received_by: FinanceParty;
  billing_cycle: BillingCycle;
  recognition_method: RecognitionMethod;
  cost_role: CostRole;
  include_before_profit_split: boolean;
  settlement_treatment: SettlementTreatment;
  receipt_url: string | null;
  notes: string | null;
  deposit_status: string;
  source: string;
  created_at: string;
  updated_at: string;
}

export interface MonthlySettlement {
  id: string;
  settlement_month: string;
  status: SettlementStatus;
  settlement_mode: SettlementMode;
  reserve_amount_twd: number | string;
  reserve_reason: string | null;
  notes: string | null;
}

export interface FinanceSummary {
  month: string;
  mode: SettlementMode;
  status: SettlementStatus;
  revenueTotalTwd: number;
  refundAdjustmentTotalTwd: number;
  recordedExpenseTotalTwd: number;
  directVariableCostTotalTwd: number;
  deductedExpenseTotalTwd: number;
  operatingProfitTwd: number;
  settlementProfitTwd: number;
  reserveAmountTwd: number;
  distributableAmountTwd: number;
  ericActualCashTwd: number;
  bruceActualCashTwd: number;
  ericEntitlementTwd: number;
  bruceEntitlementTwd: number;
  amountEricShouldTransferToBruceTwd: number;
  amountBruceShouldTransferToEricTwd: number;
  carryOutTwd: number;
}
