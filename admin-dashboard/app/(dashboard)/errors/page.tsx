"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertCircle, AlertTriangle, Info, RefreshCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

interface ErrorLog {
  id: string;
  created_at: string;
  error_type: string;
  error_message: string;
  user_id: string;
  request_id: string;
}

interface ErrorStats {
  type: string;
  count: number;
}

interface ErrorTotals {
  today: number;
  thisWeek: number;
  critical: number;
}

interface ErrorsResponse {
  errors: ErrorLog[];
  errorStats: ErrorStats[];
  totals: ErrorTotals;
  error?: string;
}

const emptyTotals: ErrorTotals = {
  today: 0,
  thisWeek: 0,
  critical: 0,
};

function formatDate(value: string): string {
  return new Date(value).toLocaleString("zh-TW", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function getErrorIcon(type: string) {
  switch (type) {
    case "API_ERROR":
    case "TIMEOUT":
      return <AlertCircle className="h-4 w-4 text-red-500" />;
    case "RATE_LIMIT":
    case "VALIDATION":
      return <AlertTriangle className="h-4 w-4 text-orange-500" />;
    default:
      return <Info className="h-4 w-4 text-gray-500" />;
  }
}

function getErrorBadge(type: string) {
  const colors: Record<string, string> = {
    API_ERROR: "bg-red-100 text-red-800",
    TIMEOUT: "bg-red-100 text-red-800",
    RATE_LIMIT: "bg-orange-100 text-orange-800",
    VALIDATION: "bg-yellow-100 text-yellow-800",
    GUARDRAIL: "bg-purple-100 text-purple-800",
    UNKNOWN: "bg-gray-100 text-gray-800",
  };

  return (
    <span
      className={`rounded-full px-2 py-1 text-xs font-medium ${
        colors[type] ?? colors.UNKNOWN
      }`}
    >
      {type}
    </span>
  );
}

export default function ErrorsPage() {
  const [errors, setErrors] = useState<ErrorLog[]>([]);
  const [errorStats, setErrorStats] = useState<ErrorStats[]>([]);
  const [totals, setTotals] = useState<ErrorTotals>(emptyTotals);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchErrors = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/errors", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as ErrorsResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取錯誤追蹤資料失敗");
      }

      setErrors(payload.errors);
      setErrorStats(payload.errorStats);
      setTotals(payload.totals);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error
          ? fetchError.message
          : "讀取錯誤追蹤資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchErrors();
  }, [fetchErrors]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">錯誤追蹤</h1>
          <p className="mt-1 text-sm text-gray-500">
            讀取 ai_logs 中 status = failed 的真實紀錄，依 error_code 或 request_type 分組。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchErrors()}
          disabled={loading}
        >
          <RefreshCcw className="h-4 w-4" />
          重新整理
        </Button>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              今日錯誤
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${
                totals.today > 10 ? "text-red-600" : "text-gray-900"
              }`}
            >
              {totals.today}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              近 7 天錯誤
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.thisWeek}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              高風險錯誤
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {totals.critical}
            </div>
            <p className="text-xs text-gray-500">API_ERROR + TIMEOUT</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="md:col-span-1">
          <CardHeader>
            <CardTitle>錯誤類型分布</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="animate-pulse space-y-2">
                {[1, 2, 3].map((item) => (
                  <div key={item} className="h-8 rounded bg-gray-100" />
                ))}
              </div>
            ) : errorStats.length === 0 ? (
              <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
                目前沒有錯誤紀錄。
              </div>
            ) : (
              <div className="space-y-3">
                {errorStats.map((stat) => (
                  <div key={stat.type} className="flex items-center gap-3">
                    {getErrorIcon(stat.type)}
                    <div className="flex-1">
                      <div className="flex justify-between">
                        <span className="text-sm font-medium">{stat.type}</span>
                        <span className="text-sm text-gray-500">
                          {stat.count}
                        </span>
                      </div>
                      <div className="mt-1 h-2 overflow-hidden rounded-full bg-gray-100">
                        <div
                          className="h-full rounded-full bg-red-400"
                          style={{
                            width: `${(stat.count / (errors.length || 1)) * 100}%`,
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
            <CardTitle>最近錯誤</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="animate-pulse space-y-2">
                {[1, 2, 3, 4, 5].map((item) => (
                  <div key={item} className="h-10 rounded bg-gray-100" />
                ))}
              </div>
            ) : errors.length === 0 ? (
              <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
                目前沒有錯誤紀錄。
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>時間</TableHead>
                    <TableHead>類型</TableHead>
                    <TableHead>錯誤訊息</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {errors.slice(0, 10).map((row) => (
                    <TableRow key={row.id}>
                      <TableCell className="whitespace-nowrap">
                        {formatDate(row.created_at)}
                      </TableCell>
                      <TableCell>{getErrorBadge(row.error_type)}</TableCell>
                      <TableCell className="max-w-xs truncate">
                        {row.error_message || "-"}
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
