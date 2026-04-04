"use client";

export const dynamic = "force-dynamic";

import { useEffect, useMemo, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { isSupabaseConfigured, supabase } from "@/lib/supabase";

type Severity = "warning" | "critical";

type SecuritySignalRow = {
  signal_key: string;
  severity: Severity;
  title: string;
  summary: string;
  window_minutes: number;
  observed_value: number;
  threshold_value: number;
  baseline_value: number | null;
  detected_at: string;
  details: Record<string, unknown> | null;
};

type SecurityAutomationStatusRow = {
  jobname: string;
  schedule: string;
  active: boolean;
  command: string;
  last_run_at: string | null;
  succeeded_runs_7d: number;
  failed_runs_7d: number;
};

const severityRank: Record<Severity, number> = {
  critical: 0,
  warning: 1,
};

function formatDateTime(value: string | null) {
  if (!value) {
    return "尚未執行";
  }

  return new Date(value).toLocaleString("zh-TW", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function severityPillClass(severity: Severity) {
  switch (severity) {
    case "critical":
      return "bg-red-100 text-red-700";
    case "warning":
    default:
      return "bg-yellow-100 text-yellow-700";
  }
}

export default function SecuritySignalsPage() {
  const [signals, setSignals] = useState<SecuritySignalRow[]>([]);
  const [jobs, setJobs] = useState<SecurityAutomationStatusRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchData() {
      if (!isSupabaseConfigured()) {
        setError("Supabase 尚未設定，無法載入 Security Signals。");
        setLoading(false);
        return;
      }

      try {
        const [{ data: signalData, error: signalError }, { data: jobData, error: jobError }] =
          await Promise.all([
            supabase.from("security_signals").select("*"),
            supabase.from("security_automation_status").select("*"),
          ]);

        if (signalError) {
          throw signalError;
        }

        if (jobError) {
          throw jobError;
        }

        const sortedSignals = ((signalData ?? []) as SecuritySignalRow[]).sort(
          (a, b) => {
            const severityDiff = severityRank[a.severity] - severityRank[b.severity];
            if (severityDiff !== 0) {
              return severityDiff;
            }

            return (
              new Date(b.detected_at).getTime() - new Date(a.detected_at).getTime()
            );
          },
        );

        setSignals(sortedSignals);
        setJobs((jobData ?? []) as SecurityAutomationStatusRow[]);
      } catch (error) {
        console.error("Failed to fetch security signals:", error);
        setError("無法載入 Security Signals，請先確認 migration 已套用。");
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, []);

  const summary = useMemo(() => {
    const critical = signals.filter((signal) => signal.severity === "critical").length;
    const warning = signals.filter((signal) => signal.severity === "warning").length;
    const activeJobs = jobs.filter((job) => job.active).length;
    const failedRuns7d = jobs.reduce((sum, job) => sum + job.failed_runs_7d, 0);

    return {
      totalSignals: signals.length,
      critical,
      warning,
      activeJobs,
      failedRuns7d,
    };
  }, [jobs, signals]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Security Signals</h1>
        <p className="mt-2 text-sm text-gray-500">
          這裡會顯示目前仍在發生的 auth / AI / webhook / cleanup 異常訊號，以及排程清理 job 的最近狀態。
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Active signals
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.totalSignals}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Critical
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">{summary.critical}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Warning
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-yellow-600">{summary.warning}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Active cleanup jobs
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.activeJobs}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Cleanup failures 7d
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {summary.failedRuns7d}
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Current signals</CardTitle>
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
          ) : signals.length === 0 ? (
            <div className="rounded-md border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-700">
              目前沒有觸發中的安全異常訊號。
            </div>
          ) : (
            <div className="space-y-3">
              {signals.map((signal) => (
                <div
                  key={signal.signal_key}
                  className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <span
                      className={`rounded-full px-2 py-1 text-xs font-medium ${severityPillClass(
                        signal.severity,
                      )}`}
                    >
                      {signal.severity}
                    </span>
                    <span className="text-sm font-semibold">{signal.title}</span>
                    <span className="text-xs text-slate-500">{signal.signal_key}</span>
                  </div>

                  <p className="mt-2 text-sm text-slate-700">{signal.summary}</p>

                  <div className="mt-3 grid gap-3 text-sm text-slate-600 md:grid-cols-4">
                    <div>
                      <div className="text-xs uppercase tracking-wide text-slate-400">
                        Observed
                      </div>
                      <div className="font-medium">{signal.observed_value}</div>
                    </div>
                    <div>
                      <div className="text-xs uppercase tracking-wide text-slate-400">
                        Threshold
                      </div>
                      <div className="font-medium">{signal.threshold_value}</div>
                    </div>
                    <div>
                      <div className="text-xs uppercase tracking-wide text-slate-400">
                        Baseline
                      </div>
                      <div className="font-medium">
                        {signal.baseline_value == null ? "-" : signal.baseline_value}
                      </div>
                    </div>
                    <div>
                      <div className="text-xs uppercase tracking-wide text-slate-400">
                        Window
                      </div>
                      <div className="font-medium">{signal.window_minutes} min</div>
                    </div>
                  </div>

                  {signal.details && Object.keys(signal.details).length > 0 ? (
                    <details className="mt-3 rounded bg-slate-50 px-3 py-2">
                      <summary className="cursor-pointer text-xs text-slate-500">
                        details
                      </summary>
                      <pre className="mt-2 whitespace-pre-wrap break-all text-xs text-slate-600">
                        {JSON.stringify(signal.details, null, 2)}
                      </pre>
                    </details>
                  ) : null}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Automation status</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex h-32 items-center justify-center">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
            </div>
          ) : jobs.length === 0 ? (
            <div className="rounded-md border border-yellow-200 bg-yellow-50 px-4 py-3 text-sm text-yellow-700">
              尚未偵測到 security cleanup cron jobs。請先確認 migration 已套用。
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full text-left text-sm">
                <thead>
                  <tr className="border-b text-gray-500">
                    <th className="px-3 py-2 font-medium">Job</th>
                    <th className="px-3 py-2 font-medium">Schedule</th>
                    <th className="px-3 py-2 font-medium">Active</th>
                    <th className="px-3 py-2 font-medium">Last run</th>
                    <th className="px-3 py-2 font-medium">Succeeded 7d</th>
                    <th className="px-3 py-2 font-medium">Failed 7d</th>
                  </tr>
                </thead>
                <tbody>
                  {jobs.map((job) => (
                    <tr key={job.jobname} className="border-b align-top">
                      <td className="px-3 py-2 font-medium">{job.jobname}</td>
                      <td className="px-3 py-2 text-gray-600">{job.schedule}</td>
                      <td className="px-3 py-2">
                        <span
                          className={`rounded-full px-2 py-1 text-xs font-medium ${
                            job.active
                              ? "bg-green-100 text-green-700"
                              : "bg-slate-100 text-slate-700"
                          }`}
                        >
                          {job.active ? "active" : "inactive"}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-gray-600">
                        {formatDateTime(job.last_run_at)}
                      </td>
                      <td className="px-3 py-2 text-gray-600">
                        {job.succeeded_runs_7d}
                      </td>
                      <td className="px-3 py-2 text-gray-600">{job.failed_runs_7d}</td>
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
