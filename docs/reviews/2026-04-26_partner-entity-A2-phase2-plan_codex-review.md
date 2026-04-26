# 2026-04-26 Partner Entity Refactor A2 Phase 2 plan Codex review

## Scope

- Branch: `feature/partner-entity-A2-ui`
- Plan: `docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md`
- Reviewed scope: Tasks 6-9 only (routing, Partner list, Add Partner, Partner
  detail)
- No production code was changed in this review

## Verdict

**REVISE_BEFORE_IMPLEMENTATION.**

The Phase 2 direction is right: Partner-first IA, `/conversation/:id`
back-compat, and Phase 1 narrow providers are the correct foundation. But the
current plan has several TDD harness and navigation issues that will create
false-red tests or a broken back stack if Claude executes it literally.

## Findings

### [P1] Test snippets import the wrong package name

The project package is `vibesync` (`pubspec.yaml:1`), but the new test snippets
use `package:vibe_sync/...` in Task 6, 7, 8, and 9
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:73`,
`:236`, `:463`, `:657`). Those tests will not compile even before reaching the
intended red/green assertions.

Required plan patch:

- Replace every `package:vibe_sync/...` import in this plan with
  `package:vibesync/...`.

### [P1] Add Partner submit uses `context.go`, which drops the Home back stack

Task 8 opens `/partner/new` from the Home FAB, then submits with
`context.go('/partner/${partner.id}')`
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:570`). `go()` rebuilds
the route stack for the new location, so the user can land on Partner detail
without a way to back-navigate to the Partner list. That conflicts with the
Phase 2 IA and the earlier A2 deep-link/no-history concern.

Required plan patch:

- Use `context.replace('/partner/${partner.id}')` or
  `context.pushReplacement('/partner/${partner.id}')` after submit so
  `/partner/new` is removed but the underlying Home route stays available.
- Add a widget/router test for: Home -> `/partner/new` -> submit -> detail ->
  back returns to Partner list.
- Add an explicit no-history fallback for direct `/partner/:partnerId` entry
  (for example a Home action when `!Navigator.canPop(context)`), or state why
  Phase 2 deliberately defers it.

### [P1] Several proposed widget tests are not hermetic and will hit real Hive/providers

The plan says each task should be TDD red -> green, but some tests will fail for
infrastructure reasons instead of the intended behavior:

- Task 6's `/conversation/:id` router test builds the real `AnalysisScreen`
  without overriding `conversationProvider('conv-1')`
  (`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:94`, `:117-123`).
  That path can touch the real repository / Hive box instead of only verifying
  route shape.
- Task 7 overrides only `partnerListProvider`, while `PartnerListCard` watches
  `partnerAggregateProvider(partner.id)`
  (`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:261-281`,
  `:360`). The tests need aggregate overrides per partner or a card API that
  accepts the already-computed aggregate.
- Task 8's `_FakeRepo extends PartnerRepository`
  (`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:468`) still calls
  the real `PartnerRepository()` constructor, which initializes from
  `StorageService.partnersBox`. In a widget test without an opened Hive box,
  that fake can fail before the submit assertion.
- Task 8's auth override note suggests `AsyncData('u-test')`
  (`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:520`), but the real
  provider is a `StreamProvider<String?>`. Existing tests override it with
  `authConversationScopeProvider.overrideWith((ref) => Stream.value('u-1'))`.

Required plan patch:

- Make the router test either use lightweight sentinel widgets for route-shape
  assertions, or provide all needed provider overrides when building the real
  `AnalysisScreen`.
- In Partner list tests, override `partnerAggregateProvider(id)` for every
  partner rendered by the card, or pass aggregate data down from
  `PartnerListScreen`.
- In Add Partner tests, use a temp Hive `Box<Partner>` with
  `PartnerRepository(box: box)`, or a fake subclass that calls `super(box:
  openedTestBox)`.
- Replace the auth override note with the real
  `authConversationScopeProvider.overrideWith((ref) => Stream.value('u-test'))`
  pattern.

### [P2] Add Partner can create an ownerless Partner that immediately disappears

Task 8 reads `authConversationScopeProvider.valueOrNull` and allows `ownerUserId`
to be null (`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:557`,
`:625`). But `partnerListProvider` returns an empty list when auth scope is null
and otherwise lists only partners whose `ownerUserId` matches the current user.
If the auth provider is briefly loading or unexpectedly null, submit can create
a Partner that will not appear in the Partner list.

Required plan patch:

- Treat null auth scope as "not ready": disable submit or show loading/error.
- Add a test that submit is blocked when `authConversationScopeProvider` emits
  null.

### [P2] Radar parser reuse is too vague to prevent duplicate parsing logic

Task 9 asks `PartnerRadarSummaryCard` to reuse the existing
`lastAnalysisSnapshotJson` parser
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:825`, `:878`), but the
live code does not expose a reusable parser from `analysis_screen.dart`; the
dimension parser is currently private inside `AnalysisResult.fromJson`. Without
an explicit target, the executor is likely to duplicate JSON parsing in the new
widget.

Required plan patch:

- Specify the exact reuse path: either call `AnalysisResult.fromJson(...)` and
  consume `dimensionScores`, or extract a small shared helper in its own commit.
- Add a `PartnerRadarSummaryCard` test that feeds a real
  `lastAnalysisSnapshotJson` with `dimensions` and asserts the five values
  render.

## Hot spot judgments

- C1 narrow-invalidation direction: acceptable. Keep the Phase 2 widget grep
  for `conversationsProvider` at 0 hits, excluding legacy files not touched by
  Phase 2.
- Route order: acceptable, but only after the import/package-name and router
  harness issues above are fixed.
- `HomeContent` deferred deletion: acceptable. `@Deprecated` + Phase 4 cleanup
  keeps this phase smaller.
- `_NewConversationSheet` extraction: acceptable if it is a pure move +
  visibility flip, with no title/copy changes in Phase 2.
- `⋮` visible-only menu: acceptable only because Phase 3/4 are planned before
  the next user-facing ship. If Phase 2 ships independently, hide or disable
  the menu items instead of no-op handlers.

## Recommended path

Patch the plan to r2, update the same queue item, then ask for a short Codex
re-review focused only on the five findings above. I do not think Eric needs to
decide anything yet; these are execution-plan correctness issues, not product
taste tradeoffs.

## r2 scoped re-review — 2026-04-26

### Verdict

**REVISE_BEFORE_IMPLEMENTATION.**

r2 fixes the main architecture direction and closes most of the r1 findings:

- `rg -n "vibe_sync" docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md`
  returns no hits.
- Add Partner submit now uses `context.replace(...)` instead of `context.go(...)`.
- Task 6 router tests now use sentinel widgets.
- Task 7 lifts the aggregate read to `PartnerListScreen` and keeps
  `PartnerListCard` pure-render.
- Task 8 blocks submit while auth is null/loading and uses the real
  `StreamProvider` override pattern.
- Task 9 has a concrete parser reuse path via `AnalysisResult.fromJson(...)`.
- The `⋮` menu changed from visible-no-op to disabled "即將推出" items.

Two scoped blockers remain in the plan's test harness, so implementation should
not start yet.

### [P1] Navigation test still cannot pass because the Home list is overridden
to stay empty

Task 8's navigation test is meant to prove:

`Home -> /partner/new -> submit -> /partner/:id -> back -> Home with Alice shown`

But the test overrides `partnerListProvider` to always return an empty list
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:801`) and later
expects `find.text('Alice')`
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:829`). That assertion
will fail even if `context.replace` is correct, because the Home screen is
forced to render the empty state forever.

Required r3 patch:

- Either make the navigation test use a simple Home sentinel and only assert
  that back returns to Home instead of `/partner/new`, or
- Remove the `partnerListProvider` empty override and make the real
  `PartnerListScreen` hermetic by overriding `partnerRepositoryProvider`,
  `authConversationScopeProvider`, and `conversationRepositoryProvider` with a
  fake repository whose `listByPartner(_)` returns an empty list for any id.

The second option preserves the stronger "Alice appears after back" assertion.

### [P1] Auth-loading test uses `StreamController` but the snippet lacks
`dart:async`

Task 8's add-partner screen test creates `StreamController<String?>()`
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:617`) but the snippet
imports only `dart:io`
(`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:527`). The test will
not compile.

Required r3 patch:

- Add `import 'dart:async';` to
  `test/widget/features/partner/add_partner_screen_test.dart`.
- Remove unused imports in that snippet, especially
  `hive_ce_flutter/hive_flutter.dart` and
  `path_provider_platform_interface/path_provider_platform_interface.dart`
  (`docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md:532-533`), unless
  the implementation actually uses them.

### Scoped status

No Eric decision is needed. The remaining issues are execution-plan correctness
problems, not product tradeoffs. Patch r3, update the same queue item, and ask
Codex to re-check only these two points.
