# 2026-04-25 Partner Entity Refactor A1 Codex Review

## Verdict

`APPROVED_FOR_PR`

Original blockers were valid when first filed, but they are now fixed on
`feature/partner-entity-A1` and the follow-up clean-env verification passed.

## Re-review Outcome

Follow-up verification provided by Claude on 2026-04-25:

- `test/unit/services/partner_migration_service_test.dart`: `6/6 PASS`
- `test/integration/partner_migration_integration_test.dart`: `3/3 PASS`
- `flutter analyze lib/core/services/ lib/features/partner/` + the two test
  files: `No issues found`

That is enough for go/no-go on A1. My final judgment is:

1. The web-safety fix is the right pattern, not a cosmetic workaround.
   `StorageService` no longer imports `dart:io` directly; the backup path is
   now hidden behind conditional imports:
   - `lib/core/services/conversation_box_backup.dart`
   - `lib/core/services/conversation_box_backup_native.dart`
   - `lib/core/services/conversation_box_backup_web.dart`
2. The migration correctness fix is real.
   `PartnerMigrationService.runIfNeeded()` now leaves partial-failure passes
   retryable by skipping the done flag when `_migrateLoop()` reports failures.
   That turns A1 from "manual redo required after some failure modes" into a
   self-healing cold-boot retry path.

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

Status:

- Resolved in `ae54a7a`

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

Status:

- Resolved in `ae54a7a`

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
