"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

interface ProfitRow {
  month: string;
  revenue: number;
  cost: number;
  profit: number;
  margin_percent: number;
  cost_per_user: number;
}

interface CostsResponse {
  rows: ProfitRow[];
  summary: {
    totalCost: number;
    avgCostPerUser: number;
    avgMargin: number;
  };
}

export default function CostsPage() {
  const [rows, setRows] = useState<ProfitRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [summary, setSummary] = useState({
    totalCost: 0,
    avgCostPerUser: 0,
    avgMargin: 0,
  });

  useEffect(() => {
    async function fetchCosts() {
      try {
        const response = await fetch("/api/admin/costs", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load costs");
        }

        const payload = (await response.json()) as CostsResponse;
        setRows(payload.rows ?? []);
        setSummary(
          payload.summary ?? {
            totalCost: 0,
            avgCostPerUser: 0,
            avgMargin: 0,
          },
        );
      } catch (error) {
        console.error("Failed to fetch costs:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchCosts();
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Costs</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              12-month AI cost
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              ${summary.totalCost.toLocaleString()}
            </div>
            <p className="text-xs text-gray-500">USD</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Avg cost per user
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">${summary.avgCostPerUser}</div>
            <p className="text-xs text-gray-500">USD / user</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Avg gross margin
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${summary.avgMargin >= 50 ? "text-green-600" : "text-orange-600"}`}
            >
              {summary.avgMargin}%
            </div>
            <p className="text-xs text-gray-500">
              Revenue minus AI/token cost
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Revenue vs cost</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-80 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : (
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={rows}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="revenue" name="Revenue" fill="#3B82F6" />
                  <Bar dataKey="cost" name="Cost" fill="#EF4444" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Monthly profit table</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((row) => (
                <div key={row} className="h-10 rounded bg-gray-100" />
              ))}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Month</TableHead>
                  <TableHead className="text-right">Revenue</TableHead>
                  <TableHead className="text-right">Cost</TableHead>
                  <TableHead className="text-right">Profit</TableHead>
                  <TableHead className="text-right">Margin</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {[...rows].reverse().map((row) => (
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
