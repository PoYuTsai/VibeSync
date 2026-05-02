# Spec 5 — Coach Follow-up v1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Status:** Revision 1 — applied Codex NEEDS-FIX amendments. Awaiting Codex re-review verdict before coding.
> **Source:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `a66ca5b` (REVISED_AND_APPROVED).
> **Codex reviews:**
> - Design review: `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` @ `3d8dd3a`
> - Plan review (Rev 0): `docs/reviews/2026-05-02_spec5-coach-follow-up-impl-plan_codex-review.md` @ `146b8e3` — verdict NEEDS-FIX, all 7 items addressed in this revision
> **Authors:** Claude (draft) → Codex (plan review) → Claude (revision) → Eric (final ACK)

**Goal:** Ship Coach Follow-up v1 — three user-triggered phases (`prepareInvite` / `preDateReminder` / `postDateReflection`) rendered as a single 5-field result card on the partner detail screen, powered by an **independent** `coach-follow-up` Supabase Edge Function with its own prompt builder, schema, validator (incl. response-level banned-token enforcement), telemetry, and CI/CD deploy step. Latest result is persisted in a dedicated local Hive box wired into `StorageService.clearAll()`; each successful generation costs 1 message credit.

**Architecture:**

1. **Backend** — New independent Edge Function `supabase/functions/coach-follow-up/` (sibling to `analyze-chat`, **NOT** a sub-mode). Files: `index.ts` / `prompts.ts` / `schemas.ts` / `validate.ts` / `logger.ts` / `README.md` + tests. **Zero imports** from `analyze-chat`. JWT-verified (default), rejects `images`. Cost = 1 credit, deducted only after **both** schema validation AND product red-line vocabulary validation pass. Quota gate covers the full edge-case matrix from `analyze-chat:3296-3604` (subscription self-heal, daily/monthly reset, test account skip, RevenueCat tier refresh, unknown tier fallback).
2. **Local data** — New Hive entity `CoachFollowUpResult` (typeId 16), repo `CoachFollowUpRepository` (CRUD + `clearAll()`), wired into `StorageService.clearAll()` (the existing privacy seam used by `SettingsScreen.deleteAccount` flow), and into partner-delete cascade. Privacy regression added to `test/unit/services/storage_service_clear_all_test.dart` (mirroring the existing test, not a parallel file).
3. **UI** — New `CoachFollowUpSection` widget inserted into `partner_detail_screen.dart` between `PartnerTraitsCard` and conversations list. Three phase chips (always visible, AI hint highlights one based on stable enum keys via pure-Dart resolver). `partnerHint.lastConversationSummary` is built by a dedicated tested helper that reads ONLY the current conversation's `ConversationSummary.content` (capped at 200 chars, omitted when Spec 3 flagged); it never touches `PartnerContextResolver`, partner traits, or raw messages.

**Tech Stack:** Deno + TypeScript (Edge), zod (request/response validation), Flutter 3 + Riverpod + Hive CE (client). Tests: Deno `Deno.test` (Edge), `flutter test` (unit + widget).

---

## 0. Open Questions (Eric must resolve before Phase B T13 lands)

| # | Question | Recommended | Why it matters |
|---|----------|-------------|----------------|
| OQ-Sign-1 | Should `signOut()` also clear `coach_follow_up_results` (and other local Hive boxes)? Currently `signOut()` does NOT clear any local data — only `deleteAccount` does. | **(a) Keep current behavior**: signOut does NOT clear local follow-up results. Matches existing semantics for Conversation / Partner / UserProfile boxes. | Changing sign-out semantics is a product behavior change that affects ALL local data, not just this feature. If Eric wants signOut to also clear, that's an independent product decision that should be its own ticket and span all boxes uniformly. |

If Eric picks (a), Phase B T13 wires `coach_follow_up_results` only into `StorageService.clearAll()` (called by the existing `deleteAccount` flow at `settings_screen.dart:686-688`). If Eric picks (b), a separate ticket changes sign-out semantics for ALL local boxes uniformly — that's out of Spec 5 scope.

---

## 1. Pre-Implementation Reading (REQUIRED before Task 1)

Before writing any code, the implementer must read these to internalize current contracts:

| File | Why |
|------|-----|
| `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` | The binding spec; this plan implements it byte-for-byte |
| `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` | Codex amendments that shaped the design — non-negotiable |
| `docs/reviews/2026-05-02_spec5-coach-follow-up-impl-plan_codex-review.md` | The 7 NEEDS-FIX items this revision addresses; understand each before touching the related task |
| `supabase/functions/analyze-chat/index.ts:3296-3604` | Subscription self-heal + daily/monthly cap check + reset + test-account skip + RevenueCat refresh + unknown tier fallback. **Copy minimal subset only**, do NOT import. The full edge-case matrix is enforced via tests (T7) |
| `supabase/functions/analyze-chat/index.ts:3606-3736` | Opener cost + deduct flow (cost gate before invoke, deduct after success). Pattern reference only |
| `supabase/functions/analyze-chat/logger.ts` | Local logger SHAPE reference; **DO NOT IMPORT**. Re-implement minimal helpers in `coach-follow-up/logger.ts` to preserve OCR baseline isolation |
| `lib/core/services/storage_service.dart:145-153` | `StorageService.clearAll()` is the privacy seam. T13 adds `coach_follow_up_results` box to this list |
| `lib/features/subscription/presentation/screens/settings_screen.dart:686-688` | The `deleteAccount → StorageService.clearAll() → clearLocalSessionAfterDeletion()` chain. Confirms StorageService is the right seam |
| `test/unit/services/storage_service_clear_all_test.dart` | Existing privacy regression test — T15 ADDS to this file (or mirrors its exact pattern), does NOT create parallel test |
| `test/unit/services/storage_service_partner_box_test.dart` | Existing Hive unit-test pattern (`Hive.init('./.dart_tool/test_hive_*')`, manual register, deleteFromDisk teardown). T12 mirrors this — **NOT** `Hive.initFlutter()` |
| `lib/features/user_profile/data/repositories/partner_style_repository.dart` | Reference repo pattern: Hive box open + CRUD + `clearAll()` |
| `lib/features/user_profile/data/repositories/partner_data_quality_repository.dart` | Same pattern, additional cascade delete reference |
| `lib/features/conversation/domain/entities/conversation.dart` + `conversation_summary.dart` | `Conversation.summaries: List<ConversationSummary>` — source for `lastConversationSummary` (latest summary's `.content`); needed by T17 helper |
| `lib/features/conversation/data/services/memory_service.dart` | How `ConversationSummary` is generated — verify shape so T17 helper consumes correctly |
| `lib/features/user_profile/data/providers/data_quality_flag_provider.dart` | `dataQualityFlagProvider(partnerId).isFlagged` — drives Spec 3 omit rule in T17 |
| `lib/features/analysis/domain/entities/game_stage.dart` | `GameStage` enum stable keys: `opening / premise / qualification / narrative / close`. **Hint resolver matches `GameStage.close`, NOT the 繁中 label '準備邀約'** |
| `lib/features/partner/domain/entities/partner.dart` | Partner entity is typeId=8; `Partner.id` is the key for new box |
| `lib/features/partner/presentation/screens/partner_detail_screen.dart` | Insertion point for `CoachFollowUpSection` widget |
| `lib/hive_registrar.g.dart` | Generated; re-run `dart run build_runner build --delete-conflicting-outputs` after adding new entity. Verify typeIds 0-15 currently used → 16 next free |
| `.github/workflows/deploy-edge-function.yml` | Add `coach-follow-up` deploy line in T9 (Phase A); **must NOT** use `--no-verify-jwt`; **must NOT** consolidate into a `deploy --all` step that strips analyze-chat's `--no-verify-jwt` |

**Stable-key discipline (Eric explicit constraint)**:
- `phase` everywhere = `prepareInvite` / `preDateReminder` / `postDateReflection` (enum `.name` serialization).
- `gameStage` matching uses `GameStage.close` enum, NOT `'邀約'` or `'準備邀約'` label strings.
- Telemetry event names = English snake_case (`coach_follow_up_*`).
- Input sheet option values = English keys (`fuzzy / concrete / undecided / proactive / polite / cooling / stillUnclear`...), not 繁中.
- Hive field stored values = enum `.name` strings (stable across rename refactors).

---

## 2. File Touch List (Concrete Paths)

### Create — Edge Function

```text
supabase/functions/coach-follow-up/
  index.ts
  prompts.ts
  schemas.ts
  validate.ts                         # request validate + truncateCard + assertCardSafe (banned-token)
  logger.ts                           # local copy of minimal log helpers (NO import from analyze-chat)
  README.md
  index_test.ts                       # request validation / response validation / image rejection / cost-on-success / quota edge matrix
  validate_test.ts                    # boundaryReminder required / truncation / banned-token rejection
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
      coach_follow_up_partner_hint_builder.dart   # NEW per Codex P2: builds partnerHint with Spec 3 omit + 200-char cap, ZERO PartnerContextResolver / traits / raw message access
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
    services/coach_follow_up_partner_hint_builder_test.dart    # NEW per Codex P2
  data/
    repositories/coach_follow_up_repository_impl_test.dart    # CRUD + clearAll + cascade (temp Hive path, NOT initFlutter)
    services/coach_follow_up_api_service_test.dart             # request shape, error mapping, debounce, banned-token client guard

test/widget/features/coach_follow_up/
  coach_follow_up_section_test.dart
  coach_follow_up_chip_row_test.dart
  coach_follow_up_input_sheet_test.dart
  coach_follow_up_result_card_test.dart
```

### Modify

```text
lib/core/services/storage_service.dart                                  # add coachFollowUpResultsBox open + clearAll() entry (per Codex P1 #2)
lib/features/partner/presentation/screens/partner_detail_screen.dart    # insert CoachFollowUpSection between traits card & conversations list
lib/features/partner/data/providers/partner_write_controller.dart       # cascade delete: when partner deleted → CoachFollowUpRepository.delete(partnerId)
lib/hive_registrar.g.dart                                                # regenerated after build_runner
test/unit/services/storage_service_clear_all_test.dart                  # add coach_follow_up_results to existing privacy regression (per Codex P1 #2 + P2 #6)
.github/workflows/deploy-edge-function.yml                              # add: supabase functions deploy coach-follow-up (in T9, Phase A — per Codex P1 #1)
```

### Out-of-scope (DO NOT touch)

```text
supabase/functions/analyze-chat/**                                # OCR baseline — zero edits this PR
lib/core/services/supabase_service.dart                            # NOT the cleanup seam — do NOT add CoachFollowUpRepository here
lib/features/analysis/**                                            # Spec 4 surface — zero edits
lib/features/learning/**                                            # v1 doesn't deep-link
lib/features/user_profile/data/repositories/partner_summary_*.dart  # NEVER write to partnerSummary
lib/features/about_me/**                                            # NEVER write to long-term memory
lib/features/analysis/data/services/partner_context_resolver.dart   # NEVER read for Edge payload (per Codex P2 #7)
```

---

## 3. Phase Plan (Commit Boundaries)

| Phase | Tasks | Outcome | Mergeable? |
|-------|-------|---------|------------|
| **A. Backend Edge function + CI deploy** | T1-T10 | `coach-follow-up` deployed to Supabase via CI; tested via curl | **Yes — CI deploy IS in this phase** (Codex P1 #1 fix) |
| **B. Local data layer** | T11-T16 | Repo + entity + StorageService wire + cascade + privacy regression in existing test file | Yes (no UI) |
| **C. UI surface** | T17-T24 | Hint helper + Section widget + input sheet + result card wired into partner detail | Yes (full feature live) |
| **X. Cross-cutting polish** | T25-T26 | Telemetry verify on staging + TF smoke 9 scenarios | Yes (final polish) |

Each task = one commit. Phase boundaries = natural PR breakpoints. Recommended: ship Phase A as standalone PR first (now genuinely deployable end-to-end), then B+C bundled, then X polish.

**Total: 26 tasks** (was 25; +1 for new T17 hint helper, CI deploy moved from X into A so net +1 not +2).

---

## 4. Phase A: Backend Edge Function + CI Deploy

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

**Step 2: Write README.md** documenting the function's contract: phase semantics, tone rules, boundary rules, banned-token list (copy from design §1.3 / §2.4 / §2.5).

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

**Step 1: Write failing test `validate_test.ts`** — all `assertRejects` calls **must** be `await`ed inside `async` test callbacks (Codex P1 #4 fix):

```typescript
import { assertEquals, assertRejects } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { validateRequest } from "./validate.ts";

Deno.test("rejects missing phase", async () => {
  await assertRejects(
    () => validateRequest({ answers: { q1: "x" } }),
    Error,
    "phase",
  );
});

Deno.test("rejects unknown phase", async () => {
  await assertRejects(
    () => validateRequest({ phase: "invalid", answers: { q1: "x" } }),
    Error,
    "phase",
  );
});

Deno.test("rejects images field (v1 prohibited)", async () => {
  await assertRejects(
    () => validateRequest({ phase: "prepareInvite", answers: { q1: "x" }, images: [] }),
    Error,
    "invalid_input_for_mode",
  );
});

Deno.test("rejects q3 over 80 chars", async () => {
  await assertRejects(
    () => validateRequest({ phase: "prepareInvite", answers: { q1: "x", q3: "a".repeat(81) } }),
    Error,
    "q3",
  );
});

Deno.test("rejects lastConversationSummary over 200 chars", async () => {
  await assertRejects(
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
// validate.ts (subset — full file expanded in T3)
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

### Task A3: Truncation + boundaryReminder enforcement + banned-token validator

**Files:**
- Modify: `supabase/functions/coach-follow-up/validate.ts`
- Modify: `supabase/functions/coach-follow-up/validate_test.ts`

**Step 1: Add failing tests** (all `assertRejects` async/await per Codex P1 #4):

```typescript
Deno.test("truncateCard caps headline to 30 chars", () => {
  const r = truncateCard({
    headline: "a".repeat(50), observation: "x", task: "y", boundaryReminder: "z",
  });
  assertEquals(r.headline.length, 30);
});

Deno.test("truncateCard caps boundaryReminder to 60 chars", () => {
  const r = truncateCard({
    headline: "a", observation: "x", task: "y", boundaryReminder: "b".repeat(100),
  });
  assertEquals(r.boundaryReminder.length, 60);
});

Deno.test("validateFullResponse fails when boundaryReminder is null", async () => {
  await assertRejects(
    () => Promise.resolve(validateFullResponse({
      phase: "prepareInvite",
      card: { headline: "h", observation: "o", task: "t", boundaryReminder: null },
      model: "m", generatedAt: "g",
    })),
    Error,
    "boundaryReminder",
  );
});

Deno.test("validateFullResponse fails when boundaryReminder is missing", async () => {
  await assertRejects(
    () => Promise.resolve(validateFullResponse({
      phase: "prepareInvite",
      card: { headline: "h", observation: "o", task: "t" },
      model: "m", generatedAt: "g",
    })),
    Error,
    "boundaryReminder",
  );
});

// Codex P1 #5 — banned-token validation at response level
Deno.test("assertCardSafe rejects card containing PUA", () => {
  assertThrows(() => assertCardSafe({
    headline: "教你 PUA 技巧", observation: "o", task: "t", boundaryReminder: "b",
  }), Error, "banned_token");
});

Deno.test("assertCardSafe rejects 收割 in observation", () => {
  assertThrows(() => assertCardSafe({
    headline: "h", observation: "她準備被收割", task: "t", boundaryReminder: "b",
  }), Error, "banned_token");
});

Deno.test.each([
  "PUA", "收割", "控住", "攻略", "壞女人", "高分妹", "玩咖",
])("assertCardSafe rejects banned token: %s", (token) => {
  assertThrows(() => assertCardSafe({
    headline: token, observation: "o", task: "t", boundaryReminder: "b",
  }), Error, "banned_token");
});

Deno.test("assertCardSafe accepts clean card", () => {
  assertCardSafe({
    headline: "節奏優先", observation: "她的回應穩定", task: "今晚先不傳", boundaryReminder: "別承諾你做不到的",
  });  // does not throw
});
```

**Step 2: Run** — fails.

**Step 3: Implement** in `validate.ts`:

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

// Codex P1 #5 — product red-line vocabulary enforced at response level
const BANNED_TOKENS = ["PUA", "收割", "控住", "攻略", "壞女人", "高分妹", "玩咖"] as const;
const VISIBLE_FIELDS = ["headline", "observation", "task", "suggestedLine", "boundaryReminder"] as const;

export function assertCardSafe(card: Record<string, string | null | undefined>): void {
  for (const field of VISIBLE_FIELDS) {
    const value = card[field];
    if (typeof value !== "string") continue;
    for (const token of BANNED_TOKENS) {
      if (value.includes(token)) {
        throw new Error(`banned_token: ${token} found in ${field}`);
      }
    }
  }
}
```

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T3 — truncateCard + boundaryReminder hard-required + assertCardSafe banned-token validator (Codex P1 #5)"
```

---

### Task A4: Phase-specific prompt builder

**Files:**
- Create: `supabase/functions/coach-follow-up/prompts.ts`
- Create: `supabase/functions/coach-follow-up/prompts_test.ts`

**Step 1: Write failing tests** (synchronous; no `assertRejects` here):

```typescript
Deno.test("prepareInvite prompt includes phase + boundary instruction", () => {
  const p = buildCoachFollowUpPrompt("prepareInvite", { q1: "fuzzy" }, { name: "C" });
  assertStringIncludes(p, "準備邀約");
  assertStringIncludes(p, "boundaryReminder");
  assertStringIncludes(p, "≤ 60");
});

Deno.test("preDateReminder prompt does NOT mention partner name in inference instructions", () => {
  const p = buildCoachFollowUpPrompt("preDateReminder", { q1: "今天" }, { name: "Candy" });
  assertEquals(p.includes("根據對方名字"), false);
});

Deno.test("postDateReflection includes 還看不出來 handling", () => {
  const p = buildCoachFollowUpPrompt("postDateReflection", { q1: "卡卡的", q2: "stillUnclear" }, { name: "X" });
  assertStringIncludes(p, "太早判斷");
});

Deno.test("partnerHint.lastConversationSummary appears verbatim when provided", () => {
  const p = buildCoachFollowUpPrompt("preDateReminder", { q1: "明天" }, {
    name: "X", lastConversationSummary: "對話氣氛輕鬆，最近聊到週末有空",
  });
  assertStringIncludes(p, "對話氣氛輕鬆");
});

Deno.test("prompt forbids 物化 vocabulary list", () => {
  const p = buildCoachFollowUpPrompt("prepareInvite", { q1: "fuzzy" }, { name: "X" });
  assertStringIncludes(p, "收割");
  assertStringIncludes(p, "PUA");
});
```

**Step 2: Run** — fails.

**Step 3: Implement `prompts.ts`** (length: ~120 lines). Note: prompt-level guardrails are still needed (defense in depth), but the **enforcement** lives in T3's `assertCardSafe` (Codex P1 #5). Both layers together = belt + suspenders.

```typescript
const SYSTEM_PROMPT_BASE = `
你是 VibeSync 的「教練跟進」AI。任務：根據用戶選擇的 phase 與少量 context，產生一張結構化的跟進建議卡。

[硬規則]
- 絕不教用戶裝冷淡 / 用話術逃避責任 / 用承諾綁住對方。
- 絕不出現以下字眼：收割 / 控住 / 壞女人 / 玩咖 / 高分妹 / 攻略 / PUA。
  (此規則同時由 server validator 強制；含這些字眼的回應會被拒絕、用戶不被扣額度。)
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
git commit -am "[feat] Spec 5 Phase A T4 — phase-specific prompt builder（boundaryReminder required + 物化字眼黑名單；validator 也擋）"
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

### Task A6: index.ts — auth + quota gate (full edge-case matrix)

**Files:**
- Modify: `supabase/functions/coach-follow-up/index.ts`
- Modify: `supabase/functions/coach-follow-up/index_test.ts` (create)

**Step 1: Write failing tests** covering the **full quota edge-case matrix** from `analyze-chat:3370-3565` (Codex P1 #3 fix). Each `assertRejects` is async/awaited (Codex P1 #4):

```typescript
// Auth + input validation
Deno.test("POST without auth returns 401", async () => { /* fetch with no Authorization */ });
Deno.test("POST with invalid phase returns 400", async () => { /* ... */ });
Deno.test("POST with images returns 400 invalid_input_for_mode", async () => { /* ... */ });

// Quota self-heal & resets (Codex P1 #3)
Deno.test("missing subscription row self-heals to free tier and proceeds", async () => {
  // Pre-condition: subscriptions has no row for user.id
  // Expectation: a row is inserted with tier=free, monthly_messages_used=0, daily_messages_used=0,
  //              and the request continues into quota gate (NOT 403)
});

Deno.test("daily reset triggers when daily_reset_at is yesterday", async () => {
  // Pre-condition: sub.daily_reset_at = yesterday, sub.daily_messages_used = dailyLimit
  // Expectation: counter is reset to 0 BEFORE cap evaluation; request proceeds
});

Deno.test("monthly reset triggers when monthly_reset_at is last month", async () => {
  // Same shape as above, monthly window
});

// Cap behavior
Deno.test("POST when monthly cap reached → 429 (after RC refresh attempted)", async () => { /* ... */ });
Deno.test("POST when daily cap reached → 429 (after RC refresh attempted)", async () => { /* ... */ });

// RevenueCat refresh path
Deno.test("RevenueCat tier refresh on monthly cap exceeded → if upgraded, request proceeds", async () => {
  // Pre-condition: sub.tier=free, monthly_messages_used >= 30
  // Mock: RC refresh returns essential tier (limit 800)
  // Expectation: request proceeds, NOT 429
});

Deno.test("RevenueCat tier refresh on daily cap exceeded → if upgraded, request proceeds", async () => { /* ... */ });

// Test account bypass (Codex P1 #3)
Deno.test("test account email skips quota gate entirely", async () => {
  // Pre-condition: user.email in TEST_EMAILS list (vibesync.test@gmail.com)
  // Expectation: cap check is bypassed even when monthly_messages_used >> limit
});

// Unknown / null tier fallback (Codex P1 #3)
Deno.test("unknown tier value falls back to free limits", async () => {
  // Pre-condition: sub.tier = 'mystery_tier'
  // Expectation: monthlyLimit = TIER_MONTHLY_LIMITS.free, dailyLimit = TIER_DAILY_LIMITS.free
});

Deno.test("null tier falls back to free limits", async () => { /* ... */ });
```

**Step 2: Run** — fails.

**Step 3: Implement** the auth + cap check in `index.ts`. Inline (do NOT import) a minimal subscription self-heal + reset + RC refresh + test-account skip + unknown-tier fallback. Pattern mirrors `analyze-chat/index.ts:3370-3565` but **adapt** for cost = 1.

```typescript
// Pseudocode shape; full implementation copies the minimum subset needed AND mirrors the analyze-chat tests.
serve(async (req) => {
  if (req.method !== "POST") return notImplemented();

  const auth = req.headers.get("Authorization");
  if (!auth) return jsonResponse({ error: "unauthorized" }, 401);

  const { user } = await getAuthenticatedUser(auth);
  if (!user) return jsonResponse({ error: "unauthorized" }, 401);

  let payload;
  try {
    payload = await validateRequest(await req.json());
  } catch (e) {
    return jsonResponse({ error: getErrorMessage(e) }, 400);
  }

  // Test account bypass
  const accountIsTest = TEST_EMAILS.includes(user.email || "");

  // Subscription self-heal
  let sub = await fetchSubscription(user.id);
  if (!sub) sub = await selfHealSubscription(user.id);
  if (!sub) return jsonResponse({ error: "No subscription found" }, 403);

  // Daily / monthly reset
  sub = await applyDailyResetIfNeeded(sub);
  sub = await applyMonthlyResetIfNeeded(sub);

  // Tier resolution with unknown fallback
  const tier = sub.tier && (sub.tier in TIER_MONTHLY_LIMITS) ? sub.tier : "free";
  const monthlyLimit = TIER_MONTHLY_LIMITS[tier];
  const dailyLimit = TIER_DAILY_LIMITS[tier];

  // Cap check (test account bypass)
  const cost = 1;
  if (!accountIsTest) {
    if (sub.monthly_messages_used + cost > monthlyLimit ||
        sub.daily_messages_used + cost > dailyLimit) {
      // RevenueCat refresh attempt before 429
      const refreshed = await maybeRefreshSubscriptionTierFromRevenueCat(user.id);
      if (refreshed) {
        sub = await fetchSubscription(user.id);
        // Re-evaluate against refreshed tier
        if (sub.monthly_messages_used + cost > TIER_MONTHLY_LIMITS[sub.tier] ||
            sub.daily_messages_used + cost > TIER_DAILY_LIMITS[sub.tier]) {
          return jsonResponse({ error: "額度不足", quotaNeeded: cost }, 429);
        }
      } else {
        return jsonResponse({ error: "額度不足", quotaNeeded: cost }, 429);
      }
    }
  }

  // ... T7 will add Claude call + post-validation deduct using the SAME sub object
  return jsonResponse({ error: "not_implemented" }, 501);
});
```

**Important**: the deduct in T7 must use the **same `sub` object** updated by the gate (already-applied resets), so counters don't drift.

**Step 4: Run** — failure-path + edge-case tests pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T6 — auth + quota gate with full edge-case matrix（self-heal / resets / test account / RC refresh / unknown tier fallback）— Codex P1 #3"
```

---

### Task A7: Claude API invocation + response validation + safety check + credit deduct

**Files:**
- Modify: `supabase/functions/coach-follow-up/index.ts`
- Modify: `supabase/functions/coach-follow-up/index_test.ts`

**Step 1: Add failing tests** (mock Claude response; all `assertRejects` async/await per Codex P1 #4):

```typescript
Deno.test("successful generation deducts 1 credit", async () => { /* assert subscriptions.monthly_messages_used += 1 AND daily += 1 */ });
Deno.test("Claude returning card with null boundaryReminder → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("Claude returning card with missing boundaryReminder → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("Claude returning card containing 'PUA' → 5xx, credit NOT deducted (Codex P1 #5)", async () => {
  // Mock Claude returning {headline:'h', observation:'o', task:'t', boundaryReminder:'PUA話術'}
  // Expectation: 500, error=banned_token, sub.monthly_messages_used unchanged
});
Deno.test("Claude returning card containing '收割' → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("Claude API timeout → 5xx, credit NOT deducted", async () => { /* ... */ });
Deno.test("over-cap headline (50 chars) → truncated to 30, credit deducted", async () => { /* ... */ });
Deno.test("test account success deducts NOTHING (cap bypass)", async () => {
  // Pre-condition: user.email in TEST_EMAILS
  // Expectation: monthly_messages_used unchanged after success
});
```

**Step 2: Run** — fails.

**Step 3: Implement** the Claude call path. **Critical sequence**: validate shape → assertCardSafe (banned tokens) → deduct credit → return. If any step fails, NO deduct.

```typescript
const apiKey = Deno.env.get("CLAUDE_API_KEY");  // NOT ANTHROPIC_API_KEY (CLAUDE.md pitfall)
if (!apiKey) return jsonResponse({ error: "config_missing" }, 500);

const model = tier === "free"
  ? "claude-haiku-4-5-20251001"
  : "claude-sonnet-4-20250514";

const prompt = buildCoachFollowUpPrompt(payload.phase, payload.answers, payload.partnerHint);

logInfo("coach_follow_up_invoked", {
  phase: payload.phase, tier,
  hasOptionalText: !!(payload.answers.q3 && payload.answers.q3.length > 0),
});

let claudeData;
const startedAt = Date.now();
try {
  claudeData = await callClaudeAPI({ model, prompt, max_tokens: 1024, timeout: 60000 });
} catch (e) {
  logWarn("coach_follow_up_failed", { phase: payload.phase, tier, errorClass: classifyError(e) });
  return jsonResponse({ error: `AI 生成失敗：${getErrorMessage(e)}` }, 500);
}

let card;
try {
  const parsed = parseClaudeJSON(claudeData);
  card = truncateCard(parsed);
  validateResponseCard(card);             // throws on missing/null boundaryReminder
  assertCardSafe(card);                    // throws on banned tokens (Codex P1 #5)
} catch (e) {
  const errorClass = e.message.startsWith("banned_token") ? "banned_token" : "schema_invalid";
  logWarn("coach_follow_up_failed", { phase: payload.phase, tier, errorClass });
  return jsonResponse({ error: errorClass }, 500);
}

// Deduct ONLY after BOTH schema and safety validation pass — and ONLY if not test account
if (!accountIsTest) {
  await supabase.from("subscriptions").update({
    monthly_messages_used: (sub.monthly_messages_used || 0) + 1,
    daily_messages_used: (sub.daily_messages_used || 0) + 1,
  }).eq("user_id", user.id);
}

logInfo("coach_follow_up_succeeded", {
  phase: payload.phase, tier, model,
  latencyMs: Date.now() - startedAt,
  costDeducted: accountIsTest ? 0 : 1,
});

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
git commit -am "[feat] Spec 5 Phase A T7 — Claude call + boundaryReminder + assertCardSafe + credit deduct on success only（test account bypass）"
```

---

### Task A8: Telemetry events full coverage

**Files:**
- Modify: `supabase/functions/coach-follow-up/index.ts`
- Modify: `supabase/functions/coach-follow-up/index_test.ts`

Verify all server-side telemetry events from design §7 fire correctly:

```text
coach_follow_up_invoked       { phase, tier, hasOptionalText: bool }
coach_follow_up_succeeded     { phase, tier, model, latencyMs, costDeducted: 0|1 }
coach_follow_up_failed        { phase, tier, errorClass }     // errorClass enum, NOT errorMessage / NOT free-text
```

Client-side `regenerated` and `phase_switched` are deferred to Phase C T22/T24.

**Step 1: Add tests** capturing stdout/stderr; assert event names + fields shape; assert NO free-text answers, NO prompt content, NO Claude raw response in any log line.

**Step 2-4: Implement, run, verify.**

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase A T8 — telemetry events 全覆蓋（不 log free-text / prompt 全文 / AI 原始 response）"
```

---

### Task A9: CI/CD deploy step (moved into Phase A per Codex P1 #1)

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
- This task lands BEFORE A10 manual smoke so the production deploy path is what's verified end-to-end.

**Step 2:** Push and verify GH Actions run completes for both `analyze-chat` (still with `--no-verify-jwt`) and `coach-follow-up` (without).

**Step 3: Commit**

```bash
git commit -am "[chore] Spec 5 Phase A T9 — CI/CD deploy step for coach-follow-up（JWT-verified，獨立 line；移進 Phase A 才能 standalone merge — Codex P1 #1）"
```

---

### Task A10: Edge function manual smoke + production deploy verification

**Step 1: Local Deno test full pass** — `deno test supabase/functions/coach-follow-up/` all green.

**Step 2: Verify CI deploy on staging** completed successfully (from T9's push) — function visible at `https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/coach-follow-up`.

**Step 3: Curl smoke** with a real JWT:

```bash
curl -X POST https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/coach-follow-up \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"phase":"prepareInvite","answers":{"q1":"fuzzy"},"partnerHint":{"name":"Test"}}'
```

Expected: 200 with valid card JSON; cost deducted; logs show `coach_follow_up_invoked` then `coach_follow_up_succeeded`.

**Step 4: Negative smoke**:
- `images: []` → 400 `invalid_input_for_mode`.
- Send Claude a mocked response with `boundaryReminder: null` (via test fixture or skip if not feasible) → 5xx, credit unchanged.
- Send Claude a mocked banned-token response → 5xx, credit unchanged.

**Step 5: Commit + push** (no code changes; just `[docs]` confirmation if needed).

> **Phase A complete — backend is genuinely standalone-mergeable: function + CI deploy + smoke all in one phase.**

---

## 5. Phase B: Local Data Layer

### Task B11: `CoachFollowUpPhase` enum

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
git commit -am "[feat] Spec 5 Phase B T11 — CoachFollowUpPhase enum（stable .name keys + display label 分離）"
```

---

### Task B12: `CoachFollowUpResult` Hive entity (typeId 16)

**Files:**
- Create: `lib/features/coach_follow_up/domain/entities/coach_follow_up_result.dart`

**Step 1: Verify next free typeId is 16** by greping `@HiveType(typeId:` (current top: 15 = `partner_data_quality_state`). If a subsequent PR has claimed 16, escalate.

```bash
grep -rn "@HiveType(typeId:" lib/ | sort -t: -k4 -n -k2
```

**Step 2: Write entity**

```dart
@HiveType(typeId: 16)  // verified free at 2026-05-02; reserved here
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
git commit -m "[feat] Spec 5 Phase B T12 — CoachFollowUpResult Hive entity（typeId 16）"
```

---

### Task B13: `CoachFollowUpRepository` (interface + Hive impl) — temp Hive path tests (Codex P2 #6)

**Files:**
- Create: `lib/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart`
- Create: `lib/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl.dart`
- Create: `test/unit/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl_test.dart`

**Step 1: Write failing tests** mirroring `test/unit/services/storage_service_partner_box_test.dart` pattern — **temp Hive path, NOT `Hive.initFlutter()`** (Codex P2 #6 fix):

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  const testHivePath = './.dart_tool/test_hive_coach_follow_up_repo';
  const testBoxName = 'test_coach_follow_up_results';

  setUpAll(() {
    Hive.init(testHivePath);                                // NOT initFlutter
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(CoachFollowUpResultAdapter());
    }
  });

  late Box<CoachFollowUpResult> box;
  late CoachFollowUpRepositoryImpl repo;

  setUp(() async {
    box = await Hive.openBox<CoachFollowUpResult>(testBoxName);
    repo = CoachFollowUpRepositoryImpl(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('put + get returns latest', () async { /* ... */ });
  test('put twice for same partner overwrites (latest only)', () async { /* ... */ });
  test('delete removes entry', () async { /* ... */ });
  test('clearAll wipes box completely', () async { /* ... */ });
  test('get for unknown partnerId returns null', () async { /* ... */ });
}
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
git commit -am "[feat] Spec 5 Phase B T13 — CoachFollowUpRepository（CRUD + clearAll；temp Hive path test pattern — Codex P2 #6）"
```

---

### Task B14: Wire `coach_follow_up_results` into `StorageService.clearAll()` (Codex P1 #2)

**Files:**
- Modify: `lib/core/services/storage_service.dart`
- Modify: `test/unit/services/storage_service_clear_all_test.dart` (ADD to existing file, do NOT create parallel)

**Pre-condition**: Eric has resolved OQ-Sign-1 (§0). This task assumes recommended verdict (a) — sign-out does NOT clear local data; only `deleteAccount → StorageService.clearAll()` chain wipes follow-up results.

**Step 1: Add the new box constant + getter** in `storage_service.dart` (mirror `partnerStyleOverridesBox` pattern):

```dart
// In storage_service.dart, alongside other boxes:
static Box<CoachFollowUpResult> get coachFollowUpResultsBox =>
    Hive.box<CoachFollowUpResult>('coach_follow_up_results');

// In initialize() — register adapter and openBox alongside others:
Hive.registerAdapter(CoachFollowUpResultAdapter());
await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');

// In clearAll() — append to the existing list:
static Future<void> clearAll() async {
  await conversationsBox.clear();
  await partnersBox.clear();
  await userProfileBox.clear();
  await partnerStyleOverridesBox.clear();
  await partnerDataQualityStatesBox.clear();
  await coachFollowUpResultsBox.clear();   // NEW
  await settingsBox.clear();
  await usageBox.clear();
}
```

**Step 2: Add failing test in existing file `storage_service_clear_all_test.dart`** — extend the open-box list and assert the new box is also cleared:

```dart
// In existing setUp / openBox block (around lines 72-80):
await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');

// Add a new test asserting clearAll() empties the new box too:
test('clearAll wipes coach_follow_up_results box (Spec 5)', () async {
  final box = Hive.box<CoachFollowUpResult>('coach_follow_up_results');
  await box.put('partner-1', CoachFollowUpResult(/* fixture */));
  expect(box.length, 1);
  await StorageService.clearAll();
  expect(box.length, 0);
});
```

**Step 3: Run** — implement → pass.

**Step 4: Verify** existing tests in `storage_service_clear_all_test.dart` still pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase B T14 — coach_follow_up_results 接 StorageService.clearAll()（Codex P1 #2）"
```

---

### Task B15: Partner-delete cascade

**Files:**
- Modify: `lib/features/partner/data/providers/partner_write_controller.dart`
- Modify or create: cascade test

**Step 1: Locate partner-delete code** (CLAUDE.md Pitfall mentions guard logic at `partner_write_controller`).

**Step 2: Write failing test** asserting that deleting a partner with a stored follow-up result also clears it from the new box.

**Step 3: Wire `CoachFollowUpRepository.delete(partnerId)`** into the partner-delete path. Match existing pattern (e.g., how `PartnerStyleRepository` / `PartnerDataQualityRepository` cascade).

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase B T15 — partner delete cascade clears coach_follow_up_results entry"
```

---

### Task B16: Privacy regression test consolidation

**Files:**
- Verify: `test/unit/services/storage_service_clear_all_test.dart` (already extended in T14)
- Add: any missing fixture helpers

**Step 1: Verify the test added in T14** asserts:
- After populating box with N entries, `StorageService.clearAll()` empties it.
- After `deleteFromDisk()` (simulated account deletion path), box file is gone.

**Step 2: Add second test** for the integration: simulate the `SettingsScreen.deleteAccount` chain (`deleteAccount → clearAll → clearLocalSessionAfterDeletion`) by calling them in sequence and verify ALL boxes (existing + new) are empty.

**Step 3: Run full `flutter test test/unit/services/storage_service_clear_all_test.dart`** — all pass.

**Step 4: Commit**

```bash
git commit -am "[test] Spec 5 Phase B T16 — 隱私 regression 補完整 deleteAccount 鏈（鏡射既有 storage_service_clear_all_test pattern — Codex P2 #6）"
```

> **Phase B complete — local data layer self-tested via existing privacy seam.**

---

## 6. Phase C: UI Surface

### Task C17: `buildCoachFollowUpPartnerHint` source helper (Codex P2 #7)

**Files:**
- Create: `lib/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart`
- Create: `test/unit/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder_test.dart`

**Why this exists (Codex P2 #7)**: design Q3 says `lastConversationSummary` must be conversation-level only, ≤ 200 chars, omitted when Spec 3 flagged, and never sourced from `PartnerContextResolver` / partner traits / raw messages. Without an explicit helper, the implementer might accidentally pipe in cross-conversation aggregate or partner summary. This helper IS the contract.

**Step 1: Write failing tests** covering EACH constraint:

```dart
group('buildCoachFollowUpPartnerHint', () {
  test('uses ONLY current conversation latest summary content', () {
    final conv = Conversation(/* summaries: [s1(content:"old"), s2(content:"latest summary text")] */);
    final hint = buildCoachFollowUpPartnerHint(
      partner: Partner(name: 'C', /* ... */),
      currentConversation: conv,
      isDataQualityFlagged: false,
    );
    expect(hint.lastConversationSummary, equals('latest summary text'));
  });

  test('caps lastConversationSummary at 200 chars', () {
    final longSummary = 'a' * 300;
    final conv = Conversation(/* summaries: [Summary(content: longSummary)] */);
    final hint = buildCoachFollowUpPartnerHint(
      partner: Partner(name: 'C'), currentConversation: conv, isDataQualityFlagged: false,
    );
    expect(hint.lastConversationSummary?.length, equals(200));
  });

  test('returns null lastConversationSummary when conversation has no summaries', () {
    final conv = Conversation(/* summaries: [] */);
    final hint = buildCoachFollowUpPartnerHint(
      partner: Partner(name: 'C'), currentConversation: conv, isDataQualityFlagged: false,
    );
    expect(hint.lastConversationSummary, isNull);
  });

  test('returns null lastConversationSummary when no current conversation', () {
    final hint = buildCoachFollowUpPartnerHint(
      partner: Partner(name: 'C'), currentConversation: null, isDataQualityFlagged: false,
    );
    expect(hint.lastConversationSummary, isNull);
  });

  test('omits lastConversationSummary when Spec 3 flagged (Codex P2 #7)', () {
    final conv = Conversation(/* summaries: [Summary(content: "good content")] */);
    final hint = buildCoachFollowUpPartnerHint(
      partner: Partner(name: 'C'), currentConversation: conv, isDataQualityFlagged: true,
    );
    expect(hint.lastConversationSummary, isNull);
  });

  test('NEVER reads PartnerContextResolver, partnerSummary, partnerTraits, or raw messages', () {
    // Compile-time guard: helper signature accepts Conversation + Partner + bool only.
    // Runtime guard: this test asserts the function body does not import those modules.
    // Enforcement: code review + import-graph linter rule.
    // We add a static-analysis guard via grep in CI:
    //   grep -E "PartnerContextResolver|partnerSummary|partnerTraits" \
    //     lib/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart \
    //     | grep -v "^//"   # exclude comments
    //   should be empty.
  });

  test('hint includes partner.name (display only) and heatScore + gameStage if provided', () {
    /* ... */
  });
});
```

**Step 2: Implement** — pure function, no Riverpod, no async, no providers:

```dart
class CoachFollowUpPartnerHint {
  final String name;
  final int? heatScore;
  final GameStage? gameStage;
  final String? lastConversationSummary;
  const CoachFollowUpPartnerHint({...});

  Map<String, dynamic> toEdgePayload() => {
    'name': name,
    if (heatScore != null) 'heatScore': heatScore,
    if (gameStage != null) 'gameStage': gameStage!.name,    // stable enum key, not displayLabel
    if (lastConversationSummary != null) 'lastConversationSummary': lastConversationSummary,
  };
}

CoachFollowUpPartnerHint buildCoachFollowUpPartnerHint({
  required Partner partner,
  required Conversation? currentConversation,
  required bool isDataQualityFlagged,
  int? heatScore,
  GameStage? gameStage,
}) {
  String? summary;
  if (!isDataQualityFlagged && currentConversation != null) {
    final latest = currentConversation.summaries?.lastOrNull;
    if (latest != null && latest.content.isNotEmpty) {
      summary = latest.content.length > 200
          ? latest.content.substring(0, 200)
          : latest.content;
    }
  }
  return CoachFollowUpPartnerHint(
    name: partner.name,
    heatScore: heatScore,
    gameStage: gameStage,
    lastConversationSummary: summary,
  );
}
```

**Step 3: Run** — pass.

**Step 4: Add CI grep guard** (single-line check, can be a pre-commit hook or CI step) ensuring the file does not import `PartnerContextResolver`, `partnerSummary*`, `partnerTraits*`, or any raw message accessor. Document the guard in `coach_follow_up_partner_hint_builder.dart`'s top comment.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T17 — buildCoachFollowUpPartnerHint helper（conv-level summary ≤200 字 + Spec 3 omit + 0 PartnerContextResolver — Codex P2 #7）"
```

---

### Task C18: AI hint resolver (pure Dart)

**Files:**
- Create: `lib/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver.dart`
- Create: `test/unit/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver_test.dart`

**Step 1: Define input shape** — pure data class containing only stable enum/scalar values:

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
  expect(r, isNot(CoachFollowUpPhase.prepareInvite));
});
```

**Step 3: Implement** — top-down rule cascade matching design §5 table. Keywords stored as constants.

**Step 4: Run** — pass.

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T18 — CoachFollowUpHintResolver pure function（GameStage.close enum，不用繁中字串）"
```

---

### Task C19: API service (Edge HTTP client)

**Files:**
- Create: `lib/features/coach_follow_up/data/services/coach_follow_up_api_service.dart`
- Create: corresponding test

**Step 1: Write failing tests** (mock `http.Client` or Supabase functions invoke):

```dart
test('builds request with stable phase key', () async { /* assert body.phase == 'prepareInvite' */ });
test('uses partnerHint from buildCoachFollowUpPartnerHint helper', () async {
  // assert body.partnerHint matches the helper's toEdgePayload output exactly
});
test('400 invalid_input_for_mode surfaces as ApiException', () async { /* ... */ });
test('429 surfaces as QuotaExceededException', () async { /* ... */ });
test('5xx surfaces as GenerationFailedException', () async { /* ... */ });
test('parses success response into CoachFollowUpResult', () async { /* ... */ });
test('rejects response with null boundaryReminder (client-side guard)', () async { /* ... */ });
test('rejects response containing banned token (client-side guard)', () async {
  // Even though server should reject, client double-checks for defense in depth
});
```

**Step 2-4:** Implement service using `SupabaseService.client.functions.invoke('coach-follow-up', body: ...)`. The hint payload comes from T17 helper output (do NOT build inline). Parse response, validate `boundaryReminder` non-null AND `assertCardSafe` client-side, hard-truncate strings if needed, construct `CoachFollowUpResult` (with `partnerId` and `phase` injected client-side).

**Step 5: Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T19 — CoachFollowUpApiService（消費 hint helper + boundaryReminder + assertCardSafe client guard）"
```

---

### Task C20: Riverpod providers + state controller

**Files:**
- Create: `lib/features/coach_follow_up/data/providers/coach_follow_up_providers.dart`

Providers:
- `coachFollowUpRepositoryProvider` — Repository (singleton)
- `coachFollowUpResultProvider(partnerId)` — current stored result
- `coachFollowUpHintProvider(partnerId)` — derives `CoachFollowUpHintInput` from existing partner state, calls hint resolver
- `coachFollowUpPartnerHintProvider(partnerId)` — uses T17 helper, depends on current conversation + Spec 3 flag
- `coachFollowUpControllerProvider(partnerId)` — `AsyncNotifier` managing generate / regenerate / phase-switch + debounce + persistence after success

**Steps 1-5:** Standard Riverpod pattern; tests assert generate flow, debounce blocks 2nd call, regenerate overwrites box, error states don't persist.

**Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T20 — Riverpod providers + AsyncNotifier controller（debounce + persist on success）"
```

---

### Task C21: Result card widget

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
git commit -am "[feat] Spec 5 Phase C T21 — CoachFollowUpResultCard 5-field widget"
```

---

### Task C22: Phase chip row + AI hint

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
git commit -am "[feat] Spec 5 Phase C T22 — phase chip row + AI hint + 生成額度文字"
```

---

### Task C23: Input sheet (3 phase variants)

**Files:**
- Create: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart`
- Create: widget test

Implements design §1.2 input flows. Required fields enforce button-disabled until all answered. Free-text Q3 limited to 80 chars by `TextField.maxLength`. "產生跟進建議" button disabled while controller is in loading state (debounce).

**Important**: All option values stored as **stable English keys** internally, with Chinese labels rendered for the user. The Edge function receives the stable keys.

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
git commit -am "[feat] Spec 5 Phase C T23 — phase input sheet（stable English option keys + 中文 label 分離）"
```

---

### Task C24: Section widget + insert into partner detail

**Files:**
- Create: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart` (insert between traits card and conversations list per design §1.1 ordering)
- Create: widget test

`CoachFollowUpSection` consumes `coachFollowUpResultProvider` + `coachFollowUpHintProvider`. Renders default-state (chip row + caption) when no result, with-result state (result card + 重新生成 / 換情境 buttons) when result exists. "重新生成" calls controller.regenerate (debounced); "換情境" returns to chip row + reopens input sheet on selection.

Telemetry: `coach_follow_up_invoked` on input sheet submit; `coach_follow_up_regenerated` on regenerate tap.

**Steps 1-5.** **Commit**

```bash
git commit -am "[feat] Spec 5 Phase C T24 — CoachFollowUpSection 接上 partner_detail_screen"
```

> **Phase C complete — full feature live.**

---

## 7. Phase X: Cross-Cutting Polish

### Task X25: Telemetry verification on staging

After Phase A+B+C deploy, run a manual end-to-end pass and verify all telemetry events appear in Supabase Edge logs + Flutter console:

Server side:
- `coach_follow_up_invoked` (Edge logs on receive)
- `coach_follow_up_succeeded` (Edge logs on 200)
- `coach_follow_up_failed` (Edge logs on any 4xx/5xx with errorClass enum)

Client side:
- `coach_follow_up_regenerated`
- `coach_follow_up_phase_switched`

Verify **none** of the events contain free-text answers (q3), prompt full text, or Claude raw response. If any violation found → block merge.

---

### Task X26: TF smoke + close v1

Eric runs on TestFlight:
1. New partner → tap 教練跟進 → 3 chips visible → AI hint absent (clean state).
2. Add a conversation containing 「明天見面」 → re-enter partner detail → AI hint highlights `preDateReminder`.
3. Tap 約會前提醒 → fill answers → 產生 → result card renders 5 fields including required `boundaryReminder`.
4. Tap 重新生成 → second card overwrites first; `monthly_messages_used` += 2 from start.
5. Tap 換情境 → return to chip row → tap 約會後復盤 → fill including `stillUnclear` Q2 → result card renders.
6. Force tier cap (Free with cap 30, generate until 429) → paywall sheet shown.
7. Force network failure (airplane mode) → 「生成失敗，credit 未扣，請再試」 → `monthly_messages_used` unchanged.
8. Delete partner → re-enter via partner picker → `coach_follow_up_results` for that partner gone (no carryover).
9. Delete account → re-create → no follow-up results carry over (StorageService.clearAll seam validated end-to-end).

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
- ❌ Adding `CoachFollowUpRepository` to `SupabaseService` (cleanup goes through `StorageService.clearAll()` only)
- ❌ Reading `PartnerContextResolver`, `partnerSummary`, `partnerTraits`, or raw message bodies in `buildCoachFollowUpPartnerHint`
- ❌ Changing `signOut()` semantics in this PR (gated by OQ-Sign-1; if Eric picks (b), it's a separate ticket spanning ALL boxes)

---

## 9. Validation Checklist (Before Each Phase Merge)

### Before Phase A merge
- [ ] `deno test supabase/functions/coach-follow-up/` all green (incl. quota edge-case matrix from T7)
- [ ] No imports from `analyze-chat/` (verify: `grep -r "from.*analyze-chat" supabase/functions/coach-follow-up/`)
- [ ] All `assertRejects` calls use `await` inside `async` test bodies
- [ ] **CI deploy line in `deploy-edge-function.yml` is committed AND verified green on GH Actions** (Codex P1 #1)
- [ ] Curl smoke: 200 success, 400 image rejection, 401 unauthenticated, 429 cap exceeded
- [ ] Boundary check: response with null `boundaryReminder` → 5xx + credit not deducted
- [ ] Banned-token check: response with `PUA` / `收割` etc. → 5xx + credit not deducted (Codex P1 #5)
- [ ] No free-text or prompt content in any log line

### Before Phase B merge
- [ ] `flutter test test/unit/features/coach_follow_up/` all green
- [ ] `flutter test test/unit/services/storage_service_clear_all_test.dart` all green (incl. new coach_follow_up_results assertion)
- [ ] `flutter analyze` clean
- [ ] `dart run build_runner build` re-run; no orphan `.g.dart` files
- [ ] Repo unit tests use **temp Hive path**, NOT `Hive.initFlutter()` (Codex P2 #6)
- [ ] `clearAll()` regression added to **existing** `storage_service_clear_all_test.dart`, not parallel file (Codex P1 #2)
- [ ] Partner-delete cascade test passes
- [ ] No imports from `SupabaseService` for cleanup wiring
- [ ] OQ-Sign-1 has been resolved by Eric

### Before Phase C merge
- [ ] `flutter test test/widget/features/coach_follow_up/` all green
- [ ] All option values are stable English keys (not 繁中) — `grep "options.*中文"` audit
- [ ] Hint resolver test asserts `GameStage.close` enum (not '邀約' / '準備邀約' string)
- [ ] `buildCoachFollowUpPartnerHint` tests pass for all 6 scenarios from C17 (Codex P2 #7)
- [ ] CI grep guard confirms `coach_follow_up_partner_hint_builder.dart` does NOT import `PartnerContextResolver` / `partnerSummary*` / `partnerTraits*`
- [ ] Result card always renders `boundaryReminder` (required field)
- [ ] "生成會使用 1 則額度" caption present at every credit-spending entry point
- [ ] `flutter test --coverage` baseline maintained

### Before Phase X merge
- [ ] CI/CD: analyze-chat still deploys with `--no-verify-jwt`
- [ ] CI/CD: coach-follow-up deploys WITHOUT `--no-verify-jwt`
- [ ] All 5 telemetry events verified in staging logs
- [ ] TF smoke passes all 9 scenarios (incl. account-delete cleanup)

---

## 10. Codex Amendments Log

### Rev 0 → Rev 1 — applied 2026-05-02

Codex plan review verdict NEEDS-FIX (see review file referenced above) raised 7 items. All addressed:

1. **P1 #1 — Phase A standalone-merge claim**: Moved CI/CD deploy step from old §X23 into new Task A9 (Phase A). Old A9 manual smoke renamed to A10. Phase A is now genuinely standalone-mergeable end to end. §3 Phase Plan table updated.
2. **P1 #2 — Wrong cleanup seam**: Removed all references to wiring through `SupabaseService.deleteAccount` / `signOut`. New T14 wires `coach_follow_up_results` into `StorageService.clearAll()` (called by `SettingsScreen.deleteAccount` chain at `settings_screen.dart:686-688`). Privacy regression added to **existing** `storage_service_clear_all_test.dart`, not a parallel file. New §0 OPEN Q OQ-Sign-1 surfaces the sign-out semantics decision to Eric explicitly (recommend keep current behavior).
3. **P1 #3 — Quota edge-case test matrix expanded**: Task A6 + A7 test list expanded to cover (a) subscription self-heal, (b) daily reset, (c) monthly reset, (d) test account skip, (e) RevenueCat tier refresh on cap, (f) unknown / null tier fallback to free, (g) deduct uses same updated counters as gate.
4. **P1 #4 — Deno assertRejects fix**: ALL `assertRejects` examples in the plan are now `await`ed inside `async` test bodies. Audit comment added to §9 Validation Checklist (Phase A).
5. **P1 #5 — Banned-token enforcement at validator**: Task A3 expanded to include `assertCardSafe(card)` function rejecting `PUA / 收割 / 控住 / 攻略 / 壞女人 / 高分妹 / 玩咖`. Task A7 calls it after `validateResponseCard`; failure → 5xx + NO credit deduct (same contract as missing `boundaryReminder`). Client-side double-check added to T19 for defense in depth.
6. **P2 #6 — Hive temp path**: Task B13 test sample rewritten to use `Hive.init('./.dart_tool/test_hive_*')` + manual register + `deleteFromDisk` teardown, mirroring `storage_service_partner_box_test.dart`. NOT `Hive.initFlutter()`.
7. **P2 #7 — `lastConversationSummary` source helper**: New Task C17 introduces `buildCoachFollowUpPartnerHint` pure helper with 6 unit tests covering: conversation-level only / 200-char cap / null when no summary / null when no current conversation / Spec 3 flagged omit / no PartnerContextResolver/traits/raw access. CI grep guard added. Helper output is the ONLY thing C19 API service may pass to Edge.

Net task count change: 25 → 26 (+1 for new C17, CI moved A↔X balances out).

---

## 11. References

- **Design (binding)**: `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `a66ca5b`
- **Design Codex review**: `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` @ `3d8dd3a`
- **Plan Rev 0 Codex review**: `docs/reviews/2026-05-02_spec5-coach-follow-up-impl-plan_codex-review.md` @ `146b8e3`
- **Pattern reference (cost machinery)**: `supabase/functions/analyze-chat/index.ts:3296-3736` (DO NOT IMPORT)
- **Pattern reference (Hive box repo)**: `lib/features/user_profile/data/repositories/partner_style_repository.dart`, `partner_data_quality_repository.dart`
- **Pattern reference (Hive unit-test temp path)**: `test/unit/services/storage_service_partner_box_test.dart`
- **Privacy seam (cleanup)**: `lib/core/services/storage_service.dart:145-153`, `test/unit/services/storage_service_clear_all_test.dart`
- **Account-deletion chain caller**: `lib/features/subscription/presentation/screens/settings_screen.dart:686-688`
- **Partner detail insertion site**: `lib/features/partner/presentation/screens/partner_detail_screen.dart`
- **Conversation summary source**: `lib/features/conversation/domain/entities/conversation.dart` + `conversation_summary.dart` + `lib/features/conversation/data/services/memory_service.dart`
- **Spec 3 flagged provider**: `lib/features/user_profile/data/providers/data_quality_flag_provider.dart`
- **Hive typeId map**: `lib/hive_registrar.g.dart` (typeIds 0-15 used; 16 is next free)
- **GameStage enum stable keys**: `lib/features/analysis/domain/entities/game_stage.dart`
- **CI/CD workflow**: `.github/workflows/deploy-edge-function.yml`
- **CLAUDE.md hard rules**: OCR isolation, `CLAUDE_API_KEY` env var (not `ANTHROPIC_API_KEY`), `--no-verify-jwt` on analyze-chat only

---

## 12. Next Step (after this Rev 1 ACK'd)

1. **Eric** resolves OQ-Sign-1 (§0). Recommended: option (a) — keep sign-out behavior unchanged.
2. **Codex** re-review on this Rev 1 → expect verdict `REVISED_AND_APPROVED` per the review's closing line ("unless the amendment introduces new scope"). Verdict file: same path, append to existing `*_codex-review.md` or new `*_codex-review-rev1.md`.
3. **Eric** final ACK after Codex verdict.
4. Open worktree (per `superpowers:using-git-worktrees`) for the implementation branch.
5. Choose execution mode: subagent-driven (this session) or parallel session (separate).
6. Begin Phase A T1; commit + push every task per CLAUDE.md rule.

Plan does NOT begin code until Codex Rev 1 verdict + Eric ACK.
