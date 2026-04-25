// lib/features/partner/data/services/partner_migration_service.dart
import 'dart:developer' as developer;

import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../conversation/domain/entities/conversation.dart';
import '../../domain/entities/partner.dart';
import '../repositories/partner_repository.dart';
import 'partner_id_factory.dart';

/// SharedPreferences keys.
///
/// IMPORTANT: these are perf shortcuts only. Migration *correctness* is
/// guaranteed by [PartnerIdFactory.deriveFromConversationId] (deterministic)
/// + per-row [Conversation.partnerId] marker (idempotent). Even if both
/// flags below were wiped, rerunning [PartnerMigrationService.runIfNeeded]
/// converges to the same final state as a single uninterrupted run.
const _kMigrationDoneFlag = 'partner_migration_v1_done';
const _kBackupDoneFlag = 'partner_migration_v1_backup_done';

/// Log tag — grep-able for the future Sentry hookup.
/// (HS1 hot spot for Codex review: A1 uses `dart:developer.log` because
///  `sentry_flutter` is not in pubspec. Replace this constant + the developer
///  calls with Sentry breadcrumbs once the SDK lands.)
const _kLogTag = 'partner_migration';

/// Owner-agnostic Hive migration that backfills a deterministic
/// [Partner] for each legacy [Conversation] and writes the derived id
/// back onto `Conversation.partnerId`. Idempotent + crash-safe.
class PartnerMigrationService {
  PartnerMigrationService({
    required Box<Conversation> conversationBox,
    required PartnerRepository partnerRepo,
    required SharedPreferences prefs,
    Future<void> Function()? backupConversationBox,

    /// Test-only injection point. Production callers must NOT pass this.
    /// Used by the crash-safe contract test (A1 task 8) to simulate a
    /// mid-loop interrupt deterministically.
    void Function(Conversation convo)? onBeforeSavePerConvo,
  })  : _convoBox = conversationBox,
        _partnerRepo = partnerRepo,
        _prefs = prefs,
        _backupConversationBox = backupConversationBox,
        _onBeforeSavePerConvo = onBeforeSavePerConvo;

  final Box<Conversation> _convoBox;
  final PartnerRepository _partnerRepo;
  final SharedPreferences _prefs;
  final Future<void> Function()? _backupConversationBox;
  final void Function(Conversation convo)? _onBeforeSavePerConvo;

  /// Run the migration if it has not yet completed on this device.
  ///
  /// Order of operations:
  /// 1. Skip immediately if the perf-shortcut "done" flag is set.
  /// 2. Run [_ensureBackup] (gated on its own flag). A backup throw
  ///    rethrows out and the loop never starts — next call retries.
  /// 3. Iterate the conversation box. For each row with `partnerId == null`,
  ///    derive the deterministic id, upsert the partner, set the marker,
  ///    save. Per-row failures are logged and skipped — they do NOT block
  ///    other rows or the done flag.
  /// 4. Write the done flag so the next call short-circuits.
  Future<void> runIfNeeded() async {
    if (_prefs.getBool(_kMigrationDoneFlag) == true) {
      return;
    }

    await _ensureBackup();
    await _migrateLoop();

    await _prefs.setBool(_kMigrationDoneFlag, true);
    developer.log('completed', name: _kLogTag);
  }

  Future<void> _ensureBackup() async {
    if (_prefs.getBool(_kBackupDoneFlag) == true) return;
    final hook = _backupConversationBox;
    if (hook != null) {
      await hook(); // throw → flag stays false → next run retries backup
    }
    await _prefs.setBool(_kBackupDoneFlag, true);
    developer.log('backup_completed', name: _kLogTag);
  }

  Future<void> _migrateLoop() async {
    for (final convo in _convoBox.values.toList()) {
      if (convo.partnerId != null) continue;
      try {
        final partnerId =
            PartnerIdFactory.deriveFromConversationId(convo.id);
        await _partnerRepo.upsertIfAbsent(Partner(
          id: partnerId,
          name: convo.name,
          avatarPath: convo.avatarPath,
          createdAt: convo.createdAt,
          updatedAt: convo.updatedAt,
          ownerUserId: convo.ownerUserId,
        ));
        convo.partnerId = partnerId;
        _onBeforeSavePerConvo?.call(convo);
        await convo.save();
      } catch (e, st) {
        developer.log(
          'per_convo_failed',
          name: _kLogTag,
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Test/dev-only: wipe both perf-shortcut flags so the next call to
  /// [runIfNeeded] re-runs the entire flow. Public because the in-app
  /// "重做升級" button (Task 11) calls this to force a re-migration on
  /// suspected corruption.
  ///
  /// HS2 hot spot for Codex review: this also clears [_kBackupDoneFlag],
  /// which means redo will re-take the backup (overwriting the prior
  /// backup file). Alternative is "backup is one-shot, never overwritten".
  /// Spec §5 #6 is ambiguous; we picked redo-rebackup. Codex must judge.
  Future<void> resetForRedo() async {
    await _prefs.remove(_kMigrationDoneFlag);
    await _prefs.remove(_kBackupDoneFlag);
  }
}
