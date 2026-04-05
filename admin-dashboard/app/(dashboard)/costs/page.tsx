// app/(dashboard)/costs/page.tsx
"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";

interface ProfitData {
  month: string;
  revenue: number;
  cost: number;
  profit: number;
  margin_percent: number;
  cost_per_user: number;
}

export default function CostsPage() {
  const [profitData, setProfitData] = useState<ProfitData[]>([]);
  const [loading, setLoading] = useState(true);
  const [summary, setSummary] = useState({
    totalCost: 0,
    avgCostPerUser: 0,
    avgMargin: 0,
  });

  useEffect(() => {
    async function fetchCosts() {
      try {
        const { data } = await supabase
          .from("monthly_profit")
          .select("*")
          .order("month", { ascending: false })
          .limit(12);

        if (data && data.length > 0) {
          const formattedData = data
            .reverse()
            .map((d) => ({
              month: new Date(d.month).toLocaleDateString("zh-TW", {
                year: "2-digit",
                month: "short",
              }),
              revenue: Number(d.revenue),
              cost: Number(d.cost),
              profit: Number(d.profit),
              margin_percent: Number(d.margin_percent),
              cost_per_user: Number(d.cost_per_user),
            }));

          setProfitData(formattedData);

          const totalCost = formattedData.reduce((sum, d) => sum + d.cost, 0);
          const avgCostPerUser =
            formattedData.reduce((sum, d) => sum + d.cost_per_user, 0) /
            formattedData.length;
          const avgMargin =
            formattedData.reduce((sum, d) => sum + d.margin_percent, 0) /
            formattedData.length;

          setSummary({
            totalCost: Math.round(totalCost * 100) / 100,
            avgCostPerUser: Math.round(avgCostPerUser * 10000) / 10000,
            avgMargin: Math.round(avgMargin * 100) / 100,
          });
        }
      } catch (error) {
        console.error("Failed to fetch costs:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchCosts();
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">成本</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              累計 AI 成本
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              ${summary.totalCost.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">USD (近 12 個月)</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均每用戶成本
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">${summary.avgCostPerUser}</div>
            <p className="text-xs text-gray-500">USD / 月</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              平均毛利率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${summary.avgMargin >= 50 ? "text-green-600" : "text-orange-600"}`}
            >
              {summary.avgMargin}%
            </div>
            <p className="text-xs text-gray-500">目標: &gt;90%</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>營收 vs 成本</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="h-80 flex items-center justify-center">
              <div className="animate-spin h-8 w-8 border-4 border-blue-500 border-t-transparent rounded-full"></div>
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={profitData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="revenue" name="營收" fill="#3B82F6" />
                  <Bar dataKey="cost" name="成本" fill="#EF4444" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>月度利潤明細</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="h-10 bg-gray-100 rounded"></div>
              ))}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>月份</TableHead>
                  <TableHead className="text-right">營收</TableHead>
                  <TableHead className="text-right">成本</TableHead>
                  <TableHead className="text-right">利潤</TableHead>
                  <TableHead className="text-right">毛利率</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {[...profitData].reverse().map((row) => (
                  <TableRow key={row.month}>
                    <TableCell className="font-medium">{row.month}</TableCell>
                    <TableCell className="text-right">
                      ${row.revenue.toLocaleString()}
                    </TableCell>
                    <TableCell className="text-right">
                      ${row.cost.toLocaleString()}
                    </TableCell>
                    <TableCell
                      className={`text-right ${row.profit >= 0 ? "text-green-600" : "text-red-600"}`}
                    >
                      ${row.profit.toLocaleString()}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.margin_percent}%
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
