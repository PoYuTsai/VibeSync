"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
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

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface AIHealthRow {
  date: string;
  total_requests: number;
  success_count: number;
  failed_count: number;
  filtered_count: number;
  success_rate: number;
}

interface AIHealthResponse {
  rows: AIHealthRow[];
}

export default function AIHealthPage() {
  const [rows, setRows] = useState<AIHealthRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchHealth() {
      try {
        const response = await fetch("/api/admin/ai-health", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load AI health");
        }

        const payload = (await response.json()) as AIHealthResponse;
        setRows(payload.rows ?? []);
      } catch (error) {
        console.error("Failed to fetch AI health:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchHealth();
  }, []);

  const chartRows = rows.map((row) => ({
    ...row,
    dateLabel: new Date(row.date).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
    }),
  }));

  const summary = {
    avgSuccessRate: chartRows.length > 0
      ? Math.round(
          (chartRows.reduce((sum, row) => sum + row.success_rate, 0) /
            chartRows.length) * 100,
        ) / 100
      : 0,
    totalRequests: chartRows.reduce((sum, row) => sum + row.total_requests, 0),
    totalFailed: chartRows.reduce((sum, row) => sum + row.failed_count, 0),
    totalFiltered: chartRows.reduce((sum, row) => sum + row.filtered_count, 0),
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">AI health</h1>
        <p className="mt-2 text-sm text-gray-500">
          30-day AI success, failure, and guardrail-filter trend.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Avg success rate
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.avgSuccessRate}%</div>
            <p className="mt-1 text-xs text-gray-500">Last 30 days</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Total requests
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {summary.totalRequests.toLocaleString()}
            </div>
            <p className="mt-1 text-xs text-gray-500">Last 30 days</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Failed
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {summary.totalFailed.toLocaleString()}
            </div>
            <p className="mt-1 text-xs text-gray-500">status=failed</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Guardrail filtered
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-orange-600">
              {summary.totalFiltered.toLocaleString()}
            </div>
            <p className="mt-1 text-xs text-gray-500">status=filtered</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Success rate trend</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartRows}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="dateLabel" />
                  <YAxis domain={[80, 100]} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="success_rate"
                    name="Success rate (%)"
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
          <CardTitle>Request outcome mix</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={chartRows}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="dateLabel" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Area
                    type="monotone"
                    dataKey="success_count"
                    name="Success"
                    stackId="1"
                    stroke="#10B981"
                    fill="#10B981"
                    fillOpacity={0.6}
                  />
                  <Area
                    type="monotone"
                    dataKey="filtered_count"
                    name="Filtered"
                    stackId="1"
                    stroke="#F59E0B"
                    fill="#F59E0B"
                    fillOpacity={0.6}
                  />
                  <Area
                    type="monotone"
                    dataKey="failed_count"
                    name="Failed"
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
