"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { RefreshCcw } from "lucide-react";
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

type AuthDiagnosticRow = {
  id: string;
  event: string;
  status: string;
  email_redacted: string | null;
  platform: string | null;
  app_version: string | null;
  build_number: string | null;
  error_code: string | null;
  message: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
};

interface AuthDiagnosticsResponse {
  rows: AuthDiagnosticRow[];
  error?: string;
}

function formatDateTime(value: string) {
  return new Date(value).toLocaleString("zh-TW", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function statusPillClass(status: string) {
  switch (status) {
    case "success":
      return "bg-green-100 text-green-700";
    case "warning":
      return "bg-yellow-100 text-yellow-700";
    case "error":
      return "bg-red-100 text-red-700";
    default:
      return "bg-slate-100 text-slate-700";
  }
}

export default function AuthDiagnosticsPage() {
  const [rows, setRows] = useState<AuthDiagnosticRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchDiagnostics = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/auth-diagnostics", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as AuthDiagnosticsResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取 Auth 診斷資料失敗");
      }

      setRows(payload.rows);
    } catch (fetchError) {
      setError(
        fetchError instanceof Error ? fetchError.message : "讀取 Auth 診斷資料失敗"
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchDiagnostics();
  }, [fetchDiagnostics]);

  const summary = useMemo(() => {
    const last24Hours = Date.now() - 24 * 60 * 60 * 1000;
    const inLast24Hours = rows.filter(
      (row) => new Date(row.created_at).getTime() >= last24Hours
    );

    return {
      total: rows.length,
      last24Hours: inLast24Hours.length,
      errors: rows.filter((row) => row.status === "error").length,
      signupRelated: rows.filter((row) => row.event.startsWith("signup_"))
        .length,
      recoveryRelated: rows.filter(
        (row) =>
          row.event.startsWith("password_reset") ||
          row.event === "password_recovery_entered" ||
          row.event === "recovery_link_detected"
      ).length,
    };
  }, [rows]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">Auth 診斷</h1>
          <p className="mt-1 text-sm text-gray-500">
            追蹤註冊、登入、重設密碼與 deep link 相關事件，資料來自 auth_diagnostics。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchDiagnostics()}
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

      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              最近 100 筆
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.total}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              24 小時內
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.last24Hours}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              錯誤事件
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {summary.errors}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              註冊相關
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.signupRelated}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              重設密碼相關
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.recoveryRelated}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>最近 Auth 事件</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-40 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : rows.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600">
              目前沒有 Auth 診斷資料。
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>時間</TableHead>
                    <TableHead>事件</TableHead>
                    <TableHead>狀態</TableHead>
                    <TableHead>Email</TableHead>
                    <TableHead>平台</TableHead>
                    <TableHead>版本</TableHead>
                    <TableHead>錯誤碼</TableHead>
                    <TableHead>訊息</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((row) => (
                    <TableRow key={row.id} className="align-top">
                      <TableCell className="whitespace-nowrap text-gray-600">
                        {formatDateTime(row.created_at)}
                      </TableCell>
                      <TableCell className="font-medium">{row.event}</TableCell>
                      <TableCell>
                        <span
                          className={`rounded-full px-2 py-1 text-xs font-medium ${statusPillClass(
                            row.status
                          )}`}
                        >
                          {row.status}
                        </span>
                      </TableCell>
                      <TableCell className="text-gray-600">
                        {row.email_redacted ?? "-"}
                      </TableCell>
                      <TableCell className="text-gray-600">
                        {row.platform ?? "-"}
                      </TableCell>
                      <TableCell className="text-gray-600">
                        {row.app_version
                          ? `${row.app_version} (${row.build_number ?? "-"})`
                          : "-"}
                      </TableCell>
                      <TableCell className="text-gray-600">
                        {row.error_code ?? "-"}
                      </TableCell>
                      <TableCell className="max-w-lg text-gray-700">
                        <div className="space-y-2">
                          <div>{row.message ?? "-"}</div>
                          {row.metadata &&
                          Object.keys(row.metadata).length > 0 ? (
                            <details className="rounded bg-slate-50 px-2 py-1">
                              <summary className="cursor-pointer text-xs text-slate-500">
                                metadata
                              </summary>
                              <pre className="mt-2 whitespace-pre-wrap break-all text-xs text-slate-600">
                                {JSON.stringify(row.metadata, null, 2)}
                              </pre>
                            </details>
                          ) : null}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
