"use client";

export const dynamic = "force-dynamic";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Calculator, HandCoins, Plus, RefreshCcw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type {
  BillingCycle,
  CostRole,
  FinanceCategory,
  FinanceEntry,
  FinanceEntryType,
  FinanceParty,
  FinanceSummary,
  MonthlySettlement,
  SettlementMode,
  SettlementStatus,
} from "@/lib/finance/types";

interface FinanceApiResponse {
  entries: FinanceEntry[];
  settlement: MonthlySettlement | null;
  summary: FinanceSummary;
}

interface EntryFormState {
  type: FinanceEntryType;
  title: string;
  category: FinanceCategory;
  amount: string;
  currency: string;
  fx_rate_to_twd: string;
  amount_twd: string;
  entry_date: string;
  paid_by: FinanceParty;
  received_by: FinanceParty;
  billing_cycle: BillingCycle;
  cost_role: CostRole;
  include_before_profit_split: boolean;
  notes: string;
}

const currencyOptions = ["TWD", "USD", "THB", "JPY", "EUR"];

const categoryLabels: Record<FinanceCategory, string> = {
  app_store_proceeds: "App Store proceeds",
  google_play_proceeds: "Google Play proceeds",
  claude: "Claude API",
  apple_developer: "Apple Developer",
  domain: "網域",
  hosting: "Hosting / Vercel / Supabase",
  revenuecat: "RevenueCat",
  marketing: "行銷",
  tooling: "工具費",
  refund_adjustment: "退款 / 調整",
  other: "其他",
};

const partyLabels: Record<FinanceParty, string> = {
  eric: "Eric",
  bruce: "Bruce",
  platform: "平台",
  none: "-",
};

const billingCycleLabels: Record<BillingCycle, string> = {
  monthly: "月費",
  annual: "年費",
  one_time: "單次",
  usage_based: "用量計費",
  campaign_based: "活動 / 廣告",
};

const costRoleLabels: Record<CostRole, string> = {
  direct_variable_cost: "直接變動成本",
  fixed_overhead: "固定營運成本",
  growth_investment: "成長投資",
  personal: "個人吸收",
  other: "其他",
};

const modeLabels: Record<SettlementMode, string> = {
  contribution_split: "扣指定成本後平分",
  net_profit_split: "扣全部成本後平分",
};

const modeExamples: Record<SettlementMode, string> = {
  contribution_split:
    "例：收入 3,000，指定扣 Claude 用量 500，剩下 2,500，Eric / Bruce 各 1,250。",
  net_profit_split:
    "例：收入 3,000，扣全部共同成本 1,200，剩下 1,800，Eric / Bruce 各 900。",
};

const statusLabels: Record<SettlementStatus, string> = {
  open: "記帳中",
  transfer_pending: "待轉帳",
  completed: "已完成",
};

const statusDescriptions: Record<SettlementStatus, string> = {
  open: "還在補收入或成本，可以修改。",
  transfer_pending: "金額已確認，等待手動轉帳。",
  completed: "已轉帳，或本月沒有需要互轉的金額。",
};

function currentMonthKey() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function defaultForm(): EntryFormState {
  return {
    type: "expense",
    title: "",
    category: "claude",
    amount: "",
    currency: "USD",
    fx_rate_to_twd: "",
    amount_twd: "",
    entry_date: todayKey(),
    paid_by: "eric",
    received_by: "none",
    billing_cycle: "usage_based",
    cost_role: "direct_variable_cost",
    include_before_profit_split: true,
    notes: "",
  };
}

function formatTwd(value: number) {
  return new Intl.NumberFormat("zh-TW", {
    style: "currency",
    currency: "TWD",
    maximumFractionDigits: 0,
  }).format(value);
}

function amountToNumber(value: number | string | null | undefined) {
  return Number(value || 0);
}

function optionalNumber(value: string) {
  if (!value.trim()) {
    return null;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function twdAmountForEntry(entry: FinanceEntry) {
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

function transferText(summary: FinanceSummary | null) {
  if (!summary) {
    return "-";
  }

  if (summary.amountEricShouldTransferToBruceTwd > 0) {
    return `Eric 轉給 Bruce ${formatTwd(summary.amountEricShouldTransferToBruceTwd)}`;
  }

  if (summary.amountBruceShouldTransferToEricTwd > 0) {
    return `Bruce 轉給 Eric ${formatTwd(summary.amountBruceShouldTransferToEricTwd)}`;
  }

  return "本月暫無需互轉";
}

function isConfirmedStatus(status: string | null | undefined) {
  return (
    status === "transfer_pending" ||
    status === "completed" ||
    status === "locked" ||
    status === "paid"
  );
}

export default function FinancePage() {
  const [month, setMonth] = useState(currentMonthKey());
  const [entries, setEntries] = useState<FinanceEntry[]>([]);
  const [summary, setSummary] = useState<FinanceSummary | null>(null);
  const [settlement, setSettlement] = useState<MonthlySettlement | null>(null);
  const [form, setForm] = useState<EntryFormState>(defaultForm());
  const [mode, setMode] = useState<SettlementMode>("contribution_split");
  const [status, setStatus] = useState<SettlementStatus>("open");
  const [reserveAmount, setReserveAmount] = useState("0");
  const [settlementNotes, setSettlementNotes] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const currency = form.currency.trim().toUpperCase() || "TWD";
  const isRevenue = form.type === "revenue";
  const requiresFx = currency !== "TWD";
  const amountValue = optionalNumber(form.amount);
  const fxRateValue = optionalNumber(form.fx_rate_to_twd);
  const manualTwdValue = optionalNumber(form.amount_twd);
  const autoTwdAmount =
    amountValue !== null && amountValue !== 0
      ? currency === "TWD"
        ? amountValue
        : fxRateValue !== null && fxRateValue > 0
          ? Math.round((amountValue * fxRateValue + Number.EPSILON) * 100) / 100
          : null
      : null;
  const previewTwdAmount = manualTwdValue ?? autoTwdAmount;

  const metricCards = useMemo(
    () => [
      {
        title: "本月官方入帳",
        value: formatTwd(summary?.revenueTotalTwd ?? 0),
        caption: "以 App Store / Google Play proceeds 為準，月結統一換算 TWD",
      },
      {
        title: "納入分潤前扣除",
        value: formatTwd(summary?.deductedExpenseTotalTwd ?? 0),
        caption: "這個月實際拿來扣的成本",
      },
      {
        title: "可分配金額",
        value: formatTwd(summary?.distributableAmountTwd ?? 0),
        caption: "扣完成本後，正數才 50/50",
      },
      {
        title: "建議互轉",
        value: transferText(summary),
        caption: "目前假設收入主要先進 Eric 帳戶",
      },
    ],
    [summary]
  );

  const loadFinance = useCallback(async (targetMonth: string) => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`/api/finance/summary?month=${targetMonth}`);
      const payload = (await response.json()) as FinanceApiResponse | { error: string };

      if (!response.ok) {
        throw new Error(
          "error" in payload ? payload.error : "Failed to load finance data"
        );
      }

      const data = payload as FinanceApiResponse;
      setEntries(data.entries);
      setSummary(data.summary);
      setSettlement(data.settlement);
      setMode(data.summary.mode);
      setStatus(data.summary.status);
      setReserveAmount(String(data.summary.reserveAmountTwd || 0));
      setSettlementNotes(data.settlement?.notes ?? "");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load finance data");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadFinance(month);
  }, [loadFinance, month]);

  function updateForm<K extends keyof EntryFormState>(key: K, value: EntryFormState[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function handleTypeChange(type: FinanceEntryType) {
    if (type === "revenue") {
      setForm((current) => ({
        ...current,
        type,
        category: "app_store_proceeds",
        currency: "THB",
        fx_rate_to_twd: "",
        amount_twd: "",
        paid_by: "none",
        received_by: "eric",
        billing_cycle: "monthly",
        cost_role: "other",
        include_before_profit_split: false,
      }));
      return;
    }

    setForm((current) => ({
      ...current,
      type,
      category: "claude",
      currency: "USD",
      fx_rate_to_twd: "",
      amount_twd: "",
      paid_by: "eric",
      received_by: "none",
      billing_cycle: "usage_based",
      cost_role: "direct_variable_cost",
      include_before_profit_split: true,
    }));
  }

  function handleCurrencyChange(nextCurrency: string) {
    const normalized = nextCurrency.toUpperCase();
    setForm((current) => ({
      ...current,
      currency: normalized,
      fx_rate_to_twd: normalized === "TWD" ? "" : current.fx_rate_to_twd,
      amount_twd: normalized === "TWD" ? "" : current.amount_twd,
    }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);

    try {
      const response = await fetch("/api/finance/entries", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          ...form,
          month,
          currency,
          amount: Number(form.amount),
          fx_rate_to_twd: form.fx_rate_to_twd
            ? Number(form.fx_rate_to_twd)
            : undefined,
          amount_twd: form.amount_twd ? Number(form.amount_twd) : undefined,
        }),
      });
      const payload = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(payload.error || "Failed to save entry");
      }

      setForm(defaultForm());
      await loadFinance(month);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save entry");
    } finally {
      setSaving(false);
    }
  }

  async function saveSettlement() {
    setSaving(true);
    setError(null);

    try {
      const response = await fetch("/api/finance/settlement", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          month,
          settlement_mode: mode,
          status,
          reserve_amount_twd: Number(reserveAmount || 0),
          notes: settlementNotes,
        }),
      });
      const payload = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(payload.error || "Failed to save settlement");
      }

      await loadFinance(month);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save settlement");
    } finally {
      setSaving(false);
    }
  }

  async function deleteEntry(id: string) {
    setSaving(true);
    setError(null);

    try {
      const response = await fetch(`/api/finance/entries?id=${id}`, {
        method: "DELETE",
      });
      const payload = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(payload.error || "Failed to delete entry");
      }

      await loadFinance(month);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to delete entry");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-3xl font-bold">財務與夥伴月結</h1>
          <p className="mt-2 text-sm text-gray-600">
            共同視角記錄收入、成本、誰先支付。原幣可用 USD / THB / TWD，月結一律換算成 TWD。
          </p>
        </div>

        <label className="flex flex-col gap-1 text-sm font-medium text-gray-700">
          月份
          <input
            type="month"
            value={month}
            onChange={(event) => setMonth(event.target.value)}
            className="h-10 rounded-md border bg-white px-3"
          />
        </label>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-4">
        {metricCards.map((card) => (
          <Card key={card.title} className="rounded-lg">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-gray-500">
                {card.title}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="min-h-8 text-xl font-semibold">{card.value}</div>
              <p className="mt-1 text-xs text-gray-500">{card.caption}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_460px]">
        <Card className="rounded-lg">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <Calculator className="h-5 w-5" />
              月結設定
            </CardTitle>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => void loadFinance(month)}
              disabled={loading || saving}
            >
              <RefreshCcw className="h-4 w-4" />
              重新整理
            </Button>
          </CardHeader>
          <CardContent className="space-y-5">
            <div className="grid gap-4 md:grid-cols-3">
              <label className="space-y-1 text-sm font-medium text-gray-700">
                分潤模式
                <select
                  value={mode}
                  onChange={(event) => setMode(event.target.value as SettlementMode)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                >
                  {Object.entries(modeLabels).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
                <p className="rounded-md bg-slate-50 px-3 py-2 text-xs font-normal leading-relaxed text-slate-600">
                  {modeExamples[mode]}
                </p>
              </label>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                狀態
                <select
                  value={status}
                  onChange={(event) => setStatus(event.target.value as SettlementStatus)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                >
                  {Object.entries(statusLabels).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
                <p className="rounded-md bg-slate-50 px-3 py-2 text-xs font-normal leading-relaxed text-slate-600">
                  {statusDescriptions[status]}
                </p>
              </label>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                保留款 TWD
                <input
                  type="number"
                  min="0"
                  value={reserveAmount}
                  onChange={(event) => setReserveAmount(event.target.value)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                />
              </label>
            </div>

            <label className="space-y-1 text-sm font-medium text-gray-700">
              月結備註
              <textarea
                value={settlementNotes}
                onChange={(event) => setSettlementNotes(event.target.value)}
                rows={3}
                className="w-full rounded-md border bg-white px-3 py-2"
                placeholder="例：本月採扣指定成本後平分；前期固定成本只記帳。"
              />
            </label>

            <div className="grid gap-3 text-sm md:grid-cols-3">
              <div className="rounded-md border bg-gray-50 p-3">
                <div className="font-medium">營運損益</div>
                <div className="mt-1 text-lg font-semibold">
                  {formatTwd(summary?.operatingProfitTwd ?? 0)}
                </div>
                <div className="mt-1 text-xs text-gray-500">收入扣全部已記錄成本</div>
              </div>
              <div className="rounded-md border bg-gray-50 p-3">
                <div className="font-medium">月結損益</div>
                <div className="mt-1 text-lg font-semibold">
                  {formatTwd(summary?.settlementProfitTwd ?? 0)}
                </div>
                <div className="mt-1 text-xs text-gray-500">收入扣納入分潤成本</div>
              </div>
              <div className="rounded-md border bg-gray-50 p-3">
                <div className="font-medium">Carry</div>
                <div className="mt-1 text-lg font-semibold">
                  {formatTwd(summary?.carryOutTwd ?? 0)}
                </div>
                <div className="mt-1 text-xs text-gray-500">負數月份待下月處理</div>
              </div>
            </div>

            <Button type="button" onClick={() => void saveSettlement()} disabled={saving}>
              <HandCoins className="h-4 w-4" />
              儲存月結設定
            </Button>
          </CardContent>
        </Card>

        <Card className="rounded-lg">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Plus className="h-5 w-5" />
              新增收入 / 成本
            </CardTitle>
          </CardHeader>
          <CardContent>
            <form className="space-y-4" onSubmit={(event) => void handleSubmit(event)}>
              <div className="rounded-md border bg-blue-50 p-3 text-sm text-blue-900">
                月結基準是 TWD。Claude 通常填 USD + 匯率；Apple 若實收進泰國帳戶，可填 THB + 匯率；台幣支出直接填 TWD。
              </div>

              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  類型
                  <select
                    value={form.type}
                    onChange={(event) =>
                      handleTypeChange(event.target.value as FinanceEntryType)
                    }
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    <option value="expense">成本</option>
                    <option value="revenue">收入</option>
                  </select>
                </label>

                <label className="space-y-1 text-sm font-medium text-gray-700">
                  日期
                  <input
                    type="date"
                    value={form.entry_date}
                    onChange={(event) => updateForm("entry_date", event.target.value)}
                    className="h-10 w-full rounded-md border bg-white px-3"
                  />
                </label>
              </div>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                項目
                <input
                  value={form.title}
                  onChange={(event) => updateForm("title", event.target.value)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                  placeholder={
                    isRevenue
                      ? "Apple proceeds 2026-05"
                      : "Claude API production usage"
                  }
                  required
                />
              </label>

              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  類別
                  <select
                    value={form.category}
                    onChange={(event) =>
                      updateForm("category", event.target.value as FinanceCategory)
                    }
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    {Object.entries(categoryLabels).map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="space-y-1 text-sm font-medium text-gray-700">
                  週期
                  <select
                    value={form.billing_cycle}
                    onChange={(event) =>
                      updateForm("billing_cycle", event.target.value as BillingCycle)
                    }
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    {Object.entries(billingCycleLabels).map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  原幣幣別
                  <select
                    value={currency}
                    onChange={(event) => handleCurrencyChange(event.target.value)}
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    {currencyOptions.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="space-y-1 text-sm font-medium text-gray-700">
                  原幣金額
                  <input
                    type="number"
                    step="0.01"
                    value={form.amount}
                    onChange={(event) => updateForm("amount", event.target.value)}
                    className="h-10 w-full rounded-md border bg-white px-3"
                    required
                  />
                </label>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  匯率到 TWD
                  <input
                    type="number"
                    step="0.0001"
                    min="0"
                    value={requiresFx ? form.fx_rate_to_twd : "1"}
                    onChange={(event) =>
                      updateForm("fx_rate_to_twd", event.target.value)
                    }
                    disabled={!requiresFx}
                    className="h-10 w-full rounded-md border bg-white px-3 disabled:bg-gray-100"
                    placeholder={currency === "USD" ? "例：32.30" : "例：0.90"}
                  />
                </label>

                <label className="space-y-1 text-sm font-medium text-gray-700">
                  TWD 金額
                  <input
                    type="number"
                    step="0.01"
                    value={form.amount_twd}
                    onChange={(event) => updateForm("amount_twd", event.target.value)}
                    className="h-10 w-full rounded-md border bg-white px-3"
                    placeholder={
                      autoTwdAmount === null
                        ? "可手動覆寫"
                        : `自動試算 ${formatTwd(autoTwdAmount)}`
                    }
                  />
                </label>
              </div>

              <div className="rounded-md border bg-gray-50 p-3 text-sm">
                <div className="font-medium">月結認列金額</div>
                <div className="mt-1 text-lg font-semibold">
                  {previewTwdAmount === null ? "-" : formatTwd(previewTwdAmount)}
                </div>
                <div className="mt-1 text-xs text-gray-500">
                  TWD 金額可留空，系統會用原幣金額 x 匯率；若帳單或銀行有實際台幣值，可手動覆寫。
                </div>
              </div>

              {isRevenue ? (
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  收款方
                  <select
                    value={form.received_by}
                    onChange={(event) =>
                      updateForm("received_by", event.target.value as FinanceParty)
                    }
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    <option value="eric">Eric</option>
                    <option value="bruce">Bruce</option>
                    <option value="platform">平台</option>
                  </select>
                </label>
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  <label className="space-y-1 text-sm font-medium text-gray-700">
                    誰先支付
                    <select
                      value={form.paid_by}
                      onChange={(event) =>
                        updateForm("paid_by", event.target.value as FinanceParty)
                      }
                      className="h-10 w-full rounded-md border bg-white px-3"
                    >
                      <option value="eric">Eric</option>
                      <option value="bruce">Bruce</option>
                      <option value="platform">平台</option>
                    </select>
                  </label>

                  <label className="space-y-1 text-sm font-medium text-gray-700">
                    成本角色
                    <select
                      value={form.cost_role}
                      onChange={(event) =>
                        updateForm("cost_role", event.target.value as CostRole)
                      }
                      className="h-10 w-full rounded-md border bg-white px-3"
                    >
                      {Object.entries(costRoleLabels).map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
              )}

              {!isRevenue ? (
                <label className="flex items-start gap-3 rounded-md border bg-gray-50 p-3 text-sm">
                  <input
                    type="checkbox"
                    checked={form.include_before_profit_split}
                    onChange={(event) =>
                      updateForm("include_before_profit_split", event.target.checked)
                    }
                    className="mt-1"
                  />
                  <span>
                    <span className="block font-medium">納入分潤前扣除</span>
                    <span className="text-gray-500">
                      例如正式用戶造成的 Claude usage；前期固定燃燒成本可先不勾。
                    </span>
                  </span>
                </label>
              ) : null}

              <label className="space-y-1 text-sm font-medium text-gray-700">
                備註
                <textarea
                  value={form.notes}
                  onChange={(event) => updateForm("notes", event.target.value)}
                  rows={3}
                  className="w-full rounded-md border bg-white px-3 py-2"
                />
              </label>

              <Button type="submit" disabled={saving}>
                <Plus className="h-4 w-4" />
                新增
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>

      <Card className="rounded-lg">
        <CardHeader>
          <CardTitle>本月帳本細項</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-2">
              {[1, 2, 3, 4].map((item) => (
                <div key={item} className="h-11 animate-pulse rounded-md bg-gray-100" />
              ))}
            </div>
          ) : entries.length === 0 ? (
            <div className="rounded-md border border-dashed py-10 text-center text-sm text-gray-500">
              這個月份還沒有任何收入或成本。
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>日期</TableHead>
                  <TableHead>項目</TableHead>
                  <TableHead>類型</TableHead>
                  <TableHead>付款 / 收款</TableHead>
                  <TableHead>週期</TableHead>
                  <TableHead>月結處理</TableHead>
                  <TableHead className="text-right">金額</TableHead>
                  <TableHead className="text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {entries.map((entry) => {
                  const rowTwdAmount = Math.abs(twdAmountForEntry(entry));
                  const entryFxRate = Number(entry.fx_rate_to_twd);

                  return (
                    <TableRow key={entry.id}>
                      <TableCell>{entry.entry_date}</TableCell>
                      <TableCell>
                        <div className="font-medium">{entry.title}</div>
                        <div className="text-xs text-gray-500">
                          {categoryLabels[entry.category]}
                        </div>
                      </TableCell>
                      <TableCell>{entry.type === "revenue" ? "收入" : "成本"}</TableCell>
                      <TableCell>
                        {entry.type === "revenue"
                          ? `收款：${partyLabels[entry.received_by]}`
                          : `支付：${partyLabels[entry.paid_by]}`}
                      </TableCell>
                      <TableCell>{billingCycleLabels[entry.billing_cycle]}</TableCell>
                      <TableCell>
                        {entry.type === "revenue"
                          ? "官方 proceeds"
                          : entry.include_before_profit_split
                            ? "納入扣除"
                            : "先不扣除"}
                      </TableCell>
                      <TableCell className="text-right">
                        <div
                          className={
                            entry.type === "revenue" ? "text-green-700" : "text-red-700"
                          }
                        >
                          {entry.type === "revenue" ? "+" : "-"}
                          {formatTwd(rowTwdAmount)}
                        </div>
                        <div className="text-xs text-gray-500">
                          {entry.currency} {amountToNumber(entry.amount).toLocaleString()}
                          {entry.currency.toUpperCase() !== "TWD" &&
                          Number.isFinite(entryFxRate)
                            ? ` x ${entryFxRate.toLocaleString()}`
                            : ""}
                        </div>
                      </TableCell>
                      <TableCell className="text-right">
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon-sm"
                          onClick={() => void deleteEntry(entry.id)}
                          disabled={saving || isConfirmedStatus(settlement?.status)}
                          aria-label="刪除"
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
