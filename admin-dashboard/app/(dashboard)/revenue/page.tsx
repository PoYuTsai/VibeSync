"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { CreditCard, HandCoins, RefreshCcw } from "lucide-react";
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface MonthlyRevenue {
  month: string;
  revenue: number;
  new_subscriptions: number;
  renewals: number;
  cancellations: number;
}

interface RevenueTotals {
  thisMonth: number;
  lastMonth: number;
  growth: number;
  totalSubscriptions: number;
}

interface RevenueResponse {
  revenueData: MonthlyRevenue[];
  totals: RevenueTotals;
  source: string;
  error?: string;
}

const emptyTotals: RevenueTotals = {
  thisMonth: 0,
  lastMonth: 0,
  growth: 0,
  totalSubscriptions: 0,
};

function formatUsd(value: number): string {
  return `$${value.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })}`;
}

export default function RevenuePage() {
  const [revenueData, setRevenueData] = useState<MonthlyRevenue[]>([]);
  const [totals, setTotals] = useState<RevenueTotals>(emptyTotals);
  const [source, setSource] = useState("revenue_events");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRevenue = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/revenue", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as RevenueResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取收入資料失敗");
      }

      setRevenueData(payload.revenueData);
      setTotals(payload.totals);
      setSource(payload.source);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error ? fetchError.message : "讀取收入資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchRevenue();
  }, [fetchRevenue]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">營收</h1>
          <p className="mt-1 text-sm text-gray-500">
            以 {source} 為營運觀察來源；正式月結仍以 App Store / Google Play
            proceeds 為準。
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button asChild type="button" variant="outline">
            <Link href="/subscriptions">
              <CreditCard className="h-4 w-4" />
              訂閱狀態
            </Link>
          </Button>
          <Button asChild type="button" variant="outline">
            <Link href="/finance">
              <HandCoins className="h-4 w-4" />
              月結
            </Link>
          </Button>
          <Button
            type="button"
            variant="outline"
            onClick={() => void fetchRevenue()}
            disabled={loading}
          >
            <RefreshCcw className="h-4 w-4" />
            重新整理
          </Button>
        </div>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              本月收入
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatUsd(totals.thisMonth)}
            </div>
            <p className="text-xs text-gray-500">USD</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              上月收入
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatUsd(totals.lastMonth)}
            </div>
            <p className="text-xs text-gray-500">USD</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              月增率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${
                totals.growth >= 0 ? "text-green-600" : "text-red-600"
              }`}
            >
              {totals.growth >= 0 ? "+" : ""}
              {totals.growth}%
            </div>
            <p className="text-xs text-gray-500">MoM</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              本月付費事件
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {totals.totalSubscriptions}
            </div>
            <p className="text-xs text-gray-500">新訂閱 + 續訂</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>收入趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : revenueData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              目前沒有 revenue_events。等 RevenueCat webhook 進來後，這裡才會有真實收入事件。
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={revenueData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="revenue"
                    name="收入 USD"
                    stroke="#2563EB"
                    strokeWidth={2}
                  />
                  <Line
                    type="monotone"
                    dataKey="new_subscriptions"
                    name="新訂閱"
                    stroke="#10B981"
                    strokeWidth={2}
                  />
                  <Line
                    type="monotone"
                    dataKey="renewals"
                    name="續訂"
                    stroke="#7C3AED"
                    strokeWidth={2}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
