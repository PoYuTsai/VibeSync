"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { AlertCircle, AlertTriangle, Info } from "lucide-react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

interface ErrorRow {
  id: string;
  created_at: string;
  error_code: string | null;
  error_message: string | null;
  user_id: string | null;
  model: string;
  request_type: string;
  latency_ms: number;
}

interface ErrorsResponse {
  rows: ErrorRow[];
}

export default function ErrorsPage() {
  const [rows, setRows] = useState<ErrorRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchErrors() {
      try {
        const response = await fetch("/api/admin/errors", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load AI errors");
        }

        const payload = (await response.json()) as ErrorsResponse;
        setRows(payload.rows ?? []);
      } catch (error) {
        console.error("Failed to fetch errors:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchErrors();
  }, []);

  const today = new Date();
  const startOfToday = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate(),
  );
  const weekAgo = new Date();
  weekAgo.setDate(weekAgo.getDate() - 7);

  const totals = {
    today: rows.filter((row) => new Date(row.created_at) >= startOfToday).length,
    thisWeek: rows.filter((row) => new Date(row.created_at) >= weekAgo).length,
    critical: rows.filter((row) =>
      ["TIMEOUT", "API_ERROR", "RATE_LIMIT"].includes(row.error_code ?? "")
    ).length,
  };

  const errorCounts = Array.from(
    rows.reduce((map, row) => {
      const key = row.error_code ?? "UNKNOWN";
      map.set(key, (map.get(key) ?? 0) + 1);
      return map;
    }, new Map<string, number>()).entries(),
  )
    .map(([code, count]) => ({ code, count }))
    .sort((a, b) => b.count - a.count);

  const formatDate = (value: string) =>
    new Date(value).toLocaleString("en-US", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });

  const errorIcon = (code: string) => {
    if (code === "TIMEOUT" || code === "API_ERROR") {
      return <AlertCircle className="h-4 w-4 text-red-500" />;
    }
    if (code === "RATE_LIMIT" || code === "VALIDATION") {
      return <AlertTriangle className="h-4 w-4 text-orange-500" />;
    }
    return <Info className="h-4 w-4 text-gray-500" />;
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">AI errors</h1>
        <p className="mt-2 text-sm text-gray-500">
          Recent failed AI calls from <code>ai_logs</code>.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Today
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.today}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Last 7 days
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.thisWeek}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Critical classes
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {totals.critical}
            </div>
            <p className="mt-1 text-xs text-gray-500">
              TIMEOUT / API_ERROR / RATE_LIMIT
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="md:col-span-1">
          <CardHeader>
            <CardTitle>Error breakdown</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="animate-pulse space-y-2">
                {[1, 2, 3].map((index) => (
                  <div key={index} className="h-8 rounded bg-gray-100" />
                ))}
              </div>
            ) : (
              <div className="space-y-3">
                {errorCounts.map((entry) => (
                  <div key={entry.code} className="flex items-center gap-3">
                    {errorIcon(entry.code)}
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium">{entry.code}</span>
                        <span className="text-sm text-gray-500">{entry.count}</span>
                      </div>
                      <div className="mt-1 overflow-hidden rounded-full bg-gray-100">
                        <div
                          className="h-2 rounded-full bg-red-400"
                          style={{
                            width: `${(entry.count / Math.max(rows.length, 1)) * 100}%`,
                          }}
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Recent failures</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="animate-pulse space-y-2">
                {[1, 2, 3, 4, 5].map((index) => (
                  <div key={index} className="h-10 rounded bg-gray-100" />
                ))}
              </div>
            ) : rows.length === 0 ? (
              <div className="py-8 text-center text-gray-500">
                No recent failed AI calls.
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Time</TableHead>
                    <TableHead>Error code</TableHead>
                    <TableHead>Model / request</TableHead>
                    <TableHead>Message</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.slice(0, 10).map((row) => (
                    <TableRow key={row.id}>
                      <TableCell className="whitespace-nowrap">
                        {formatDate(row.created_at)}
                      </TableCell>
                      <TableCell>{row.error_code ?? "UNKNOWN"}</TableCell>
                      <TableCell className="whitespace-nowrap">
                        <div className="text-sm font-medium">{row.model}</div>
                        <div className="text-xs text-gray-500">
                          {row.request_type} / {row.latency_ms}ms
                        </div>
                      </TableCell>
                      <TableCell className="max-w-md truncate">
                        {row.error_message ?? "-"}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
