import { NextResponse } from "next/server";
import { calculateFinanceSummary, monthDateFromKey } from "@/lib/finance/calculations";
import type { FinanceEntry, MonthlySettlement } from "@/lib/finance/types";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const url = new URL(request.url);
  const settlementMonth = monthDateFromKey(url.searchParams.get("month"));
  const monthKey = settlementMonth.slice(0, 7);

  const [entriesResult, settlementResult] = await Promise.all([
    admin.session.supabase
      .from("finance_entries")
      .select("*")
      .eq("settlement_month", settlementMonth)
      .order("entry_date", { ascending: false })
      .order("created_at", { ascending: false }),
    admin.session.supabase
      .from("monthly_settlements")
      .select(
        "id, settlement_month, status, settlement_mode, reserve_amount_twd, reserve_reason, notes"
      )
      .eq("settlement_month", settlementMonth)
      .maybeSingle(),
  ]);

  if (entriesResult.error) {
    return NextResponse.json({ error: entriesResult.error.message }, { status: 500 });
  }

  if (settlementResult.error) {
    return NextResponse.json(
      { error: settlementResult.error.message },
      { status: 500 }
    );
  }

  const entries = (entriesResult.data ?? []) as FinanceEntry[];
  const settlement = settlementResult.data as MonthlySettlement | null;
  const summary = calculateFinanceSummary({
    month: monthKey,
    entries,
    settlement,
  });

  return NextResponse.json({
    entries,
    settlement,
    summary,
  });
}
