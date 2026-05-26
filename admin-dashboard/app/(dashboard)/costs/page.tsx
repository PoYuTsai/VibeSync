"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
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

interface ProfitData {
  month: string;
  revenue: number;
  cost: number;
  profit: number;
  margin_percent: number;
  cost_per_user: number;
}

interface CostSummary {
  totalCost: number;
  avgCostPerUser: number;
  avgMargin: number;
}

interface CostsResponse {
  profitData: ProfitData[];
  summary: CostSummary;
  source: string;
  error?: string;
}

const emptySummary: CostSummary = {
  totalCost: 0,
  avgCostPerUser: 0,
  avgMargin: 0,
};

function formatUsd(value: number, digits = 2): string {
  return `$${value.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  })}`;
}

export default function CostsPage() {
  const [profitData, setProfitData] = useState<ProfitData[]>([]);
  const [summary, setSummary] = useState<CostSummary>(emptySummary);
  const [source, setSource] = useState("token_usage + revenue_events");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchCosts = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/costs", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as CostsResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取成本資料失敗");
      }

      setProfitData(payload.profitData);
      setSummary(payload.summary);
      setSource(payload.source);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error ? fetchError.message : "讀取成本資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchCosts();
  }, [fetchCosts]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">AI 成本明細</h1>
          <p className="mt-1 text-sm text-gray-500">
            以 {source} 計算 Claude / token usage 成本；手動共同成本請在財務月結頁登錄。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchCosts()}
          disabled={loading}
        >
          <RefreshCcw className="h-4 w-4" />
          重新整理
        </Button>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              近 12 月 AI 成本
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatUsd(summary.totalCost)}
            </div>
            <p className="text-xs text-gray-500">USD</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均每用戶成本
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatUsd(summary.avgCostPerUser, 4)}
            </div>
            <p className="text-xs text-gray-500">USD / active AI user</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均毛利率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${
                summary.avgMargin >= 50 ? "text-green-600" : "text-orange-600"
              }`}
            >
              {summary.avgMargin}%
            </div>
            <p className="text-xs text-gray-500">收入扣 AI 用量成本</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>收入 vs AI 成本</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : profitData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              目前沒有 token_usage 或 revenue_events 可計算成本。
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={profitData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="revenue" name="收入" fill="#2563EB" />
                  <Bar dataKey="cost" name="AI 成本" fill="#EF4444" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>月度成本明細</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((item) => (
                <div key={item} className="h-10 rounded bg-gray-100" />
              ))}
            </div>
          ) : profitData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              尚無月份資料。
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>月份</TableHead>
                  <TableHead className="text-right">收入</TableHead>
                  <TableHead className="text-right">AI 成本</TableHead>
                  <TableHead className="text-right">毛利</TableHead>
                  <TableHead className="text-right">毛利率</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {[...profitData].reverse().map((row) => (
                  <TableRow key={row.month}>
                    <TableCell className="font-medium">{row.month}</TableCell>
                    <TableCell className="text-right">
                      {formatUsd(row.revenue)}
                    </TableCell>
                    <TableCell className="text-right">
                      {formatUsd(row.cost)}
                    </TableCell>
                    <TableCell
                      className={`text-right ${
                        row.profit >= 0 ? "text-green-600" : "text-red-600"
                      }`}
                    >
                      {formatUsd(row.profit)}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.margin_percent}%
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
