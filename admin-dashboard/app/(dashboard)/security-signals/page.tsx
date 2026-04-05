"use client";

export const dynamic = "force-dynamic";

import { useEffect, useMemo, useState } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

type Severity = "warning" | "critical";
type AlertStatus =
  | "pending"
  | "sent"
  | "suppressed"
  | "failed"
  | "skipped_no_channel";

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

type SecurityAlertEventRow = {
  dedupe_key: string;
  signal_key: string;
  severity: Severity;
  channel: string;
  title: string | null;
  last_detected_at: string;
  last_notified_at: string | null;
  notification_count: number;
  last_status: AlertStatus;
  last_response_code: number | null;
  last_error_message: string | null;
};

const severityRank: Record<Severity, number> = {
  critical: 0,
  warning: 1,
};

function formatDateTime(value: string | null) {
  if (!value) return "Never";

  return new Date(value).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function severityPillClass(severity: Severity) {
  return severity === "critical"
    ? "bg-red-100 text-red-700"
    : "bg-yellow-100 text-yellow-700";
}

function alertStatusPillClass(status: AlertStatus) {
  switch (status) {
    case "sent":
      return "bg-green-100 text-green-700";
    case "suppressed":
      return "bg-slate-100 text-slate-700";
    case "failed":
      return "bg-red-100 text-red-700";
    case "skipped_no_channel":
      return "bg-yellow-100 text-yellow-700";
    case "pending":
    default:
      return "bg-blue-100 text-blue-700";
  }
}

export default function SecuritySignalsPage() {
  const [signals, setSignals] = useState<SecuritySignalRow[]>([]);
  const [jobs, setJobs] = useState<SecurityAutomationStatusRow[]>([]);
  const [alerts, setAlerts] = useState<SecurityAlertEventRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchData() {
      try {
        const response = await fetch("/api/admin/security-signals", {
          cache: "no-store",
        });
        const payload = await response.json();

        if (!response.ok) {
          throw new Error(payload.error || "Failed to load security data");
        }

        const sortedSignals = ((payload.signals ?? []) as SecuritySignalRow[]).sort(
          (a, b) => {
            const severityDiff = severityRank[a.severity] -
              severityRank[b.severity];
            if (severityDiff !== 0) {
              return severityDiff;
            }

            return new Date(b.detected_at).getTime() -
              new Date(a.detected_at).getTime();
          },
        );

        setSignals(sortedSignals);
        setJobs((payload.jobs ?? []) as SecurityAutomationStatusRow[]);
        setAlerts((payload.alerts ?? []) as SecurityAlertEventRow[]);
      } catch (fetchError) {
        console.error("Failed to fetch security data:", fetchError);
        setError(
          "Failed to load security data. Check migrations, admin API routes, and database access.",
        );
      } finally {
        setLoading(false);
      }
    }

    void fetchData();
  }, []);

  const summary = useMemo(() => {
    const critical = signals.filter((signal) => signal.severity === "critical")
      .length;
    const warning = signals.filter((signal) => signal.severity === "warning")
      .length;
    const activeJobs = jobs.filter((job) => job.active).length;
    const failedRuns7d = jobs.reduce((sum, job) => sum + job.failed_runs_7d, 0);
    const sentAlerts = alerts.filter((alert) => alert.last_status === "sent")
      .length;

    return {
      totalSignals: signals.length,
      critical,
      warning,
      activeJobs,
      failedRuns7d,
      sentAlerts,
    };
  }, [alerts, jobs, signals]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Security signals</h1>
        <p className="mt-2 text-sm text-gray-500">
          Active anomalies, cron health, and recent alert-delivery state.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-6">
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
            <div className="text-2xl font-bold text-red-600">
              {summary.critical}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Warning
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-yellow-600">
              {summary.warning}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Active jobs
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.activeJobs}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Failed jobs (7d)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {summary.failedRuns7d}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              Alert sends (all channels)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-600">
              {summary.sentAlerts}
            </div>
          </CardContent>
        </Card>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Active signals</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-2 animate-pulse">
                {[1, 2, 3].map((row) => (
                  <div key={row} className="h-14 rounded bg-gray-100" />
                ))}
              </div>
            ) : signals.length === 0 ? (
              <div className="text-sm text-gray-500">No active signals.</div>
            ) : (
              <div className="space-y-3">
                {signals.map((signal) => (
                  <div
                    key={`${signal.signal_key}-${signal.detected_at}`}
                    className="rounded-lg border border-slate-200 p-4"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="font-medium">{signal.title}</div>
                        <div className="mt-1 text-sm text-gray-600">
                          {signal.summary}
                        </div>
                      </div>
                      <span
                        className={`rounded-full px-2 py-1 text-xs font-medium ${severityPillClass(
                          signal.severity,
                        )}`}
                      >
                        {signal.severity}
                      </span>
                    </div>
                    <div className="mt-3 text-xs text-gray-500">
                      observed {signal.observed_value}, threshold {signal.threshold_value},
                      window {signal.window_minutes} min, detected {formatDateTime(signal.detected_at)}
                    </div>
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
              <div className="space-y-2 animate-pulse">
                {[1, 2, 3].map((row) => (
                  <div key={row} className="h-14 rounded bg-gray-100" />
                ))}
              </div>
            ) : jobs.length === 0 ? (
              <div className="text-sm text-gray-500">No automation jobs found.</div>
            ) : (
              <div className="space-y-3">
                {jobs.map((job) => (
                  <div
                    key={job.jobname}
                    className="rounded-lg border border-slate-200 p-4"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div className="font-medium">{job.jobname}</div>
                      <span
                        className={`rounded-full px-2 py-1 text-xs font-medium ${
                          job.active
                            ? "bg-green-100 text-green-700"
                            : "bg-slate-100 text-slate-700"
                        }`}
                      >
                        {job.active ? "active" : "inactive"}
                      </span>
                    </div>
                    <div className="mt-1 text-sm text-gray-600">
                      schedule: {job.schedule}
                    </div>
                    <div className="mt-1 text-xs text-gray-500">
                      last run {formatDateTime(job.last_run_at)} / succeeded 7d {job.succeeded_runs_7d}
                      / failed 7d {job.failed_runs_7d}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent alert deliveries</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-2 animate-pulse">
              {[1, 2, 3].map((row) => (
                <div key={row} className="h-14 rounded bg-gray-100" />
              ))}
            </div>
          ) : alerts.length === 0 ? (
            <div className="text-sm text-gray-500">No alert deliveries yet.</div>
          ) : (
            <div className="space-y-3">
              {alerts.map((alert) => (
                <div
                  key={alert.dedupe_key}
                  className="rounded-lg border border-slate-200 p-4"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="font-medium">
                        {alert.title ?? alert.signal_key}
                      </div>
                      <div className="mt-1 text-sm text-gray-600">
                        {alert.channel} / {alert.signal_key}
                      </div>
                    </div>
                    <span
                      className={`rounded-full px-2 py-1 text-xs font-medium ${alertStatusPillClass(
                        alert.last_status,
                      )}`}
                    >
                      {alert.last_status}
                    </span>
                  </div>
                  <div className="mt-2 text-xs text-gray-500">
                    detected {formatDateTime(alert.last_detected_at)} / notified{" "}
                    {formatDateTime(alert.last_notified_at)} / count{" "}
                    {alert.notification_count}
                    {alert.last_response_code
                      ? ` / response ${alert.last_response_code}`
                      : ""}
                  </div>
                  {alert.last_error_message ? (
                    <div className="mt-2 text-xs text-red-600">
                      {alert.last_error_message}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
