import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

type CleanupTarget = {
  table: string;
  column: string;
  value: string;
  required?: boolean;
};

function isMissingRelationError(error: {
  code?: string;
  message?: string;
  details?: string;
}): boolean {
  const combined = `${error.code ?? ""} ${error.message ?? ""} ${
    error.details ?? ""
  }`.toLowerCase();

  return combined.includes("42p01") ||
    combined.includes("relation") && combined.includes("does not exist");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !/^Bearer\s+\S+/i.test(authHeader)) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    if (!isPlainObject(body)) {
      return jsonResponse({ error: "Request body must be a JSON object" }, 400);
    }

    const confirmation = typeof body.confirmation === "string"
      ? body.confirmation.trim().toUpperCase()
      : "";
    if (confirmation != "DELETE") {
      return jsonResponse({ error: "Invalid confirmation" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = stripBearer(authHeader);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    const cleanupTargets: CleanupTarget[] = [
      { table: "revenue_events", column: "user_id", value: user.id, required: true },
      { table: "test_users", column: "user_id", value: user.id, required: false },
      { table: "token_usage", column: "user_id", value: user.id, required: false },
      { table: "rate_limits", column: "user_id", value: user.id, required: false },
      { table: "ai_logs", column: "user_id", value: user.id, required: false },
      { table: "subscriptions", column: "user_id", value: user.id, required: false },
      { table: "users", column: "id", value: user.id, required: false },
      { table: "feedback", column: "user_id", value: user.id, required: false },
      { table: "webhook_logs", column: "user_id", value: user.id, required: false },
    ];

    for (const target of cleanupTargets) {
      const { error } = await supabase.from(target.table).delete().eq(
        target.column,
        target.value,
      );

      if (error) {
        if (isMissingRelationError(error)) {
          console.warn(
            `Skip cleanup for missing table ${target.table}:`,
            error.message,
          );
          continue;
        }

        if (!target.required) {
          console.warn(
            `Non-blocking cleanup failed for ${target.table}:`,
            error.message,
          );
          continue;
        }

        console.error(`Failed to clean ${target.table}:`, error);
        return jsonResponse({
          error: "Delete account data cleanup failed",
          detail: target.table,
        }, 500);
      }
    }

    const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error("Failed to delete auth user:", deleteError);
      return jsonResponse({
        error: "Delete account failed",
        detail: deleteError.message,
      }, 500);
    }

    return jsonResponse({
      success: true,
      deletedUserId: user.id,
    });
  } catch (error) {
    console.error("delete-account error:", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
