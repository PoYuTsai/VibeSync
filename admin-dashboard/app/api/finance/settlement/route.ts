import { NextResponse } from "next/server";
import { calculateFinanceSummary, monthDateFromKey } from "@/lib/finance/calculations";
import type {
  FinanceEntry,
  MonthlySettlement,
  SettlementMode,
  SettlementStatus,
} from "@/lib/finance/types";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

const SETTLEMENT_MODES: SettlementMode[] = [
  "contribution_split",
  "net_profit_split",
  "no_distribution",
];
const STATUSES: SettlementStatus[] = ["draft", "review", "locked", "paid"];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function asEnum<T extends string>(value: unknown, options: readonly T[], fallback: T) {
  return typeof value === "string" && options.includes(value as T)
    ? (value as T)
    : fallback;
}

function asNullableText(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function asNumber(value: unknown, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

export async function PATCH(request: Request) {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return jsonError(admin.error, admin.status);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonError("Invalid request body", 400);
  }

  if (!isRecord(body)) {
    return jsonError("Invalid request body", 400);
  }

  const settlementMonth = monthDateFromKey(
    typeof body.month === "string" ? body.month : null
  );
  const monthKey = settlementMonth.slice(0, 7);
  const mode = asEnum(body.settlement_mode, SETTLEMENT_MODES, "contribution_split");
  const status = asEnum(body.status, STATUSES, "draft");

  const { data: entriesData, error: entriesError } = await admin.session.supabase
    .from("finance_entries")
    .select("*")
    .eq("settlement_month", settlementMonth);

  if (entriesError) {
    return jsonError(entriesError.message, 500);
  }

  const settlementDraft: MonthlySettlement = {
    id: "",
    settlement_month: settlementMonth,
    status,
    settlement_mode: mode,
    reserve_amount_twd: asNumber(body.reserve_amount_twd, 0),
    reserve_reason: asNullableText(body.reserve_reason),
    notes: asNullableText(body.notes),
  };
  const summary = calculateFinanceSummary({
    month: monthKey,
    entries: (entriesData ?? []) as FinanceEntry[],
    settlement: settlementDraft,
  });

  const payload = {
    settlement_month: settlementMonth,
    status,
    settlement_mode: mode,
    revenue_total_twd: summary.revenueTotalTwd,
    refund_adjustment_total_twd: summary.refundAdjustmentTotalTwd,
    recorded_expense_total_twd: summary.recordedExpenseTotalTwd,
    deducted_expense_total_twd: summary.deductedExpenseTotalTwd,
    direct_variable_cost_total_twd: summary.directVariableCostTotalTwd,
    operating_profit_twd: summary.operatingProfitTwd,
    settlement_profit_twd: summary.settlementProfitTwd,
    reserve_amount_twd: summary.reserveAmountTwd,
    reserve_reason: settlementDraft.reserve_reason,
    distributable_amount_twd: summary.distributableAmountTwd,
    eric_actual_cash_twd: summary.ericActualCashTwd,
    bruce_actual_cash_twd: summary.bruceActualCashTwd,
    eric_entitlement_twd: summary.ericEntitlementTwd,
    bruce_entitlement_twd: summary.bruceEntitlementTwd,
    amount_eric_should_transfer_to_bruce_twd:
      summary.amountEricShouldTransferToBruceTwd,
    amount_bruce_should_transfer_to_eric_twd:
      summary.amountBruceShouldTransferToEricTwd,
    carry_out_twd: summary.carryOutTwd,
    locked_by: status === "locked" ? admin.session.user.id : null,
    locked_at: status === "locked" ? new Date().toISOString() : null,
    paid_at: status === "paid" ? new Date().toISOString() : null,
    notes: settlementDraft.notes,
    created_by: admin.session.user.id,
    updated_by: admin.session.user.id,
  };

  const { data, error } = await admin.session.supabase
    .from("monthly_settlements")
    .upsert(payload, { onConflict: "settlement_month" })
    .select("*")
    .single();

  if (error) {
    return jsonError(error.message, 500);
  }

  await admin.session.supabase.from("finance_audit_logs").insert({
    actor_user_id: admin.session.user.id,
    action: "upsert",
    table_name: "monthly_settlements",
    record_id: data.id,
    new_values: data,
  });

  return NextResponse.json({ settlement: data, summary });
}
