// supabase/functions/coach-follow-up/cors_test.ts
//
// CORS contract tests — mirrors analyze-chat:3256-3275 pattern. coach-follow-up
// is JWT-verified (no --no-verify-jwt at deploy), but the browser still issues
// preflight OPTIONS for cross-origin POSTs from web/iOS clients, so CORS headers
// MUST land on every response (preflight + auth-fail + body-error + success).
//
// Three cases give complete coverage:
//   1. OPTIONS preflight → 200 + CORS (dedicated branch in handleRequest)
//   2. POST without Authorization → 401 + CORS (early return path)
//   3. jsonResponse helper carries CORS headers (proves all error paths —
//      400 invalid_request_body, 501 not_implemented, 429 quota — get CORS
//      since they all funnel through jsonResponse)

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleRequest, jsonResponse } from "./index.ts";

Deno.test("CORS: OPTIONS preflight returns 200 with CORS headers", async () => {
  const req = new Request("https://test.local/", { method: "OPTIONS" });
  const res = await handleRequest(req);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(res.headers.get("access-control-allow-methods"), "POST, OPTIONS");
  assertEquals(
    res.headers.get("access-control-allow-headers"),
    "Authorization, Content-Type, x-client-info, apikey",
  );
});

Deno.test("CORS: POST without Authorization returns 401 with CORS headers", async () => {
  const req = new Request("https://test.local/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  const res = await handleRequest(req);
  assertEquals(res.status, 401);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
});

Deno.test("CORS: jsonResponse helper attaches CORS headers to all body responses", () => {
  // Covers 400 invalid_request_body / 429 quota / 501 not_implemented / 500
  // — they all go through jsonResponse, so testing the helper proves coverage.
  const res = jsonResponse({ error: "anything" }, 400);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(res.headers.get("access-control-allow-methods"), "POST, OPTIONS");
  assertEquals(res.headers.get("content-type"), "application/json");
});
