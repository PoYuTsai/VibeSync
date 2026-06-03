# Full Streaming Analyze-Chat Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the "wait ~15–20s for one big JSON" analyze-chat experience with a single full-prompt path that streams typed NDJSON events, so the user sees progress → 本回合怎麼接 (3–8s) → AI 推薦回覆 (6–12s) → the rest of the report incrementally.

**Architecture:** Extend the existing `analyze-chat/index.ts` with a 4th `responseMode: "stream"` branch (reusing auth / subscription / quota-gate / context-compile / guardrail / post-process). One full Claude call runs with `stream: true`; a new **reframer** turns Claude's text deltas into complete, validated, contract-ordered NDJSON events AND assembles the legacy `AnalysisResult` for the final `done` event. Quota uses **charge-before-emit** on the `analysis.recommendation` event, backed by a **new dedicated `analysis_stream_runs` table + `charge_stream_analysis_run` RPC** (the existing two-stage `analysis_runs` lifecycle is left untouched). Streaming is **whitelist-gated** server- and client-side; everyone else, and any pre-recommendation failure, falls back to the existing stable full path (= rollback path). Flutter reuses the proven spike transport (`http.Client().send()` + `utf8.decoder` + `LineSplitter`).

**Tech Stack:** Supabase Edge (Deno/TypeScript), Anthropic Messages API streaming SSE, Postgres (PL/pgSQL RPC + migration), Flutter (Riverpod notifier, `package:http` streaming).

**Source of truth:** `docs/plans/2026-06-03-full-streaming-analyze-contract.md` (v2). This plan implements that contract. Where this plan and the contract disagree, STOP and ask.

**Scope guardrails (locked 2026-06-03):**
- IN: analyze-chat text path streaming, Flutter streaming UI, one whitelist-gated TestFlight dogfood build that doubles as iOS transport/feel verification (redefined gate #5).
- OUT: optimize_message/草稿潤飾 (next-stage todo), Coach 1:1, coach follow-up, Opener, Paywall, App Review video, screenshot/OCR streaming.
- This dogfood build is NOT submission-ready. Streaming is NOT "safe" until dogfood proves incremental arrival on a real iPhone.

**Redefined Gate #5 (was: standalone Flutter spike must pass):**
- No standalone spike required. The first whitelist dogfood build verifies transport.
- PASS = on a real iPhone, events arrive incrementally (progress within ~1–3s, 本回合怎麼接 within 3–8s, AI 推薦回覆 within 6–12s) — NOT all at once near the end.
- FAIL (iOS buffers, or no incremental milestones) = STOP, do not submit, return to architecture (test SSE variant or chunked/polling fallback). Do not treat streaming as done.

**Review gate:** High-risk (analyze-chat + quota + AI prompt/token + Edge schema + frontend analysis state). Codex read-only review REQUIRED before telling Eric/Bruce the build is safe to dogfood. Leave evidence (job id / review doc / queue update).

---

## Phase 0 — Branch & scaffolding

### Task 0.1: Create implementation branch off main

**Files:** none (git only)

**Steps:**
1. The throwaway spike branch (`spike/streaming-ndjson`) and its commits are NOT the base. Branch off `main`:
   ```bash
   git fetch origin
   git switch -c feat/streaming-analyze origin/main
   ```
2. Copy the contract + this plan onto the new branch (they currently live only on spike/codex branches):
   ```bash
   git checkout spike/streaming-ndjson -- \
     docs/plans/2026-06-03-full-streaming-analyze-contract.md \
     docs/plans/2026-06-03-full-streaming-analyze-implementation.md
   git add docs/plans/2026-06-03-full-streaming-analyze-*.md
   git commit -m "docs: 帶入完整串流分析契約與實作計畫"
   ```
3. Confirm `lib/spike/` and `supabase/functions/spike-stream/` are NOT on this branch (they are throwaway and must not ship):
   ```bash
   ls lib/spike 2>/dev/null && echo "WARN: spike present" || echo "ok: no lib/spike"
   ```
   If present, do not delete the spike's *learnings* — the transport pattern is documented in this plan (Task 6.1). Just ensure spike code is not carried into the real branch.

**Commit:** as above.

---

## Phase 1 — Database: `analysis_stream_runs` + charge RPC

> The reframer charges quota the instant a valid `analysis.recommendation` is produced, BEFORE that event is flushed to the client. The charge must be atomic with persisting the recommendation, so a charged run can always be resumed/re-sent without re-charging.

### Task 1.1: Migration — `analysis_stream_runs` table

**Files:**
- Create: `supabase/migrations/20260603120000_analysis_stream_runs.sql`

**Step 1: Write the migration**

```sql
-- Streaming analyze lifecycle: pending -> charged -> done | failed
-- Deliberately separate from analysis_runs (two-stage quick/full), which has
-- quick_result NOT NULL and a charged-boolean model that does not fit this
-- lifecycle. Keeping them separate limits blast radius on the live quota path.
CREATE TABLE IF NOT EXISTS public.analysis_stream_runs (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_hash   TEXT        NOT NULL,
  status              TEXT        NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','charged','done','failed')),
  selected_style      TEXT,                 -- one of extend|resonate|tease|humor|coldRead
  recommendation_json JSONB,                -- validated, re-sendable official recommendation
  final_result_json   JSONB,                -- legacy-compatible AnalysisResult at done
  charged_at          TIMESTAMPTZ,          -- non-null => quota already consumed, never re-charge
  last_error_code     TEXT,
  request_context     JSONB,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at          TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 minutes')
);

CREATE INDEX IF NOT EXISTS analysis_stream_runs_user_idx
  ON public.analysis_stream_runs (user_id);

ALTER TABLE public.analysis_stream_runs ENABLE ROW LEVEL SECURITY;
-- service_role only; clients never query directly (parity with analysis_runs).

-- Invariants enforced by the charge RPC, not by constraints alone:
--   charged_at IS NOT NULL  =>  recommendation_json IS NOT NULL AND selected_style IS NOT NULL
COMMENT ON TABLE public.analysis_stream_runs IS
  'Streaming analyze runs. charged_at non-null is the single source of truth for "already billed"; resume/retry must never re-charge.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_analysis_stream_runs()
RETURNS void LANGUAGE sql AS $$
  DELETE FROM public.analysis_stream_runs
  WHERE expires_at < now() - interval '1 hour';
$$;
```

**Step 2: Verify SQL parses locally (if a local db / supabase is available)**

Run (best-effort; if no local stack, mark as "deferred to deploy"):
```bash
npx supabase db lint 2>/dev/null || echo "no local lint; verify on deploy"
```

**Step 3: Commit**
```bash
git add supabase/migrations/20260603120000_analysis_stream_runs.sql
git commit -m "feat(db): 新增 analysis_stream_runs 串流分析生命週期表"
```

### Task 1.2: Migration — `charge_stream_analysis_run` RPC (atomic charge-before-emit)

**Files:**
- Create: `supabase/migrations/20260603120100_charge_stream_analysis_run.sql`

**Step 1: Write the RPC**

```sql
-- Atomic: writes charged_at + recommendation_json + selected_style + status in
-- ONE transaction and consumes quota via increment_usage. If increment_usage
-- raises (quota exhausted), the whole TX rolls back: no charge, no charged_at.
--
-- Idempotency: a run whose charged_at is already set is returned UNCHANGED and
-- increment_usage is NOT called again (retry/resume safety).
CREATE OR REPLACE FUNCTION public.charge_stream_analysis_run(
  p_run_id              UUID,
  p_user_id             UUID,
  p_conversation_hash   TEXT,
  p_recommendation_json JSONB,
  p_selected_style      TEXT,
  p_message_count       INTEGER,
  p_charge_quota        BOOLEAN
) RETURNS public.analysis_stream_runs
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row public.analysis_stream_runs;
BEGIN
  SELECT * INTO v_row
  FROM public.analysis_stream_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STREAM_RUN_NOT_FOUND';
  END IF;

  -- Ownership + conversation identity (defense in depth).
  IF v_row.user_id <> p_user_id THEN
    RAISE EXCEPTION 'STREAM_RUN_OWNER_MISMATCH';
  END IF;
  IF v_row.conversation_hash <> p_conversation_hash THEN
    RAISE EXCEPTION 'RUN_CONVERSATION_MISMATCH';
  END IF;

  -- Already charged => idempotent return, never double-charge.
  IF v_row.charged_at IS NOT NULL THEN
    RETURN v_row;
  END IF;

  IF p_charge_quota THEN
    PERFORM public.increment_usage(p_user_id, p_message_count);
  END IF;

  UPDATE public.analysis_stream_runs
  SET status              = 'charged',
      charged_at          = now(),
      recommendation_json = p_recommendation_json,
      selected_style      = p_selected_style
  WHERE id = p_run_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
```

**Step 2: Commit**
```bash
git add supabase/migrations/20260603120100_charge_stream_analysis_run.sql
git commit -m "feat(db): 新增 charge_stream_analysis_run 原子扣費 RPC（charge-before-emit）"
```

> NOTE: `increment_usage(p_user_id, p_message_count)` is the existing function used by `create_charged_analysis_run`. Reuse it verbatim. Confirm its signature in `supabase/migrations/20260528001200_create_charged_analysis_run.sql` before writing this RPC; match argument names/types exactly.

---

## Phase 2 — Backend reframer (pure, TDD-heavy)

> The reframer is the core. It is a PURE module (no network, no DB) so it can be unit-tested exhaustively. It takes Claude text chunks and emits validated, contract-ordered events; it also assembles the legacy `AnalysisResult`. Charge/IO happens in the index.ts branch (Phase 4), driven by a callback the reframer invokes when the recommendation is ready.

### Task 2.1: Event types + line parser

**Files:**
- Create: `supabase/functions/analyze-chat/stream_events.ts`
- Test: `supabase/functions/analyze-chat/stream_events_test.ts`

**Step 1: Write the failing test** (`stream_events_test.ts`)

```ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseEventLine, STREAM_STYLES } from "./stream_events.ts";

Deno.test("parseEventLine returns null for blank / partial lines", () => {
  assertEquals(parseEventLine(""), null);
  assertEquals(parseEventLine("   "), null);
  assertEquals(parseEventLine('{"type":"analysis.decision"'), null); // unterminated
});

Deno.test("parseEventLine parses a complete minified event", () => {
  const line = '{"type":"analysis.decision","selectedStyle":"resonate","nextStepTitle":"先接住情緒","nextStepBody":"b","doThis":"d","avoidThis":"a","confidence":"high"}';
  const ev = parseEventLine(line);
  assertEquals(ev?.type, "analysis.decision");
});

Deno.test("STREAM_STYLES are the five canonical styles", () => {
  assertEquals([...STREAM_STYLES].sort(), ["coldRead","extend","humor","resonate","tease"]);
});
```

**Step 2: Run, expect FAIL**
Run: `~/.deno/bin/deno test supabase/functions/analyze-chat/stream_events_test.ts`
Expected: FAIL (module/exports missing).

**Step 3: Implement `stream_events.ts`**

```ts
export const STREAM_STYLES = new Set([
  "extend", "resonate", "tease", "humor", "coldRead",
] as const);

export type StreamEventType =
  | "analysis.started"
  | "analysis.progress"
  | "analysis.decision"
  | "analysis.recommendation"
  | "analysis.reply_option"
  | "analysis.metrics"
  | "analysis.coach_hint"
  | "analysis.report_section"
  | "analysis.done"
  | "analysis.error";

export interface StreamEvent {
  type: StreamEventType;
  [k: string]: unknown;
}

/** Parse ONE NDJSON line. Returns null for blank lines or incomplete JSON. */
export function parseEventLine(line: string): StreamEvent | null {
  const trimmed = line.trim();
  if (!trimmed) return null;
  try {
    const obj = JSON.parse(trimmed);
    if (obj && typeof obj === "object" && typeof obj.type === "string") {
      return obj as StreamEvent;
    }
    return null;
  } catch {
    return null; // partial/garbled line — caller keeps buffering
  }
}
```

**Step 4: Run, expect PASS**
Run: `~/.deno/bin/deno test supabase/functions/analyze-chat/stream_events_test.ts`

**Step 5: Commit**
```bash
git add supabase/functions/analyze-chat/stream_events*.ts
git commit -m "feat(stream): 串流事件型別與單行 NDJSON parser"
```

### Task 2.2: Recommendation-only guardrail

**Files:**
- Create: `supabase/functions/analyze-chat/stream_recommendation_guardrail.ts`
- Test: `supabase/functions/analyze-chat/stream_recommendation_guardrail_test.ts`

> Per contract §"Recommendation-only guardrail": the charge-time guardrail cannot wait for the full AnalysisResult. Validate only the recommendation payload.

**Step 1: Failing test**

```ts
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { validateRecommendationEvent } from "./stream_recommendation_guardrail.ts";

Deno.test("rejects empty message", () => {
  const r = validateRecommendationEvent({ type:"analysis.recommendation", selectedStyle:"resonate", message:"  ", reason:"x", quotedContext:"y" });
  assertEquals(r.ok, false);
  assertEquals(r.code, "STREAM_MALFORMED_RECOMMENDATION");
});

Deno.test("rejects invalid style", () => {
  const r = validateRecommendationEvent({ type:"analysis.recommendation", selectedStyle:"flirty", message:"嗨", reason:"x", quotedContext:"y" });
  assertEquals(r.ok, false);
});

Deno.test("accepts a valid recommendation", () => {
  const r = validateRecommendationEvent({ type:"analysis.recommendation", selectedStyle:"resonate", message:"我懂，你最近很忙，慢慢來就好。", reason:"降低壓力", quotedContext:"我最近很累" });
  assert(r.ok);
  assertEquals(r.selectedStyle, "resonate");
});
```

**Step 2–4:** Run fail → implement → run pass.

```ts
import { STREAM_STYLES } from "./stream_events.ts";
import { checkAiOutput } from "./guardrails.ts"; // reuse existing safety checks where applicable

export type RecoValidation =
  | { ok: true; selectedStyle: string; message: string }
  | { ok: false; code: "STREAM_MALFORMED_RECOMMENDATION" | "STREAM_UNSAFE_RECOMMENDATION" };

export function validateRecommendationEvent(ev: Record<string, unknown>): RecoValidation {
  const style = String(ev.selectedStyle ?? "");
  const message = String(ev.message ?? "").trim();
  if (!message) return { ok: false, code: "STREAM_MALFORMED_RECOMMENDATION" };
  if (!STREAM_STYLES.has(style as never)) return { ok: false, code: "STREAM_MALFORMED_RECOMMENDATION" };
  // Reuse existing prompt-injection / unsafe-instruction screening on the single string.
  // If existing guardrails operate on the full result, extract the minimal string check here.
  if (looksUnsafe(message)) return { ok: false, code: "STREAM_UNSAFE_RECOMMENDATION" };
  return { ok: true, selectedStyle: style, message };
}

function looksUnsafe(_message: string): boolean {
  // TODO during impl: port the minimal subset of server_guardrails.ts that
  // applies to a single outbound message (no harassment/threat/boundary-cross,
  // no instruction leakage). Keep it conservative.
  return false;
}
```

> During implementation, READ `server_guardrails.ts` and `guardrails.ts` and port the minimal single-string checks; do not duplicate the full-result validator. If that proves non-trivial, raise it as a checkpoint — it is security-relevant.

**Step 5: Commit**
```bash
git add supabase/functions/analyze-chat/stream_recommendation_guardrail*.ts
git commit -m "feat(stream): recommendation-only guardrail（扣費前驗證）"
```

### Task 2.3: The reframer — deltas → ordered events + legacy assembly

**Files:**
- Create: `supabase/functions/analyze-chat/reframer.ts`
- Test: `supabase/functions/analyze-chat/reframer_test.ts`

**Design contract for the reframer:**
- Input: repeated `pushText(chunk: string)` calls (raw Claude text deltas), then `end()`.
- It maintains a text buffer, splits on `\n`, and parses complete lines via `parseEventLine`.
- It enforces contract order: it will NOT emit `analysis.recommendation` to the client until the charge callback resolves. Other events that arrive before their slot are buffered and released in contract order.
- When a valid `analysis.recommendation` line is parsed, it calls the injected `onRecommendation(reco)` async callback (which does guardrail+charge in Phase 4). Only if that resolves `{ charged: true }` does the recommendation event get emitted; otherwise an `analysis.error` is emitted and the stream ends.
- It accumulates all events into a legacy `AnalysisResult` assembler; on `end()` (or on `analysis.done`) it emits a final `analysis.done` with `finalResult`.
- Output: an async generator / callback `emit(event)` the caller pipes to the NDJSON ReadableStream.

**Step 1: Failing tests (representative subset — write all of these)**

```ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { createReframer } from "./reframer.ts";

function collect() {
  const out: any[] = [];
  return { out, emit: (e: any) => { out.push(e); } };
}

Deno.test("emits decision before recommendation; charges before emitting recommendation", async () => {
  const { out, emit } = collect();
  const calls: string[] = [];
  const r = createReframer({
    emit,
    onRecommendation: async (reco) => { calls.push("charge:" + reco.selectedStyle); return { charged: true }; },
  });
  r.pushText('{"type":"analysis.decision","selectedStyle":"resonate","nextStepTitle":"t","nextStepBody":"b","doThis":"d","avoidThis":"a","confidence":"high"}\n');
  r.pushText('{"type":"analysis.recommendation","selectedStyle":"resonate","message":"我懂","reason":"r","quotedContext":"q"}\n');
  await r.flush();
  const types = out.map((e) => e.type);
  // decision emitted before recommendation
  assertEquals(types.indexOf("analysis.decision") < types.indexOf("analysis.recommendation"), true);
  // charge happened before recommendation was emitted
  assertEquals(calls, ["charge:resonate"]);
});

Deno.test("does NOT emit recommendation when charge fails; emits analysis.error", async () => {
  const { out, emit } = collect();
  const r = createReframer({
    emit,
    onRecommendation: async () => ({ charged: false, code: "QUOTA_EXHAUSTED" }),
  });
  r.pushText('{"type":"analysis.recommendation","selectedStyle":"resonate","message":"嗨","reason":"r","quotedContext":"q"}\n');
  await r.flush();
  const types = out.map((e) => e.type);
  assertEquals(types.includes("analysis.recommendation"), false);
  assertEquals(out.at(-1).type, "analysis.error");
  assertEquals(out.at(-1).code, "QUOTA_EXHAUSTED");
});

Deno.test("malformed recommendation does not charge", async () => {
  const { out, emit } = collect();
  let charged = false;
  const r = createReframer({ emit, onRecommendation: async () => { charged = true; return { charged: true }; } });
  r.pushText('{"type":"analysis.recommendation","selectedStyle":"resonate","message":"   ","reason":"r","quotedContext":"q"}\n');
  await r.flush();
  assertEquals(charged, false);
});

Deno.test("partial line split across chunks is parsed once complete", async () => {
  const { out, emit } = collect();
  const r = createReframer({ emit, onRecommendation: async () => ({ charged: true }) });
  r.pushText('{"type":"analysis.progress","step":"read_context",');
  r.pushText('"message":"讀脈絡","ordinal":1,"total":7}\n');
  await r.flush();
  assertEquals(out.some((e) => e.type === "analysis.progress"), true);
});

Deno.test("assembles legacy AnalysisResult into analysis.done", async () => {
  const { out, emit } = collect();
  const r = createReframer({ emit, onRecommendation: async () => ({ charged: true }) });
  r.pushText('{"type":"analysis.recommendation","selectedStyle":"resonate","message":"我懂","reason":"r","quotedContext":"q"}\n');
  r.pushText('{"type":"analysis.reply_option","style":"resonate","isSelected":true,"message":"我懂","approach":"共鳴","reason":"r"}\n');
  r.pushText('{"type":"analysis.done"}\n');
  await r.flush();
  const done = out.find((e) => e.type === "analysis.done");
  assertEquals(typeof done.finalResult, "object");
  assertEquals(done.finalResult.finalRecommendation.pick, "resonate");
});
```

**Step 2: Run fail.** `~/.deno/bin/deno test supabase/functions/analyze-chat/reframer_test.ts`

**Step 3: Implement `reframer.ts`** (skeleton — fill to satisfy tests)

```ts
import { parseEventLine, StreamEvent } from "./stream_events.ts";
import { validateRecommendationEvent } from "./stream_recommendation_guardrail.ts";

export interface ChargeResult { charged: boolean; code?: string; }
export interface ReframerOpts {
  emit: (event: StreamEvent) => void;
  onRecommendation: (reco: { selectedStyle: string; message: string; raw: StreamEvent }) => Promise<ChargeResult>;
}

export function createReframer(opts: ReframerOpts) {
  let buffer = "";
  let pending: Promise<void> = Promise.resolve();
  const assembler = createLegacyAssembler();

  async function handleLine(line: string) {
    const ev = parseEventLine(line);
    if (!ev) return;

    if (ev.type === "analysis.recommendation") {
      const v = validateRecommendationEvent(ev);
      if (!v.ok) { opts.emit({ type: "analysis.error", code: v.code, message: "推薦回覆格式異常", recoverable: true }); return; }
      const charge = await opts.onRecommendation({ selectedStyle: v.selectedStyle, message: v.message, raw: ev });
      if (!charge.charged) { opts.emit({ type: "analysis.error", code: charge.code ?? "CHARGE_FAILED_RETRYABLE", message: "扣額度失敗", recoverable: true }); return; }
      assembler.absorb(ev);
      opts.emit(ev);
      return;
    }

    if (ev.type === "analysis.done") {
      opts.emit({ type: "analysis.done", finalResult: assembler.build() });
      return;
    }

    assembler.absorb(ev);
    opts.emit(ev); // decision/progress/reply_option/metrics/coach_hint/report_section pass through in arrival order
  }

  return {
    pushText(chunk: string) {
      buffer += chunk;
      let idx: number;
      while ((idx = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 1);
        pending = pending.then(() => handleLine(line));
      }
    },
    async flush() {
      if (buffer.trim()) { const last = buffer; buffer = ""; pending = pending.then(() => handleLine(last)); }
      await pending;
      // If Claude never sent analysis.done but produced data, still close out.
    },
  };
}

// Maps streamed events into the legacy AnalysisResult shape (analysis_result.dart consumes this).
function createLegacyAssembler() {
  const result: Record<string, unknown> = {};
  return {
    absorb(ev: StreamEvent) {
      switch (ev.type) {
        case "analysis.recommendation":
          result.finalRecommendation = {
            pick: ev.selectedStyle, content: ev.message, reason: ev.reason, psychology: ev["reason"],
          };
          break;
        case "analysis.reply_option": {
          const opts2 = (result.replyOptions ??= {}) as Record<string, unknown>;
          (opts2 as Record<string, unknown>)[String(ev.style)] = { approach: ev.approach, messages: [{ reply: ev.message, reason: ev.reason, label: "建議訊息", sourceMessage: "" }] };
          break;
        }
        case "analysis.metrics":
          result.enthusiasm = ev.enthusiasm; result.dimensions = ev.dimensions; result.topicDepth = ev.topicDepth;
          break;
        case "analysis.coach_hint":
          result.coachActionHint = ev;
          break;
        case "analysis.report_section":
          (result as Record<string, unknown>)[String(ev.section)] = ev.payload;
          break;
      }
    },
    build() { return result; },
  };
}
```

> During impl: the assembler MUST produce a shape that survives the existing `postProcessAnalysisResult` + `AnalysisResult.fromJson` (Flutter). READ `analysis_result.dart:58–148` and `post_process.ts` and align field names exactly. Add a test asserting `postProcessAnalysisResult(assembler.build(), …)` returns non-empty replies/finalRecommendation.

**Step 4: Run pass. Step 5: Commit**
```bash
git add supabase/functions/analyze-chat/reframer*.ts
git commit -m "feat(stream): reframer — Claude 文字流轉有序事件 + 組裝 legacy AnalysisResult"
```

---

## Phase 3 — Streaming Claude call

### Task 3.1: `callClaudeStreaming`

**Files:**
- Create: `supabase/functions/analyze-chat/streaming_fallback.ts`
- Test: `supabase/functions/analyze-chat/streaming_fallback_test.ts`

> Mirrors `fallback.ts` headers/caching but sets `stream: true` and yields text deltas. Anthropic streams SSE; parse `content_block_delta` → `delta.text`. Keep model fallback OFF for v1 (a mid-stream model swap is out of scope); on stream error before any recommendation, the index.ts branch falls back to the non-streaming path.

**Step 1: Failing test** — feed a fake SSE body via a stubbed `fetch`/Response and assert deltas are yielded in order; assert non-text events are ignored.

```ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseAnthropicSse } from "./streaming_fallback.ts";

Deno.test("parseAnthropicSse extracts text deltas in order", async () => {
  const sse = [
    'event: content_block_delta',
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"{\\"type\\":\\"analysis.progress\\""}}',
    '',
    'event: content_block_delta',
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":",\\"ordinal\\":1}\\n"}}',
    '',
    'event: message_stop',
    'data: {"type":"message_stop"}',
    '',
  ].join("\n");
  const chunks: string[] = [];
  for await (const t of parseAnthropicSse(streamFromString(sse))) chunks.push(t);
  assertEquals(chunks.join(""), '{"type":"analysis.progress","ordinal":1}\n');
});
```
(Provide a `streamFromString` helper in the test.)

**Step 2–4:** implement `parseAnthropicSse(readable): AsyncGenerator<string>` + `callClaudeStreaming(request, apiKey, opts): { textStream, model }`. Headers identical to `fallback.ts:111` (`x-api-key`, `anthropic-version: 2023-06-01`, `anthropic-beta: prompt-caching-2024-07-31`), body adds `stream: true`. Reuse `buildCachedSystemPrompt`.

**Step 5: Commit**
```bash
git add supabase/functions/analyze-chat/streaming_fallback*.ts
git commit -m "feat(stream): Anthropic streaming 呼叫 + SSE text_delta 解析"
```

---

## Phase 4 — Wire the `responseMode: "stream"` branch into index.ts

### Task 4.1: NDJSON response helper + whitelist gate

**Files:**
- Modify: `supabase/functions/analyze-chat/request_mode.ts` (add `"stream"` to `ResponseMode`)
- Create: `supabase/functions/analyze-chat/stream_gate.ts` (+ test)
- Modify: `supabase/functions/analyze-chat/index.ts` (response helper)

**Step 1 (gate, TDD):** `isStreamingAllowed(email: string, tier: string, flagOn: boolean): boolean` — true only for whitelist emails (`vibesync.test@gmail.com`, Eric, Bruce — read from an env var `STREAM_WHITELIST` comma-list, with the test account hard-allowed) AND `flagOn`. Test the allow/deny matrix.

```ts
// stream_gate.ts
export function isStreamingAllowed(email: string | null, whitelistCsv: string | null): boolean {
  if (!email) return false;
  const hard = new Set(["vibesync.test@gmail.com"]);
  const list = new Set((whitelistCsv ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean));
  const e = email.toLowerCase();
  return hard.has(e) || list.has(e);
}
```

**Step 2:** Add NDJSON streaming response in index.ts:
```ts
function ndjsonStreamResponse(start: (emit: (e: unknown) => void, close: () => void) => void): Response {
  const stream = new ReadableStream({
    start(controller) {
      const enc = new TextEncoder();
      const emit = (e: unknown) => controller.enqueue(enc.encode(JSON.stringify(e) + "\n"));
      const close = () => controller.close();
      start(emit, close);
    },
  });
  return new Response(stream, {
    status: 200,
    headers: { "Content-Type": "application/x-ndjson", ...corsHeaders },
  });
}
```

**Step 3: Commit** gate + helper.

### Task 4.2: The stream branch

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts` (new branch, ~after the quick/full/legacy dispatch around line 5420)

**Behavior (assemble from earlier phases):**
1. After auth + input validation + prompt build (all reused), check `responseMode === "stream"`.
2. Gate: if `!isStreamingAllowed(user.email, Deno.env.get("STREAM_WHITELIST"))` → DO NOT stream; fall through to the existing stable full/legacy path (rollback). (Client also gates, but defend server-side.)
3. Compute `conversationHash = hashConversation(...)` (reuse `conversation_hash.ts`).
4. Insert a `pending` row into `analysis_stream_runs` (status='pending', conversation_hash, user_id, request_context). Get `runId`.
5. Open `ndjsonStreamResponse`. Inside:
   - emit `analysis.started` `{ runId, conversationHash, etaSeconds: 18 }`.
   - emit an initial `analysis.progress` (`正在讀對話脈絡...`).
   - call `callClaudeStreaming(... STREAM_SYSTEM_PROMPT ...)`.
   - build `createReframer({ emit, onRecommendation })` where `onRecommendation` runs:
     - `validateRecommendationEvent` already passed inside reframer; here call `charge_stream_analysis_run` RPC with `(runId, user.id, conversationHash, recommendationJson, selectedStyle, messageCount, shouldChargeQuota)`.
     - map RPC errors: `increment_usage` quota raise → `{ charged:false, code:"QUOTA_EXHAUSTED" }`; other → `{ charged:false, code:"CHARGE_FAILED_RETRYABLE" }`.
   - `for await (const textChunk of claude.textStream) reframer.pushText(textChunk)`.
   - `await reframer.flush()`.
   - On `analysis.done`, UPDATE `analysis_stream_runs` set status='done', final_result_json. Then `logAiCall(...)` (reuse) with `responseMode:"stream"`.
   - Wrap the whole thing in try/catch: a stream error BEFORE recommendation charged → emit `analysis.error {recoverable:true}`, set status='failed', last_error_code; nothing charged. A stream error AFTER charge → emit `analysis.error` but keep recommendation_json (resume path).
   - 30s watchdog: if no `analysis.done` within 30s, emit `analysis.error {code:"STREAM_TIMEOUT", recoverable:true}` and close (charge state already persisted authoritatively).
6. Drift: after `done`, compare `final_result_json.finalRecommendation` style vs `selected_style`; if mismatch, log `streaming_recommendation_drift` (warn-only v1), keep the charged recommendation.

**Tests:** index.ts has `index_test.ts`. Add a focused static/integration test `stream_branch_test.ts` that:
- asserts `responseMode:"stream"` for a non-whitelist user does NOT take the stream path (greppable behavior or a small dependency-injected handler test).
- asserts the branch calls `charge_stream_analysis_run` (not `create_charged_analysis_run`).
Given index.ts size, prefer extracting the branch body into a testable `handleStreamRequest(deps)` module (`stream_handler.ts`) with injected `claude`, `db`, `emit` so it can be unit-tested without a live Edge runtime. THIS IS THE PREFERRED APPROACH — do not bury logic in the 6000-line file.

**Files (preferred):**
- Create: `supabase/functions/analyze-chat/stream_handler.ts` (+ `stream_handler_test.ts`)
- Modify: `index.ts` to call `handleStreamRequest({...deps})` in the new branch.

**Commit** per sub-step (gate, helper, handler, wiring) — keep commits small.

---

## Phase 5 — Streaming system prompt

### Task 5.1: `STREAM_SYSTEM_PROMPT`

**Files:**
- Create: `supabase/functions/analyze-chat/stream_prompt.ts`
- Test: `supabase/functions/analyze-chat/stream_prompt_test.ts`

**Content requirements (per contract §"Claude 事件輸出格式" and §"Output Order"):**
- Reuse the analytical *reasoning* of `SYSTEM_PROMPT` (situation classification, emotion/pressure/boundary, five-style selection, stage, recommended reply, coach action, radar, deeper report).
- CHANGE the output format: emit JSONL — one complete minified JSON object per line, newline as the only separator, no pretty-print, no real newlines inside strings (use `\n`).
- Enforce emission ORDER: `analysis.progress` ×2–4 → `analysis.decision` → `analysis.recommendation` → `analysis.reply_option`(selected first, then other 4) → `analysis.metrics` → `analysis.coach_hint` → `analysis.report_section`× → `analysis.done`.
- The `analysis.recommendation` MUST be the official reply (same reasoning path), declaring `selectedStyle`.

**Test:** assert the prompt string contains the JSONL rules, the ordered event list, the five styles, and the "one object per line / minified / no real newlines" instructions; assert length is reasonable (< ~12000 chars).

**Commit:** `feat(stream): STREAM_SYSTEM_PROMPT — JSONL 有序事件輸出契約`.

> RISK NOTE: reliable ordered JSONL from the model is the single biggest quality risk. During dogfood, log raw lines + any `parseEventLine` failures (telemetry `stream_malformed_line`) so we can tighten the prompt. The reframer already tolerates blank/partial lines; a malformed *recommendation* must never charge.

---

## Phase 6 — Flutter streaming transport

### Task 6.1: `StreamingAnalysisService`

**Files:**
- Create: `lib/features/analysis/data/services/streaming_analysis_service.dart`
- Test: `test/features/analysis/streaming_analysis_service_test.dart`

**Proven transport pattern (from the spike — reuse exactly):**
```dart
final req = http.Request('POST', Uri.parse('$supabaseUrl/functions/v1/analyze-chat'))
  ..headers['Authorization'] = 'Bearer $accessToken'
  ..headers['apikey'] = anonKey
  ..headers['Content-Type'] = 'application/json'
  ..headers['Accept'] = 'application/x-ndjson'
  ..body = jsonEncode({ 'responseMode': 'stream', 'messages': msgs, 'context': ctx });

final resp = await client.send(req);                 // NOT .post() — must stream
final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
await for (final line in lines) {
  if (line.trim().isEmpty) continue;
  yield AnalysisStreamEvent.fromJson(jsonDecode(line));
}
```
- Return `Stream<AnalysisStreamEvent>`.
- 30s timeout on the whole stream (`.timeout(...)`) → emit a synthetic timeout event the notifier maps to retry UX.
- On non-200 (e.g. gate rejected the stream and server returned JSON), surface a `fallbackRequired` signal so the caller uses the existing `AnalysisService`.

**Test:** feed a fake `http.Client` (mock `send`) returning a canned NDJSON byte stream; assert events decode in order, blank lines skipped, partial-by-byte chunks reassemble (LineSplitter handles this).

**Commit:** `feat(flutter): 串流分析 transport（http send + NDJSON LineSplitter）`.

### Task 6.2: `AnalysisStreamEvent` model

**Files:**
- Create: `lib/features/analysis/domain/entities/analysis_stream_event.dart` (+ test)
- Sealed/union types for the event kinds; `fromJson` switch on `type`.

**Commit.**

---

## Phase 7 — Flutter streaming notifier (state machine)

### Task 7.1: `StreamingAnalyzeNotifier`

**Files:**
- Create: `lib/features/analysis/data/notifiers/streaming_analyze_notifier.dart` (+ test)

**State machine (per contract §"Frontend Shape"):**
`idle → connecting → decisionLoading → decisionReady → recommendationReady → reportStreaming → done`
plus `failedBeforeRecommendation` (no charge, retry whole) and `failedAfterRecommendation` (charged, keep recommendation, retry remainder).

- `start()` subscribes to `StreamingAnalysisService.analyze(...)`.
- Map events → state: `analysis.started`→connecting+runId; `analysis.progress`→update progress copy; `analysis.decision`→decisionReady (本回合怎麼接); `analysis.recommendation`→recommendationReady (official AI 推薦回覆, enable copy); `analysis.reply_option`/`metrics`/`coach_hint`/`report_section`→reportStreaming accumulate; `analysis.done`→done (build full `AnalysisResult` from `finalResult`); `analysis.error`→failedBefore/AfterRecommendation by whether recommendation already arrived.
- If service signals `fallbackRequired` (non-whitelist / pre-stream failure) → delegate to existing `AnalysisService` and present the legacy result (rollback path).
- `retry()`: if charged (recommendation seen) → re-request stream with same `runId` (server resends stored recommendation, re-streams remainder, no recharge). Else → fresh run.

**Tests:** drive the notifier with a fake event stream; assert state transitions and the no-charge-on-early-failure / keep-recommendation-on-late-failure behaviors. Assert copy button only enabled at/after `recommendationReady`.

**Commit** per logical chunk.

---

## Phase 8 — Flutter UI

### Task 8.1: Streaming analysis surface

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart`
- Modify/Create: progress + section widgets as needed.

**Requirements (contract §"UI Contract" + user points 3,4,5,7,8,9):**
- Above-the-fold order: conversation preview → progress/status → 本回合怎麼接 → AI 推薦回覆 → report sections as they arrive.
- During streaming: do NOT show the screenshot upload block as the waiting area; do NOT show copy buttons for unfinished content; show stable "完整分析還在整理中" + named placeholders for not-yet-arrived sections.
- REMOVE the "AI 推薦回覆速覽" quick-preview surface (point 8) — the only official 推薦回覆 is the streamed `analysis.recommendation`.
- Progress copy set: `正在讀對話脈絡...` / `正在判斷這回合怎麼接...` / `已抓到方向，正在整理正式回覆...` / `正式回覆已完成，完整分析繼續整理中...` / `五種回覆風格整理中...` / `互動雷達整理中...` / `深層策略整理中...`.
- 30s timeout / error → clear, human retry UX (point 9). Distinguish "retry whole" vs "retry remaining report (recommendation kept)".
- Gate: only whitelist users hit the stream path; others see the existing screen unchanged.

**Verification (manual, since UI):** `flutter analyze` clean; widget test for the state→widget mapping where feasible; the real feel is verified in dogfood (gate #5).

**Commit** per logical chunk.

---

## Phase 9 — Whitelist plumbing (client + server) & flag

### Task 9.1: Server env + client capability

**Files:**
- Server: set `STREAM_WHITELIST` env in Supabase (Eric/Bruce emails); `vibesync.test@gmail.com` hard-allowed in `stream_gate.ts`.
- Client: a capability check — the client requests `responseMode:"stream"` only when it knows it's enabled. Options: (a) a lightweight `/me` capability flag, or (b) the client always tries stream and on the gate's JSON "not allowed" response falls back. Prefer (b) for v1 simplicity: try stream; if first byte is a JSON error or 4xx, fall back to `AnalysisService`. Document the choice.

**Commit:** `feat(stream): 白名單 gate 串接（server env + client fallback）`.

---

## Phase 10 — Verification & dogfood (redefined Gate #5)

### Task 10.1: Backend test sweep
Run all analyze-chat Deno tests:
```bash
~/.deno/bin/deno test supabase/functions/analyze-chat/ --allow-read
```
Expected: all green, including new stream_* and reframer tests.

### Task 10.2: Flutter analyze + tests
```bash
flutter analyze
flutter test test/features/analysis/
```
Expected: no issues; streaming service/notifier tests green.

### Task 10.3: Codex read-only review (REQUIRED before "safe to dogfood")
- Scope: the streaming feature range only (Phase 0 base .. HEAD). State the exact range.
- High-risk dimensions to flag for Codex: charge-before-emit atomicity & idempotency (no double charge, no free core value), gate cannot be bypassed, malformed/partial JSONL never charges, drift handling, 30s timeout charge-state correctness, no regression to quick/full/legacy.
- Record evidence (job id / verdict / queue update). Do NOT claim APPROVED from memory.

### Task 10.4: Deploy + TestFlight dogfood build (whitelist only)
- Deploy `analyze-chat` (this is high-risk; per project rule analyze-chat deploy uses `--no-verify-jwt` only where already established — confirm current deploy command in CLAUDE.md/docs before deploying). Apply the two migrations.
- Cut a TestFlight build. Verify on a REAL iPhone (Eric):
  - events arrive incrementally (NOT all at ~end);
  - progress ~1–3s, 本回合怎麼接 3–8s, AI 推薦回覆 6–12s;
  - copy works on the official recommendation;
  - 30s failure shows clear retry;
  - non-whitelist account still uses the stable path.
- If iOS BUFFERS or milestones miss → STOP, do not submit, return to architecture (SSE variant / chunked / polling). Streaming is not done.

### Task 10.5: Closeout
- If a durable decision/architecture emerged, update `docs/decisions.md`; update `docs/snapshot.md` only if the project stage changed. Otherwise git history + this plan suffice (per shared-agent-rules closeout matrix).
- optimize_message/草稿潤飾 remains a next-stage TODO (already-written fix stranded in commit `72d7ff8`, off main; revisit after streaming is stable).

---

## Risk register (watch during execution)

1. **Reliable ordered JSONL from Claude** — biggest quality risk. Telemetry on malformed lines; tighten prompt; reframer tolerates partials and never charges on a bad recommendation.
2. **iOS transport buffering** — unverified until dogfood (accepted risk, gate #5). Keep fallback path intact.
3. **Charge atomicity** — `charge_stream_analysis_run` must be the ONLY charge point in the stream branch; idempotent on `charged_at`. Codex must verify.
4. **Legacy assembly drift** — streamed events must assemble into a shape the existing `postProcessAnalysisResult` + `AnalysisResult.fromJson` accept, or report cards break.
5. **Don't regress quick/full/legacy** — the stream branch is additive and gated; existing paths must be untouched and remain the fallback.
