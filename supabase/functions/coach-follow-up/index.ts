// supabase/functions/coach-follow-up/index.ts
//
// Spec 5 Coach Follow-up v1 — independent Edge function (sibling to analyze-chat).
// MUST NOT import from supabase/functions/analyze-chat/** (OCR baseline isolation).
// JWT-verified deploy (no --no-verify-jwt). Cost = 1 credit, deducted only on success.
//
// T1 skeleton: GET / returns health probe; everything else returns 501 not_implemented.
// Subsequent tasks (T2-T8) flesh out validation, auth, quota gate, prompt, Claude call.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req: Request) => {
  if (req.method === "GET") {
    return new Response(
      JSON.stringify({ status: "ok", function: "coach-follow-up" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ error: "not_implemented" }),
    { status: 501, headers: { "Content-Type": "application/json" } },
  );
});
