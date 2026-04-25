# 2026-04-25 Partner Entity Refactor design Codex review

## Scope

- Review `docs/plans/2026-04-25-partner-entity-design.md`
- Verify the requested blind spots against the current repo
- No code changes in this review

## Verdict

**Critical flaw - revise the spec before A1 implementation planning.**

The current design has two blocking issues:

1. `Partner @HiveType(typeId: 5)` collides with an existing Hive adapter
2. the proposed startup migration is not crash-safe or idempotent when rerun

`Conversation @HiveField(15)` itself looks free, so the blocker is not the
field number. The blocker is the adapter id and the migration algorithm.

## Findings

### [P1] `Partner typeId=5` collides with the existing `UserGoal` adapter

- Design doc proposes `@HiveType(typeId: 5)` for `Partner`
  (`docs/plans/2026-04-25-partner-entity-design.md:39`)
- The repo already uses `typeId = 5` for `UserGoal`
  (`lib/features/conversation/domain/entities/session_context.dart:89`,
  `lib/features/conversation/domain/entities/session_context.g.dart:199`)
- `StorageService.initialize()` registers that adapter on every app start
  (`lib/core/services/storage_service.dart:18-25`)

This means the spec cannot be implemented as written. `Partner` must take a new
unused type id before any A1 work starts.

### [P1] The migration plan is not rerun-safe after a mid-flight crash

The proposed migration is:

1. check a terminal SharedPreferences flag
2. create a new `Partner` with a fresh UUID from each `Conversation`
3. write `conversation.partnerId`
4. set the done flag at the end

That flow appears in the design doc
(`docs/plans/2026-04-25-partner-entity-design.md:61-65`).

If the app is killed after some `Partner` rows are created but before all
`conversation.partnerId` writes finish, the next launch will rerun the
migration because the done flag was never written. Since the design uses fresh
UUIDs, it will create duplicate `Partner` rows for the same legacy
conversation(s). The current repo has no transaction boundary around the Hive
box that would make this atomic, and the only existing migration guard pattern
is a coarse settings-box flag
(`lib/features/conversation/data/repositories/conversation_repository.dart:17-36`).

This needs a deterministic rerun strategy, not just a final flag.

### [P2] The token-budget claim is not backed by a hard cap or ranking rule

The spec says the `Partner` summary should be about `200-400` tokens and that
the added prompt cost is negligible
(`docs/plans/2026-04-25-partner-entity-design.md:134,150`).

Current analysis payload already includes:

- session context (`supabase/functions/analyze-chat/index.ts:4109-4116`)
- older context summary (`supabase/functions/analyze-chat/index.ts:4120-4121`)
- recent conversation text (`supabase/functions/analyze-chat/index.ts:4125-4141`)

and the server already rejects oversized summary context at `5000` chars
(`supabase/functions/analyze-chat/index.ts:264,3159-3178`). The client even
maps that failure into a dedicated `CONTEXT_TOO_LONG` path
(`lib/features/analysis/data/services/analysis_service.dart:270-275`).

On top of that, current partner-like data would likely come from persisted
analysis snapshots
(`lib/features/analysis/presentation/screens/analysis_screen.dart:489`),
which are raw JSON and not size-bounded for prompt reuse. So `200-400 tokens`
is not a guarantee yet; it is only a hope. The spec needs a concrete selection
and truncation algorithm before A2.

### [P2] `auto invalidate on any Conversation change` is too blunt for the
current Riverpod graph

The design proposes wrapping Partner aggregates in a
`Provider.family<Partner, String>` and auto-invalidating it on any
conversation change (`docs/plans/2026-04-25-partner-entity-design.md:128`).

Current providers are very coarse:

- `conversationsProvider` re-reads the full list
  (`lib/features/conversation/data/providers/conversation_providers.dart:21-25`)
- `conversationProvider(id)` re-reads by id
  (`lib/features/conversation/data/providers/conversation_providers.dart:28-34`)
- the app already invalidates those providers from many UI paths
  (`lib/features/analysis/presentation/screens/analysis_screen.dart:495-514,542,614,650,935-936,1000-1001,1113`,
  `lib/features/conversation/presentation/screens/home_screen.dart:91`,
  `lib/features/conversation/presentation/screens/new_conversation_screen.dart:146`)

If Partner aggregation is derived from all conversations and invalidated on
every write, the home list, partner detail, and analysis flows will all fan out
through the same coarse provider graph. That is a real UI churn risk. The spec
should name a narrower invalidation boundary before A2.

### [P2] A1 effort and test scope are too optimistic for the migration risk

The doc budgets `Schema + Migration` at `1.5` days and total test work at
`1.5` days
(`docs/plans/2026-04-25-partner-entity-design.md:232,240,247`).
That is light for a change that includes:

- a new Hive entity + adapter/codegen
- startup migration
- rerun/idempotence guarantees
- Sentry instrumentation
- at least one TF soak before A2

The current repo test surface is also still fairly thin around storage and
migration. There is only one lightweight repository unit test file for
conversation parsing (`test/unit/repositories/conversation_repository_test.dart`),
and no existing Hive migration integration harness. I would not plan A1 as
`1.5` days unless the migration scope is simplified.

## Verified non-blocker

### `Conversation @HiveField(15)` looks free

The current `Conversation` entity uses fields `0..14`
(`lib/features/conversation/domain/entities/conversation.dart:8-62`), and the
generated adapter writes 15 fields total ending at field `14`
(`lib/features/conversation/domain/entities/conversation.g.dart:9-41`).

So `@HiveField(15)` is currently available and is not the blocker.

## Recommended spec changes before implementation

1. Reassign `Partner` to a new unused Hive type id, then rerun the repo grep
   during implementation.
2. Replace the migration algorithm with a rerun-safe plan:
   - deterministic legacy-to-partner mapping
   - checkpointable progress
   - no "fresh UUID every rerun" behavior
3. Add an explicit `Partner` prompt budget:
   - ranking rule
   - max items per section
   - char cap before request assembly
4. Re-estimate A1 separately from A2 after the migration rewrite.

## Recommended path

Do **not** start the A1 implementation plan from the current spec. First revise
the design doc on the two P1 issues, then rerun Codex spec review.
