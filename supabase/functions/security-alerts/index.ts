import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_SECURITY_CHAT_ID") ||
  Deno.env.get("TELEGRAM_CHAT_ID");
const SECURITY_ALERT_SECRET = Deno.env.get("SECURITY_ALERT_SECRET");
const SECURITY_ALERT_WEBHOOK_URL = Deno.env.get("SECURITY_ALERT_WEBHOOK_URL")
  ?.trim();
const SECURITY_ALERT_WEBHOOK_BEARER_TOKEN = Deno.env.get(
  "SECURITY_ALERT_WEBHOOK_BEARER_TOKEN",
)?.trim();
const SECURITY_ALERT_WEBHOOK_TIMEOUT_MS = Number(
  Deno.env.get("SECURITY_ALERT_WEBHOOK_TIMEOUT_MS") ?? "5000",
);
const ALERT_COOLDOWN_MINUTES = Number(
  Deno.env.get("SECURITY_ALERT_COOLDOWN_MINUTES") ?? "360",
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey, x-security-alert-secret",
};

type Severity = "warning" | "critical";
type AlertChannel = "telegram" | "webhook";
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

type SecurityAlertEventRow = {
  dedupe_key: string;
  first_detected_at: string | null;
  last_notified_at: string | null;
  notification_count: number | null;
};

type DeliveryResult = {
  ok: boolean;
  responseCode?: number;
  errorMessage?: string;
};

type DeliveryTarget = {
  channel: AlertChannel;
  configured: boolean;
  missingMessage: string;
  deliver(signal: SecuritySignalRow, source: string): Promise<DeliveryResult>;
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeSeverity(value: unknown): Severity | "all" {
  if (typeof value !== "string") {
    return "critical";
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === "warning" || normalized === "critical") {
    return normalized;
  }
  if (normalized === "all") {
    return "all";
  }

  return "critical";
}

function normalizeBoolean(value: unknown): boolean {
  return value === true || value === "true" || value === 1 || value === "1";
}

function dedupeKey(signal: SecuritySignalRow, channel: AlertChannel): string {
  return `${channel}:${signal.severity}:${signal.signal_key}`;
}

function withinCooldown(
  lastNotifiedAt: string | null,
  cooldownMinutes: number,
): boolean {
  if (!lastNotifiedAt) {
    return false;
  }

  const parsed = new Date(lastNotifiedAt);
  if (Number.isNaN(parsed.getTime())) {
    return false;
  }

  return Date.now() - parsed.getTime() < cooldownMinutes * 60 * 1000;
}

function truncate(value: string, maxLength: number): string {
  return value.length <= maxLength ? value : `${value.slice(0, maxLength)}...`;
}

function formatNumber(value: number | null): string {
  return value == null ? "-" : value.toLocaleString("en-US");
}

function formatDetails(details: Record<string, unknown> | null): string | null {
  if (!details || Object.keys(details).length === 0) {
    return null;
  }

  const serialized = JSON.stringify(details, null, 2);
  return truncate(serialized, 1200);
}

function buildTelegramMessage(signal: SecuritySignalRow): string {
  const detailsText = formatDetails(signal.details);
  const parts = [
    `VibeSync Security Alert (${signal.severity.toUpperCase()})`,
    "",
    `Signal: ${signal.signal_key}`,
    `Title: ${signal.title}`,
    `Observed: ${formatNumber(signal.observed_value)}`,
    `Threshold: ${formatNumber(signal.threshold_value)}`,
    `Baseline: ${formatNumber(signal.baseline_value)}`,
    `Window: ${signal.window_minutes} min`,
    `Detected: ${new Date(signal.detected_at).toISOString()}`,
    "",
    signal.summary,
  ];

  if (detailsText) {
    parts.push("", "Details:", detailsText);
  }

  return parts.join("\n");
}

function buildWebhookPayload(signal: SecuritySignalRow, source: string) {
  return {
    type: "security_alert",
    source,
    signalKey: signal.signal_key,
    severity: signal.severity,
    title: signal.title,
    summary: signal.summary,
    detectedAt: signal.detected_at,
    windowMinutes: signal.window_minutes,
    observedValue: signal.observed_value,
    thresholdValue: signal.threshold_value,
    baselineValue: signal.baseline_value,
    details: signal.details ?? {},
  };
}

async function sendTelegram(text: string): Promise<DeliveryResult> {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    return {
      ok: false,
      errorMessage: "Telegram security channel not configured",
    };
  }

  try {
    const response = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: TELEGRAM_CHAT_ID,
          text,
        }),
      },
    );

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      return {
        ok: false,
        responseCode: response.status,
        errorMessage: truncate(detail || "Telegram API request failed", 500),
      };
    }

    return { ok: true, responseCode: response.status };
  } catch (error) {
    return {
      ok: false,
      errorMessage: truncate(
        error instanceof Error ? error.message : String(error),
        500,
      ),
    };
  }
}

async function sendWebhook(
  signal: SecuritySignalRow,
  source: string,
): Promise<DeliveryResult> {
  if (!SECURITY_ALERT_WEBHOOK_URL) {
    return {
      ok: false,
      errorMessage: "Security alert webhook not configured",
    };
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (SECURITY_ALERT_WEBHOOK_BEARER_TOKEN) {
    headers.Authorization = `Bearer ${SECURITY_ALERT_WEBHOOK_BEARER_TOKEN}`;
  }

  try {
    const response = await fetch(SECURITY_ALERT_WEBHOOK_URL, {
      method: "POST",
      headers,
      body: JSON.stringify(buildWebhookPayload(signal, source)),
      signal: AbortSignal.timeout(SECURITY_ALERT_WEBHOOK_TIMEOUT_MS),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      return {
        ok: false,
        responseCode: response.status,
        errorMessage: truncate(detail || "Webhook request failed", 500),
      };
    }

    return { ok: true, responseCode: response.status };
  } catch (error) {
    return {
      ok: false,
      errorMessage: truncate(
        error instanceof Error ? error.message : String(error),
        500,
      ),
    };
  }
}

function buildDeliveryTargets(): DeliveryTarget[] {
  const targets: DeliveryTarget[] = [
    {
      channel: "telegram",
      configured: Boolean(TELEGRAM_BOT_TOKEN && TELEGRAM_CHAT_ID),
      missingMessage: "Telegram security channel not configured",
      deliver(signal) {
        return sendTelegram(buildTelegramMessage(signal));
      },
    },
  ];

  if (SECURITY_ALERT_WEBHOOK_URL) {
    targets.push({
      channel: "webhook",
      configured: true,
      missingMessage: "Security alert webhook not configured",
      deliver(signal, source) {
        return sendWebhook(signal, source);
      },
    });
  }

  return targets;
}

async function upsertAlertEvent(
  supabase: ReturnType<typeof createClient<any>>,
  payload: {
    signal: SecuritySignalRow;
    channel: AlertChannel;
    source: string;
    nowIso: string;
    existing: SecurityAlertEventRow | undefined;
    status: AlertStatus;
    responseCode?: number | null;
    errorMessage?: string | null;
    incrementNotificationCount?: boolean;
    lastNotifiedAt?: string | null;
  },
) {
  const key = dedupeKey(payload.signal, payload.channel);
  const nextNotificationCount = (payload.existing?.notification_count ?? 0) +
    (payload.incrementNotificationCount ? 1 : 0);

  const { error } = await supabase.from("security_alert_events").upsert({
    signal_key: payload.signal.signal_key,
    severity: payload.signal.severity,
    channel: payload.channel,
    dedupe_key: key,
    title: payload.signal.title,
    signal_snapshot: {
      ...payload.signal,
      source: payload.source,
      channel: payload.channel,
    },
    first_detected_at: payload.existing?.first_detected_at ?? payload.nowIso,
    last_detected_at: payload.signal.detected_at || payload.nowIso,
    last_notified_at: payload.lastNotifiedAt ?? payload.existing?.last_notified_at ??
      null,
    notification_count: nextNotificationCount,
    last_status: payload.status,
    last_response_code: payload.responseCode ?? null,
    last_error_message: payload.errorMessage ?? null,
  }, { onConflict: "dedupe_key" });

  return error;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  if (!SECURITY_ALERT_SECRET || !SECURITY_ALERT_SECRET.trim()) {
    return jsonResponse({ error: "Server misconfigured" }, 500);
  }

  const providedSecret = req.headers.get("x-security-alert-secret");
  if (providedSecret !== SECURITY_ALERT_SECRET) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: unknown = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const requestBody = isPlainObject(body) ? body : {};
  const severityFilter = normalizeSeverity(requestBody.severity);
  const dryRun = normalizeBoolean(requestBody.dryRun);
  const source = typeof requestBody.source === "string"
    ? requestBody.source.trim().slice(0, 80)
    : "unknown";

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await supabase.from("security_signals").select("*");

    if (error) {
      console.error("security-alerts failed to fetch signals", error);
      return jsonResponse({ error: "Failed to fetch security signals" }, 500);
    }

    const signals = ((data ?? []) as SecuritySignalRow[]).filter((signal) =>
      severityFilter === "all" ? true : signal.severity === severityFilter
    );

    const deliveryTargets = buildDeliveryTargets();

    if (signals.length === 0) {
      return jsonResponse({
        success: true,
        source,
        dryRun,
        checkedSignals: 0,
        checkedChannels: deliveryTargets.length,
        sent: 0,
        suppressed: 0,
        failed: 0,
        skippedNoChannel: 0,
      });
    }

    const keys = signals.flatMap((signal) =>
      deliveryTargets.map((target) => dedupeKey(signal, target.channel))
    );

    const { data: existingRows, error: existingError } = await supabase
      .from("security_alert_events")
      .select(
        "dedupe_key, first_detected_at, last_notified_at, notification_count",
      )
      .in("dedupe_key", keys);

    if (existingError) {
      console.error("security-alerts failed to fetch alert events", existingError);
      return jsonResponse({ error: "Failed to fetch alert events" }, 500);
    }

    const existingMap = new Map(
      ((existingRows ?? []) as SecurityAlertEventRow[]).map((row) => [
        row.dedupe_key,
        row,
      ]),
    );

    let sent = 0;
    let suppressed = 0;
    let failed = 0;
    let skippedNoChannel = 0;

    for (const signal of signals) {
      for (const target of deliveryTargets) {
        const key = dedupeKey(signal, target.channel);
        const existing = existingMap.get(key);
        const nowIso = new Date().toISOString();

        if (!target.configured) {
          skippedNoChannel++;
          const upsertError = await upsertAlertEvent(supabase, {
            signal,
            channel: target.channel,
            source,
            nowIso,
            existing,
            status: "skipped_no_channel",
            errorMessage: target.missingMessage,
          });

          if (upsertError) {
            console.error(
              `security-alerts ${target.channel} skipped_no_channel upsert failed`,
              upsertError,
            );
          }
          continue;
        }

        if (
          !dryRun &&
          withinCooldown(existing?.last_notified_at ?? null, ALERT_COOLDOWN_MINUTES)
        ) {
          suppressed++;
          const upsertError = await upsertAlertEvent(supabase, {
            signal,
            channel: target.channel,
            source,
            nowIso,
            existing,
            status: "suppressed",
            errorMessage: `Cooldown active (${ALERT_COOLDOWN_MINUTES}m)`,
          });

          if (upsertError) {
            console.error(
              `security-alerts ${target.channel} suppressed upsert failed`,
              upsertError,
            );
          }
          continue;
        }

        if (dryRun) {
          suppressed++;
          continue;
        }

        const result = await target.deliver(signal, source);
        const upsertError = await upsertAlertEvent(supabase, {
          signal,
          channel: target.channel,
          source,
          nowIso,
          existing,
          status: result.ok ? "sent" : "failed",
          responseCode: result.responseCode ?? null,
          errorMessage: result.errorMessage ?? null,
          incrementNotificationCount: result.ok,
          lastNotifiedAt: result.ok ? nowIso : existing?.last_notified_at ?? null,
        });

        if (upsertError) {
          console.error(
            `security-alerts ${target.channel} result upsert failed`,
            upsertError,
          );
        }

        if (result.ok) {
          sent++;
        } else {
          failed++;
        }
      }
    }

    return jsonResponse({
      success: true,
      source,
      dryRun,
      checkedSignals: signals.length,
      checkedChannels: deliveryTargets.length,
      sent,
      suppressed,
      failed,
      skippedNoChannel,
      cooldownMinutes: ALERT_COOLDOWN_MINUTES,
      enabledChannels: deliveryTargets
        .filter((target) => target.configured)
        .map((target) => target.channel),
    });
  } catch (error) {
    console.error("security-alerts unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
