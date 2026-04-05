"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import {
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from "recharts";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface TierStat {
  tier: string;
  count: number;
  percentage: number;
}

interface SubscriptionsResponse {
  tierStats: TierStat[];
  totals: {
    active: number;
    churned: number;
    conversionRate: number;
  };
}

const TIER_COLORS: Record<string, string> = {
  free: "#9CA3AF",
  starter: "#3B82F6",
  essential: "#8B5CF6",
};

export default function SubscriptionsPage() {
  const [tierStats, setTierStats] = useState<TierStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [totals, setTotals] = useState({
    active: 0,
    churned: 0,
    conversionRate: 0,
  });

  useEffect(() => {
    async function fetchSubscriptions() {
      try {
        const response = await fetch("/api/admin/subscriptions", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load subscriptions");
        }

        const payload = (await response.json()) as SubscriptionsResponse;
        setTierStats(payload.tierStats ?? []);
        setTotals(payload.totals ?? { active: 0, churned: 0, conversionRate: 0 });
      } catch (error) {
        console.error("Failed to fetch subscriptions:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchSubscriptions();
  }, []);

  const pieData = tierStats.map((tier) => ({
    name: tier.tier,
    value: tier.count,
  }));

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Subscriptions</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Active paid
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
              Conversion rate
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.conversionRate}%</div>
            <p className="text-xs text-gray-500">Free to paid</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Churned
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.churned}</div>
            <p className="text-xs text-gray-500">Cancelled records</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Tier mix</CardTitle>
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
                      {pieData.map((entry, index) => (
                        <Cell
                          key={`cell-${index}`}
                          fill={TIER_COLORS[entry.name.toLowerCase()] ?? "#ccc"}
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
            <CardTitle>Tier detail</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {tierStats.map((tier) => (
                <div key={tier.tier} className="flex items-center gap-4">
                  <div
                    className="h-3 w-3 rounded-full"
                    style={{
                      backgroundColor:
                        TIER_COLORS[tier.tier.toLowerCase()] ?? "#ccc",
                    }}
                  />
                  <div className="flex-1">
                    <div className="flex justify-between">
                      <span className="font-medium">{tier.tier}</span>
                      <span className="text-gray-500">{tier.count} users</span>
                    </div>
                    <div className="mt-1 overflow-hidden rounded-full bg-gray-100">
                      <div
                        className="h-2 rounded-full"
                        style={{
                          width: `${tier.percentage}%`,
                          backgroundColor:
                            TIER_COLORS[tier.tier.toLowerCase()] ?? "#ccc",
                        }}
                      />
                    </div>
                  </div>
                  <span className="w-12 text-right text-sm text-gray-500">
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
