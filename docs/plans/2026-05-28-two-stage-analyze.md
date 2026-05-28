# Two-Stage Analyze Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
> **For Codex review:** This is a high-risk change (touches quota, auth, AI prompts). Required review focus: (1) quota double-charge, (2) full-mode auth bypass, (3) quick/full result contradiction, (4) RLS/policy on `analysis_runs`. See §Codex Review Checklist at the bottom.

**Status:** Draft v2 — Eric 已 ack 方向，下達 11 點修正（見 §Plan Changelog v2）；尚待 Codex 高風險 review。

## Plan Changelog

**v2 (2026-05-28, Eric DC feedback)**
1. I7 改為「Full 只能 confirm / supplement / lightly polish quick，**不能換方向**」；D1 同步註明 Haiku quick 就是使用者長期看到的建議
2. Full retry：retry_count 在 Claude call **之前**原子預留；失敗的 Claude call 也算一次（避免無限燒 token）
3. Migration cleanup 函式去掉 `RETURNING ... INTO`，改純 `GET DIAGNOSTICS ROW_COUNT`
4. `analysis_runs` 加 explicit `GRANT ... TO service_role` + `REVOKE ALL ... FROM anon, authenticated`（Supabase 2026-10-30 新 Data API 政策）
5. `MISSING_RUN_ID` 狀態碼 401 → 400（請求格式錯誤；401 留給 unauthenticated）
6. `hashConversation` 對所有 string 值跑 `normalize("NFC")`，加 2 個 Unicode 測試
7. Migration smoke test 去掉 `auth.uid()`（raw SQL 裡會是 NULL），改成從 `auth.users` 查 test user UUID
8. Codex checklist 對 quota double-charge 的條件改成「full branch 不得 call increment_usage」（不再說全 repo 限定 2 處）
9. UI skeleton 文案加 ETA 與 server 回傳 `estimatedFullSeconds`；client 顯示為 `eta-2 ~ eta+3` 區間（軟告知）
10. Task 4.3 CLAUDE.md 更新從 build 213 拿掉；改 follow-up PR 同步 CLAUDE.md + AGENTS.md + docs/shared-agent-rules.md
11. 新增 Full 失敗時 server 回傳 `retriesRemaining`，UI 顯示「可重試（剩 N 次）」

**Goal:** Cut perceived analyze latency from ~20s to 3-5s by splitting the existing single Claude call into a fast `quick` phase (above-the-fold summary) followed by a background `full` phase (cards, radar, deep psychology, 5-style replyOptions). One analyze action = one quota charge. Full retry on failure does not recharge.

**Architecture:**
1. **Backend** — `analyze-chat` learns a new `responseMode: "quick" | "full" | "legacy"` parameter. `quick` runs a slim system prompt with ~300 max_tokens and creates a server-owned `analysis_runs` row (charged=true). `full` requires `analysisRunId`, validates (user, conversation hash, not expired, charged), injects the quick result as an anchor into the full prompt, and does NOT recharge. `legacy` keeps build-211 behaviour for backwards compatibility (delete after build 213 ships).
2. **Frontend** — `_runAnalysis` becomes a two-phase orchestrator. Phase 1 awaits quick → renders summary card. Phase 2 fires-and-awaits full → merges into existing `AnalysisResult` notifiers. Full failure preserves quick and surfaces a retry CTA that reuses the same `analysisRunId`.
3. **Storage** — new Postgres table `analysis_runs` with conversation hash, cached quick payload, expires_at, retry_count. Cleaned up by pg_cron daily.

**Tech Stack:** Supabase Postgres + Edge Function (Deno), Flutter/Dart client, Anthropic Claude Sonnet 4 (full) + Haiku 4.5 (quick), Riverpod for client state.

---

## Invariants (must remain true at every step; all have a dedicated test)

| # | Invariant | Where it's enforced |
|---|---|---|
| I1 | A user is charged at most **once** per analyze session, regardless of full success/failure/retries. | `increment_usage` RPC only called on `quick` success. `full` path has `// NO RPC` comment + lint rule via grep guard. |
| I2 | `full` requests without a valid `analysisRunId` → **400** `MISSING_RUN_ID` (request-format error; 401 reserved for unauthenticated). | First `if` in `full` handler before any prompt building. |
| I3 | `full` requests with a `runId` owned by another user → 403 `RUN_FORBIDDEN`. | RLS on `analysis_runs` + explicit `user_id` equality check in handler. |
| I4 | `full` requests for expired runs (> 30 min old) → 410 `RUN_EXPIRED`. | `expires_at < now()` check. |
| I5 | `full` requests where current conversation hash ≠ stored hash → 409 `RUN_CONVERSATION_MISMATCH`. | SHA-256 of NFC-normalized canonicalized messages compared. |
| I6 | `full` cannot be retried unbounded — max 3 attempts per run, **counting failed Claude calls**. | Atomic `UPDATE analysis_runs SET retry_count = retry_count + 1 WHERE id = $1 AND retry_count < 3 RETURNING *` **reserved BEFORE the Claude call**. If 0 rows returned → 429 `RUN_RETRY_EXHAUSTED`. A failed Claude call still burns one attempt — by design, so a misbehaving client can't loop forever. |
| I7 | `full` is **confirm/supplement/light-polish only** of `quick`. `full` MUST NOT switch direction (different topic, different intent, different addressed message). It MUST keep `quickResult.recommendedReply` and `quickResult.nextStep` as authoritative anchor and only enrich the surrounding structured fields (psychology, 5 styles as alternatives, radar, healthCheck, strategy). The user must never see "建議 A 變建議 B" in 10s. | Anchor injection in prompt (strict language; see `buildFullPromptAnchor`). Drift detector logs `full_anchor_drift_detected` when reply text overlap < 80% — warn-only in v1, may become hard reject in v2 if drift rate is high. |
| I8 | If `quick` fails (timeout / Claude error), NO row is inserted in `analysis_runs` and NO quota charged. | `increment_usage` only after both Claude success AND insert success. |
| I9 | `quick` and `full` outputs both pass server guardrails (existing `server_guardrails.ts`). | Run guardrails on both response paths. |
| I10 | Old clients (build 211 and earlier) sending requests without `responseMode` fall through `legacy` path and behave as today. | `responseMode ?? "legacy"` default. |

---

## Open Decisions (Eric to sign off before implementation starts)

| # | Decision | Default if no answer | Why it matters |
|---|---|---|---|
| D1 | Quick uses Haiku 4.5 or Sonnet 4? | Haiku 4.5 (~3-5s @ 300 tokens output) | Quality risk; Haiku may degrade reply taste. **NOTE (per Eric 2026-05-28):** Full does NOT "overwrite" the quick recommendation — Full only confirms/supplements/lightly polishes it (see I7). So Haiku's quick output IS the recommendation the user sees long-term. If Haiku quality is unacceptable, escalate to Sonnet for quick before shipping. |
| D2 | Quick `max_tokens` ceiling? | 400 | Haiku 4.5 at ~250 tps + 400 tokens ≈ 1.6s pure output + ~1s overhead = 2.5-3s p50. |
| D3 | Conversation hash includes `userDraft` and `partnerSummary`? | YES (full canonical context, not just messages) | Otherwise user could edit draft between quick and full and trick server into anchoring on stale context. |
| D4 | `analysis_runs` TTL? | 30 min | Long enough for slow UX, short enough to bound DB size. |
| D5 | Where does `nextStep` come from in quick? | Reuse existing `coachActionHint.catchablePoint + microMove` style. Single sentence. | UI continuity with current "本回合怎麼接" pattern. |
| D6 | Quick failure UX? | Show generic error + "再試一次" button. Do NOT auto-fallback to legacy path. | Auto-fallback would hide perf regressions and complicate quota logic. |
| D7 | Telemetry — log quick & full as separate `ai_logs` rows or one merged? | Two rows linked by `analysisRunId` | Easier to debug; can JOIN for cost analysis. |

If Eric doesn't override any of D1-D7, defaults apply.

---

## Files Touched (overview)

**Create:**
- `supabase/migrations/20260528_analysis_runs.sql` — table + RLS + cleanup function
- `supabase/functions/analyze-chat/analysis_run_store.ts` — DB helpers (insert/get/touch)
- `supabase/functions/analyze-chat/analysis_run_store_test.ts` — Deno tests
- `supabase/functions/analyze-chat/quick_prompt.ts` — slim system prompt for quick mode
- `supabase/functions/analyze-chat/quick_prompt_test.ts` — assertions on prompt shape
- `supabase/functions/analyze-chat/conversation_hash.ts` — canonicalization + SHA-256
- `supabase/functions/analyze-chat/conversation_hash_test.ts` — Deno tests
- `lib/features/analysis/domain/entities/quick_analysis_result.dart` — new entity
- `lib/features/analysis/data/services/two_stage_analyze_orchestrator.dart` — client orchestrator
- `test/unit/features/analysis/two_stage_analyze_orchestrator_test.dart` — orchestrator tests
- `test/widget/screens/analysis_screen_two_stage_test.dart` — UI state tests

**Modify:**
- `supabase/functions/analyze-chat/index.ts:4432-4510` — parse `responseMode` and `analysisRunId`
- `supabase/functions/analyze-chat/index.ts:5545-5614` — split handler into `runQuick()` and `runFull()` branches
- `supabase/functions/analyze-chat/index.ts:5685-5762` — wrap Claude call with mode-aware prompt and max_tokens
- `lib/features/analysis/data/services/analysis_service.dart:422-540` — add `analyzeQuick()` + `analyzeFull()` methods; keep `analyzeConversation()` as legacy fallback
- `lib/features/analysis/presentation/screens/analysis_screen.dart:2548-2700` — replace `_runAnalysis` body with orchestrator call + new state fields
- `lib/features/analysis/domain/entities/analysis_result.dart:58-148` — add `static AnalysisResult mergeWithQuick(QuickAnalysisResult quick, AnalysisResult full)` helper

---

## Phase Sequence

| Phase | Scope | Goal | Reviewed by |
|---|---|---|---|
| Phase 0 | Schema + storage + hash utility | DB row safely created/read; hash stable across calls | Codex |
| Phase 1 | Backend `quick` mode | quick returns < 5s, charges once, creates run | Codex |
| Phase 2 | Backend `full` mode | full validates auth/hash/expiry/retry, doesn't recharge, anchors on quick | Codex (highest risk) |
| Phase 3 | Frontend orchestrator + UI | UI shows quick at 3-5s, full merges later, retry works | Codex (UI flow only) |
| Phase 4 | Hardening | pg_cron cleanup, telemetry, deprecation notice for legacy | Codex |

**Each phase commits independently.** Codex review between Phase 2 → Phase 3 is mandatory before client work starts.

---

## Phase 0: Schema + Storage + Hash Utility

### Task 0.1: Create `analysis_runs` migration

**Files:**
- Create: `supabase/migrations/20260528_analysis_runs.sql`

**Step 1: Write the migration**

```sql
-- Two-stage analyze: server-owned run record linking quick and full phases.
-- Goal: quota charged once on quick success; full validates against this row.
CREATE TABLE IF NOT EXISTS public.analysis_runs (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_hash TEXT      NOT NULL,
  charged         BOOLEAN     NOT NULL DEFAULT FALSE,
  quick_result    JSONB       NOT NULL,
  request_context JSONB,
  retry_count     INTEGER     NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 minutes'),
  consumed_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_analysis_runs_user_expires
  ON public.analysis_runs (user_id, expires_at);

ALTER TABLE public.analysis_runs ENABLE ROW LEVEL SECURITY;

-- service_role only; clients never read this table directly.
CREATE POLICY analysis_runs_service_role
  ON public.analysis_runs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Supabase 2026-10-30 後 public 新表的 Data API 預設不再自動 GRANT；
-- 必須明確聲明 service_role 可讀寫，且 anon / authenticated 完全沒權限。
GRANT SELECT, INSERT, UPDATE, DELETE ON public.analysis_runs TO service_role;
REVOKE ALL ON public.analysis_runs FROM anon, authenticated;

-- Cleanup function for pg_cron (Phase 4 wires the schedule).
CREATE OR REPLACE FUNCTION public.cleanup_expired_analysis_runs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted INTEGER;
BEGIN
  -- 不要用 DELETE ... RETURNING ... INTO（刪多筆會 too_many_rows）。
  -- GET DIAGNOSTICS ROW_COUNT 是 plpgsql 標準的批次計數方式。
  DELETE FROM public.analysis_runs
   WHERE expires_at < now() - interval '1 hour';
  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_runs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_analysis_runs() TO service_role;
```

**Step 2: Apply locally**

Run: `npx supabase db reset --linked` (or staging only if you don't want to wipe local).
Expected: migration applies clean, no errors.

**Step 3: Smoke test**

不要用 `auth.uid()`（在 raw SQL session 裡會是 NULL，違反 NOT NULL）。改成在已存在的 test user 上跑，或用 Edge Function 整合測試覆蓋（Task 1.3 已含）。手動驗證範例：

```bash
TEST_USER_ID=$(psql "$SUPABASE_DB_URL" -At -c \
  "SELECT id FROM auth.users WHERE email = 'vibesync.test@gmail.com' LIMIT 1;")

psql "$SUPABASE_DB_URL" <<SQL
INSERT INTO analysis_runs (user_id, conversation_hash, quick_result)
VALUES ('$TEST_USER_ID', 'smoke-test-hash', '{}'::jsonb);

SELECT id, charged, retry_count,
       expires_at > now() + interval '29 minutes' AS expires_at_ok
  FROM analysis_runs
 WHERE conversation_hash = 'smoke-test-hash';

DELETE FROM analysis_runs WHERE conversation_hash = 'smoke-test-hash';
SQL
```

Expected: 1 row, `charged = false`, `retry_count = 0`, `expires_at_ok = true`. 跑完務必 DELETE 清掉 smoke row。

**Step 4: Commit**

```bash
git add supabase/migrations/20260528_analysis_runs.sql
git commit -m "feat(analyze): add analysis_runs table for two-stage analyze"
```

---

### Task 0.2: Conversation hash utility (TDD)

**Files:**
- Create: `supabase/functions/analyze-chat/conversation_hash.ts`
- Create: `supabase/functions/analyze-chat/conversation_hash_test.ts`

**Step 1: Write failing test first**

```typescript
// conversation_hash_test.ts
import { assertEquals, assertNotEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { hashConversation } from "./conversation_hash.ts";

Deno.test("identical inputs produce identical hash", () => {
  const a = hashConversation({
    messages: [{ isFromMe: true, content: "hi" }],
    userDraft: "test",
    partnerSummary: "alice loves jazz",
    sessionContext: { meetingContext: "tinder" },
  });
  const b = hashConversation({
    messages: [{ isFromMe: true, content: "hi" }],
    userDraft: "test",
    partnerSummary: "alice loves jazz",
    sessionContext: { meetingContext: "tinder" },
  });
  assertEquals(a, b);
});

Deno.test("different userDraft produces different hash", () => {
  const a = hashConversation({ messages: [], userDraft: "v1" });
  const b = hashConversation({ messages: [], userDraft: "v2" });
  assertNotEquals(a, b);
});

Deno.test("key order does not affect hash", () => {
  // Canonicalization must sort keys before hashing.
  const a = hashConversation({ userDraft: "a", messages: [] });
  const b = hashConversation({ messages: [], userDraft: "a" });
  assertEquals(a, b);
});

Deno.test("hash is 64-char hex", async () => {
  const h = await hashConversation({ messages: [] });
  assertEquals(h.length, 64);
  assertEquals(/^[a-f0-9]{64}$/.test(h), true);
});

Deno.test("Unicode NFC vs NFD produce same hash", async () => {
  // 「練」 = U+7DF4 (NFC) vs U+7DF4 actually decomposes to itself, but
  // many CJK chars + combining marks (and accented Latin) do differ.
  // Example: "café" can be "café" (NFD) or "café" (NFC).
  const nfd = "café";  // c, a, f, e, combining acute
  const nfc = "café";    // c, a, f, é
  const a = await hashConversation({ messages: [], userDraft: nfd });
  const b = await hashConversation({ messages: [], userDraft: nfc });
  assertEquals(a, b);
});

Deno.test("CJK NFC normalization is idempotent for typical input", async () => {
  // Sanity: 同一段繁中重複呼叫不會因為 normalize 而發散
  const text = "她剛剛說「最近在追《絕命毒師》」";
  const a = await hashConversation({ messages: [], userDraft: text });
  const b = await hashConversation({ messages: [], userDraft: text });
  assertEquals(a, b);
});
```

**Step 2: Verify tests fail**

Run: `deno test supabase/functions/analyze-chat/conversation_hash_test.ts`
Expected: FAIL — module not found.

**Step 3: Implement minimal hash**

```typescript
// conversation_hash.ts
export interface HashInput {
  messages?: unknown;
  userDraft?: unknown;
  partnerSummary?: unknown;
  sessionContext?: unknown;
  conversationSummary?: unknown;
  effectiveStyleContext?: unknown;
  knownContactName?: unknown;
}

function normalizeString(value: string): string {
  // NFC: Chinese context + accented Latin can be encoded differently
  // (precomposed vs combining marks). Normalize to canonical composition
  // so 「café」(NFD) and 「café」(NFC) hash the same.
  return value.normalize("NFC").trim();
}

function canonicalize(value: unknown): unknown {
  if (typeof value === "string") return normalizeString(value);
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    const sortedKeys = Object.keys(value as Record<string, unknown>).sort();
    const result: Record<string, unknown> = {};
    for (const k of sortedKeys) {
      result[k] = canonicalize((value as Record<string, unknown>)[k]);
    }
    return result;
  }
  return value;
}

export async function hashConversation(input: HashInput): Promise<string> {
  const canonical = canonicalize({
    messages: input.messages ?? [],
    userDraft: input.userDraft ?? "",
    partnerSummary: input.partnerSummary ?? "",
    sessionContext: input.sessionContext ?? null,
    conversationSummary: input.conversationSummary ?? "",
    effectiveStyleContext: input.effectiveStyleContext ?? "",
    knownContactName: input.knownContactName ?? "",
  });
  const encoded = new TextEncoder().encode(JSON.stringify(canonical));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

Note: tests need to be `async` to await the hash. Update tests accordingly.

**Step 4: Tests pass**

Run: `deno test supabase/functions/analyze-chat/conversation_hash_test.ts`
Expected: PASS, 4 tests.

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/conversation_hash{,_test}.ts
git commit -m "feat(analyze): add canonical conversation hash for run validation"
```

---

### Task 0.3: `analysis_run_store` DB helpers (TDD)

**Files:**
- Create: `supabase/functions/analyze-chat/analysis_run_store.ts`
- Create: `supabase/functions/analyze-chat/analysis_run_store_test.ts`

**Contract:**

```typescript
export interface AnalysisRun {
  id: string;
  user_id: string;
  conversation_hash: string;
  charged: boolean;
  quick_result: Record<string, unknown>;
  retry_count: number;
  created_at: string;
  expires_at: string;
  consumed_at: string | null;
}

export interface CreateRunInput {
  userId: string;
  conversationHash: string;
  quickResult: Record<string, unknown>;
  requestContext?: Record<string, unknown>;
}

export type ValidateError =
  | "MISSING_RUN_ID"
  | "RUN_NOT_FOUND"
  | "RUN_FORBIDDEN"
  | "RUN_EXPIRED"
  | "RUN_CONVERSATION_MISMATCH"
  | "RUN_NOT_CHARGED"
  | "RUN_RETRY_EXHAUSTED";

export interface ValidateInput {
  runId: string | null | undefined;
  userId: string;
  conversationHash: string;
}

export interface ValidateOk { ok: true; run: AnalysisRun; }
export interface ValidateFail { ok: false; error: ValidateError; }
export type ValidateResult = ValidateOk | ValidateFail;
```

**Behaviour to test:**
1. `createRun` inserts with charged=false → caller must call `markCharged` after quota RPC succeeds.
2. `validateRunForFull` enforces I2-I6 in that order.
3. `incrementRetry` is atomic (no double-spend on concurrent retries).

Tests should mock the Supabase client through a small interface. Don't hit real DB in unit tests — Phase 1 has an integration test that does.

**Commit:**
```bash
git add supabase/functions/analyze-chat/analysis_run_store{,_test}.ts
git commit -m "feat(analyze): add analysis_run_store with validate/create/markCharged helpers"
```

---

## Phase 1: Backend `quick` Mode

### Task 1.1: Slim quick system prompt

**Files:**
- Create: `supabase/functions/analyze-chat/quick_prompt.ts`
- Create: `supabase/functions/analyze-chat/quick_prompt_test.ts`

**Decision:** Quick prompt is **NOT** a copy of `SYSTEM_PROMPT`. It's a small focused prompt that asks for:
- `nextStep` (single sentence: "本回合怎麼接")
- `recommendedReply` (single message text, ≤ 1.8x partner's last message)
- `shortReason` (why this reply works, ≤ 30 chars)
- `insufficientContext` (boolean — true if model can't decide without more info)
- `confidence` ("low" | "medium" | "high")

Target output budget: ~200 tokens.

**Key prompt rules carried over from `SYSTEM_PROMPT`:**
- 1.8x rule
- 接住情緒 → 互動感 → 順勢延伸
- 不教操控 / 不施壓 / 不丟棄 consent

**Skip from full prompt** (these come back in Phase 2 full): scenarioDetected matrix, 5-style replyOptions, psychology.shitTest, dimensions radar, healthCheck, strategy.

**Test:**
```typescript
Deno.test("quick prompt mentions 1.8x rule", () => {
  assertStringIncludes(QUICK_SYSTEM_PROMPT, "1.8");
});
Deno.test("quick prompt requires JSON-only output", () => {
  assertStringIncludes(QUICK_SYSTEM_PROMPT.toLowerCase(), "json");
});
Deno.test("quick prompt is dramatically shorter than full", () => {
  // Sanity: should be < 10% of full SYSTEM_PROMPT size.
  assert(QUICK_SYSTEM_PROMPT.length < 20000);
});
```

**Commit:**
```bash
git add supabase/functions/analyze-chat/quick_prompt{,_test}.ts
git commit -m "feat(analyze): add slim quick-mode system prompt"
```

---

### Task 1.2: Parse `responseMode` + `analysisRunId` in handler

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:4493-4510` (destructure block)

**Step 1: Add to `requestBody` destructure**

```typescript
const {
  // ... existing fields ...
  responseMode: rawResponseMode,
  analysisRunId: rawAnalysisRunId,
} = requestBody;
```

**Step 2: Normalize**

```typescript
const responseMode: "quick" | "full" | "legacy" =
  rawResponseMode === "quick" ? "quick"
  : rawResponseMode === "full" ? "full"
  : "legacy";
const analysisRunId = typeof rawAnalysisRunId === "string"
  ? rawAnalysisRunId.trim()
  : null;
```

**Step 3: Add validation tests in `index_test.ts`**

```typescript
Deno.test("legacy mode used when responseMode missing", ...);
Deno.test("quick mode rejects analysisRunId presence (defensive)", ...);
Deno.test("full mode rejects missing analysisRunId with MISSING_RUN_ID", ...);
```

**Commit:**
```bash
git commit -am "feat(analyze): parse responseMode and analysisRunId from request"
```

---

### Task 1.3: Quick handler branch

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:5640-5762` (Claude call site)

**Sketch:**

```typescript
if (responseMode === "quick") {
  // Use Haiku + slim prompt + 400 max_tokens.
  const claudeResult = await callClaudeWithFallback({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 400,
    system: QUICK_SYSTEM_PROMPT,
    messages: [{ role: "user", content: userPromptForQuick }],
  }, CLAUDE_API_KEY, { timeout: 15000, allowModelFallback: false });

  const quickPayload = parseQuickResponse(claudeResult.data);

  // Guardrails (existing pipeline).
  const guarded = applyServerGuardrails(quickPayload, { mode: "quick" });

  const conversationHash = await hashConversation({
    messages, userDraft, partnerSummary, sessionContext,
    conversationSummary, effectiveStyleContext, knownContactName,
  });

  // ORDER MATTERS: insert THEN charge. If insert fails, we DON'T charge.
  // If charge fails, we DELETE the row (best-effort) and return error.
  const run = await analysisRunStore.createRun({
    userId: user.id,
    conversationHash,
    quickResult: guarded,
    requestContext: { responseMode, requestType },
  });

  if (!accountIsTest && quotaUsage.shouldChargeQuota) {
    const { error: usageError } = await supabase.rpc("increment_usage", {
      p_user_id: user.id,
      p_messages: quotaUsage.chargedMessageCount,
    });
    if (usageError) {
      // Rollback: best-effort delete so retry doesn't double-charge.
      await analysisRunStore.deleteRun(run.id);
      return jsonResponse({ error: "Failed to record usage", code: "QUOTA_RPC_FAILED" }, 500);
    }
    await analysisRunStore.markCharged(run.id);
  } else {
    await analysisRunStore.markCharged(run.id); // free / test accounts: mark charged but with cost=0
  }

  // estimatedFullSeconds: conservative ETA the client uses for the loading
  // skeleton copy ("完整分析整理中，約 N 秒後自動補上"). Build 213 uses table
  // lookup, not a real predictor — calibrate post-launch.
  const estimatedFullSeconds = estimateFullSeconds({
    model: selectedModelForFull, // Sonnet vs Haiku
    hasImages,
    cacheHit: tokenUsage.cacheReadTokens > 0,
  });

  return jsonResponse({
    responseMode: "quick",
    analysisRunId: run.id,
    quickResult: guarded,
    estimatedFullSeconds,
    telemetry: { /* quick-specific */ },
  });
}
```

**`estimateFullSeconds` lookup table (build 213 baseline, per Eric 2026-05-28):**

```typescript
function estimateFullSeconds(opts: {
  model: string;
  hasImages: boolean;
  cacheHit: boolean;
}): number {
  // Conservative — round up. Better to under-promise.
  if (opts.hasImages) return 22;        // Sonnet vision ≈ 18-25s
  if (opts.model.includes("haiku")) return 5;  // Haiku quick path uses this fn too
  return 17;                            // Sonnet text ≈ 15-20s
}
```

The client renders this as a range (`eta-2` to `eta+3`) so the user sees「約 15-20 秒」rather than「約 17 秒」— softer, doesn't feel like a broken promise if it lands at 18s.
```

**Tests required (in `index_test.ts`):**

1. `quick succeeds → returns analysisRunId + quickResult shape valid`
2. `quick succeeds → increment_usage called exactly once with correct count`
3. `quick succeeds → analysis_runs row exists with charged=true`
4. `quick fails (Claude error) → no row inserted + no quota charged`
5. `quick succeeds but increment_usage fails → row is deleted (rollback)`
6. `quick test account → no quota charged but row exists`

**Commit:**
```bash
git commit -am "feat(analyze): implement quick response mode with run record + single quota charge"
```

---

## Phase 2: Backend `full` Mode (Codex's highest-risk review surface)

### Task 2.1: Full handler validation + anchor injection

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:5640-5762`

**Sketch:**

```typescript
if (responseMode === "full") {
  // I2 — must have runId. 400 (request-format error), NOT 401.
  if (!analysisRunId) {
    return jsonResponse({ error: "Missing analysisRunId", code: "MISSING_RUN_ID" }, 400);
  }

  const conversationHash = await hashConversation({
    messages, userDraft, partnerSummary, sessionContext,
    conversationSummary, effectiveStyleContext, knownContactName,
  });

  // Stage 1: pure read validation (cheap, no side effects).
  // Covers I3 (user), I4 (expired), I5 (hash), and "RUN_NOT_CHARGED" (quick never completed).
  const validation = await analysisRunStore.validateRunForFull({
    runId: analysisRunId,
    userId: user.id,
    conversationHash,
  });
  if (!validation.ok) {
    const statusByError: Record<string, number> = {
      RUN_NOT_FOUND: 404,
      RUN_FORBIDDEN: 403,
      RUN_EXPIRED: 410,
      RUN_CONVERSATION_MISMATCH: 409,
      RUN_NOT_CHARGED: 409, // Quick never completed; client should re-run quick.
    };
    return jsonResponse(
      { error: validation.error, code: validation.error },
      statusByError[validation.error] ?? 400,
    );
  }

  // Stage 2: ATOMICALLY RESERVE a retry slot BEFORE calling Claude.
  // Why: if we incremented retry_count only on success, a misbehaving client
  // could loop on Claude failures (timeouts, parse errors) forever and burn tokens.
  // By reserving first, every Claude invocation — success OR failure — consumes
  // one of the 3 slots. This is I6.
  //
  // Implementation (in analysis_run_store.ts):
  //   UPDATE analysis_runs
  //      SET retry_count = retry_count + 1,
  //          consumed_at = COALESCE(consumed_at, now())
  //    WHERE id = $1
  //      AND retry_count < 3   -- hardcoded limit; matches I6
  //      AND charged = true
  //      AND expires_at > now()
  //    RETURNING *;
  //
  // 0 rows returned → reservation refused → 429 RUN_RETRY_EXHAUSTED.
  const reservation = await analysisRunStore.reserveRetrySlot(analysisRunId);
  if (!reservation.ok) {
    return jsonResponse(
      { error: "RUN_RETRY_EXHAUSTED", code: "RUN_RETRY_EXHAUSTED" },
      429,
    );
  }
  const run = reservation.run;

  // I7 — anchor injection. Strict language: confirm/supplement/polish only.
  const anchorBlock = buildFullPromptAnchor(run.quick_result);
  const fullUserPrompt = joinPromptSections(userPrompt, anchorBlock);

  // I1 — NO RPC. NO increment_usage. NO quota changes.
  // (lint guard: this comment block is greppable so reviewers can verify
  //  that the full mode branch does not call `supabase.rpc("increment_usage", ...)`)

  let claudeResult;
  try {
    claudeResult = await callClaudeWithFallback({
      model: selectedModel, // existing Sonnet selection logic
      max_tokens: hasImages ? 2560 : 1536, // same as legacy
      system: SYSTEM_PROMPT, // existing full prompt
      messages: [{ role: "user", content: hasImages ? buildVisionContent(fullUserPrompt, images) : fullUserPrompt }],
    }, CLAUDE_API_KEY, { timeout: hasImages ? 120000 : 30000, allowModelFallback: !hasImages });
  } catch (error) {
    // Reservation already consumed; do NOT roll it back. Surface error so client
    // can retry (up to remaining slots).
    return jsonResponse({
      error: "FULL_AI_FAILED",
      code: "FULL_AI_FAILED",
      retriesRemaining: Math.max(0, 3 - run.retry_count),
    }, 502);
  }

  // Parse + repair (existing).
  const fullPayload = parseFullResponse(claudeResult.data);
  const guarded = applyServerGuardrails(fullPayload, { mode: "full" });

  // I7 — drift detector (warn-only in v1).
  const drift = detectAnchorDrift(run.quick_result, guarded);
  if (drift.driftedFields.length > 0) {
    logWarn("full_anchor_drift_detected", { runId: run.id, drift });
  }

  return jsonResponse({
    responseMode: "full",
    analysisRunId: run.id,
    quickResult: run.quick_result,
    result: guarded,
    telemetry: { /* full-specific */ },
  });
}
```

**`buildFullPromptAnchor` template:**

```
## ANCHOR (from quick analysis)
The user has already seen this above-the-fold recommendation. Your full analysis MUST treat it as authoritative anchor, not as a starting point to be revised.

- nextStep: ${quick.nextStep}
- recommendedReply: ${quick.recommendedReply}
- shortReason: ${quick.shortReason}

Rules:
- finalRecommendation.content MUST use the same reply text as recommendedReply, with at most stylistic edits (word substitutions, punctuation). Do NOT change the topic, intent, or main verb.
- finalRecommendation.reason MUST be consistent with shortReason — you can elaborate, but cannot reverse the judgment.
- coachActionHint.microMove MUST align with nextStep direction.
- replyOptions.{extend|resonate|tease|humor|coldRead} can offer alternatives, but the picked `finalRecommendation.pick` MUST point to a style that uses the recommendedReply substantially.
```

**Tests:**

1. `full without runId → 400 MISSING_RUN_ID + no Claude call`
2. `full with another user's runId → 403 RUN_FORBIDDEN + no Claude call`
3. `full with expired runId → 410 RUN_EXPIRED + no Claude call`
4. `full with mutated conversation → 409 RUN_CONVERSATION_MISMATCH`
5. `full with run that never got charged (quick failed mid-flight) → 409 RUN_NOT_CHARGED`
6. `full retry_count already 3 → 429 RUN_RETRY_EXHAUSTED + no Claude call` (reservation refused)
7. `full Claude call fails → reservation IS consumed (retry_count incremented) + returns 502 FULL_AI_FAILED + retriesRemaining shown`
8. `full success → increment_usage NOT called`
9. `full success → result.finalRecommendation.content shares ≥ 80% token overlap with quickResult.recommendedReply` (drift detector — log only, request still succeeds)
10. `full retry that bumps count to 3 then fails → next request gets 429`
11. `concurrent full requests for same runId → only one reservation succeeds atomically; second gets 429 (race safety)`

**Commit:**
```bash
git commit -am "feat(analyze): implement full response mode with anchor + run validation"
```

---

### Task 2.2: Anchor drift detector

**Files:**
- Create: `supabase/functions/analyze-chat/anchor_drift.ts`
- Create: `supabase/functions/analyze-chat/anchor_drift_test.ts`

Pure function comparing `quick.recommendedReply` to `full.finalRecommendation.content`. Returns a list of drifted fields. Used for telemetry only in v1 (Phase 4 may turn into hard reject if drift rate is high).

**Tests:**
1. Identical reply → no drift
2. Light edit (typo fix) → no drift
3. Topic change → drift
4. Empty full → drift

**Commit:**
```bash
git commit -am "feat(analyze): detect quick→full anchor drift for telemetry"
```

---

### Task 2.3: Wire telemetry for both modes

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts` (after Claude success in both branches)
- Modify: `supabase/functions/analyze-chat/logger.ts` (extend `logAiCall` payload if needed)

Add to `requestBody` field of `logAiCall`:
```typescript
{
  responseMode,
  analysisRunId: run?.id,
  quickToFullLagMs: responseMode === "full"
    ? Date.now() - new Date(run.created_at).getTime()
    : null,
  cacheReadTokens: tokenUsage.cacheReadTokens ?? 0,  // Bonus from previous DC discussion
  cacheCreationTokens: tokenUsage.cacheCreationTokens ?? 0,
}
```

This also closes the Path 5 finding from yesterday's DC (cache hit rate monitoring).

**Commit:**
```bash
git commit -am "feat(analyze): log responseMode + analysisRunId + cache token usage"
```

---

## Phase 3: Frontend Two-Phase Orchestrator + UI

### Task 3.1: Quick result entity

**Files:**
- Create: `lib/features/analysis/domain/entities/quick_analysis_result.dart`

```dart
class QuickAnalysisResult {
  final String analysisRunId;
  final String nextStep;
  final String recommendedReply;
  final String shortReason;
  final bool insufficientContext;
  final String confidence;
  final int? estimatedFullSeconds; // server-supplied ETA for skeleton copy

  const QuickAnalysisResult({
    required this.analysisRunId,
    required this.nextStep,
    required this.recommendedReply,
    required this.shortReason,
    required this.insufficientContext,
    required this.confidence,
    this.estimatedFullSeconds,
  });

  factory QuickAnalysisResult.fromJson(Map<String, dynamic> json) {
    final quick = (json['quickResult'] ?? {}) as Map<String, dynamic>;
    final etaRaw = json['estimatedFullSeconds'];
    return QuickAnalysisResult(
      analysisRunId: (json['analysisRunId'] ?? '').toString(),
      nextStep: (quick['nextStep'] ?? '').toString(),
      recommendedReply: (quick['recommendedReply'] ?? '').toString(),
      shortReason: (quick['shortReason'] ?? '').toString(),
      insufficientContext: quick['insufficientContext'] == true,
      confidence: (quick['confidence'] ?? 'medium').toString(),
      estimatedFullSeconds: etaRaw is num ? etaRaw.round() : null,
    );
  }
}
```

**Tests:** `fromJson` happy path + missing fields → safe defaults + `estimatedFullSeconds` null when server omits.

**Commit:**
```bash
git add lib/features/analysis/domain/entities/quick_analysis_result.dart
git add test/unit/features/analysis/quick_analysis_result_test.dart
git commit -m "feat(analyze): add QuickAnalysisResult entity"
```

---

### Task 3.2: `analyzeQuick` + `analyzeFull` service methods

**Files:**
- Modify: `lib/features/analysis/data/services/analysis_service.dart:422-540`

Add two new methods; **keep `analyzeConversation` (the legacy method) intact** for non-paywall flows (`recognizeOnly`, `my_message`, opener delegating to analyze-chat) until we audit them.

```dart
Future<QuickAnalysisResult> analyzeQuick({
  required List<Message> messages,
  SessionContext? sessionContext,
  String? conversationSummary,
  String? partnerSummary,
  String? effectiveStyleContext,
  String? knownContactName,
  int? previousAnalyzedCount,
}) async {
  // POST with responseMode: 'quick', timeout 15s.
  // Throws AnalysisException on failure; on success returns QuickAnalysisResult.
}

Future<AnalysisResult> analyzeFull({
  required String analysisRunId,
  required List<Message> messages,
  // ... same context fields as quick (server validates hash) ...
}) async {
  // POST with responseMode: 'full' + analysisRunId, timeout 60s.
  // Throws specific AnalysisException codes:
  //   RUN_EXPIRED, RUN_CONVERSATION_MISMATCH, RUN_RETRY_EXHAUSTED → user-facing message
  //   All other → generic "完整分析失敗"
}
```

**Tests:** mock `http.Client`, assert request body shape, assert exception mapping on each error code.

**Commit:**
```bash
git commit -am "feat(analyze): add analyzeQuick + analyzeFull service methods"
```

---

### Task 3.3: Orchestrator state machine

**Files:**
- Create: `lib/features/analysis/data/services/two_stage_analyze_orchestrator.dart`
- Create: `test/unit/features/analysis/two_stage_analyze_orchestrator_test.dart`

```dart
enum TwoStagePhase { idle, runningQuick, quickReady, runningFull, fullReady, fullFailed }

class TwoStageAnalyzeState {
  final TwoStagePhase phase;
  final QuickAnalysisResult? quick;
  final AnalysisResult? full;
  final String? fullErrorMessage;
  final String? fullErrorCode;
  final int retryCount;
  // ...
}

class TwoStageAnalyzeOrchestrator {
  final AnalysisService _service;
  final Stream<TwoStageAnalyzeState> stateStream; // emits transitions

  Future<void> start({ /* same params as analyzeQuick */ }) async {
    // 1. emit runningQuick
    // 2. await _service.analyzeQuick(...)
    // 3. emit quickReady with QuickAnalysisResult
    // 4. fire-and-await _service.analyzeFull(analysisRunId, ...)
    // 5. emit runningFull, then fullReady or fullFailed
  }

  Future<void> retryFull() async {
    // Reuses last analysisRunId. Does NOT call quick again.
    // If retry exceeds server limit → emit fullFailed with RUN_RETRY_EXHAUSTED.
  }
}
```

**Tests (the orchestrator is the critical path — comprehensive coverage):**

| Test | Verifies |
|---|---|
| `happy path emits 5 states in order` | idle → runningQuick → quickReady → runningFull → fullReady |
| `quick failure stops at runningQuick → idle with error` | I8 (no full attempted, no charge) |
| `full failure emits fullFailed but quick remains` | Eric's rule #7 |
| `retryFull reuses analysisRunId` | Eric's rule #8 |
| `retryFull does NOT call analyzeQuick` | Eric's rule #8 |
| `retry exhausted maps to user-facing 「無法再重試，請重新分析」` | I6 + UX |

**Commit:**
```bash
git commit -am "feat(analyze): add TwoStageAnalyzeOrchestrator with retry support"
```

---

### Task 3.4: Wire orchestrator into `analysis_screen.dart`

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:2548-2700`

Replace `_runAnalysis` body. Add new state fields:
- `QuickAnalysisResult? _quickResult`
- `bool _isLoadingFullAnalysis`
- `String? _fullErrorMessage`
- `String? _lastAnalysisRunId`
- `int? _estimatedFullSeconds` ← from quick response (see backend §)

Render rules in `build()`:
- If `_quickResult != null && _fullResult == null` → render `_buildQuickSummaryCard()` + placeholder skeletons for psychology / radar / 5 styles / strategy.
- **Placeholder skeleton copy MUST include estimated time** (per Eric 2026-05-28). Use `_estimatedFullSeconds` from server; show range `[eta-2, eta+3]` to feel honest, e.g. server says 17 → 顯示「約 15-20 秒」:

  ```
  完整分析整理中，約 {etaRange} 秒後自動補上
  五大回覆風格整理中，完成後會自動展開
  互動雷達整理中，完成後會自動更新
  深層策略整理中，完成後會自動補上
  ```

  Helper: `String _formatEtaRange(int s)` → e.g. `15-20`. If `_estimatedFullSeconds` is null (server didn't send), fallback to hard-coded `15-20`.

  **Note:** because full is currently a single Claude call, all four sections finish at the same moment. Only the top "完整分析整理中" card carries the time; the other three say "完成後會自動..." so we don't lie to the user about parallel progress. When/if we split into per-section calls (out of scope for build 213), each block gets its own ETA.

- If `_fullErrorMessage != null` → keep summary card; replace skeletons with retry CTA card that shows `retriesRemaining` from server (e.g.「完整分析暫時失敗，可重試（剩 2 次）」).

**Tests (widget test in `test/widget/screens/analysis_screen_two_stage_test.dart`):**
1. After quick: summary card visible + 4 skeleton blocks visible + ETA copy renders with server value
2. ETA fallback: if `estimatedFullSeconds` missing → renders「約 15-20 秒」
3. After full: skeletons gone, full cards rendered
4. After full failure: summary card + retry CTA with `retriesRemaining`
5. Retry CTA calls orchestrator.retryFull (verify via mock)
6. After 3 failures: retry CTA disabled / shows「無法再重試，請重新分析」

**Commit:**
```bash
git commit -am "feat(analyze): two-phase render with placeholder skeletons + retry CTA"
```

---

## Phase 4: Hardening

### Task 4.1: pg_cron cleanup schedule

**Files:**
- Create: `supabase/migrations/20260528_analysis_runs_cron.sql`

Conditional install — only if pg_cron extension is available (Supabase Pro enables it by default).

```sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'cleanup_expired_analysis_runs',
      '0 4 * * *', -- daily 04:00 UTC
      $$SELECT public.cleanup_expired_analysis_runs();$$
    );
  ELSE
    RAISE NOTICE 'pg_cron not available; manual cleanup required for analysis_runs';
  END IF;
END $$;
```

**Commit:**
```bash
git add supabase/migrations/20260528_analysis_runs_cron.sql
git commit -m "feat(analyze): schedule daily cleanup of expired analysis_runs"
```

---

### Task 4.2: Add legacy mode deprecation log

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts` (where legacy branch begins)

```typescript
if (responseMode === "legacy") {
  logWarn("analyze_chat_legacy_mode_used", {
    user: summarizeUser(user.id),
    clientVersion: req.headers.get("x-client-version") ?? "unknown",
    hasImages,
  });
  // ... existing handler unchanged ...
}
```

Once production logs show < 1% legacy traffic for a week, schedule removal in a follow-up PR.

**Commit:**
```bash
git commit -am "feat(analyze): log legacy-mode usage for deprecation tracking"
```

---

### Task 4.3: ~~Update CLAUDE.md Common Pitfalls~~ (deferred)

**Removed from build 213 scope.** Per Eric 2026-05-28:

> Build 213 目標是 App Review performance hotfix，docs cleanup 可以延後。CLAUDE.md 不要單獨改，會違反目前 shared agent rules — 要同步改也要連 `AGENTS.md` / `docs/shared-agent-rules.md` 一起。

Punt to a follow-up docs PR after build 213 ships and the two-stage flow is stable in production. When that PR happens, the docs update MUST cover all three files in one commit:

- `CLAUDE.md` Common Pitfalls
- `AGENTS.md` (mirror — pre-commit hook enforces parity)
- `docs/shared-agent-rules.md` (cross-agent reference)

Suggested wording for that future PR (do NOT commit now):
- `analyze-chat full mode 必須帶有效 analysisRunId，否則 400；前端不要試圖直接呼叫 full path 拿免費完整分析。`
- `Quick → Full 之間 conversation hash 比對：客戶端在 quick 後不能再修改 messages / userDraft / partnerSummary，否則 full 會回 409。`
- `full retry_count 由 server 原子預留（max 3）；失敗的 Claude call 也算一次，避免 client loop 燒 token。`

---

## Codex Review Checklist

When handing off to Codex for high-risk review, ask Codex to explicitly verify each of these:

| Risk | Verification |
|---|---|
| **Quota double-charge** | Read the `full` branch (`if (responseMode === "full")`) end-to-end — it MUST NOT call `supabase.rpc("increment_usage", ...)`. Existing opener / legacy / rate_limiter call sites are fine; the check is scoped to the full branch only. Bonus: confirm `quick` branch calls `increment_usage` exactly once and rolls back via `deleteRun` on RPC failure. |
| **Full bypass for free analysis** | Trace: client sends `responseMode=full` without `analysisRunId` → must 400 before any Claude call. Test: client sends another user's `analysisRunId` → must 403. Test: client sends `responseMode=full` with `analysisRunId` from a quick that never charged (e.g., killed mid-RPC) → must 409. |
| **Quick→full result contradiction** | Read `buildFullPromptAnchor` output — confirm the anchor language is strong enough. Run live test with adversarial conversation that tempts the model to drift. Check `full_anchor_drift_detected` log frequency in staging. |
| **RLS on `analysis_runs`** | Confirm authenticated/anon roles have NO direct access. Only `service_role` (used by Edge Function) can read/write. |
| **Conversation hash robustness** | Verify canonicalization handles: nested objects, arrays of objects, null/undefined, empty strings, unicode normalization. Confirm hash changes when ANY field changes. |
| **Retry abuse** | Verify retry_count atomicity (concurrent retries don't both succeed). |
| **TTL & cleanup** | Confirm `expires_at` enforced server-side, not client-trusted. |
| **Race: quick rollback on RPC failure** | Confirm `deleteRun` is called BEFORE returning error. Cover with test using a stub that throws on `increment_usage`. |
| **Edge Function deploy** | Confirm `analyze-chat` still deploys with `--no-verify-jwt` per OCR baseline note. New helper files must be in the same function directory. |
| **Backwards compatibility** | Confirm legacy clients (no `responseMode`) still work identically. |

---

## Out of Scope (do NOT include in build 213)

- Streaming Anthropic responses (deferred — bigger refactor)
- Haiku/Sonnet A/B for full mode (separate experiment)
- 5-style replyOptions trimming (product decision)
- Caching the full result against the same `analysisRunId` so user can re-open detail later (deferred to build 214)

---

## Rough Sizing (informational)

| Phase | Tasks | Est. effort |
|---|---|---|
| Phase 0 | 3 tasks | 0.5 day |
| Phase 1 | 3 tasks | 1 day |
| Phase 2 | 3 tasks | 1.5 days (highest risk, Codex review gate) |
| Phase 3 | 4 tasks | 1.5 days |
| Phase 4 | 3 tasks | 0.5 day |
| **Total** | **16 tasks** | **~5 working days** |

If build 213 deadline is tighter than 5 days, ship-cut order:
1. Phase 0 + Phase 1 + Phase 2 + Phase 3 (core)
2. Phase 4.1 + 4.3 (cleanup + docs)
3. Defer Phase 4.2 (legacy log)

---

## Notes for the Implementer

- Each task should commit independently. If a Codex review comes back with issues in Phase 1, only Phase 1 should rewind.
- The legacy code path stays in `analyze-chat` until production logs confirm < 1% legacy traffic. Don't delete it as part of this PR.
- Edge Function deploy uses `npx supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg` (per OCR baseline). New helper `.ts` files must live under `supabase/functions/analyze-chat/` to be bundled.
- Recommend running this in a worktree (`feature/two-stage-analyze`) per repo convention.
