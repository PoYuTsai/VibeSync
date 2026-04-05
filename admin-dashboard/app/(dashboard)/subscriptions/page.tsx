// app/(dashboard)/subscriptions/page.tsx
"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase } from "@/lib/supabase";
import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
  Legend,
  Tooltip,
} from "recharts";

interface TierStats {
  tier: string;
  count: number;
  percentage: number;
}

const TIER_COLORS: Record<string, string> = {
  free: "#9CA3AF",
  starter: "#3B82F6",
  essential: "#8B5CF6",
};

export default function SubscriptionsPage() {
  const [tierStats, setTierStats] = useState<TierStats[]>([]);
  const [loading, setLoading] = useState(true);
  const [totals, setTotals] = useState({
    active: 0,
    churned: 0,
    conversionRate: 0,
  });

  useEffect(() => {
    async function fetchSubscriptions() {
      try {
        // 取得各 tier 用戶數
        const { data: subs } = await supabase
          .from("real_subscriptions")
          .select("tier, status");

        const { count: totalUsers } = await supabase
          .from("real_users")
          .select("*", { count: "exact", head: true });

        const activeSubs = subs?.filter((s) => s.status === "active") || [];
        const churnedSubs = subs?.filter((s) => s.status === "cancelled") || [];

        // 計算 tier 分佈
        const tierCounts: Record<string, number> = {
          free: (totalUsers || 0) - activeSubs.length,
          starter: 0,
          essential: 0,
        };

        activeSubs.forEach((sub) => {
          if (sub.tier in tierCounts) {
            tierCounts[sub.tier]++;
          }
        });

        const total = Object.values(tierCounts).reduce((a, b) => a + b, 0);
        const stats = Object.entries(tierCounts).map(([tier, count]) => ({
          tier: tier.charAt(0).toUpperCase() + tier.slice(1),
          count,
          percentage: total > 0 ? Math.round((count / total) * 100) : 0,
        }));

        setTierStats(stats);
        setTotals({
          active: activeSubs.length,
          churned: churnedSubs.length,
          conversionRate:
            totalUsers && totalUsers > 0
              ? Math.round((activeSubs.length / totalUsers) * 100)
              : 0,
        });
      } catch (error) {
        console.error("Failed to fetch subscriptions:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchSubscriptions();
  }, []);

  const pieData = tierStats.map((t) => ({
    name: t.tier,
    value: t.count,
  }));

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">訂閱</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              活躍訂閱
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.active}</div>
            <p className="text-xs text-gray-500">Starter + Essential</p>
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
            <p className="text-xs text-gray-500">Free → Paid</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              流失數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.churned}</div>
            <p className="text-xs text-gray-500">已取消訂閱</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>訂閱分佈</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="h-64 flex items-center justify-center">
                <div className="animate-spin h-8 w-8 border-4 border-blue-500 border-t-transparent rounded-full"></div>
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
                      {pieData.map((entry, index) => (
                        <Cell
                          key={`cell-${index}`}
                          fill={TIER_COLORS[entry.name.toLowerCase()] || "#ccc"}
                        />
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
                    className="w-3 h-3 rounded-full"
                    style={{
                      backgroundColor:
                        TIER_COLORS[tier.tier.toLowerCase()] || "#ccc",
                    }}
                  ></div>
                  <div className="flex-1">
                    <div className="flex justify-between">
                      <span className="font-medium">{tier.tier}</span>
                      <span className="text-gray-500">{tier.count} 人</span>
                    </div>
                    <div className="mt-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full"
                        style={{
                          width: `${tier.percentage}%`,
                          backgroundColor:
                            TIER_COLORS[tier.tier.toLowerCase()] || "#ccc",
                        }}
                      ></div>
                    </div>
                  </div>
                  <span className="text-sm text-gray-500 w-12 text-right">
                    {tier.percentage}%
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
