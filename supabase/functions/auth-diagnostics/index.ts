import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

const EVENT_REGEX = /^[a-z0-9_.:-]{1,64}$/;
const VALID_STATUSES = new Set(["info", "success", "warning", "error"]);
const VALID_PLATFORMS = new Set([
  "web",
  "ios",
  "android",
  "macos",
  "windows",
  "linux",
  "fuchsia",
]);
const MAX_MESSAGE_LENGTH = 500;
const MAX_ERROR_CODE_LENGTH = 80;
const MAX_METADATA_BYTES = 4096;
const MAX_PER_10_MINUTES = 30;
const MAX_PER_HOUR = 120;

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeOptionalString(
  value: unknown,
  maxLength: number,
): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  if (!normalized) {
    return undefined;
  }

  return normalized.length <= maxLength
    ? normalized
    : normalized.slice(0, maxLength);
}

function normalizeEvent(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_")
    .replace(/[^a-z0-9_.:-]/g, "_");

  return EVENT_REGEX.test(normalized) ? normalized : null;
}

function normalizeStatus(value: unknown): string {
  if (typeof value !== "string") {
    return "info";
  }

  const normalized = value.trim().toLowerCase();
  return VALID_STATUSES.has(normalized) ? normalized : "info";
}

function normalizePlatform(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim().toLowerCase();
  return VALID_PLATFORMS.has(normalized) ? normalized : undefined;
}

function sanitizeMetadata(value: unknown): Record<string, unknown> {
  if (!isPlainObject(value)) {
    return {};
  }

  const sanitized: Record<string, unknown> = {};
  for (const [rawKey, rawValue] of Object.entries(value).slice(0, 12)) {
    const key = rawKey.trim().replace(/\s+/g, "_").slice(0, 40);
    if (!key || rawValue === null || rawValue === undefined) {
      continue;
    }

    if (
      typeof rawValue === "string" || typeof rawValue === "number" ||
      typeof rawValue === "boolean"
    ) {
      sanitized[key] = typeof rawValue === "string"
        ? rawValue.trim().slice(0, 160)
        : rawValue;
      continue;
    }

    try {
      sanitized[key] = JSON.parse(JSON.stringify(rawValue));
    } catch {
      sanitized[key] = String(rawValue).slice(0, 160);
    }
  }

  const encoded = JSON.stringify(sanitized);
  if (new TextEncoder().encode(encoded).length <= MAX_METADATA_BYTES) {
    return sanitized;
  }

  const keys = Object.keys(sanitized);
  while (keys.length > 0) {
    const key = keys.pop()!;
    delete sanitized[key];
    sanitized._truncated = true;
    if (
      new TextEncoder().encode(JSON.stringify(sanitized)).length <=
        MAX_METADATA_BYTES
    ) {
      break;
    }
  }

  return sanitized;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function buildClientFingerprint(
  req: Request,
  emailRedacted?: string,
): Promise<string> {
  const forwardedFor = req.headers.get("x-forwarded-for") || "";
  const ipPrefix = forwardedFor.split(",")[0]?.trim().slice(0, 64) || "unknown";
  const userAgent = (req.headers.get("user-agent") || "unknown").slice(0, 160);
  const clientInfo = (req.headers.get("x-client-info") || "unknown").slice(
    0,
    160,
  );

  return await sha256Hex(`${ipPrefix}|${userAgent}|${clientInfo}|${emailRedacted ?? "no-email"}`);
}

function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

async function resolveAuthenticatedUserId(
  supabase: any,
  req: Request,
): Promise<string | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !/^Bearer\s+\S+/i.test(authHeader)) {
    return null;
  }

  try {
    const token = stripBearer(authHeader);
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser(token);

    if (error || !user) {
      return null;
    }

    return user.id;
  } catch {
    return null;
  }
}

async function checkRateLimit(
  supabase: any,
  clientFingerprint: string,
): Promise<{ allowed: boolean; retryAfterSeconds?: number }> {
  const now = Date.now();
  const tenMinutesAgo = new Date(now - 10 * 60 * 1000).toISOString();
  const oneHourAgo = new Date(now - 60 * 60 * 1000).toISOString();

  const { count: count10m, error: error10m } = await supabase
    .from("auth_diagnostics")
    .select("id", { count: "exact", head: true })
    .eq("client_fingerprint", clientFingerprint)
    .gte("created_at", tenMinutesAgo);

  if (error10m) {
    throw new Error(`Failed auth diagnostics 10m rate check: ${error10m.message}`);
  }

  if ((count10m ?? 0) >= MAX_PER_10_MINUTES) {
    return { allowed: false, retryAfterSeconds: 10 * 60 };
  }

  const { count: count1h, error: error1h } = await supabase
    .from("auth_diagnostics")
    .select("id", { count: "exact", head: true })
    .eq("client_fingerprint", clientFingerprint)
    .gte("created_at", oneHourAgo);

  if (error1h) {
    throw new Error(`Failed auth diagnostics 1h rate check: ${error1h.message}`);
  }

  if ((count1h ?? 0) >= MAX_PER_HOUR) {
    return { allowed: false, retryAfterSeconds: 60 * 60 };
  }

  return { allowed: true };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    if (!isPlainObject(body)) {
      return jsonResponse({ error: "Request body must be a JSON object" }, 400);
    }

    const event = normalizeEvent(body.event);
    if (!event) {
      return jsonResponse({ error: "Invalid event" }, 400);
    }

    const status = normalizeStatus(body.status);
    const emailRedacted = normalizeOptionalString(body.email_redacted, 255);
    const platform = normalizePlatform(body.platform);
    const appVersion = normalizeOptionalString(body.app_version, 32);
    const buildNumber = normalizeOptionalString(body.build_number, 32);
    const errorCode = normalizeOptionalString(body.error_code, MAX_ERROR_CODE_LENGTH);
    const message = normalizeOptionalString(body.message, MAX_MESSAGE_LENGTH);
    const metadata = sanitizeMetadata(body.metadata);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const clientFingerprint = await buildClientFingerprint(req, emailRedacted);
    const rateCheck = await checkRateLimit(supabase, clientFingerprint);

    if (!rateCheck.allowed) {
      return jsonResponse(
        { error: "Too many auth diagnostics requests" },
        429,
      );
    }

    const authenticatedUserId = await resolveAuthenticatedUserId(supabase, req);
    if (authenticatedUserId) {
      metadata.user_id = authenticatedUserId;
    }

    const { error: insertError } = await supabase.from("auth_diagnostics").insert({
      event,
      status,
      email_redacted: emailRedacted,
      platform,
      app_version: appVersion,
      build_number: buildNumber,
      error_code: errorCode,
      message,
      metadata,
      client_fingerprint: clientFingerprint,
    });

    if (insertError) {
      console.error("auth-diagnostics insert failed", insertError.message);
      return jsonResponse({ error: "Failed to record auth diagnostics" }, 500);
    }

    return jsonResponse({ success: true });
  } catch (error) {
    console.error("auth-diagnostics unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
