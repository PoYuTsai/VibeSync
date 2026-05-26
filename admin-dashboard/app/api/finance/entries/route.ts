import { NextResponse } from "next/server";
import { monthDateFromKey, monthKeyFromDate } from "@/lib/finance/calculations";
import type {
  BillingCycle,
  CostRole,
  FinanceCategory,
  FinanceEntryType,
  FinanceParty,
  RecognitionMethod,
  SettlementTreatment,
} from "@/lib/finance/types";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

const ENTRY_TYPES: FinanceEntryType[] = ["revenue", "expense"];
const CATEGORIES: FinanceCategory[] = [
  "app_store_proceeds",
  "google_play_proceeds",
  "claude",
  "apple_developer",
  "domain",
  "hosting",
  "revenuecat",
  "marketing",
  "tooling",
  "refund_adjustment",
  "other",
];
const PARTIES: FinanceParty[] = ["eric", "bruce", "platform", "none"];
const BILLING_CYCLES: BillingCycle[] = [
  "monthly",
  "annual",
  "one_time",
  "usage_based",
  "campaign_based",
];
const RECOGNITION_METHODS: RecognitionMethod[] = [
  "cash_basis",
  "amortize_evenly",
  "usage_based",
  "manual_schedule",
];
const COST_ROLES: CostRole[] = [
  "direct_variable_cost",
  "fixed_overhead",
  "growth_investment",
  "personal",
  "other",
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function asEnum<T extends string>(value: unknown, options: readonly T[], fallback: T) {
  return typeof value === "string" && options.includes(value as T)
    ? (value as T)
    : fallback;
}

function asText(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function asNullableText(value: unknown) {
  const text = asText(value);
  return text.length > 0 ? text : null;
}

function asDate(value: unknown, fallback: string) {
  const text = asText(value);
  return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : fallback;
}

function asNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? number : NaN;
}

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

export async function POST(request: Request) {
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

  const type = asEnum(body.type, ENTRY_TYPES, "expense");
  const title = asText(body.title);
  const amount = asNumber(body.amount);

  if (!title || title.length > 160) {
    return jsonError("Title is required and must be shorter than 160 characters", 400);
  }

  if (!Number.isFinite(amount) || amount === 0) {
    return jsonError("Amount must be a non-zero number", 400);
  }

  const today = new Date().toISOString().slice(0, 10);
  const entryDate = asDate(body.entry_date, today);
  const monthKey = asText(body.month) || monthKeyFromDate(entryDate);
  const settlementMonth = monthDateFromKey(monthKey);
  const { data: settlementLock, error: settlementLockError } =
    await admin.session.supabase
      .from("monthly_settlements")
      .select("status")
      .eq("settlement_month", settlementMonth)
      .maybeSingle();

  if (settlementLockError) {
    return jsonError(settlementLockError.message, 500);
  }

  if (
    settlementLock?.status === "transfer_pending" ||
    settlementLock?.status === "completed" ||
    settlementLock?.status === "locked" ||
    settlementLock?.status === "paid"
  ) {
    return jsonError("This settlement month is already confirmed", 409);
  }

  const costRole = asEnum(body.cost_role, COST_ROLES, "fixed_overhead");
  const defaultIncluded = type === "expense" && costRole === "direct_variable_cost";
  const includeBeforeProfitSplit =
    costRole === "personal"
      ? false
      : typeof body.include_before_profit_split === "boolean"
      ? body.include_before_profit_split
      : defaultIncluded;
  const settlementTreatment: SettlementTreatment = includeBeforeProfitSplit
    ? "included_before_profit_split"
    : "excluded_for_now";
  const currency = (asText(body.currency) || "TWD").toUpperCase();
  const amountTwdInput = asNumber(body.amount_twd);
  const fxRateInput = asNumber(body.fx_rate_to_twd);
  const hasFxRate = Number.isFinite(fxRateInput) && fxRateInput > 0;
  const hasAmountTwd = Number.isFinite(amountTwdInput);
  const fxRateToTwd = currency === "TWD" ? 1 : hasFxRate ? fxRateInput : null;
  const amountTwd =
    currency === "TWD"
      ? amount
      : hasAmountTwd
        ? amountTwdInput
        : hasFxRate
          ? Math.round((amount * fxRateInput + Number.EPSILON) * 100) / 100
          : null;

  if (currency !== "TWD" && !amountTwd) {
    return jsonError("Non-TWD entries require an FX rate or TWD amount", 400);
  }

  const payload = {
    entry_date: entryDate,
    paid_at: asNullableText(body.paid_at),
    settlement_month: settlementMonth,
    type,
    title,
    category: asEnum(body.category, CATEGORIES, "other"),
    amount,
    currency,
    amount_twd: amountTwd,
    fx_rate_to_twd: fxRateToTwd,
    paid_by:
      type === "expense"
        ? asEnum(body.paid_by, PARTIES, "eric")
        : asEnum(body.paid_by, PARTIES, "none"),
    received_by:
      type === "revenue"
        ? asEnum(body.received_by, PARTIES, "eric")
        : asEnum(body.received_by, PARTIES, "none"),
    billing_cycle: asEnum(body.billing_cycle, BILLING_CYCLES, "one_time"),
    recognition_method: asEnum(
      body.recognition_method,
      RECOGNITION_METHODS,
      "cash_basis"
    ),
    cost_role: costRole,
    include_before_profit_split: includeBeforeProfitSplit,
    settlement_treatment: settlementTreatment,
    receipt_url: asNullableText(body.receipt_url),
    notes: asNullableText(body.notes),
    created_by: admin.session.user.id,
    updated_by: admin.session.user.id,
  };

  const { data, error } = await admin.session.supabase
    .from("finance_entries")
    .insert(payload)
    .select("*")
    .single();

  if (error) {
    return jsonError(error.message, 500);
  }

  await admin.session.supabase.from("finance_audit_logs").insert({
    actor_user_id: admin.session.user.id,
    action: "create",
    table_name: "finance_entries",
    record_id: data.id,
    new_values: data,
  });

  return NextResponse.json({ entry: data }, { status: 201 });
}

export async function DELETE(request: Request) {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return jsonError(admin.error, admin.status);
  }

  const url = new URL(request.url);
  const id = url.searchParams.get("id");
  if (!id) {
    return jsonError("Entry id is required", 400);
  }

  const { data: existing, error: readError } = await admin.session.supabase
    .from("finance_entries")
    .select("*")
    .eq("id", id)
    .single();

  if (readError || !existing) {
    return jsonError(readError?.message || "Entry not found", 404);
  }

  const { data: settlementLock, error: settlementLockError } =
    await admin.session.supabase
      .from("monthly_settlements")
      .select("status")
      .eq("settlement_month", existing.settlement_month)
      .maybeSingle();

  if (settlementLockError) {
    return jsonError(settlementLockError.message, 500);
  }

  if (
    settlementLock?.status === "transfer_pending" ||
    settlementLock?.status === "completed" ||
    settlementLock?.status === "locked" ||
    settlementLock?.status === "paid"
  ) {
    return jsonError("This settlement month is already confirmed", 409);
  }

  const { error } = await admin.session.supabase
    .from("finance_entries")
    .delete()
    .eq("id", id);

  if (error) {
    return jsonError(error.message, 500);
  }

  await admin.session.supabase.from("finance_audit_logs").insert({
    actor_user_id: admin.session.user.id,
    action: "delete",
    table_name: "finance_entries",
    record_id: id,
    old_values: existing,
  });

  return NextResponse.json({ success: true });
}
