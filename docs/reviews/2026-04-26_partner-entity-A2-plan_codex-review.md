# 2026-04-26 Partner Entity Refactor A2 plan Codex review

## Scope

- Review `docs/plans/2026-04-26-partner-entity-A2-impl.md`
- Check the plan against the current A1-shipped repo, not just the design doc
- No production code changes in this review

## Verdict

**PASS - A2 plan r4 is approved for `feature/partner-entity-A2`.**

The plan direction is still right, and I do not think ADR-15 or the A2 product
scope should be reopened. r3 fixed the earlier legacy-consumer freshness issue,
and r4 closes the remaining direct-write coverage gap by changing Task 3's unit
of analysis from invalidate sites to repository write sites.

## Prior r1/r2 Findings

These findings explain the first two review rounds. The current r3 verdict is
recorded in the latest section below.

### [P1] r2 fixes the invalidation owner, but now drops required updates for
existing non-Partner consumers

- r2 correctly introduces `ConversationWriteController extends Notifier<void>`
  as the write owner
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:372-415`)
- But the same task now explicitly asserts that the controller must **not**
  invalidate global `conversationsProvider`
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:330-332,356-357,438`)
- In the live app, `conversationsProvider` still feeds non-Partner surfaces:
  - `reportDataProvider` watches it directly
    (`lib/features/report/data/providers/report_providers.dart:12-14`)
  - `MyReportScreen` depends on that provider
    (`lib/features/report/presentation/screens/my_report_screen.dart:17`)
- The plan currently migrates the old UI invalidation calls into the controller,
  but it does **not** replace or re-home those non-Partner consumers

So r2 fixed the original "who owns invalidation?" question, but it introduced a
new one: after A2 starts routing writes through the controller, report data can
quietly go stale unless the plan also preserves updates for legacy global
consumers.

This is still a blocker because it changes existing app behavior outside the
Partner screens.

The plan needs one explicit answer before implementation:

1. either the controller also invalidates legacy consumers that still depend on
   `conversationsProvider` during A2, or
2. A2 must migrate those consumers off `conversationsProvider` before enforcing
   the "no global invalidate" rule.

Until one of those is written into the plan, Task 3 is still not TDD-safe.

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

r2 successfully names a real invalidation owner, but it over-tightens the
contract by forbidding global invalidation before all current global consumers
have been migrated. That is the new blocker.

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

1. Amend Task 3 so the controller preserves correctness for remaining global
   consumers.
   - Either explicitly invalidate those legacy consumers during A2, or
   - move them off `conversationsProvider` before the controller test forbids
     global invalidation
2. Keep Task 4's char-safe truncation fix, but strengthen the boundary test:
   - require char-safe truncation
   - add a boundary test with emoji ZWJ sequence, not only a generic
     non-ASCII case
3. Keep the stale-reference fixes from r2
4. Keep D1/D2/D3/D4 plan-defaults unless Eric wants a product override.

## Recommended path

Do **not** cut `feature/partner-entity-A2` yet.

First revise the plan on the P1/P2 items above, then rerun Codex review. I do
not expect another product-level debate here; this should be one more execution
plan tightening pass.

---

## r2 re-review

### Summary

r2 fixed three real issues from the first review:

1. Task 3 now has a concrete invalidation owner
2. Task 4 now proposes grapheme-safe truncation via `characters`
3. Task 5 / 6 / provider naming references are mostly corrected

That is good progress. The remaining blocker is specifically that the new
controller contract forbids global invalidation while the app still has at least
one important non-Partner consumer (`reportDataProvider`) hanging off
`conversationsProvider`.

### What improved

- `ConversationWriteController` is the right direction for write ownership
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:372-415`)
- Task 4 now uses `characters.take(...)` instead of raw substring
  (`...:561-569`)
- Task 5 and Task 6 point at the live caller / router files
  (`...:589`, `...:642`)

### What still blocks PASS

- Controller tests still assert "does NOT invalidate global
  conversationsProvider"
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:330-332,356-357`)
- But `reportDataProvider` still watches that provider today
  (`lib/features/report/data/providers/report_providers.dart:12-14`)

So this is not passable yet without one more plan edit.

---

## r3 re-review (latest)

### Summary

r3 resolves the r2 architecture blocker:

1. The narrow invalidation contract is now correctly defined as cross-partner
   fan-out prevention, not "never touch global feeds".
2. The controller keeps `reportDataProvider` / My Report fresh during A2 via
   `_invalidateLegacyGlobal()`.
3. Task 4 now requires `characters` truncation plus an explicit emoji ZWJ /
   grapheme boundary test.
4. The post-A2 cleanup section is clear enough for a later cleanup PR.

That said, I found one last execution-plan gap that is easier to fix before
A2 starts than during implementation.

### What improved

- Task 3 now preserves legacy global consumers during A2
  (`docs/plans/2026-04-26-partner-entity-A2-impl.md:328`,
  `...:461-467`).
- The cross-partner fan-out contract is testable:
  write partner X must not rebuild `partnerAggregateProvider(Y)`
  (`...:368-372`).
- Task 4 now uses `characters.take(...)` and calls out the emoji ZWJ boundary
  case (`...:550-558`, `...:646-652`).
- Task 5 / 6 stale file references are fixed.

### Remaining issue before implementation

#### [P1] Task 3 only migrates invalidate sites, not all direct conversation writes

r3's migration table and verification gate are centered on existing
`ref.invalidate(conversationsProvider)` calls:

- `docs/plans/2026-04-26-partner-entity-A2-impl.md:489-505`
- `docs/plans/2026-04-26-partner-entity-A2-impl.md:509-511`

But the live app has direct repository writes that do **not** currently
invalidate `conversationsProvider`:

- `lib/features/analysis/presentation/screens/analysis_screen.dart:541`
  toggles message sender and saves the conversation
- `lib/features/analysis/presentation/screens/analysis_screen.dart:613`
  edits a message and saves the conversation
- `lib/features/analysis/presentation/screens/analysis_screen.dart:649`
  deletes a message and saves the conversation

Those are still conversation writes. Under A2, they can change partner
aggregates, last interaction, message-derived summary, and report data. If Task
3 only migrates the invalidate call sites, these writes can bypass
`ConversationWriteController` and leave partner-scoped providers stale.

The plan should add one more implementation gate:

- grep for direct calls to
  `repository.createConversation`, `repository.updateConversation`, and
  `repository.deleteConversation` outside repository/tests
- require conversation content writes to go through `ConversationWriteController`
- explicitly list or justify any remaining direct repository writes

The existing `grep -rn "ref.invalidate(conversationsProvider)" lib/` gate is
still useful, but it is not enough to prove write ownership.

### Verdict

`WAITING_ON_DAISY`

I do not see a new A2 architecture problem. The r3 contract is acceptable.
However, this is Codex's third review round and there is still one P1-level
plan gap. Eric should decide between:

1. require a quick r4 plan patch before `feature/partner-entity-A2`, or
2. allow A2 to start with a hard Task 3 implementation gate that covers all
   direct repository writes.

My recommendation is option 1. It should be a small doc patch, not another
architecture debate.

---

## r4 re-review (latest)

### Summary

r4 closes the r3 gap. I am approving the plan for A2 implementation.

The important correction is that Task 3 now tracks conversation repository
writes, not just `ref.invalidate(conversationsProvider)` sites. I verified the
current repo with both searches:

- `rg -n "repository\.(create|update|delete)Conversation" lib`
- `rg -n "\b(create|update|delete)Conversation\(" lib`

The first search returns the same 13 app-layer write sites that r4 lists. The
second wider search only adds the repository method definitions, so I do not see
an obvious false negative in the r4 table.

### Findings

No blocking findings.

### Notes

- The 13-site table is now a valid Task 3 execution checklist.
- The four session-scope invalidates remain correctly out of the primary gate;
  they are auth/session cleanup, not conversation content writes.
- The secondary `ref.invalidate(conversationsProvider)` gate is still useful
  after implementation, but it should stay secondary.
- Optional implementation hardening: when running the gate, also use the wider
  `\b(create|update|delete)Conversation\(` search once, so a future direct call
  like `ref.read(conversationRepositoryProvider).updateConversation(...)` does
  not slip past a variable-name-specific grep.

### Verdict

`PASS`

Claude can cut `feature/partner-entity-A2` and start the 17-task implementation
plan.
