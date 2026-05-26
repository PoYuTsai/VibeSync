"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import {
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from "recharts";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

type Tier = "free" | "starter" | "essential";

interface TierStats {
  tier: Tier;
  count: number;
  percentage: number;
}

interface SubscriptionTotals {
  totalUsers: number;
  activePaid: number;
  cancelled: number;
  cancelledButUsable: number;
  expired: number;
  conversionRate: number;
}

interface SubscriptionsResponse {
  totals: SubscriptionTotals;
  tierStats: TierStats[];
  error?: string;
}

const emptyTotals: SubscriptionTotals = {
  totalUsers: 0,
  activePaid: 0,
  cancelled: 0,
  cancelledButUsable: 0,
  expired: 0,
  conversionRate: 0,
};

const tierLabels: Record<Tier, string> = {
  free: "Free",
  starter: "Starter",
  essential: "Essential",
};

const tierColors: Record<Tier, string> = {
  free: "#9CA3AF",
  starter: "#2563EB",
  essential: "#7C3AED",
};

export default function SubscriptionsPage() {
  const [tierStats, setTierStats] = useState<TierStats[]>([]);
  const [totals, setTotals] = useState<SubscriptionTotals>(emptyTotals);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchSubscriptions = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/subscriptions", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as SubscriptionsResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取訂閱資料失敗");
      }

      setTierStats(payload.tierStats);
      setTotals(payload.totals);
    } catch (fetchError) {
      setError(fetchError instanceof Error ? fetchError.message : "讀取失敗");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchSubscriptions();
  }, [fetchSubscriptions]);

  const pieData = tierStats.map((tier) => ({
    name: tierLabels[tier.tier],
    tier: tier.tier,
    value: tier.count,
  }));

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">訂閱</h1>
          <p className="mt-1 text-sm text-gray-500">
            以目前可用付費權益統計；已取消續訂但未到期仍算付費權益。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchSubscriptions()}
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
              付費訂閱
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.activePaid}</div>
            <p className="text-xs text-gray-500">含取消續訂但未到期</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              轉換率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.conversionRate}%</div>
            <p className="text-xs text-gray-500">付費 / 總用戶</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              已取消
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.cancelled}</div>
            <p className="text-xs text-gray-500">
              其中 {totals.cancelledButUsable} 人仍有效
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              已過期
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.expired}</div>
            <p className="text-xs text-gray-500">status = expired</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>方案分布</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="flex h-64 items-center justify-center">
                <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
              </div>
            ) : (
              <div className="h-64">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={pieData}
                      cx="50%"
                      cy="50%"
                      innerRadius={60}
                      outerRadius={80}
                      paddingAngle={5}
                      dataKey="value"
                    >
                      {pieData.map((entry) => (
                        <Cell key={entry.tier} fill={tierColors[entry.tier]} />
                      ))}
                    </Pie>
                    <Tooltip />
                    <Legend />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Tier 統計</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {tierStats.map((tier) => (
                <div key={tier.tier} className="flex items-center gap-4">
                  <div
                    className="h-3 w-3 rounded-full"
                    style={{ backgroundColor: tierColors[tier.tier] }}
                  />
                  <div className="flex-1">
                    <div className="flex justify-between">
                      <span className="font-medium">{tierLabels[tier.tier]}</span>
                      <span className="text-gray-500">{tier.count} 人</span>
                    </div>
                    <div className="mt-1 h-2 overflow-hidden rounded-full bg-gray-100">
                      <div
                        className="h-full rounded-full"
                        style={{
                          width: `${tier.percentage}%`,
                          backgroundColor: tierColors[tier.tier],
                        }}
                      />
                    </div>
                  </div>
                  <span className="w-12 text-right text-sm text-gray-500">
                    {tier.percentage}%
                  </span>
                </div>
              ))}
              {tierStats.length === 0 && !loading ? (
                <div className="py-8 text-center text-gray-500">
                  目前沒有訂閱資料
                </div>
              ) : null}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
