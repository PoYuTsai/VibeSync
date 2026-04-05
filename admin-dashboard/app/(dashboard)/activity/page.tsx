"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface ActivityRow {
  date: string;
  dau: number;
}

interface ActivityResponse {
  rows: ActivityRow[];
}

export default function ActivityPage() {
  const [rows, setRows] = useState<ActivityRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchActivity() {
      try {
        const response = await fetch("/api/admin/activity", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load activity");
        }

        const payload = (await response.json()) as ActivityResponse;
        setRows(payload.rows ?? []);
      } catch (error) {
        console.error("Failed to fetch activity:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchActivity();
  }, []);

  const chartRows = rows.map((row) => ({
    date: new Date(row.date).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
    }),
    dau: row.dau,
  }));

  const todayDau = chartRows.at(-1)?.dau ?? 0;
  const averageDau = chartRows.length > 0
    ? Math.round(
        chartRows.reduce((sum, row) => sum + row.dau, 0) / chartRows.length,
      )
    : 0;
  const peakDau = chartRows.length > 0
    ? Math.max(...chartRows.map((row) => row.dau))
    : 0;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Activity</h1>
        <p className="mt-2 text-sm text-gray-500">
          Daily active-user trend for the last 30 days.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Today DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{todayDau}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              30d average DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{averageDau}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              30d peak DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-600">{peakDau}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Daily active users</CardTitle>
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
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
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
          <CardTitle>DAU bar view</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-64 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartRows}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
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
