# Spec 5 — Coach Follow-up v1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Status:** drafted 2026-05-02; awaiting Codex spec review verdict before coding.
> **Source:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `a66ca5b` (REVISED_AND_APPROVED).
> **Codex review (design):** `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` @ `3d8dd3a`.
> **Authors:** Claude (draft) → Codex (plan review) → Eric (final ACK)

**Goal:** Ship Coach Follow-up v1 — three user-triggered phases (`prepareInvite` / `preDateReminder` / `postDateReflection`) rendered as a single 5-field result card on the partner detail screen, powered by an **independent** `coach-follow-up` Supabase Edge Function with its own prompt builder, schema, validator, telemetry, and CI/CD deploy step. Latest result is persisted in a dedicated local Hive box; each successful generation costs 1 message credit.

**Architecture:**

1. **Backend** — New independent Edge Function `supabase/functions/coach-follow-up/` (sibling to `analyze-chat`, **NOT** a sub-mode). Files: `index.ts` / `prompts.ts` / `schemas.ts` / `validate.ts` / `README.md` / `index_test.ts`. **Zero imports** from `analyze-chat`. JWT-verified (default), rejects `images`. Cost = 1 credit, deducted only on successful response that passes schema validation (incl. `boundaryReminder` non-null check).
2. **Local data** — New Hive entity `CoachFollowUpResult` (typeId 16), repo `CoachFollowUpRepository` (CRUD + `clearAll()`), wired into `SupabaseService.deleteAccount()` / `signOut()` and partner-delete cascade. Privacy regression test mirrors Spec 1 about-me clear test.
3. **UI** — New `CoachFollowUpSection` widget inserted into `partner_detail_screen.dart` between `PartnerTraitsCard` and conversations list. Three phase chips (always visible, AI hint highlights one based on stable enum keys). Click → phase-specific input sheet → Edge call → result card. Phase enums use stable string keys (`prepareInvite` / `preDateReminder` / `postDateReflection`); GameStage matching uses `GameStage.close` enum (NOT 繁中 label string).

**Tech Stack:** Deno + TypeScript (Edge), zod (request/response validation), Flutter 3 + Riverpod + Hive CE (client). Tests: Deno `Deno.test` (Edge), `flutter test` (unit + widget).

---

## 1. Pre-Implementation Reading (REQUIRED before Task 1)

Before writing any code, the implementer must read these to internalize current contracts:

| File | Why |
|------|-----|
| `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` | The binding spec; this plan implements it byte-for-byte |
| `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` | Codex amendments that shaped the design — non-negotiable |
| `supabase/functions/analyze-chat/index.ts:3296-3604` | Subscription self-heal + daily/monthly cap check pattern. **Copy minimal subset only**, do NOT import |
| `supabase/functions/analyze-chat/index.ts:3606-3736` | Opener cost + deduct flow (cost gate before invoke, deduct after success). Pattern reference only |
| `supabase/functions/analyze-chat/logger.ts` | `logInfo` / `logWarn` / `logError` helpers — **may be re-implemented locally** in `coach-follow-up/`, do NOT import (preserve OCR isolation) |
| `lib/features/user_profile/data/repositories/partner_style_repository.dart` | Reference repo pattern: Hive box open + CRUD + `clearAll()` |
| `lib/features/user_profile/data/repositories/partner_data_quality_repository.dart` | Same pattern, additional cascade delete reference |
| `lib/features/analysis/domain/entities/game_stage.dart` | `GameStage` enum stable keys: `opening / premise / qualification / narrative / close`. **Hint resolver matches `GameStage.close`, NOT the 繁中 label '準備邀約'** |
| `lib/features/partner/domain/entities/partner.dart` | Partner entity is typeId=8; `Partner.id` is the key for new box |
| `lib/features/partner/presentation/screens/partner_detail_screen.dart` | Insertion point for `CoachFollowUpSection` widget |
| `lib/features/user_profile/data/providers/data_quality_flag_provider.dart` | `dataQualityFlagProvider(partnerId).isFlagged` — drives Spec 3 `lastConversationSummary` omit rule |
| `lib/core/services/supabase_service.dart:157-220` | `deleteAccount()` and `signOut()` — wire `clearAll()` into these |
| `lib/hive_registrar.g.dart` | Generated; re-run `dart run build_runner build --delete-conflicting-outputs` after adding new entity |
| `.github/workflows/deploy-edge-function.yml` | Add `coach-follow-up` deploy line; **must NOT** use `--no-verify-jwt`; **must NOT** be merged into a `deploy all` step that strips analyze-chat's `--no-verify-jwt` |

**Stable-key discipline (Eric explicit constraint)**:
- `phase` everywhere = `prepareInvite` / `preDateReminder` / `postDateReflection` (enum `.name` serialization).
- `gameStage` matching uses `GameStage.close` (enum value), NOT `'邀約'` or `'準備邀約'` (繁中 label strings).
- Telemetry event names = English snake_case (`coach_follow_up_*`).
- Hive field stored values = enum `.name` strings (stable across rename refactors).

---

## 2. File Touch List (Concrete Paths)

### Create — Edge Function

```text
supabase/functions/coach-follow-up/
  index.ts
  prompts.ts
  schemas.ts
  validate.ts
  logger.ts                           # local copy of minimal log helpers (NO import from analyze-chat)
  README.md
  index_test.ts                       # request validation / response validation / image rejection / cost-on-success
  validate_test.ts                    # boundaryReminder required / truncation / Spec 3 flagged omit
  prompts_test.ts                     # phase-specific prompt assembly snapshot tests
```

### Create — Flutter (domain + data)

```text
lib/features/coach_follow_up/
  domain/
    entities/
      coach_follow_up_phase.dart                  # enum with stable .name keys
      coach_follow_up_result.dart                 # Hive @HiveType(typeId: 16)
    services/
      coach_follow_up_hint_resolver.dart          # pure function: PartnerState → CoachFollowUpPhase?
    repositories/
      coach_follow_up_repository.dart             # abstract interface
  data/
    repositories/
      coach_follow_up_repository_impl.dart        # Hive impl
    services/
      coach_follow_up_api_service.dart            # Edge function HTTP client
    providers/
      coach_follow_up_providers.dart              # Riverpod providers
```

### Create — Flutter (presentation)

```text
lib/features/coach_follow_up/presentation/
  widgets/
    coach_follow_up_section.dart                  # entry block on partner detail
    coach_follow_up_chip_row.dart                 # 3 phase chips + AI hint
    coach_follow_up_input_sheet.dart              # bottom sheet, phase-specific Q1-Q3
    coach_follow_up_result_card.dart              # 5-field card
    coach_follow_up_loading_skeleton.dart         # reusable skeleton
```

### Create — Tests

```text
test/unit/features/coach_follow_up/
  domain/
    entities/coach_follow_up_phase_test.dart
    services/coach_follow_up_hint_resolver_test.dart
  data/
    repositories/coach_follow_up_repository_impl_test.dart    # CRUD + clearAll + cascade
    services/coach_follow_up_api_service_test.dart             # request shape, error mapping, debounce
  privacy/
    coach_follow_up_clear_all_regression_test.dart             # mirrors Spec 1 about-me clear test

test/widget/features/coach_follow_up/
  coach_follow_up_section_test.dart
  coach_follow_up_chip_row_test.dart
  coach_follow_up_input_sheet_test.dart
  coach_follow_up_result_card_test.dart
```

### Modify

```text
lib/features/partner/presentation/screens/partner_detail_screen.dart   # insert CoachFollowUpSection between traits card & conversations list
lib/core/services/supabase_service.dart                                 # call CoachFollowUpRepository.clearAll() in deleteAccount() + signOut()
lib/features/partner/data/providers/partner_write_controller.dart       # cascade delete: when partner deleted → CoachFollowUpRepository.delete(partnerId)
lib/hive_registrar.g.dart                                                # regenerated after build_runner
.github/workflows/deploy-edge-function.yml                              # add: supabase functions deploy coach-follow-up
```

### Out-of-scope (DO NOT touch)

```text
supabase/functions/analyze-chat/**       # OCR baseline — zero edits this PR
lib/features/analysis/**                  # Spec 4 surface — zero edits
lib/features/learning/**                  # v1 doesn't deep-link
lib/features/user_profile/data/repositories/partner_summary_*.dart      # NEVER write to partnerSummary
lib/features/about_me/**                  # NEVER write to long-term memory
```

---

## 3. Phase Plan (Commit Boundaries)

| Phase | Tasks | Outcome | Mergeable? |
|-------|-------|---------|------------|
| **A. Backend Edge function** | T1-T9 | `coach-follow-up` deployable + tested via curl | Yes (server-only PR) |
| **B. Local data layer** | T10-T15 | Repo + entity + clearAll + cascade + privacy regression | Yes (no UI) |
| **C. UI surface** | T16-T22 | Section widget + input sheet + result card wired into partner detail | Yes (full feature live) |
| **X. Cross-cutting** | T23-T25 | CI/CD, telemetry verify, smoke test | Yes (final polish) |

Each task = one commit. Phase boundaries = natural PR breakpoints. Recommended: ship Phase A as standalone PR first (zero client risk), then B+C bundled, then X polish.

---

## 4. Phase A: Backend Edge Function

### Task A1: Bootstrap `coach-follow-up/` skeleton

**Files:**
- Create: `supabase/functions/coach-follow-up/index.ts`
- Create: `supabase/functions/coach-follow-up/README.md`

**Step 1: Write skeleton `index.ts`** that returns 501 NotImplemented for any request, plus health probe `GET /` returns 200 OK.

```typescript
// supabase/functions/coach-follow-up/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  if (req.method === "GET") {
    return new Response(JSON.stringify({ status: "ok", function: "coach-follow-up" }), {
      headers: { "Content-Type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ error: "not_implemented" }), {
    status: 501,
    headers: { "Content-Type": "application/json" },
  });
});
```

**Step 2: Write README.md** documenting the function's contract: phase semantics, tone rules, boundary rules (copy from design §1.3 / §2.4 / §2.5).

**Step 3: Manual local sanity** — `deno run --allow-net index.ts` and `curl localhost:8000/` returns 200.

**Step 4: Commit**

```bash
git add supabase/functions/coach-follow-up/
git commit -m "[feat] Spec 5 Phase A T1 — coach-follow-up Edge function 骨架"
```

---

### Task A2: Define request schema + validator (zod)

**Files:**
- Create: `supabase/functions/coach-follow-up/schemas.ts`
- Create: `supabase/functions/coach-follow-up/validate.ts`
- Create: `supabase/functions/coach-follow-up/validate_test.ts`

**Step 1: Write failing test `validate_test.ts`**

```typescript
import { assertEquals, assertRejects } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { validateRequest } from "./validate.ts";

Deno.test("rejects missing phase", () => {
  assertRejects(() => validateRequest({ answers: { q1: "x" } }), Error, "phase");
});

Deno.test("rejects unknown phase", () => {
  assertRejects(
    () => validateRequest({ phase: "invalid", answers: { q1: "x" } }),
    Error,
    "phase",
  );
});

Deno.test("rejects images field (v1 prohibited)", () => {
  assertRejects(
    () => validateRequest({ phase: "prepareInvite", answers: { q1: "x" }, images: [] }),
    Error,
    "invalid_input_for_mode",
  );
});

Deno.test("rejects q3 over 80 chars", () => {
  assertRejects(
    () => validateRequest({ phase: "prepareInvite", answers: { q1: "x", q3: "a".repeat(81) } }),
    Error,
    "q3",
  );
});

Deno.test("rejects lastConversationSummary over 200 chars", () => {
  assertRejects(
    () => validateRequest({
      phase: "prepareInvite",
      answers: { q1: "x" },
      partnerHint: { name: "C", lastConversationSummary: "a".repeat(201) },
    }),
    Error,
    "lastConversationSummary",
  );
});

Deno.test("accepts minimal valid payload", async () => {
  const r = await validateRequest({ phase: "prepareInvite", answers: { q1: "fuzzy" } });
  assertEquals(r.phase, "prepareInvite");
});
```

**Step 2: Run** `deno test validate_test.ts` — fails (modules don't exist).

**Step 3: Implement `schemas.ts` + `validate.ts`**

```typescript
// schemas.ts
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const PhaseEnum = z.enum(["prepareInvite", "preDateReminder", "postDateReflection"]);

export const RequestSchema = z.object({
  phase: PhaseEnum,
  answers: z.object({
    q1: z.string().min(1),
    q2: z.string().nullable().optional(),
    q3: z.string().max(80).nullable().optional(),
  }),
  partnerHint: z.object({
    name: z.string(),
    heatScore: z.number().int().min(0).max(100).nullable().optional(),
    gameStage: z.string().nullable().optional(),
    lastConversationSummary: z.string().max(200).nullable().optional(),
  }).optional(),
}).strict();

export const ResponseCardSchema = z.object({
  headline: z.string().min(1).max(30),
  observation: z.string().min(1).max(80),
  task: z.string().min(1).max(30),
  suggestedLine: z.string().max(80).nullable().optional(),
  boundaryReminder: z.string().min(1).max(60),  // REQUIRED, non-null
});

export const ResponseSchema = z.object({
  phase: PhaseEnum,
  card: ResponseCardSchema,
  model: z.string(),
  generatedAt: z.string(),
});
```

```typescript
// validate.ts
import { RequestSchema, ResponseCardSchema, ResponseSchema } from "./schemas.ts";

export async function validateRequest(payload: unknown) {
  if (typeof payload === "object" && payload !== null && "images" in payload) {
    throw new Error("invalid_input_for_mode: images not accepted in coach-follow-up v1");
  }
  return RequestSchema.parse(payload);
}

export function validateResponseCard(card: unknown) {
  return ResponseCardSchema.parse(card);
}

export function validateFullResponse(payload: unknown) {
  return ResponseSchema.parse(payload);
}
```

**Step 4: Run** `deno test validate_test.ts` — all pass.

**Step 5: Commit**

```bash
git add supabase/functions/coach-follow-up/{schemas,validate,validate_test}.ts
git commit -m "[feat] Spec 5 Phase A T2 — request/response zod schemas + validator (boundaryReminder required, images rejected)"
```

---

### Task A3: Truncation + boundaryReminder enforcement helpers

**Files:**
- Modify: `supabase/functions/coach-follow-up/validate.ts`
- Modify: `supabase/functions/coach-follow-up/validate_test.ts`

**Step 1: Add failing tests**

```typescript
Deno.test("truncateCard caps headline to 30 chars", () => {
  const r = truncateCard({ headline: "a".repeat(50), observation: "x", task: "y", boundaryReminder: "z" });
  assertEquals(r.headline.length, 30);
});

Deno.test("truncateCard caps boundaryReminder to 60 chars", () => {
  const r = truncateCard({ headline: "a", observation: "x", task: "y", boundaryReminder: "b".repeat(100) });
  assertEquals(r.boundaryReminder.length, 60);
});

Deno.test("validateFullResponse fails when boundaryReminder is null", () => {
  assertRejects(() => Promise.resolve(validateFullResponse({
    phase: "prepareInvite",
    card: { headline: "h", observation: "o", task: "t", boundaryReminder: null },
    model: "m", generatedAt: "g",
  })), Error, "boundaryReminder");
});

Deno.test("validateFullResponse fails when boundaryReminder is missing", () => {
  assertRejects(() => Promise.resolve(validateFullResponse({
    phase: "prepareInvite",
    card: { headline: "h", observation: "o", task: "t" },
    model: "m", generatedAt: "g",
  })), Error, "boundaryReminder");
});
```

**Step 2: Run** — fails.

**Step 3: Implement `truncateCard`** in `validate.ts`:

```typescript
const FIELD_CAPS = { headline: 30, observation: 80, task: 30, suggestedLine: 80, boundaryReminder: 60 };

export function truncateCard<T extends Record<string, string | null | undefined>>(card: T): T {
  const out = { ...card };
  for (const [field, cap] of Object.entries(FIELD_CAPS)) {
    const v = out[field];
    if (typeof v === "string" && v.length > cap) {
      (out as any)[field] = v.slice(0, cap);
    }
  }
  return out;
}
```

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T3 — truncateCard + boundaryReminder hard-required enforcement"
```

---

### Task A4: Phase-specific prompt builder

**Files:**
- Create: `supabase/functions/coach-follow-up/prompts.ts`
- Create: `supabase/functions/coach-follow-up/prompts_test.ts`

**Step 1: Write failing tests**

```typescript
Deno.test("prepareInvite prompt includes phase + boundary instruction", () => {
  const p = buildCoachFollowUpPrompt("prepareInvite", { q1: "fuzzy" }, { name: "C" });
  assertStringIncludes(p, "準備邀約");
  assertStringIncludes(p, "boundaryReminder");      // mention required field
  assertStringIncludes(p, "≤ 60");                   // cap mention
});

Deno.test("preDateReminder prompt does NOT mention partner name in inference instructions", () => {
  const p = buildCoachFollowUpPrompt("preDateReminder", { q1: "今天" }, { name: "Candy" });
  // Name may appear as display label only; prompt must not say "based on name X infer..."
  assertEquals(p.includes("根據對方名字"), false);
});

Deno.test("postDateReflection includes 還看不出來 handling", () => {
  const p = buildCoachFollowUpPrompt("postDateReflection", { q1: "卡卡的", q2: "stillUnclear" }, { name: "X" });
  assertStringIncludes(p, "太早判斷");
});

Deno.test("partnerHint.lastConversationSummary appears verbatim when provided", () => {
  const p = buildCoachFollowUpPrompt("preDateReminder", { q1: "明天" }, { name: "X", lastConversationSummary: "對話氣氛輕鬆，最近聊到週末有空" });
  assertStringIncludes(p, "對話氣氛輕鬆");
});

Deno.test("prompt forbids 物化 vocabulary list", () => {
  const p = buildCoachFollowUpPrompt("prepareInvite", { q1: "fuzzy" }, { name: "X" });
  assertStringIncludes(p, "收割");        // banned word listed in prohibition
  assertStringIncludes(p, "PUA");
});
```

**Step 2: Run** — fails.

**Step 3: Implement `prompts.ts`** (length: ~120 lines):

```typescript
const SYSTEM_PROMPT_BASE = `
你是 VibeSync 的「教練跟進」AI。任務：根據用戶選擇的 phase 與少量 context，產生一張結構化的跟進建議卡。

[硬規則]
- 絕不教用戶裝冷淡 / 用話術逃避責任 / 用承諾綁住對方。
- 絕不出現以下字眼：收割 / 控住 / 壞女人 / 玩咖 / 高分妹 / 攻略 / PUA。
- 失敗 / 拒絕 / 對方變淡情境必須降低焦慮、不製造焦慮、不催促重訊息轟炸。
- partnerHint.name 只是顯示用，不可從名字推測對方性格 / 文化背景 / 任何屬性。
- 必須輸出 5 個欄位：headline (≤30字) / observation (≤80字) / task (≤30字) / suggestedLine (≤80字, optional) / boundaryReminder (≤60字, **REQUIRED, 永不可為 null**)。
- boundaryReminder 是強制欄位，每次都要產出邊界視角；缺欄位將視為失敗、用戶不會被扣額度。

[輸出格式]
僅輸出 JSON，schema:
{
  "headline": string,
  "observation": string,
  "task": string,
  "suggestedLine": string | null,
  "boundaryReminder": string
}
`;

const PHASE_INSTRUCTIONS: Record<string, string> = {
  prepareInvite: `[Phase: 準備邀約] ...`,
  preDateReminder: `[Phase: 約會前提醒] ...`,
  postDateReflection: `[Phase: 約會後復盤] 「還看不出來」/「太早判斷不出」案例：先安撫，提示再觀察一兩輪，給一個低壓小動作，不要催促 follow-up 訊息。`,
};

export function buildCoachFollowUpPrompt(
  phase: "prepareInvite" | "preDateReminder" | "postDateReflection",
  answers: { q1: string; q2?: string | null; q3?: string | null },
  hint: { name: string; heatScore?: number | null; gameStage?: string | null; lastConversationSummary?: string | null } = { name: "" },
): string {
  const parts = [
    SYSTEM_PROMPT_BASE,
    PHASE_INSTRUCTIONS[phase],
    `[用戶輸入] q1=${answers.q1}; q2=${answers.q2 ?? "(skip)"}; q3=${answers.q3 ?? "(skip)"}`,
    hint.heatScore != null ? `[Context] heatScore=${hint.heatScore}` : "",
    hint.gameStage ? `[Context] gameStage=${hint.gameStage}` : "",
    hint.lastConversationSummary ? `[Context] 最近對話摘要：${hint.lastConversationSummary}` : "",
  ].filter(Boolean);
  return parts.join("\n\n");
}
```

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T4 — phase-specific prompt builder（boundaryReminder enforced, 物化字眼黑名單）"
```

---

### Task A5: Local logger (no analyze-chat import)

**Files:**
- Create: `supabase/functions/coach-follow-up/logger.ts`

**Step 1: Implement minimal logger** (mirror `analyze-chat/logger.ts` shape but **own copy** — preserves OCR isolation):

```typescript
export function logInfo(event: string, data: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ level: "info", event, ts: new Date().toISOString(), ...data }));
}
export function logWarn(event: string, data: Record<string, unknown> = {}) {
  console.warn(JSON.stringify({ level: "warn", event, ts: new Date().toISOString(), ...data }));
}
export function logError(event: string, data: Record<string, unknown> = {}) {
  console.error(JSON.stringify({ level: "error", event, ts: new Date().toISOString(), ...data }));
}
export function summarizeUser(uid: string): string {
  return uid.slice(0, 8);
}
```

**Step 2: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T5 — local logger（無 analyze-chat import，OCR 隔離）"
```

---

### Task A6: index.ts — auth + quota gate + dispatch (failure paths)

**Files:**
- Modify: `supabase/functions/coach-follow-up/index.ts`
- Modify: `supabase/functions/coach-follow-up/index_test.ts` (create)

**Step 1: Write failing tests** for the failure paths first (no Claude call yet):

```typescript
Deno.test("POST without auth returns 401", async () => { /* fetch with no Authorization */ });
Deno.test("POST with invalid phase returns 400", async () => { /* ... */ });
Deno.test("POST with images returns 400 invalid_input_for_mode", async () => { /* ... */ });
Deno.test("POST when monthly cap reached returns 429", async () => { /* mock subscriptions row */ });
Deno.test("POST when daily cap reached returns 429", async () => { /* ... */ });
```

**Step 2: Run** — fails.

**Step 3: Implement** the auth + cap check skeleton in `index.ts`. Inline (do NOT import) a minimal subscription self-heal, daily/monthly reset, and cap check — pattern mirrors `analyze-chat/index.ts:3354-3604` but **copy + adapt minimally** for cost = 1.

```typescript
// Pseudocode shape; full implementation copies the minimum subset needed.
serve(async (req) => {
  if (req.method !== "POST") return notImplemented();

  const auth = req.headers.get("Authorization");
  if (!auth) return jsonResponse({ error: "unauthorized" }, 401);

  // Auth check via supabase.auth.getUser(jwt)
  const { user } = await getAuthenticatedUser(auth);
  if (!user) return jsonResponse({ error: "unauthorized" }, 401);

  let payload;
  try {
    payload = await validateRequest(await req.json());
  } catch (e) {
    return jsonResponse({ error: getErrorMessage(e) }, 400);
  }

  // Subscription self-heal + cap check (cost=1)
  const sub = await fetchOrCreateSubscription(user.id);
  const [monthlyLimit, dailyLimit] = [TIER_MONTHLY_LIMITS[sub.tier], TIER_DAILY_LIMITS[sub.tier]];
  const cost = 1;
  if (sub.monthly_messages_used + cost > monthlyLimit ||
      sub.daily_messages_used + cost > dailyLimit) {
    return jsonResponse({ error: "額度不足", quotaNeeded: cost }, 429);
  }

  // ... Task A7 will add Claude call
  return jsonResponse({ error: "not_implemented" }, 501);
});
```

**Step 4: Run** — failure-path tests pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T6 — index.ts auth + quota gate + 400/401/429 paths（無 Claude call）"
```

---

### Task A7: Claude API invocation + response validation + credit deduct

**Files:**
- Modify: `supabase/functions/coach-follow-up/index.ts`
- Modify: `supabase/functions/coach-follow-up/index_test.ts`

**Step 1: Add failing tests** (mock Claude response):

```typescript
Deno.test("successful generation deducts 1 credit", async () => { /* assert subscriptions.monthly_messages_used += 1 */ });
Deno.test("Claude returning card with null boundaryReminder → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("Claude returning card with missing boundaryReminder → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("Claude API timeout → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("over-cap headline (50 chars) → truncated to 30, credit deducted", async () => { /* ... */ });
```

**Step 2: Run** — fails.

**Step 3: Implement** the Claude call path:

```typescript
const apiKey = Deno.env.get("CLAUDE_API_KEY");  // NOT ANTHROPIC_API_KEY (CLAUDE.md pitfall)
if (!apiKey) return jsonResponse({ error: "config_missing" }, 500);

const model = sub.tier === "free"
  ? "claude-haiku-4-5-20251001"
  : "claude-sonnet-4-20250514";

const prompt = buildCoachFollowUpPrompt(payload.phase, payload.answers, payload.partnerHint);

let claudeData;
try {
  claudeData = await callClaudeAPI({ model, prompt, max_tokens: 1024, timeout: 60000 });
} catch (e) {
  logWarn("coach_follow_up_failed", { phase: payload.phase, tier: sub.tier, errorClass: classifyError(e) });
  return jsonResponse({ error: `AI 生成失敗：${getErrorMessage(e)}` }, 500);
}

let card;
try {
  const parsed = parseClaudeJSON(claudeData);
  card = truncateCard(parsed);
  validateResponseCard(card);  // throws on missing/null boundaryReminder
} catch (e) {
  logWarn("coach_follow_up_failed", { phase: payload.phase, tier: sub.tier, errorClass: "schema_invalid" });
  return jsonResponse({ error: "response_invalid" }, 500);
}

// Deduct ONLY after successful validation
await supabase.from("subscriptions").update({
  monthly_messages_used: (sub.monthly_messages_used || 0) + 1,
  daily_messages_used: (sub.daily_messages_used || 0) + 1,
}).eq("user_id", user.id);

logInfo("coach_follow_up_succeeded", { phase: payload.phase, tier: sub.tier, model, latencyMs, costDeducted: 1 });

return jsonResponse({
  phase: payload.phase,
  card,
  model,
  generatedAt: new Date().toISOString(),
});
```

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T7 — Claude call + boundaryReminder enforcement + credit deduct on success only"
```

---

### Task A8: Telemetry events full coverage

**Files:**
- Modify: `supabase/functions/coach-follow-up/index.ts`
- Modify: `supabase/functions/coach-follow-up/index_test.ts`

Verify all 5 telemetry events from design §7 fire correctly:

```text
coach_follow_up_invoked       { phase, tier, hasOptionalText: bool }
coach_follow_up_succeeded     { phase, tier, model, latencyMs, costDeducted: 1 }
coach_follow_up_failed        { phase, tier, errorClass }     // errorClass = enum, NOT errorMessage
```

`regenerated` and `phase_switched` are client-side events (deferred to Phase C T20).

**Step 1: Add tests** that capture stdout/stderr and assert event names + fields shape.

**Step 2-4: Implement, run, verify.**

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T8 — telemetry events 全覆蓋（不 log free-text / prompt 全文）"
```

---

### Task A9: Edge function manual smoke + deploy verification

**Step 1: Local Deno test full pass** — `deno test supabase/functions/coach-follow-up/` all green.

**Step 2: Deploy preview** (Eric runs this):

```bash
SUPABASE_ACCESS_TOKEN=sbp_xxx npx supabase functions deploy coach-follow-up \
  --project-ref fcmwrmwdoqiqdnbisdpg
# NOTE: NO --no-verify-jwt flag (this function REQUIRES JWT)
```

**Step 3: Curl smoke** with a real JWT:

```bash
curl -X POST https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/coach-follow-up \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"phase":"prepareInvite","answers":{"q1":"fuzzy"},"partnerHint":{"name":"Test"}}'
```

Expected: 200 with valid card JSON; cost deducted; logs show `coach_follow_up_succeeded`.

**Step 4: Negative smoke**: try `images: []` → 400 `invalid_input_for_mode`.

**Step 5: Commit + push** (no code changes; just confirmation).

> **Phase A complete — backend deployable in isolation. Open PR if shipping in stages.**

---

## 5. Phase B: Local Data Layer

### Task B10: `CoachFollowUpPhase` enum

**Files:**
- Create: `lib/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart`
- Create: `test/unit/features/coach_follow_up/domain/entities/coach_follow_up_phase_test.dart`

**Step 1: Write failing test**

```dart
test('phase serializes to stable string keys', () {
  expect(CoachFollowUpPhase.prepareInvite.name, equals('prepareInvite'));
  expect(CoachFollowUpPhase.preDateReminder.name, equals('preDateReminder'));
  expect(CoachFollowUpPhase.postDateReflection.name, equals('postDateReflection'));
});

test('fromString returns matching enum', () {
  expect(CoachFollowUpPhase.fromString('prepareInvite'), equals(CoachFollowUpPhase.prepareInvite));
});

test('fromString returns null for invalid', () {
  expect(CoachFollowUpPhase.fromString('invalid'), isNull);
});
```

**Step 2-4: Implement / run / pass**:

```dart
enum CoachFollowUpPhase {
  prepareInvite,
  preDateReminder,
  postDateReflection;

  static CoachFollowUpPhase? fromString(String? value) {
    if (value == null) return null;
    for (final v in CoachFollowUpPhase.values) {
      if (v.name == value) return v;
    }
    return null;
  }

  String get displayLabel {
    switch (this) {
      case prepareInvite:    return '準備邀約';
      case preDateReminder:  return '約會前提醒';
      case postDateReflection: return '約會後復盤';
    }
  }
}
```

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase B T10 — CoachFollowUpPhase enum（stable .name keys + display label 分離）"
```

---

### Task B11: `CoachFollowUpResult` Hive entity (typeId 16)

**Files:**
- Create: `lib/features/coach_follow_up/domain/entities/coach_follow_up_result.dart`

**Step 1: Verify next free typeId is 16** by greping `@HiveType(typeId:` (current top: 15 = `partner_data_quality_state`). If a subsequent PR has claimed 16, escalate.

**Step 2: Write entity**

```dart
@HiveType(typeId: 16)  // verified free at 2026-05-02
class CoachFollowUpResult extends HiveObject {
  @HiveField(0) final String partnerId;
  @HiveField(1) final String phase;            // CoachFollowUpPhase.name
  @HiveField(2) final String headline;
  @HiveField(3) final String observation;
  @HiveField(4) final String task;
  @HiveField(5) final String? suggestedLine;
  @HiveField(6) final String boundaryReminder;  // required, non-null
  @HiveField(7) final DateTime generatedAt;
  @HiveField(8) final String modelUsed;

  CoachFollowUpResult({
    required this.partnerId,
    required this.phase,
    required this.headline,
    required this.observation,
    required this.task,
    this.suggestedLine,
    required this.boundaryReminder,
    required this.generatedAt,
    required this.modelUsed,
  });
}
```

**Step 3: Generate adapter**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expect `coach_follow_up_result.g.dart` created and `hive_registrar.g.dart` updated.

**Step 4: Verify** with `flutter analyze` — no warnings.

**Step 5: Commit**

```bash
git add lib/features/coach_follow_up/domain/entities/coach_follow_up_result.dart \
        lib/features/coach_follow_up/domain/entities/coach_follow_up_result.g.dart \
        lib/hive_registrar.g.dart
git commit -m "[feat] Spec 5 Phase B T11 — CoachFollowUpResult Hive entity（typeId 16）"
```

---

### Task B12: `CoachFollowUpRepository` (interface + Hive impl)

**Files:**
- Create: `lib/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart`
- Create: `lib/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl.dart`
- Create: `test/unit/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl_test.dart`

**Step 1: Write failing tests** covering the full surface:

```dart
group('CoachFollowUpRepositoryImpl', () {
  late Box<CoachFollowUpResult> box;
  late CoachFollowUpRepositoryImpl repo;

  setUp(() async {
    await Hive.initFlutter();
    Hive.registerAdapter(CoachFollowUpResultAdapter());
    box = await Hive.openBox<CoachFollowUpResult>('test_coach_follow_up_results');
    repo = CoachFollowUpRepositoryImpl(box);
  });

  tearDown(() async => await box.deleteFromDisk());

  test('put + get returns latest', () async { /* ... */ });
  test('put twice for same partner overwrites (latest only)', () async { /* ... */ });
  test('delete removes entry', () async { /* ... */ });
  test('clearAll wipes box completely', () async { /* ... */ });
  test('get for unknown partnerId returns null', () async { /* ... */ });
});
```

**Step 2: Run** — fails.

**Step 3: Implement** abstract interface + Hive impl. Mirror `PartnerStyleRepository` and `PartnerDataQualityRepository` shape.

```dart
// repositories/coach_follow_up_repository.dart (interface)
abstract class CoachFollowUpRepository {
  CoachFollowUpResult? get(String partnerId);
  Future<void> put(CoachFollowUpResult result);
  Future<void> delete(String partnerId);
  Future<void> clearAll();
}

// data/repositories/coach_follow_up_repository_impl.dart
class CoachFollowUpRepositoryImpl implements CoachFollowUpRepository {
  CoachFollowUpRepositoryImpl(this._box);
  final Box<CoachFollowUpResult> _box;

  @override
  CoachFollowUpResult? get(String partnerId) => _box.get(partnerId);

  @override
  Future<void> put(CoachFollowUpResult result) async => _box.put(result.partnerId, result);

  @override
  Future<void> delete(String partnerId) async => _box.delete(partnerId);

  @override
  Future<void> clearAll() async => _box.clear();
}
```

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase B T12 — CoachFollowUpRepository（CRUD + clearAll，鏡射 PartnerStyleRepository pattern）"
```

---

### Task B13: Wire `clearAll()` into account-clear paths

**Files:**
- Modify: `lib/core/services/supabase_service.dart` (deleteAccount + signOut)
- Modify: `test/unit/.../supabase_service_test.dart` (or new) to verify clearAll fires

**Step 1: Read `supabase_service.dart:157-220`** to understand existing pattern. Look for how Spec 1 about-me box is cleared (it should already be in the chain — match that pattern).

**Step 2: Write failing test** asserting that calling `signOut()` triggers `CoachFollowUpRepository.clearAll()`.

**Step 3: Wire in** — inject `CoachFollowUpRepository` (via Riverpod or service locator pattern matching what's there).

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase B T13 — 帳號清理路徑接 CoachFollowUpRepository.clearAll()"
```

---

### Task B14: Partner-delete cascade

**Files:**
- Modify: `lib/features/partner/data/providers/partner_write_controller.dart`
- Modify or create: cascade test

**Step 1: Locate partner-delete code** (CLAUDE.md Pitfall mentions guard logic at `partner_write_controller`).

**Step 2: Write failing test** asserting that deleting a partner with a stored follow-up result also clears it from the new box.

**Step 3: Wire `CoachFollowUpRepository.delete(partnerId)`** into the partner-delete path. Match existing pattern (e.g., how `PartnerStyleRepository` / `PartnerDataQualityRepository` cascade).

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase B T14 — partner delete cascade clears coach_follow_up_results entry"
```

---

### Task B15: Privacy regression test (mirror Spec 1)

**Files:**
- Create: `test/unit/features/coach_follow_up/privacy/coach_follow_up_clear_all_regression_test.dart`

**Step 1: Read Spec 1 about-me clearAll regression test** (find via grep `clearAll.*about_me` or similar) to mirror its shape exactly — the test asserts the box file is gone or empty after the account-clear flow runs.

**Step 2: Write equivalent test** for `coach_follow_up_results` box: pre-populate with N entries, run `signOut()` (or `deleteAccount()`), assert box is empty / file absent.

**Step 3: Run** — pass (because B13 wired it).

**Step 5: Commit**

```bash
git commit -am "[test] Spec 5 Phase B T15 — privacy regression：clearAll 後 box 空（鏡射 Spec 1 about-me test）"
```

> **Phase B complete — local data layer self-tested. Open PR if shipping with Phase A separately.**

---

## 6. Phase C: UI Surface

### Task C16: AI hint resolver (pure Dart)

**Files:**
- Create: `lib/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver.dart`
- Create: `test/unit/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver_test.dart`

**Step 1: Define input shape** — pure data class `CoachFollowUpHintInput` containing only stable enum/scalar values:

```dart
class CoachFollowUpHintInput {
  final GameStage? gameStage;
  final int? heatScore;
  final List<String> recentMessageBodies;  // raw text, kept locally only
  final Duration? timeSinceLastMessage;
  final Duration? averageMessageInterval;
  const CoachFollowUpHintInput({...});
}
```

**Step 2: Write failing tests** covering each rule from design §5:

```dart
test('gameStage close + heat 70 → prepareInvite', () {
  final r = CoachFollowUpHintResolver.resolve(CoachFollowUpHintInput(
    gameStage: GameStage.close, heatScore: 70, recentMessageBodies: [], ...));
  expect(r, equals(CoachFollowUpPhase.prepareInvite));
});

test('recent message contains 明天 → preDateReminder', () { /* ... */ });
test('recent message contains 見面 → preDateReminder', () { /* ... */ });

test('long quiet + recent meet keyword → postDateReflection', () { /* ... */ });

test('no signal → null', () {
  final r = CoachFollowUpHintResolver.resolve(CoachFollowUpHintInput(
    gameStage: GameStage.opening, heatScore: 30, recentMessageBodies: ['你好'], ...));
  expect(r, isNull);
});

test('hint resolver matches GameStage.close enum, not 繁中 label', () {
  // explicit guard: '準備邀約' as a string must NOT trigger anything
  final r = CoachFollowUpHintResolver.resolve(CoachFollowUpHintInput(
    gameStage: null, heatScore: 70, recentMessageBodies: ['準備邀約'], ...));
  // resolver should NOT match this as gameStage signal
  expect(r, isNot(CoachFollowUpPhase.prepareInvite));
});
```

**Step 3: Implement** — top-down rule cascade matching design §5 table. Keywords stored as constants.

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T16 — CoachFollowUpHintResolver pure function（GameStage.close enum，不用繁中字串）"
```

---

### Task C17: API service (Edge HTTP client)

**Files:**
- Create: `lib/features/coach_follow_up/data/services/coach_follow_up_api_service.dart`
- Create: corresponding test

**Step 1: Write failing tests** (mock `http.Client`):

```dart
test('builds request with stable phase key', () async { /* assert body.phase == 'prepareInvite' */ });
test('omits lastConversationSummary when Spec 3 flagged', () async {
  // Pass isFlagged=true → assert payload.partnerHint.lastConversationSummary is absent
});
test('400 invalid_input_for_mode surfaces as ApiException', () async { /* ... */ });
test('429 surfaces as QuotaExceededException', () async { /* ... */ });
test('5xx surfaces as GenerationFailedException', () async { /* ... */ });
test('parses success response into CoachFollowUpResult', () async { /* ... */ });
test('rejects response with null boundaryReminder', () async { /* ... */ });
```

**Step 2-4:** Implement service. Use `SupabaseService.client.functions.invoke('coach-follow-up', body: ...)` (matches existing pattern for `analyze-chat`, `delete-account`). Parse response, validate `boundaryReminder` non-null, hard-truncate strings, construct `CoachFollowUpResult` (with `partnerId` and `phase` injected client-side).

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T17 — CoachFollowUpApiService（Spec 3 flagged omit + boundaryReminder client-side guard）"
```

---

### Task C18: Riverpod providers + state controller

**Files:**
- Create: `lib/features/coach_follow_up/data/providers/coach_follow_up_providers.dart`

Providers:
- `coachFollowUpRepositoryProvider` — Repository (singleton)
- `coachFollowUpResultProvider(partnerId)` — current stored result
- `coachFollowUpHintProvider(partnerId)` — derives `CoachFollowUpHintInput` from existing partner state, calls resolver
- `coachFollowUpControllerProvider(partnerId)` — `AsyncNotifier` managing generate / regenerate / phase-switch + debounce + persistence after success

**Steps 1-5:** Standard Riverpod pattern; tests assert generate flow, debounce blocks 2nd call, regenerate overwrites box, error states don't persist.

**Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T18 — Riverpod providers + AsyncNotifier controller（debounce + persist on success）"
```

---

### Task C19: Result card widget

**Files:**
- Create: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_result_card.dart`
- Create: widget test

**Step 1: Write widget tests** for each field rendering, including:
- `boundaryReminder` always shown (required, never null)
- `suggestedLine` hidden when null
- `headline` displayed bold without label
- UI labels match design §1.3 table (我看到的重點 / 這次建議你做 / 可以這樣說 / 邊界提醒)
- Card renders the **stored** `CoachFollowUpResult.phase` enum's `displayLabel` in header

**Step 2-5:** Build widget. Reuse Spec 4's `CoachActionCard` visual style for consistency.

**Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T19 — CoachFollowUpResultCard 5-field widget"
```

---

### Task C20: Phase chip row + AI hint

**Files:**
- Create: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_chip_row.dart`
- Create: widget test

Behavior:
- 3 chips always visible (use `CoachFollowUpPhase.values` order).
- AI hint (if present) renders as a small text line below chips (e.g., 💡 看起來你最近聊到見面，可以試「約會前提醒」).
- Highlighted chip is purely visual; user can still tap any chip.
- "生成會使用 1 則額度" caption always visible.
- Telemetry: tap fires `coach_follow_up_phase_switched` (client event).

**Steps 1-5** standard. **Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T20 — phase chip row + AI hint + 生成額度文字"
```

---

### Task C21: Input sheet (3 phase variants)

**Files:**
- Create: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart`
- Create: widget test

Implements design §1.2 input flows. Required fields enforce button-disabled until all answered. Free-text Q3 limited to 80 chars by `TextField.maxLength`. "產生跟進建議" button disabled while controller is in loading state (debounce).

**Important**: All option values stored as **stable English keys** internally (e.g., `'fuzzy' / 'concrete' / 'undecided'` for prepareInvite Q1), with Chinese labels rendered for the user. The Edge function receives the stable keys.

```dart
const _Q1_OPTIONS_PREPARE_INVITE = [
  ('fuzzy',     '模糊邀約（看看她要不要）'),
  ('concrete',  '具體邀約（時間 + 活動都明確）'),
  ('undecided', '還沒想好'),
];
const _Q2_OPTIONS_POST_DATE = [
  ('proactive',     '有（主動找下一次 / 主動延續話題）'),
  ('polite',        '還在禮貌回應'),
  ('cooling',       '變慢或變淡'),
  ('stillUnclear',  '還看不出來（剛結束 / 訊息還沒回 / 太早判斷不出）'),
];
```

**Steps 1-5.** **Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T21 — phase input sheet（stable English option keys + 中文 label 分離）"
```

---

### Task C22: Section widget + insert into partner detail

**Files:**
- Create: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart` (insert between traits card and conversations list per design §1.1 ordering)
- Create: widget test

`CoachFollowUpSection` consumes `coachFollowUpResultProvider` + `coachFollowUpHintProvider`. Renders default-state (chip row + caption) when no result, with-result state (result card + 重新生成 / 換情境 buttons) when result exists. "重新生成" calls controller.regenerate (debounced); "換情境" returns to chip row + reopens input sheet on selection.

Telemetry: `coach_follow_up_invoked` on input sheet submit; `coach_follow_up_regenerated` on regenerate tap.

**Steps 1-5.** **Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T22 — CoachFollowUpSection 接上 partner_detail_screen"
```

> **Phase C complete — full feature live.**

---

## 7. Cross-Cutting Tasks

### Task X23: CI/CD deploy step

**Files:**
- Modify: `.github/workflows/deploy-edge-function.yml`

**Step 1:** Add a **separate** deploy line for `coach-follow-up`:

```yaml
- name: Deploy Edge Functions
  run: |
    supabase functions deploy analyze-chat --no-verify-jwt
    supabase functions deploy delete-account
    supabase functions deploy sync-subscription
    supabase functions deploy submit-feedback
    supabase functions deploy revenuecat-webhook --no-verify-jwt
    supabase functions deploy coach-follow-up                    # NEW: JWT-verified, NO --no-verify-jwt
```

**Hard rules**:
- **NEVER** consolidate into a `supabase functions deploy --all` (would strip analyze-chat's `--no-verify-jwt`).
- coach-follow-up explicitly OMITS `--no-verify-jwt` (it requires authenticated user to deduct credit).

**Step 2:** Push and verify GH Actions run completes for both functions.

**Step 3: Commit**

```bash
git commit -am "[chore] Spec 5 X23 — CI/CD deploy step for coach-follow-up（JWT-verified，獨立 line）"
```

---

### Task X24: Telemetry verification on staging

After deploy, run a manual end-to-end pass and verify the 5 telemetry events appear in Supabase Edge logs:

- `coach_follow_up_invoked` (Edge logs on receive)
- `coach_follow_up_succeeded` (Edge logs on 200)
- `coach_follow_up_failed` (Edge logs on any 4xx/5xx with errorClass enum)
- `coach_follow_up_regenerated` (client log; needs separate Flutter telemetry hook)
- `coach_follow_up_phase_switched` (client log)

Verify **none** of the events contain free-text answers (q3), prompt full text, or Claude raw response. If any violation found → block merge.

---

### Task X25: TF smoke + close Phase 1 v1

Eric runs on TestFlight:
1. New partner → tap 教練跟進 → 3 chips visible → AI hint absent (clean state).
2. Add a conversation containing 「明天見面」 → re-enter partner detail → AI hint highlights `preDateReminder`.
3. Tap 約會前提醒 → fill answers → 產生 → result card renders 5 fields including required `boundaryReminder`.
4. Tap 重新生成 → second card overwrites first; `monthly_messages_used` += 2 from start.
5. Tap 換情境 → return to chip row → tap 約會後復盤 → fill including `stillUnclear` Q2 → result card renders.
6. Force tier cap (test account in Free with cap 30, generate until 429) → paywall sheet shown.
7. Force network failure (airplane mode) → 「生成失敗，credit 未扣，請再試」 → `monthly_messages_used` unchanged.
8. Delete partner → re-enter via partner picker → `coach_follow_up_results` for that partner gone (no carryover).
9. Sign out → sign in → `coach_follow_up_results` cleared.

If all pass → ADR + snapshot update (post-ship doc closeout, separate commit).

---

## 8. Out of Scope (v1 — explicit DO NOT)

(Mirrors design §8 — repeated here so implementers don't drift.)

- ❌ Push notification / 主動 nudge / dormant reminder
- ❌ Intimacy aftercare / short-term maintenance / fit reflection (draft 5D/E/F)
- ❌ Chatbot 多輪 / 在 result card 上追問
- ❌ 結果卡歷史列表 / 跨 partner 比較
- ❌ Learning tab deep link
- ❌ 寫入 partnerTraits / partnerSummary / about-me / partner override / 任何 long-term memory
- ❌ 接受截圖 input (`images` field rejected by validator)
- ❌ 跨 partner aggregate
- ❌ Calendar integration
- ❌ 同 partner 多 phase 結果並存
- ❌ 第 4 個 phase「她回覆變慢」(Q-Eric-2 deferred to v2)
- ❌ Importing anything from `supabase/functions/analyze-chat/`
- ❌ Editing `analyze-chat/` source files (OCR baseline frozen)
- ❌ Using 繁中 strings as enum / phase / gameStage matching keys

---

## 9. Validation Checklist (Before Each Phase Merge)

### Before Phase A merge
- [ ] `deno test supabase/functions/coach-follow-up/` all green
- [ ] No imports from `analyze-chat/` (verify: `grep -r "from.*analyze-chat" supabase/functions/coach-follow-up/`)
- [ ] Curl smoke: 200 success, 400 image rejection, 401 unauthenticated, 429 cap exceeded
- [ ] Boundary check: response with null `boundaryReminder` → 5xx + credit not deducted
- [ ] No free-text or prompt content in any log line

### Before Phase B merge
- [ ] `flutter test test/unit/features/coach_follow_up/` all green
- [ ] `flutter analyze` clean
- [ ] `dart run build_runner build` re-run; no orphan `.g.dart` files
- [ ] `clearAll()` regression test passes (mirror Spec 1)
- [ ] Partner-delete cascade test passes
- [ ] No imports from analysis / partnerSummary / about_me writes

### Before Phase C merge
- [ ] `flutter test test/widget/features/coach_follow_up/` all green
- [ ] All option values are stable English keys (not 繁中) — `grep "options.*中文"` audit
- [ ] Hint resolver test asserts `GameStage.close` enum (not '邀約' / '準備邀約' string)
- [ ] Result card always renders `boundaryReminder` (required field)
- [ ] "生成會使用 1 則額度" caption present at every credit-spending entry point
- [ ] `flutter test --coverage` baseline maintained

### Before Phase X merge
- [ ] CI/CD: analyze-chat still deploys with `--no-verify-jwt`
- [ ] CI/CD: coach-follow-up deploys WITHOUT `--no-verify-jwt`
- [ ] Telemetry events all 5 verified in staging logs
- [ ] TF smoke passes all 9 scenarios

---

## 10. Codex Amendments Log

(Empty — populated after Codex spec review of this plan.)

---

## 11. References

- **Design (binding)**: `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `a66ca5b`
- **Design Codex review**: `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md`
- **Pattern reference (cost machinery)**: `supabase/functions/analyze-chat/index.ts:3296-3736` (DO NOT IMPORT)
- **Pattern reference (Hive box repo)**: `lib/features/user_profile/data/repositories/partner_style_repository.dart`, `partner_data_quality_repository.dart`
- **Account-clear hooks**: `lib/core/services/supabase_service.dart:157-220`
- **Partner detail insertion site**: `lib/features/partner/presentation/screens/partner_detail_screen.dart`
- **Hive typeId map**: `lib/hive_registrar.g.dart` (typeIds 0-15 used; 16 is next free)
- **GameStage enum stable keys**: `lib/features/analysis/domain/entities/game_stage.dart`
- **CI/CD workflow**: `.github/workflows/deploy-edge-function.yml`
- **CLAUDE.md hard rules**: OCR isolation, `CLAUDE_API_KEY` env var (not `ANTHROPIC_API_KEY`), `--no-verify-jwt` on analyze-chat only

---

## 12. Next Step (after this plan ACK'd)

1. **Codex** spec review on this plan → verdict in `docs/reviews/2026-05-02_spec5-coach-follow-up-impl-plan_codex-review.md`. Areas to scrutinize:
   - Cost machinery copy: did we miss any quota edge case from `analyze-chat:3296-3604`?
   - typeId 16 collision check
   - CI/CD deploy ordering
   - Phase boundary mergeability claim (Phase A ships standalone?)
2. **Eric** final read-through after Codex amendments applied.
3. Open worktree (per `superpowers:using-git-worktrees`) for the implementation branch.
4. Choose execution mode: subagent-driven (this session) or parallel session (separate).
5. Begin Phase A T1; commit + push every task per CLAUDE.md rule.

Plan does NOT begin code until Codex + Eric ACK.
