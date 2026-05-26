"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import {
  Area,
  AreaChart,
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

interface AIHealthData {
  date: string;
  total_requests: number;
  success_count: number;
  failed_count: number;
  filtered_count: number;
  success_rate: number;
}

interface AIHealthSummary {
  avgSuccessRate: number | null;
  totalRequests: number;
  totalFailed: number;
  totalFiltered: number;
}

interface AIHealthResponse {
  healthData: AIHealthData[];
  summary: AIHealthSummary;
  error?: string;
}

const emptySummary: AIHealthSummary = {
  avgSuccessRate: null,
  totalRequests: 0,
  totalFailed: 0,
  totalFiltered: 0,
};

function formatDateLabel(value: string): string {
  return new Date(`${value}T00:00:00`).toLocaleDateString("zh-TW", {
    month: "short",
    day: "numeric",
  });
}

function getHealthColor(rate: number | null): string {
  if (rate === null) return "text-gray-900";
  if (rate >= 95) return "text-green-600";
  if (rate >= 90) return "text-yellow-600";
  return "text-red-600";
}

export default function AIHealthPage() {
  const [healthData, setHealthData] = useState<AIHealthData[]>([]);
  const [summary, setSummary] = useState<AIHealthSummary>(emptySummary);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAIHealth = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/ai-health", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as AIHealthResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取 AI 健康資料失敗");
      }

      setHealthData(
        payload.healthData.map((row) => ({
          ...row,
          date: formatDateLabel(row.date),
        }))
      );
      setSummary(payload.summary);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error ? fetchError.message : "讀取 AI 健康資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchAIHealth();
  }, [fetchAIHealth]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">AI 健康</h1>
          <p className="mt-1 text-sm text-gray-500">
            直接讀取 ai_logs，統計近 30 天成功、失敗與 guardrail 過濾狀態。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchAIHealth()}
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

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均成功率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${getHealthColor(
                summary.avgSuccessRate
              )}`}
            >
              {summary.avgSuccessRate === null
                ? "尚無資料"
                : `${summary.avgSuccessRate}%`}
            </div>
            <p className="text-xs text-gray-500">近 30 天</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              總請求數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {summary.totalRequests.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">近 30 天</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              失敗數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {summary.totalFailed.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">status = failed</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              過濾數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-orange-600">
              {summary.totalFiltered.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">status = filtered</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>成功率趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : healthData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              目前沒有 ai_logs 可統計。
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={healthData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis domain={[0, 100]} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="success_rate"
                    name="成功率 (%)"
                    stroke="#10B981"
                    strokeWidth={2}
                    dot={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>請求結果分布</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : healthData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              尚無請求結果資料。
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={healthData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Area
                    type="monotone"
                    dataKey="success_count"
                    name="成功"
                    stackId="1"
                    stroke="#10B981"
                    fill="#10B981"
                    fillOpacity={0.6}
                  />
                  <Area
                    type="monotone"
                    dataKey="filtered_count"
                    name="過濾"
                    stackId="1"
                    stroke="#F59E0B"
                    fill="#F59E0B"
                    fillOpacity={0.6}
                  />
                  <Area
                    type="monotone"
                    dataKey="failed_count"
                    name="失敗"
                    stackId="1"
                    stroke="#EF4444"
                    fill="#EF4444"
                    fillOpacity={0.6}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
