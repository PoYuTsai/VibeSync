"use client";

export const dynamic = "force-dynamic";

import { useEffect, useMemo, useState } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

type AuthDiagnosticRow = {
  id: string;
  event: string;
  status: "info" | "success" | "warning" | "error";
  email_redacted: string | null;
  platform: string | null;
  app_version: string | null;
  build_number: string | null;
  error_code: string | null;
  message: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
};

function formatDateTime(value: string) {
  return new Date(value).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function statusPillClass(status: AuthDiagnosticRow["status"]) {
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

  useEffect(() => {
    async function fetchDiagnostics() {
      try {
        const response = await fetch("/api/admin/auth-diagnostics", {
          cache: "no-store",
        });
        const payload = await response.json();

        if (!response.ok) {
          throw new Error(payload.error || "Failed to load auth diagnostics");
        }

        setRows((payload.rows ?? []) as AuthDiagnosticRow[]);
      } catch (fetchError) {
        console.error("Failed to fetch auth diagnostics:", fetchError);
        setError(
          "Failed to load auth diagnostics. Check the admin API route and database access.",
        );
      } finally {
        setLoading(false);
      }
    }

    void fetchDiagnostics();
  }, []);

  const summary = useMemo(() => {
    const last24Hours = Date.now() - 24 * 60 * 60 * 1000;
    const inLast24Hours = rows.filter(
      (row) => new Date(row.created_at).getTime() >= last24Hours,
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
          row.event === "recovery_link_detected",
      ).length,
    };
  }, [rows]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Auth diagnostics</h1>
        <p className="mt-2 text-sm text-gray-500">
          Signup, resend, password reset, and recovery-link event history.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Last 100 rows
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.total}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Last 24h
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.last24Hours}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Errors
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
              Signup-related
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.signupRelated}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Recovery-related
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.recoveryRelated}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent auth events</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-40 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : error ? (
            <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          ) : rows.length === 0 ? (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
              No auth diagnostic rows yet.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full text-left text-sm">
                <thead>
                  <tr className="border-b text-gray-500">
                    <th className="px-3 py-2 font-medium">Time</th>
                    <th className="px-3 py-2 font-medium">Event</th>
                    <th className="px-3 py-2 font-medium">Status</th>
                    <th className="px-3 py-2 font-medium">Email</th>
                    <th className="px-3 py-2 font-medium">Platform</th>
                    <th className="px-3 py-2 font-medium">Build</th>
                    <th className="px-3 py-2 font-medium">Error code</th>
                    <th className="px-3 py-2 font-medium">Message</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.id} className="border-b align-top">
                      <td className="px-3 py-2 whitespace-nowrap text-gray-600">
                        {formatDateTime(row.created_at)}
                      </td>
                      <td className="px-3 py-2 font-medium">{row.event}</td>
                      <td className="px-3 py-2">
                        <span
                          className={`rounded-full px-2 py-1 text-xs font-medium ${statusPillClass(
                            row.status,
                          )}`}
                        >
                          {row.status}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-gray-600">
                        {row.email_redacted ?? "-"}
                      </td>
                      <td className="px-3 py-2 text-gray-600">
                        {row.platform ?? "-"}
                      </td>
                      <td className="px-3 py-2 text-gray-600">
                        {row.app_version
                          ? `${row.app_version} (${row.build_number ?? "-"})`
                          : "-"}
                      </td>
                      <td className="px-3 py-2 text-gray-600">
                        {row.error_code ?? "-"}
                      </td>
                      <td className="max-w-xl px-3 py-2 text-gray-600">
                        {row.message ?? "-"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
