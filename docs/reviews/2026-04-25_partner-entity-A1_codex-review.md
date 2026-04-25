# 2026-04-25 Partner Entity Refactor A1 Codex Review

## Verdict

`REQUEST_CHANGES` — do not open the PR yet.

The branch is close, but two implementation issues still block landing A1 on
`main`:

1. `StorageService` now imports `dart:io` directly, which is not web-safe and
   risks breaking the web build / preview path.
2. `PartnerMigrationService.runIfNeeded()` always writes the migration-done flag
   even when per-conversation failures occurred, so partial migration can become
   permanently stuck until a manual redo path exists.

## Findings

### [P1] `StorageService` reintroduces a direct `dart:io` import into a shared startup path

- File: `lib/core/services/storage_service.dart:2`
- Evidence:
  - The file now imports `dart:io show File;`
  - `lib/main.dart` calls `StorageService.initialize()` on app startup
  - The repo already uses conditional IO gating for shared code, e.g.
    `lib/core/utils/platform_info.dart`
  - `AGENTS.md` explicitly lists `Flutter Web 用 dart:io -> 不支援` as a live pitfall
- Why this blocks landing:
  - A1 does not just add a mobile-only helper; it places the import in a shared
    core service on the app bootstrap path.
  - `kIsWeb` inside `_backupConversationBox()` is too late; the import itself is
    what makes the file non-web-safe.
- Expected fix direction:
  - Move backup IO behind a conditional import / platform abstraction, or split
    the backup helper into native + web implementations.

### [P1] The migration marks itself done even when rows failed, so failed legacy rows will not auto-retry

- File: `lib/features/partner/data/services/partner_migration_service.dart:65-74`
- Evidence:
  - `_migrateLoop()` catches and logs per-row errors, then continues
  - `runIfNeeded()` still unconditionally sets `_kMigrationDoneFlag = true`
  - The crash-safe tests only recover by calling `resetForRedo()` manually
  - `resetForRedo()` is not wired into the app yet; it is only referenced in
    tests and the A1 plan
- Why this blocks landing:
  - On a real device, one failed `convo.save()` or row-level exception can
    leave some conversations with `partnerId == null`
  - Because the done flag is already written, the next cold start short-circuits
    and the unfinished rows never get another automatic pass
  - A2 may later add a redo UI, but A1 explicitly ships without that escape hatch
- Expected fix direction:
  - Track whether any per-row failures occurred and refuse to write the done
    flag when the migration was only partially successful
  - Keep the existing per-row isolation if desired, but let future boots retry
    unfinished rows automatically

## HS Judgments

### HS1 — Sentry SDK gap

`APPROVE_DEFER`

I agree with Claude's direction here: after the two blockers above are fixed,
keeping A1 on `dart:developer.log(name: 'partner_migration')` is acceptable for
the planned TF soak. Adding `sentry_flutter` inside A1 would increase blast
radius more than it helps, especially because the migration path itself is what
we are trying to stabilize.

Condition:

- This defer is acceptable only if the migration correctness issue above is
  fixed first. Without that fix, local-only logs are too weak because the app
  can silently mark a partial migration as done.

### HS2 — Redo-backup policy

`KEEP_CURRENT_POLICY`

I agree with the current redo-rebackup policy. For a user-initiated redo,
treating the current on-device state as the new ground truth is a reasonable
default, and it matches Claude's rationale better than freezing a possibly
stale first-run backup forever.

## Notes

- Verified separately: `Partner @HiveType(typeId: 8)` is still collision-free
  on this branch (`grep -rn 'typeId:' lib/`).
- No review finding on the deterministic UUID namespace, backup gate shape, or
  the close+reopen crash-safe test adjustment itself.
