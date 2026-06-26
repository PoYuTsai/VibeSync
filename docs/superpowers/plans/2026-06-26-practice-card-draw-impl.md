# AI 實戰練習室每日翻牌機制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development`. Follow this plan batch by batch. Do not push until Codex review and Eric approval, because this touches quota, paywall, Edge schema, and a new DB migration.

**Goal:** Add a daily card-draw flow to AI 實戰練習室: users flip a dynamic profile card to reveal a practice girl, free daily draw allowance depends on subscription tier, paid extra draws cost 5 message quota, Free extra draws route to paywall, and the reveal animation closely matches the provided reference with blurred thumbnail grid, card back, 3D flip, gold orbit/glow, front profile card, and expanded profile.

**Architecture:** Supabase Edge `practice-chat` remains the server boundary. A new draw ledger and SECURITY DEFINER RPC atomically decide free vs paid draw, deduct extra draw quota when needed, and record the profile. Flutter owns draft/reveal state, bundled photos, animation, and paywall routing. The existing chat/debrief/continuation ledger remains unchanged.

**Tech Stack:** Flutter 3.x, Riverpod, Hive/local persistence, Supabase Edge Functions/Deno, Supabase Postgres RPC, RevenueCat-derived subscription tier, bundled practice girl JPEG assets.

---

## Reference Docs

- Product spec: `docs/superpowers/specs/2026-06-26-practice-card-draw-design.md`
- Existing profile continuation spec: `docs/superpowers/specs/2026-06-25-practice-chat-20-turns-continue-date-goal-design.md`
- Existing profile continuation plan: `docs/superpowers/plans/2026-06-25-practice-chat-realistic-profile-continuation-impl.md`

## Important Current Files

Server:

- `supabase/functions/practice-chat/index.ts`
- `supabase/functions/practice-chat/validate.ts`
- `supabase/functions/practice-chat/quota_decision.ts`
- `supabase/functions/practice-chat/practice_persona.ts`
- `supabase/functions/_shared/quota.ts`
- `supabase/migrations/`

Flutter:

- `lib/features/practice_chat/domain/entities/practice_profile.dart`
- `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
- `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
- `lib/features/practice_chat/data/repositories/practice_session_repository.dart`
- `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`
- `lib/features/practice_chat/presentation/widgets/practice_girl_photo.dart`
- `lib/features/practice_chat/presentation/widgets/practice_profile_sheet.dart`
- `lib/features/subscription/presentation/screens/paywall_screen.dart`

Tests:

- `supabase/functions/practice-chat/*_test.ts`
- `test/unit/features/practice_chat/`
- `test/widget/features/practice_chat/`
- `test/widget/screens/paywall_screen_test.dart`

## Non-Negotiable Invariants

- Client never sends prompt text, persona snippets, reaction model text, or free-form profile data.
- Client may send only allowlisted ids: `profileId`, `nameId`, `professionId`, `photoId`, `personaId`, `difficulty`.
- Draw mode must not require `DEEPSEEK_API_KEY`.
- Draw quota charge must be atomic with draw event insert.
- Same `requestId` retry must not double charge.
- Free second draw must not deduct quota and must not create a new profile event.
- Starter/Essential extra draw must cost exactly 5 message quota.
- Chat first successful AI reply still costs exactly 1 quota and gives 20 AI replies.
- Continue same girl does not consume draw allowance.
- Changing difficulty does not consume draw allowance and does not change girl.
- Push is blocked until migration is applied, tests pass, Codex review passes, and Eric approves.

## Batch 0: Preflight

- [ ] Load VibeSync bootstrap.

```powershell
Get-Content docs/snapshot.md
Get-Content docs/shared-agent-rules.md
git log --oneline -15
Get-Content docs/reviews/ai-arbitration-queue.md -TotalCount 160
git status --short --branch
```

- [ ] Record base commit for review.

```powershell
git rev-parse --short HEAD
```

- [ ] Inspect current APIs and route patterns.

```powershell
rg -n "mode|practice-chat|PracticeUpgradeRequiredException|QuotaExceeded|context.push\\('/paywall|paywall\\?|SubscriptionTier|normalizeTier|applyResetsIfNeeded" supabase/functions lib test
```

Expected notes:

- `practice-chat` currently supports `chat` and `debrief`.
- Practice chat already has upgrade/quota exceptions for chat continuation.
- Paywall route currently may be plain `/paywall`; inspect router before changing.

- [ ] Confirm working tree is clean or only has unrelated files named in closeout.

```powershell
git status --short
```

## Batch 1: DB Migration And RPC

**Concern:** Server-side draw ledger and atomic quota accounting.

### 1.1 Add migration

Add one new migration under `supabase/migrations/`, for example:

```text
supabase/migrations/20260626120000_practice_profile_draw_events.sql
```

Do not use `supabase db push`. Because this repo already has a known migration version mismatch, deployment must use Supabase MCP `apply_migration`.

### 1.2 Table

Create `practice_profile_draw_events`:

```sql
create table if not exists public.practice_profile_draw_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null,
  profile_id text not null,
  tier_at_draw text not null,
  reset_window_start_at timestamptz not null,
  cost_messages integer not null check (cost_messages in (0, 5)),
  created_at timestamptz not null default now(),
  unique (user_id, request_id),
  unique (user_id, reset_window_start_at, profile_id)
);

create index if not exists practice_profile_draw_events_user_window_idx
  on public.practice_profile_draw_events (user_id, reset_window_start_at, created_at desc);
```

RLS:

```sql
alter table public.practice_profile_draw_events enable row level security;
```

No public read/write policies. Edge function uses service role or SECURITY DEFINER RPC.

### 1.3 RPC

Add SECURITY DEFINER RPC, suggested name:

```sql
public.claim_practice_profile_draw(
  p_user_id uuid,
  p_request_id text,
  p_profile_id text,
  p_reset_window_start_at timestamptz,
  p_tier text,
  p_free_allowance integer,
  p_extra_cost integer,
  p_allow_paid_extra boolean,
  p_daily_limit integer,
  p_monthly_limit integer,
  p_charge_quota boolean default true
)
```

Return JSONB or a table containing:

```text
profile_id
cost_messages
free_allowance
free_used
free_remaining
daily_messages_used
monthly_messages_used
```

RPC rules:

- Lock the subscription row for the user with `for update`.
- If `(user_id, request_id)` already exists, return the existing event and current usage without another deduction.
- Count events in the same `reset_window_start_at`.
- If count < `p_free_allowance`, insert event with `cost_messages = 0`.
- If count >= allowance and `p_allow_paid_extra = false`, raise or return a structured upgrade-required code.
- If paid extra is allowed, check `daily_messages_used + p_extra_cost <= p_daily_limit` and `monthly_messages_used + p_extra_cost <= p_monthly_limit`.
- If insufficient, raise or return a structured quota-exceeded code and do not insert event.
- If sufficient, update subscription usage by `p_extra_cost`, then insert event with `cost_messages = p_extra_cost`.
- Use `p_charge_quota = false` for test-account bypass if current project conventions support it, but still write event.

### 1.4 Tests

Add SQL/RPC test if project has a pattern. If not, add Edge-level tests in Batch 2 that exercise the RPC through a mock client.

Minimum manual SQL assertions after migration in a local/test DB:

```sql
select to_regclass('public.practice_profile_draw_events');
select proname from pg_proc where proname = 'claim_practice_profile_draw';
```

### 1.5 Commit

```powershell
git add supabase/migrations/20260626120000_practice_profile_draw_events.sql
git commit -m "feat(practice-chat): 新增每日翻牌 ledger 與扣費 RPC"
```

Do not push.

## Batch 2: Edge Draw Mode

**Concern:** `practice-chat` supports `mode: draw_profile` with tier allowance, profile selection, idempotency, and quota payloads.

### 2.1 Add pure quota helpers

Modify `supabase/functions/practice-chat/quota_decision.ts` or add a small `draw_decision.ts`.

Constants:

```ts
export const PRACTICE_DRAW_EXTRA_COST = 5;
export const PRACTICE_DRAW_FREE_ALLOWANCE = {
  free: 1,
  starter: 3,
  essential: 5,
} as const;
```

Pure helpers:

```ts
export function drawAllowanceForTier(tier: string): number;
export function paidExtraDrawAllowedForTier(tier: string): boolean;
export function taipeiNoonResetWindow(now: Date): {
  resetWindowStartAt: string;
  nextResetAt: string;
};
```

Tests:

- Free allowance 1.
- Starter allowance 3.
- Essential allowance 5.
- Unknown tier normalizes to Free or fail-closed according to existing `normalizeTier`.
- Taipei 11:59 uses previous day noon.
- Taipei 12:00 uses current day noon.

### 2.2 Validate draw request

Update `supabase/functions/practice-chat/validate.ts` so draw mode is a separate request shape.

Request:

```ts
type PracticeDrawRequest = {
  mode: "draw_profile";
  requestId: string;
  currentProfileId?: string;
  visiblePracticeThreadId?: string;
};
```

Validation:

- `requestId` must be non-empty UUID or safe id string.
- `currentProfileId`, if present, must be allowlisted.
- `visiblePracticeThreadId`, if present, must pass existing safe string bounds.
- Draw mode must not require `turns`.
- Chat/debrief validation remains unchanged.

Tests:

- draw request without turns passes.
- bad `requestId` rejected.
- bad `currentProfileId` rejected.
- old chat/debrief tests unchanged.

### 2.3 Profile selection

In `practice_persona.ts`, add server helper:

```ts
export function selectPracticeDrawProfile(args: {
  currentProfileId?: string;
  excludedProfileIds: Set<string>;
  seed: string;
}): PracticeGirlProfile;
```

Selection rules:

- Exclude `currentProfileId`.
- Exclude already drawn profiles in current reset window.
- Prefer deterministic randomness from `userId + requestId + windowStart`, so retries are stable.
- If all excluded, allow any profile except current when possible.
- If RPC unique conflict happens due concurrency, Edge retries with another candidate up to 3 times.

Tests:

- Does not return current profile when alternatives exist.
- Does not return excluded profile when alternatives exist.
- Deterministic for same seed.
- Returns valid profile ids and matching `nameId/professionId/photoId/personaId`.

### 2.4 Implement `mode: draw_profile` in `index.ts`

Important ordering:

1. Parse and validate request.
2. Auth user.
3. Fetch subscription and apply resets like existing paths.
4. If draw mode, do not check `DEEPSEEK_API_KEY`.
5. Compute allowance and reset window.
6. Query already drawn profile ids in this reset window.
7. Select candidate profile.
8. Call `claim_practice_profile_draw` RPC.
9. Return profile ids and draw receipt.

Pseudo-flow:

```ts
if (request.mode === "draw_profile") {
  const tier = normalizeTier(sub.tier);
  const allowance = drawAllowanceForTier(tier);
  const allowPaidExtra = paidExtraDrawAllowedForTier(tier);
  const window = taipeiNoonResetWindow(new Date());
  const alreadyDrawn = await loadDrawnProfileIds(user.id, window.resetWindowStartAt);
  const profile = selectPracticeDrawProfile({
    currentProfileId: request.currentProfileId,
    excludedProfileIds: alreadyDrawn,
    seed: `${user.id}:${request.requestId}:${window.resetWindowStartAt}`,
  });
  const claim = await claimPracticeProfileDraw(...);
  return json({
    profile: profileMetadataIds(profile),
    draw: buildDrawReceipt(claim, window),
    usage: buildUsage(subOrClaim),
  });
}
```

Error mapping:

- Free allowance exhausted: HTTP 402, error `practice_draw_upgrade_required`.
- Quota exhausted for paid extra: HTTP 429 with standard quota payload.
- DB/RPC failure: existing 500 style, no prompt/transcript logging.

### 2.5 Edge tests

Add tests for:

- `draw_profile` does not require turns.
- `draw_profile` does not require DeepSeek env.
- Free first draw returns cost 0.
- Free second draw returns 402 upgrade.
- Starter first 3 draws cost 0.
- Starter 4th draw costs 5.
- Essential first 5 draws cost 0.
- Essential 6th draw costs 5.
- Idempotent same requestId does not double charge and returns same profile.
- Bad `currentProfileId` rejected.
- Draw response profile ids are self-consistent.
- Existing chat continuation gate still passes tests.

Commands:

```powershell
deno test --allow-env --allow-net supabase/functions/practice-chat/
deno check supabase/functions/practice-chat/index.ts
```

### 2.6 Commit

```powershell
git add supabase/functions/practice-chat supabase/functions/_shared
git commit -m "feat(practice-chat): 新增每日翻牌 Edge 模式"
```

Do not push.

## Batch 3: Flutter Service, State, And Draft Persistence

**Concern:** Client can request a draw, preserve revealed draft, handle upgrade/quota, and never client-randoms a girl.

### 3.1 API service

Modify `lib/features/practice_chat/data/services/practice_chat_api_service.dart`.

Add DTO:

```dart
class PracticeProfileDrawResult {
  final PracticeProfileDto profile;
  final int costMessages;
  final int freeAllowance;
  final int freeUsed;
  final int freeRemaining;
  final int extraCostMessages;
  final DateTime nextResetAt;
}
```

Add method:

```dart
Future<PracticeProfileDrawResult> drawProfile({
  required String requestId,
  String? currentProfileId,
  String? visiblePracticeThreadId,
});
```

Add exceptions:

```dart
class PracticeDrawUpgradeRequiredException implements Exception { ... }
class PracticeDrawQuotaExceededException extends PracticeQuotaExceededException { ... }
```

If existing quota exception can carry all needed payload, reuse it for 429.

Tests:

- Body has `mode: draw_profile`, `requestId`, `currentProfileId`, `visiblePracticeThreadId`.
- 200 parses profile and draw receipt.
- 402 throws draw upgrade exception.
- 429 throws quota exception.

### 3.2 Draft persistence

Do not create zero-message `PracticeSession` rows for revealed but unstarted cards. Add a small local repository instead.

Suggested file:

```text
lib/features/practice_chat/data/repositories/practice_card_draft_repository.dart
```

Store:

```dart
class PracticeCardDraft {
  final String profileId;
  final String difficultyPreference;
  final String difficulty;
  final String resetWindowStartAt;
  final DateTime revealedAt;
  final int freeAllowance;
  final int freeUsed;
  final int freeRemaining;
  final DateTime nextResetAt;
}
```

Storage options:

- Hive box if project already has a small settings box pattern.
- If adding Hive adapter is heavy, use an existing encrypted key-value repository if present.

Rules:

- Restore draft only if `now < nextResetAt`.
- Clear draft when first message persists into `PracticeSession`.
- Clear draft when user draws a new card.
- Clear draft when user explicitly starts new partner after previous thread.

Tests:

- Saves and restores same profile before reset.
- Stale draft after reset is ignored.
- Clearing draft removes it.

### 3.3 Provider state

Modify `PracticeChatState` with draw fields:

```dart
enum PracticeCardRevealStatus { locked, drawing, revealed, error }

final PracticeCardRevealStatus revealStatus;
final int drawFreeAllowance;
final int drawFreeUsed;
final int drawFreeRemaining;
final int drawExtraCostMessages;
final DateTime? drawNextResetAt;
final bool drawUpgradeRequired;
```

Initialize:

- If restoring existing `PracticeSession`, status is `revealed`.
- If restoring valid draft, status is `revealed` with draft profile.
- If no draft/session, status is `locked`.

Add methods:

```dart
Future<void> drawNewPracticeGirl();
void clearDrawError();
```

Replace `regeneratePersona()` / `startNewPartner()` direct random behavior:

- Before messages: call `drawNewPracticeGirl()`.
- After debrief new partner: clear messages to new visible thread and call draw, or move to locked state and let user tap. Prefer call draw immediately if UX wants smoother "換一位".

Important:

- `createPracticeProfile()` should no longer reveal a random profile automatically in new-room state.
- Difficulty chips still update preference before first message.
- `setDifficultyPreference()` does not trigger draw and does not change profile.
- `continueWithSamePartner()` remains unchanged regarding profile.
- `sendMessage()` requires `revealStatus == revealed`; otherwise block and show "先翻開今日女孩".

Tests:

- New state has locked reveal and does not show profile.
- Successful draw sets profileId from server response and status revealed.
- Draw persists draft.
- Restore draft reveals same girl and does not call API.
- First send clears draft and persists session.
- Free 402 sets drawUpgradeRequired and does not change current profile.
- Paid 429 quota error does not change current profile.
- Difficulty chip after reveal does not change girl.
- Continue same partner preserves profile and does not call draw.
- Start new partner calls draw and changes profile.

Commands:

```powershell
flutter test test/unit/features/practice_chat
flutter test test/widget/features/practice_chat
flutter analyze lib/features/practice_chat
```

### 3.4 Commit

```powershell
git add lib/features/practice_chat test/unit/features/practice_chat test/widget/features/practice_chat
git commit -m "feat(practice-chat): 接上每日翻牌狀態與草稿保存"
```

Do not push.

## Batch 4: Flip UI And Animation

**Concern:** High-fidelity visual reveal, still performant and testable.

### 4.1 Add widgets

Suggested files:

```text
lib/features/practice_chat/presentation/widgets/practice_card_teaser_grid.dart
lib/features/practice_chat/presentation/widgets/practice_card_flip_reveal.dart
lib/features/practice_chat/presentation/widgets/practice_card_glow_painter.dart
```

`PracticeCardTeaserGrid`:

- 3 x 4 or 4 x 3 grid.
- Use 12 local profile photos.
- Apply blur and dark overlay.
- Central text:

```text
每日登入就送新女孩
```

- Use stable dimensions so layout does not jump.

`PracticeCardFlipReveal`:

- Stateful widget with `AnimationController`.
- Back card phase.
- Y-axis flip using `Transform`:

```dart
final matrix = Matrix4.identity()
  ..setEntry(3, 2, 0.0012)
  ..rotateY(pi * animation.value);
```

- Switch child at `animation.value >= 0.5`.
- Gold orbit/sparkle `CustomPainter` around the card.
- Front card includes photo, name, age, city.
- On animation complete, notify controller/screen to show expanded profile hero.

Accessibility:

- If `MediaQuery.disableAnimations` or `MediaQuery.accessibleNavigation` is true, skip animation and reveal immediately.

### 4.2 Integrate screen

Modify `practice_chat_screen.dart`.

Opening area state:

```text
locked -> teaser grid + flip button + allowance text
drawing -> flip reveal animation
revealed -> existing profile hero
messages not empty -> chat list + compact header
```

Copy:

```text
每日登入就送新女孩
翻開今日女孩
今日免費翻牌 1/3
中午 12:00 重置
再翻一張 · 5 則
升級解鎖更多女孩
```

Paywall CTA should only appear when `drawUpgradeRequired`.

### 4.3 Visual rules

- Preserve the current practice-chat dark style.
- Card back should feel like a romantic playing card, not casino gambling.
- Gold glow and orbit are decorative, not blocking.
- Do not use purple/blue-only one-note palette; use current dark purple plus warm orange/gold accents.
- Avoid putting card inside another card if the existing hero already frames it. The reveal stage can be a single central component.
- Text must not overlap on small iPhones.

### 4.4 Tests

Widget tests:

- Locked state shows teaser copy and no profile hero.
- Successful draw transitions to revealed hero.
- Reduce motion renders revealed hero without waiting animation.
- Free draw upgrade shows paywall CTA.
- `practice-card-teaser-grid`, `practice-card-back`, `practice-card-front`, and profile hero have stable keys for QA.

Manual QA:

- Record a short iOS simulator or TestFlight video of the reveal.
- Compare against reference stages:
  - blurred grid
  - card back
  - flip midpoint
  - gold orbit
  - front card
  - expanded profile

Commands:

```powershell
flutter test test/widget/features/practice_chat
flutter analyze lib/features/practice_chat
```

### 4.5 Commit

```powershell
git add lib/features/practice_chat/presentation test/widget/features/practice_chat
git commit -m "feat(practice-chat): 加入每日翻牌首屏與翻牌動畫"
```

Do not push.

## Batch 5: Paywall Integration

**Concern:** Paywall copy and source-aware upgrade path.

### 5.1 Add source route

Inspect router before editing:

```powershell
rg -n "GoRoute|/paywall|PaywallScreen|context.push\\('/paywall" lib
```

Preferred:

- Use query param: `/paywall?source=practice_card_draw_limit`
- Or use existing route `extra` pattern if project already prefers it.

### 5.2 Update paywall table

Modify `paywall_screen.dart`:

Rows:

```text
AI 模型 | 經濟型 | 高階型 | 高階型
AI 陪練女孩 | 限量 | 開放 | 開放
每日免費翻牌 | 1 次 | 3 次 | 5 次
額外翻牌 | 升級解鎖 | 5 則 / 次 | 5 則 / 次
```

If source is `practice_card_draw_limit`, add context copy:

```text
想每天遇見更多陪練女孩？
Starter 每天 3 次，Essential 每天 5 次，還能用 5 則額外翻牌。
```

### 5.3 Tests

Modify `test/widget/screens/paywall_screen_test.dart`:

- Shows `AI 模型`, `經濟型`, `高階型`.
- Shows `AI 陪練女孩`, `限量`, `開放`.
- Shows `每日免費翻牌`, `1 次`, `3 次`, `5 次`.
- Shows `額外翻牌`, `升級解鎖`, `5 則 / 次`.
- Source-aware copy appears when route/source is draw limit.

Commands:

```powershell
flutter test test/widget/screens/paywall_screen_test.dart
flutter analyze lib/features/subscription
```

### 5.4 Commit

```powershell
git add lib test/widget/screens/paywall_screen_test.dart
git commit -m "feat(subscription): paywall 補每日翻牌方案差異"
```

Do not push.

## Batch 6: Integration Tests, Review, Migration Deploy, Push

**Concern:** Prove the full system, then deploy in safe order.

### 6.1 Full targeted verification

Run:

```powershell
deno test --allow-env --allow-net supabase/functions/practice-chat/
deno check supabase/functions/practice-chat/index.ts
flutter test test/unit/features/practice_chat
flutter test test/widget/features/practice_chat
flutter test test/widget/screens/paywall_screen_test.dart
flutter analyze lib
```

If `flutter analyze lib` is too slow, do not kill it unless truly hung. Let it complete.

### 6.2 Manual pre-review checklist

Before asking Codex review:

- [ ] `draw_profile` does not require DeepSeek key.
- [ ] No prompt text or reaction model is sent from client.
- [ ] Draw response ids match local catalog.
- [ ] Free second draw goes to paywall.
- [ ] Starter fourth draw deducts 5.
- [ ] Essential sixth draw deducts 5.
- [ ] Retry same request id does not double charge.
- [ ] Existing chat first-reply charge still deducts 1.
- [ ] Continue same girl still does not call draw.
- [ ] Recent practice history still groups by visible thread.
- [ ] Paywall rows render and text fits.
- [ ] Reduce motion path works.

### 6.3 Codex review request

Ask Codex to review `<base>..HEAD`.

Review focus:

1. DB/RPC atomicity and idempotency.
2. Free/Starter/Essential draw allowance math.
3. Noon Asia/Taipei reset boundary.
4. Edge draw mode not requiring DeepSeek and not breaking chat/debrief.
5. Client only sends allowlisted ids.
6. Draft persistence does not create fake recent sessions.
7. Continue same girl and difficulty switch do not accidentally consume draw.
8. Paywall source and rows are correct.
9. Animation widgets are not layout-fragile or inaccessible.

Do not push on `CONCERNS` if any finding touches quota, paywall, or Edge behavior.

### 6.4 Apply migration

After Codex approval and Eric approval, apply the migration to prod with Supabase MCP `apply_migration`.

Do not use:

```powershell
supabase db push
```

Reason: known local/remote migration version mismatch exists from previous work.

Verify prod:

```sql
select to_regclass('public.practice_profile_draw_events');
select proname from pg_proc where proname = 'claim_practice_profile_draw';
```

### 6.5 Push

Only after migration is live:

```powershell
git push origin main
```

Wait for:

- Edge deploy workflow success.
- App build workflow status noted.

### 6.6 Post-push smoke

On TestFlight or local iOS build:

- Free user:
  - first draw reveals card.
  - second draw opens paywall.
  - first AI reply still deducts 1.
- Starter/Essential test account:
  - free draw allowance count is correct.
  - first paid extra draw deducts 5.
- Visual:
  - animation stages are visible.
  - profile hero shows correct photo/name.
  - full photo viewer still works.
  - reduce motion does not blank.

## Suggested Batch Ownership

If context is high, split into separate sessions:

1. Batch 1 only: migration/RPC.
2. Batch 2 only: Edge draw mode.
3. Batch 3 only: Flutter service/state/draft.
4. Batch 4 only: animation/UI.
5. Batch 5 and 6: paywall/tests/review/deploy.

Do not combine Batch 1, 2, and 4 in a red-zone context. This feature crosses quota, Edge schema, DB, and animation UX, so the cost of a wrong assumption is high.

## Closeout Template

Use this closeout when reporting back:

```text
Batch X 完成：
- Commits:
  - <hash> <message>
- Tests:
  - <command> -> <result>
- High-risk notes:
  - <quota/paywall/Edge/migration notes>
- Not pushed:
  - yes/no
- Next:
  - <exact next batch>
```

Final ship closeout must include:

```text
Base commit:
Review range:
Migration applied:
Edge deploy workflow:
Flutter/TestFlight rebuild needed:
Known non-blockers:
```
