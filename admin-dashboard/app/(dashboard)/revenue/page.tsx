"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
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

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface MonthlyRevenueRow {
  month: string;
  revenue: number;
  new_subscriptions: number;
  renewals: number;
  cancellations: number;
}

interface RevenueResponse {
  rows: MonthlyRevenueRow[];
  totals: {
    thisMonth: number;
    lastMonth: number;
    growth: number;
    totalSubscriptions: number;
  };
}

export default function RevenuePage() {
  const [rows, setRows] = useState<MonthlyRevenueRow[]>([]);
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
        const response = await fetch("/api/admin/revenue", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load revenue");
        }

        const payload = (await response.json()) as RevenueResponse;
        setRows(payload.rows ?? []);
        setTotals(
          payload.totals ?? {
            thisMonth: 0,
            lastMonth: 0,
            growth: 0,
            totalSubscriptions: 0,
          },
        );
      } catch (error) {
        console.error("Failed to fetch revenue:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchRevenue();
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Revenue</h1>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              This month
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
              Last month
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
              Growth
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
              Subscription events
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.totalSubscriptions}</div>
            <p className="text-xs text-gray-500">New + renewals</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>12-month revenue trend</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={rows}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="revenue"
                    name="Revenue (USD)"
                    stroke="#3B82F6"
                    strokeWidth={2}
                  />
                  <Line
                    type="monotone"
                    dataKey="new_subscriptions"
                    name="New subscriptions"
                    stroke="#10B981"
                    strokeWidth={2}
                  />
                  <Line
                    type="monotone"
                    dataKey="renewals"
                    name="Renewals"
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
