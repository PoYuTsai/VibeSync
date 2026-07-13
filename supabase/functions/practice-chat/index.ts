import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { callDeepSeek } from "./deepseek.ts";
import { callClaude } from "./claude.ts";
import { adjudicatePracticeCandidate } from "./semantic_quality.ts";
import {
  createPracticeChatHandler,
  type PracticeSupabaseClient,
} from "./handler.ts";

export const handleRequest = createPracticeChatHandler({
  createSupabaseClient: () =>
    createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } },
    ) as unknown as PracticeSupabaseClient,
  callDeepSeek,
  callClaude,
  semanticAdjudicate: adjudicatePracticeCandidate,
  getEnv: (name) => Deno.env.get(name),
});

serve(handleRequest);
