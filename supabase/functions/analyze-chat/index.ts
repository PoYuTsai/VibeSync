// supabase/functions/analyze-chat/index.ts
// Composition root：只負責 serve bootstrap 與公開介面 re-export；
// 所有請求邏輯都在 analyze_chat_handler.ts 與各 mode 模組。
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { withOperationalErrorMonitoring } from "../_shared/operational_error_monitor.ts";
import { createAnalyzeChatHandler } from "./analyze_chat_handler.ts";

export {
  type AnalyzeChatHandlerDeps,
  createAnalyzeChatHandler,
} from "./analyze_chat_handler.ts";

if (import.meta.main) {
  serve(
    withOperationalErrorMonitoring("analyze-chat", createAnalyzeChatHandler()),
  );
}

// Prompt Caching enabled
// Last deployed: 2026-03-06
