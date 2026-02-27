// app/(dashboard)/ai-health/page.tsx
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
  AreaChart,
  Area,
} from "recharts";

interface AIHealthData {
  date: string;
  total_requests: number;
  success_count: number;
  failed_count: number;
  filtered_count: number;
  success_rate: number;
}

export default function AIHealthPage() {
  const [healthData, setHealthData] = useState<AIHealthData[]>([]);
  const [loading, setLoading] = useState(true);
  const [summary, setSummary] = useState({
    avgSuccessRate: 0,
    totalRequests: 0,
    totalFailed: 0,
    totalFiltered: 0,
  });

  useEffect(() => {
    async function fetchAIHealth() {
      try {
        const { data } = await supabase
          .from("ai_success_rate")
          .select("*")
          .order("date", { ascending: true })
          .limit(30);

        if (data && data.length > 0) {
          const formattedData = data.map((d) => ({
            date: new Date(d.date).toLocaleDateString("zh-TW", {
              month: "short",
              day: "numeric",
            }),
            total_requests: Number(d.total_requests),
            success_count: Number(d.success_count),
            failed_count: Number(d.failed_count),
            filtered_count: Number(d.filtered_count),
            success_rate: Number(d.success_rate),
          }));

          setHealthData(formattedData);

          const totalRequests = formattedData.reduce(
            (sum, d) => sum + d.total_requests,
            0
          );
          const totalFailed = formattedData.reduce(
            (sum, d) => sum + d.failed_count,
            0
          );
          const totalFiltered = formattedData.reduce(
            (sum, d) => sum + d.filtered_count,
            0
          );
          const avgSuccessRate =
            formattedData.reduce((sum, d) => sum + d.success_rate, 0) /
            formattedData.length;

          setSummary({
            avgSuccessRate: Math.round(avgSuccessRate * 100) / 100,
            totalRequests,
            totalFailed,
            totalFiltered,
          });
        }
      } catch (error) {
        console.error("Failed to fetch AI health:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchAIHealth();
  }, []);

  const getHealthColor = (rate: number) => {
    if (rate >= 95) return "text-green-600";
    if (rate >= 90) return "text-yellow-600";
    return "text-red-600";
  };

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">AI 健康度</h1>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均成功率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${getHealthColor(summary.avgSuccessRate)}`}
            >
              {summary.avgSuccessRate}%
            </div>
            <p className="text-xs text-gray-500">近 30 天</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              總請求數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {summary.totalRequests.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">近 30 天</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              失敗次數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {summary.totalFailed.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">需要關注</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              被過濾
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-orange-600">
              {summary.totalFiltered.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">Guardrails 攔截</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>成功率趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="h-80 flex items-center justify-center">
              <div className="animate-spin h-8 w-8 border-4 border-blue-500 border-t-transparent rounded-full"></div>
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={healthData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis domain={[80, 100]} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="success_rate"
                    name="成功率 (%)"
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
          <CardTitle>請求分佈</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="h-80 flex items-center justify-center">
              <div className="animate-spin h-8 w-8 border-4 border-blue-500 border-t-transparent rounded-full"></div>
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={healthData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Area
                    type="monotone"
                    dataKey="success_count"
                    name="成功"
                    stackId="1"
                    stroke="#10B981"
                    fill="#10B981"
                    fillOpacity={0.6}
                  />
                  <Area
                    type="monotone"
                    dataKey="filtered_count"
                    name="過濾"
                    stackId="1"
                    stroke="#F59E0B"
                    fill="#F59E0B"
                    fillOpacity={0.6}
                  />
                  <Area
                    type="monotone"
                    dataKey="failed_count"
                    name="失敗"
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
