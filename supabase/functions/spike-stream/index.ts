// supabase/functions/spike-stream/index.ts
//
// THROWAWAY SPIKE — delete after the streaming transport question is answered.
//
// Purpose: prove that a real Supabase Edge Function on project
// fcmwrmwdoqiqdnbisdpg can deliver an NDJSON response *incrementally* to a
// Flutter/iOS client, instead of buffering the whole body and flushing it at
// the end. This is the single blocking question for the full streaming
// analyze contract (docs/plans/2026-06-03-full-streaming-analyze-contract.md).
//
// Hard isolation guarantees (per Eric, 2026-06-03):
//   - Does NOT touch analyze-chat or any other function.
//   - Does NOT read or write the database.
//   - Does NOT charge quota.
//   - Does NOT change any schema.
//   - Does NOT call Claude.
// It only emits a scripted NDJSON stream so we can measure per-event arrival
// time on the device.
//
// Deploy (manual, NOT via main merge):
//   npx supabase functions deploy spike-stream \
//     --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
//
// --no-verify-jwt is intentional: it removes the JWT gateway as a buffering
// variable so this is the *purest* transport test. The Flutter harness still
// attaches a real `Authorization: Bearer` header so we also confirm header
// plumbing works end to end.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// One scripted analyze-like timeline. `delayMs` is how long to wait *before*
// emitting this line, so the cumulative wall clock matches `t` (seconds).
// The shape mirrors Eric's NDJSON example and the product target timeline in
// the full streaming contract (progress -> recommendation -> reply -> sections
// -> done).
interface ScriptStep {
  delayMs: number;
  event: Record<string, unknown>;
}

function buildScript(intervalMs: number): ScriptStep[] {
  const step = (
    seconds: number,
    event: Record<string, unknown>,
  ): ScriptStep => ({ delayMs: intervalMs, event: { ...event, t: seconds } });

  return [
    step(1, { type: "progress", message: "正在整理這段對話..." }),
    step(2, { type: "progress", message: "正在確認誰說了什麼..." }),
    step(3, { type: "progress", message: "正在判斷目前節奏與壓力點..." }),
    step(4, { type: "progress", message: "找出這回合最安全的接法..." }),
    step(5, {
      type: "recommendation",
      title: "本回合怎麼接",
      message: "先接住對方情緒，不急著推進。",
    }),
    step(6, { type: "progress", message: "已抓到方向，正在整理正式回覆..." }),
    step(8, {
      type: "reply",
      message: "我懂，你最近應該真的有點累。我們慢慢來就好。",
    }),
    step(10, {
      type: "section",
      name: "五種回覆風格",
      message: "完整分析區塊範例（風格列表）。",
    }),
    step(12, {
      type: "section",
      name: "互動雷達",
      message: "完整分析區塊範例（雷達數據）。",
    }),
    step(14, {
      type: "section",
      name: "深層策略",
      message: "完整分析區塊範例（策略建議）。",
    }),
    step(15, { type: "done" }),
  ];
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  // Allow a faster cadence for quick local checks: ?intervalMs=200
  const url = new URL(req.url);
  const intervalMs = Math.min(
    5000,
    Math.max(0, Number(url.searchParams.get("intervalMs") ?? "1000") || 1000),
  );

  const encoder = new TextEncoder();
  const script = buildScript(intervalMs);

  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      // `serverEmitMs` lets the client cross-check server emit time against
      // client receive time, isolating "model/server slow" from "transport
      // buffered the whole thing".
      const emit = (event: Record<string, unknown>) => {
        const line = JSON.stringify({ ...event, serverEmitMs: Date.now() }) +
          "\n";
        controller.enqueue(encoder.encode(line));
      };

      try {
        for (const stepDef of script) {
          await sleep(stepDef.delayMs);
          emit(stepDef.event);
        }
      } catch (err) {
        // If the client disconnects mid-stream, enqueue throws; swallow it so
        // we don't spam logs. This is the "中途斷線" path we want to observe.
        console.log("spike-stream aborted:", String(err));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(body, {
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/x-ndjson; charset=utf-8",
      // Hints to defeat any proxy/CDN buffering between Edge and the device.
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
    },
  });
});
