// app/(dashboard)/revenue/page.tsx
"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase } from "@/lib/supabase";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";

interface MonthlyRevenue {
  month: string;
  revenue: number;
  new_subscriptions: number;
  renewals: number;
  cancellations: number;
}

export default function RevenuePage() {
  const [revenueData, setRevenueData] = useState<MonthlyRevenue[]>([]);
  const [loading, setLoading] = useState(true);
  const [totals, setTotals] = useState({
    thisMonth: 0,
    lastMonth: 0,
    growth: 0,
    totalSubscriptions: 0,
  });

  useEffect(() => {
    async function fetchRevenue() {
      try {
        const { data } = await supabase
          .from("monthly_revenue")
          .select("*")
          .order("month", { ascending: true })
          .limit(12);

        if (data && data.length > 0) {
          const formattedData = data.map((d) => ({
            month: new Date(d.month).toLocaleDateString("zh-TW", {
              year: "2-digit",
              month: "short",
            }),
            revenue: Number(d.revenue),
            new_subscriptions: Number(d.new_subscriptions),
            renewals: Number(d.renewals),
            cancellations: Number(d.cancellations),
          }));

          setRevenueData(formattedData);

          const thisMonth = formattedData[formattedData.length - 1];
          const lastMonth =
            formattedData.length > 1
              ? formattedData[formattedData.length - 2]
              : null;

          const growth = lastMonth
            ? lastMonth.revenue > 0
              ? Math.round(
                  ((thisMonth.revenue - lastMonth.revenue) / lastMonth.revenue) *
                    100
                )
              : 100
            : 0;

          setTotals({
            thisMonth: thisMonth.revenue,
            lastMonth: lastMonth?.revenue || 0,
            growth,
            totalSubscriptions:
              thisMonth.new_subscriptions + thisMonth.renewals,
          });
        }
      } catch (error) {
        console.error("Failed to fetch revenue:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchRevenue();
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">營收</h1>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              本月營收
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              ${totals.thisMonth.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">USD</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              上月營收
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              ${totals.lastMonth.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">USD</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              月成長率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${totals.growth >= 0 ? "text-green-600" : "text-red-600"}`}
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
              本月交易數
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
          <CardTitle>營收趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="h-80 flex items-center justify-center">
              <div className="animate-spin h-8 w-8 border-4 border-blue-500 border-t-transparent rounded-full"></div>
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
                    name="營收 (USD)"
                    stroke="#3B82F6"
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
                    stroke="#8B5CF6"
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
