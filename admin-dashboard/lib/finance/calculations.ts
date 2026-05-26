import type {
  FinanceEntry,
  FinanceSummary,
  MonthlySettlement,
  SettlementMode,
  SettlementStatus,
} from "@/lib/finance/types";

const DEFAULT_MODE: SettlementMode = "contribution_split";
const DEFAULT_STATUS: SettlementStatus = "open";

function money(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function normalizeSettlementMode(value: unknown): SettlementMode {
  return value === "net_profit_split" ? "net_profit_split" : DEFAULT_MODE;
}

function normalizeSettlementStatus(value: unknown): SettlementStatus {
  if (value === "transfer_pending" || value === "locked") {
    return "transfer_pending";
  }

  if (value === "completed" || value === "paid") {
    return "completed";
  }

  return DEFAULT_STATUS;
}

export function monthDateFromKey(monthKey?: string | null) {
  const now = new Date();
  const fallback = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  const key = monthKey && /^\d{4}-\d{2}$/.test(monthKey) ? monthKey : fallback;
  return `${key}-01`;
}

export function monthKeyFromDate(dateValue: string | Date) {
  const date = typeof dateValue === "string" ? new Date(dateValue) : dateValue;
  if (Number.isNaN(date.getTime())) {
    return monthDateFromKey().slice(0, 7);
  }
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export function toTwdAmount(entry: FinanceEntry) {
  const amountTwd = Number(entry.amount_twd);
  if (Number.isFinite(amountTwd)) {
    return amountTwd;
  }

  const amount = Number(entry.amount || 0);
  if (entry.currency.toUpperCase() === "TWD") {
    return amount;
  }

  const fxRate = Number(entry.fx_rate_to_twd);
  if (Number.isFinite(fxRate) && fxRate > 0) {
    return amount * fxRate;
  }

  return 0;
}

function expenseAmount(entry: FinanceEntry) {
  return Math.abs(toTwdAmount(entry));
}

function isDeductedExpense(entry: FinanceEntry, mode: SettlementMode) {
  if (entry.type !== "expense") {
    return false;
  }

  const isExplicitlyIncluded =
    entry.include_before_profit_split ||
    entry.settlement_treatment === "included_before_profit_split";

  if (mode === "contribution_split") {
    return entry.cost_role === "direct_variable_cost" && isExplicitlyIncluded;
  }

  return isExplicitlyIncluded;
}

export function calculateFinanceSummary(params: {
  month: string;
  entries: FinanceEntry[];
  settlement?: MonthlySettlement | null;
}): FinanceSummary {
  const mode = normalizeSettlementMode(params.settlement?.settlement_mode);
  const status = normalizeSettlementStatus(params.settlement?.status);
  const reserveAmountTwd = money(Number(params.settlement?.reserve_amount_twd || 0));

  const revenueEntries = params.entries.filter((entry) => entry.type === "revenue");
  const expenseEntries = params.entries.filter((entry) => entry.type === "expense");
  const deductedExpenses = expenseEntries.filter((entry) =>
    isDeductedExpense(entry, mode)
  );

  const revenueTotalTwd = money(
    revenueEntries.reduce((sum, entry) => sum + toTwdAmount(entry), 0)
  );
  const refundAdjustmentTotalTwd = money(
    params.entries
      .filter((entry) => entry.category === "refund_adjustment")
      .reduce((sum, entry) => sum + toTwdAmount(entry), 0)
  );
  const recordedExpenseTotalTwd = money(
    expenseEntries.reduce((sum, entry) => sum + expenseAmount(entry), 0)
  );
  const directVariableCostTotalTwd = money(
    expenseEntries
      .filter((entry) => entry.cost_role === "direct_variable_cost")
      .reduce((sum, entry) => sum + expenseAmount(entry), 0)
  );
  const deductedExpenseTotalTwd = money(
    deductedExpenses.reduce((sum, entry) => sum + expenseAmount(entry), 0)
  );

  const operatingProfitTwd = money(revenueTotalTwd - recordedExpenseTotalTwd);
  const settlementProfitTwd = money(revenueTotalTwd - deductedExpenseTotalTwd);
  const distributableAmountTwd = money(
    Math.max(settlementProfitTwd - reserveAmountTwd, 0)
  );

  const ericEntitlementTwd = money(distributableAmountTwd / 2);
  const bruceEntitlementTwd = money(distributableAmountTwd / 2);

  const ericRevenueTwd = revenueEntries
    .filter((entry) => entry.received_by === "eric")
    .reduce((sum, entry) => sum + toTwdAmount(entry), 0);
  const bruceRevenueTwd = revenueEntries
    .filter((entry) => entry.received_by === "bruce")
    .reduce((sum, entry) => sum + toTwdAmount(entry), 0);
  const ericDeductedCostsTwd = deductedExpenses
    .filter((entry) => entry.paid_by === "eric")
    .reduce((sum, entry) => sum + expenseAmount(entry), 0);
  const bruceDeductedCostsTwd = deductedExpenses
    .filter((entry) => entry.paid_by === "bruce")
    .reduce((sum, entry) => sum + expenseAmount(entry), 0);

  const ericActualCashTwd = money(ericRevenueTwd - ericDeductedCostsTwd);
  const bruceActualCashTwd = money(bruceRevenueTwd - bruceDeductedCostsTwd);

  let amountEricShouldTransferToBruceTwd = 0;
  let amountBruceShouldTransferToEricTwd = 0;

  if (distributableAmountTwd > 0) {
    const ericBalance = money(ericActualCashTwd - ericEntitlementTwd);
    const bruceBalance = money(bruceActualCashTwd - bruceEntitlementTwd);

    if (ericBalance > 0 && bruceBalance < 0) {
      amountEricShouldTransferToBruceTwd = money(
        Math.min(ericBalance, Math.abs(bruceBalance))
      );
    } else if (bruceBalance > 0 && ericBalance < 0) {
      amountBruceShouldTransferToEricTwd = money(
        Math.min(bruceBalance, Math.abs(ericBalance))
      );
    }
  } else if (settlementProfitTwd < 0) {
    if (ericActualCashTwd > 0 && bruceActualCashTwd < 0) {
      amountEricShouldTransferToBruceTwd = money(
        Math.min(ericActualCashTwd, Math.abs(bruceActualCashTwd))
      );
    } else if (bruceActualCashTwd > 0 && ericActualCashTwd < 0) {
      amountBruceShouldTransferToEricTwd = money(
        Math.min(bruceActualCashTwd, Math.abs(ericActualCashTwd))
      );
    }
  }

  return {
    month: params.month,
    mode,
    status,
    revenueTotalTwd,
    refundAdjustmentTotalTwd,
    recordedExpenseTotalTwd,
    directVariableCostTotalTwd,
    deductedExpenseTotalTwd,
    operatingProfitTwd,
    settlementProfitTwd,
    reserveAmountTwd,
    distributableAmountTwd,
    ericActualCashTwd,
    bruceActualCashTwd,
    ericEntitlementTwd,
    bruceEntitlementTwd,
    amountEricShouldTransferToBruceTwd,
    amountBruceShouldTransferToEricTwd,
    carryOutTwd: money(Math.max(-settlementProfitTwd, 0)),
  };
}
