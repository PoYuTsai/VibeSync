# 2026-04-26 Partner Entity Refactor A2 plan Codex review

## Scope

- Review `docs/plans/2026-04-26-partner-entity-A2-impl.md`
- Check the plan against the current A1-shipped repo, not just the design doc
- No production code changes in this review

## Verdict

**Critical flaw - revise the A2 plan before opening `feature/partner-entity-A2`.**

The plan direction is still right, and I do not think ADR-15 or the A2 product
scope should be reopened. The blocker is narrower than that: one load-bearing
part of the plan is not executable in the current codebase.

## Findings

### [P1] Task 3's narrow invalidation contract has no valid owner yet

- Task 3 says A2 must keep Partner invalidation narrow and then shows this
  pseudocode in the conversation save path:
  `docs/plans/2026-04-26-partner-entity-A2-impl.md:351-360`
- That pseudocode calls `ref.invalidate(...)` from repository save logic
  (`...:353-359`)
- The live `ConversationRepository` is a plain storage wrapper with no
  Riverpod `Ref`, notifier, or event bus
  (`lib/features/conversation/data/repositories/conversation_repository.dart:11-110`)
- Current invalidation is still scattered across UI entrypoints:
  - `lib/features/conversation/presentation/screens/new_conversation_screen.dart:146`
  - `lib/features/conversation/presentation/screens/home_screen.dart:91`
  - `lib/app/main_shell.dart:245`
  - `lib/features/analysis/presentation/screens/analysis_screen.dart:495-514,935-936,1000-1001,1113`
- The current provider graph is also still coarse:
  `conversationsProvider` is a plain `Provider<List<Conversation>>`
  (`lib/features/conversation/data/providers/conversation_providers.dart:21-25`)

So the plan currently asks for a contract it has not actually assigned to any
real layer. Before implementation starts, the plan must pick one concrete owner
for Partner-scoped invalidation, for example:

1. a dedicated Riverpod controller / notifier that owns conversation writes and
   invalidates partner-scoped providers centrally, or
2. a repository-exposed partner-scoped listenable / stream strategy that the
   new providers subscribe to directly.

Without that rewrite, Task 3 is not TDD-ready.

### [P2] The summary truncation sketch is still unsafe at Unicode boundaries

- HS-A2-2 correctly flags this risk
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:1052-1060`)
- But Task 4 still truncates with raw `substring`
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:473-477`)
- The proposed tests do not force a real boundary case; they only mention a
  `1000-char` custom note and a generic truncation marker test
  (`...:395-396`, `...:418-419`)

This is not a product blocker, but the plan should be fixed before execution:

- require char-safe truncation (`String.runes` or equivalent)
- add one test that truncates exactly across a non-ASCII boundary

### [P2] Several task entrypoints still point at stale files or provider names

The plan is mostly aligned to the repo, but a few load-bearing references are
still stale:

- Task 5 targets
  `lib/features/conversation/data/services/analyze_chat_client.dart`
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:495-497`), but the live
  analyze-chat caller is
  `lib/features/analysis/data/services/analysis_service.dart`
- Task 6 refers to `lib/app/router/app_router.dart`
  (`...:575-576`), but the current router lives in `lib/app/routes.dart`
- Task 3 uses `currentUserIdProvider` in its sketch (`...:344-345`), but the
  current auth-scoping provider is `authConversationScopeProvider`
  (`lib/features/conversation/data/providers/conversation_providers.dart:14-18`)

These are not architecture blockers by themselves, but they will create
false-red TDD steps and wasted debugging time if the plan is executed as-is.

## Hot Spot Judgments

### HS-A2-1 - Riverpod narrow invalidation

`REVISE_BEFORE_IMPLEMENTATION`

This is the main blocker. The plan must name a real invalidation owner before
Claude opens the feature branch.

### HS-A2-2 - Partner summary worst-case / truncation

`FIX_IN_PLAN`

Keep the 1500-char cap and `N=8` ranking, but require char-safe truncation and
a boundary test.

### HS-A2-3 - D1 fallback path

`ACCEPT_CURRENT_DIRECTION`

I do **not** recommend proactive name-based dedupe on ingest. Keeping the
fallback path non-deduping and letting same-name cleanup happen via banner +
manual merge is safer than false-positive auto-merge.

So this does **not** require Daisy arbitration from my side.

### HS-A2-4 - 7-8 dev day estimate

`TIGHT_BUT_PLAUSIBLE_AFTER_PLAN_FIX`

If Task 3 is rewritten cleanly and stale entrypoints are repaired up front,
`7-8` dev days is still believable. In the current draft, it is more likely to
spill because Task 3 would force architecture decisions mid-run.

### HS-A2-5 - Routing back-stack / deep-link case

`NON-BLOCKING IMPLEMENTATION NOTE`

Do **not** synthesize a fake back stack by default. For direct
`/conversation/:id` entry, it is acceptable that navigation history differs
from in-app push flow. What A2 should guarantee is:

- normal in-app navigation: conversation back returns to Partner detail
- direct deep-link entry: no crash, and a clear explicit way back to Partner or
  Home when history is absent

That means Task 6 test coverage should include the deep-link/no-history case,
but this does not block the whole plan.

## Recommended plan edits before Claude starts implementation

1. Rewrite Task 3 around one explicit invalidation owner.
   - Remove the repository pseudocode that calls `ref.invalidate(...)`
   - Replace it with a controller / notifier or equivalent concrete pattern
2. Tighten Task 4:
   - require char-safe truncation
   - add a boundary test with non-ASCII text
3. Repair stale task references:
   - Task 5 -> `analysis_service.dart`
   - Task 6 -> `lib/app/routes.dart`
   - Task 3 -> current auth-scoping provider names
4. Keep D1/D2/D3/D4 plan-defaults unless Eric wants a product override.

## Recommended path

Do **not** cut `feature/partner-entity-A2` yet.

First revise the plan on the P1/P2 items above, then rerun Codex review. If the
Task 3 architecture hole is closed cleanly, I expect the next review can move
to `PASS` without reopening the whole A2 scope.
