"use client";

import { useCallback, useEffect, useState } from "react";
import { CreditCard, DollarSign, RefreshCcw, Users, Zap } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface DashboardStats {
  totalUsers: number;
  activeSubscriptions: number;
  monthlyRevenue: number;
  aiSuccessRate: number | null;
}

interface DashboardResponse {
  stats: DashboardStats;
  error?: string;
}

const emptyStats: DashboardStats = {
  totalUsers: 0,
  activeSubscriptions: 0,
  monthlyRevenue: 0,
  aiSuccessRate: null,
};

function formatUsd(value: number): string {
  return `$${value.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })}`;
}

function formatPercent(value: number | null): string {
  return value === null ? "尚無資料" : `${value}%`;
}

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats>(emptyStats);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchStats = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/overview", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as DashboardResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取總覽資料失敗");
      }

      setStats(payload.stats);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error ? fetchError.message : "讀取總覽資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchStats();
  }, [fetchStats]);

  const kpiCards = [
    {
      title: "總用戶數",
      value: stats.totalUsers.toLocaleString(),
      icon: Users,
      description: "扣除 test_users 後的正式用戶",
    },
    {
      title: "有效付費用戶",
      value: stats.activeSubscriptions.toLocaleString(),
      icon: CreditCard,
      description: "Starter / Essential 權益仍有效",
    },
    {
      title: "本月收入",
      value: formatUsd(stats.monthlyRevenue),
      icon: DollarSign,
      description: "RevenueCat revenue_events，USD",
    },
    {
      title: "AI 成功率",
      value: formatPercent(stats.aiSuccessRate),
      icon: Zap,
      description: "近 7 天 ai_logs",
    },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">總覽</h1>
          <p className="mt-1 text-sm text-gray-500">
            透過 Admin API 讀取 Supabase 真實資料，沒有資料時不使用假數字。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchStats()}
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

      {loading ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((item) => (
            <Card key={item} className="animate-pulse">
              <CardHeader className="pb-2">
                <div className="h-4 w-1/2 rounded bg-gray-200" />
              </CardHeader>
              <CardContent>
                <div className="h-8 w-3/4 rounded bg-gray-200" />
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {kpiCards.map((card) => (
            <Card key={card.title}>
              <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium text-gray-500">
                  {card.title}
                </CardTitle>
                <card.icon className="h-5 w-5 text-gray-400" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{card.value}</div>
                <p className="mt-1 text-xs text-gray-500">
                  {card.description}
                </p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
