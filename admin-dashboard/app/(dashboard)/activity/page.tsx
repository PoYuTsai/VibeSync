"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import {
  Bar,
  BarChart,
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

interface ActivityData {
  date: string;
  dau: number;
}

interface ActivitySummary {
  todayDAU: number;
  avgDAU: number;
  peakDAU: number;
  wau: number;
  mau: number;
}

interface ActivityResponse {
  activityData: ActivityData[];
  summary: ActivitySummary;
  error?: string;
}

const emptySummary: ActivitySummary = {
  todayDAU: 0,
  avgDAU: 0,
  peakDAU: 0,
  wau: 0,
  mau: 0,
};

function formatDateLabel(value: string): string {
  return new Date(`${value}T00:00:00`).toLocaleDateString("zh-TW", {
    month: "short",
    day: "numeric",
  });
}

export default function ActivityPage() {
  const [activityData, setActivityData] = useState<ActivityData[]>([]);
  const [summary, setSummary] = useState<ActivitySummary>(emptySummary);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchActivity = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/activity", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as ActivityResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取用戶活動資料失敗");
      }

      setActivityData(
        payload.activityData.map((row) => ({
          ...row,
          date: formatDateLabel(row.date),
        }))
      );
      setSummary(payload.summary);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error ? fetchError.message : "讀取用戶活動資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchActivity();
  }, [fetchActivity]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">用戶活動</h1>
          <p className="mt-1 text-sm text-gray-500">
            看有多少人真的回來用 VibeSync。這裡用 AI 功能使用紀錄計算，並排除 test_users。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchActivity()}
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

      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              今日活躍 DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.todayDAU}</div>
            <p className="text-xs text-gray-500">今天至少用過一次 AI 功能</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均每日活躍
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.avgDAU}</div>
            <p className="text-xs text-gray-500">近 30 天平均每天回來幾人</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              單日最高活躍
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-600">
              {summary.peakDAU}
            </div>
            <p className="text-xs text-gray-500">近 30 天最多的一天</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              近 7 天活躍 WAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.wau}</div>
            <p className="text-xs text-gray-500">這週有回來使用的人數</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              近 30 天活躍 MAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.mau}</div>
            <p className="text-xs text-gray-500">這個月有回來使用的人數</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardContent className="grid gap-3 text-sm text-gray-600 md:grid-cols-3">
          <div>
            <div className="font-semibold text-gray-900">DAU 看今天熱不熱</div>
            <p className="mt-1">適合看發文、廣告、朋友測試後，當天有沒有真的啟動使用。</p>
          </div>
          <div>
            <div className="font-semibold text-gray-900">WAU 看這週有沒有回來</div>
            <p className="mt-1">比 DAU 穩一點，適合早期用來看朋友測試或小流量。</p>
          </div>
          <div>
            <div className="font-semibold text-gray-900">MAU 看整體活躍盤</div>
            <p className="mt-1">之後行銷放量時，用來看這個月真正留下多少活躍用戶。</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>DAU 趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : activityData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              目前沒有 ai_logs 可計算用戶活動。
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={activityData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis allowDecimals={false} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="dau"
                    name="DAU"
                    stroke="#2563EB"
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
          <CardTitle>近 30 天每日活躍用戶</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-64 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : activityData.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              尚無活動資料。
            </div>
          ) : (
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={activityData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis allowDecimals={false} />
                  <Tooltip />
                  <Bar dataKey="dau" name="DAU" fill="#2563EB" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
