// app/(dashboard)/activity/page.tsx
"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase } from "@/lib/supabase";
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

interface ActivityData {
  date: string;
  dau: number;
}

export default function ActivityPage() {
  const [activityData, setActivityData] = useState<ActivityData[]>([]);
  const [loading, setLoading] = useState(true);
  const [summary, setSummary] = useState({
    todayDAU: 0,
    avgDAU: 0,
    peakDAU: 0,
    wau: 0,
    mau: 0,
  });

  useEffect(() => {
    async function fetchActivity() {
      try {
        const { data, error } = await supabase
          .from("user_activity")
          .select("*")
          .order("date", { ascending: true })
          .limit(30);

        if (error) {
          throw error;
        }

        if (data && data.length > 0) {
          const formattedData = data.map((row) => ({
            date: new Date(row.date).toLocaleDateString("zh-TW", {
              month: "short",
              day: "numeric",
            }),
            dau: Number(row.dau),
          }));

          setActivityData(formattedData);

          const todayDAU = formattedData[formattedData.length - 1]?.dau || 0;
          const avgDAU =
            formattedData.reduce((sum, row) => sum + row.dau, 0) /
            formattedData.length;
          const peakDAU = Math.max(...formattedData.map((row) => row.dau));

          setSummary({
            todayDAU,
            avgDAU: Math.round(avgDAU),
            peakDAU,
            wau: Math.round(avgDAU * 2.5),
            mau: Math.round(avgDAU * 5),
          });
        }
      } catch (error) {
        console.error("Failed to fetch activity:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchActivity();
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">用戶活動</h1>

      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              今日 DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.todayDAU}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均 DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.avgDAU}</div>
            <p className="text-xs text-gray-500">最近 30 天</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              峰值 DAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-600">
              {summary.peakDAU}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              預估 WAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.wau}</div>
            <p className="text-xs text-gray-500">近似估算</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              預估 MAU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.mau}</div>
            <p className="text-xs text-gray-500">近似估算</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>DAU 趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={activityData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="dau"
                    name="DAU"
                    stroke="#3B82F6"
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
          <CardTitle>最近 30 天活躍分佈</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-64 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={activityData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="dau" name="DAU" fill="#3B82F6" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
