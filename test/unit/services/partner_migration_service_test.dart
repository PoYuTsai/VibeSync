import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/data/services/partner_id_factory.dart';
import 'package:vibesync/features/partner/data/services/partner_migration_service.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

late Box<Conversation> convoBox;
late Box<Partner> partnerBox;
late PartnerRepository repo;

Future<void> _setUpBoxes() async {
  Hive.init('./.dart_tool/test_hive_partner_migration');
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ConversationAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MessageAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ConversationSummaryAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(MeetingContextAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AcquaintanceDurationAdapter());
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
  if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(SessionContextAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(UserStyleAdapter());
  if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PartnerAdapter());

  final ts = DateTime.now().microsecondsSinceEpoch;
  convoBox = await Hive.openBox<Conversation>('conv_mig_$ts');
  partnerBox = await Hive.openBox<Partner>('partner_mig_$ts');
  repo = PartnerRepository(box: partnerBox);
}

Future<void> _tearDownBoxes() async {
  await convoBox.deleteFromDisk();
  await partnerBox.deleteFromDisk();
}

Conversation _legacyConv(String id, String name) {
  final t = DateTime(2026, 4, 25);
  return Conversation(
    id: id,
    name: name,
    messages: const [],
    createdAt: t,
    updatedAt: t,
    ownerUserId: 'user-1',
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _setUpBoxes();
  });

  tearDown(_tearDownBoxes);

  test('happy path — N legacy conversations → N partners with deterministic ids',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    await convoBox.put('c-2', _legacyConv('c-2', '小白'));
    await convoBox.put('c-3', _legacyConv('c-3', '阿狗'));

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: await SharedPreferences.getInstance(),
    );
    await svc.runIfNeeded();

    expect(partnerBox.length, 3);
    for (final id in ['c-1', 'c-2', 'c-3']) {
      final expectedPartnerId =
          PartnerIdFactory.deriveFromConversationId(id);
      expect(convoBox.get(id)!.partnerId, expectedPartnerId);
      expect(partnerBox.get(expectedPartnerId)?.name,
          convoBox.get(id)!.name);
    }
  });

  test('continuity — conv-abc maps to recorded UUID from Task 3', () async {
    await convoBox.put('conv-abc', _legacyConv('conv-abc', 'continuity-check'));

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: await SharedPreferences.getInstance(),
    );
    await svc.runIfNeeded();

    expect(
      convoBox.get('conv-abc')!.partnerId,
      '3a9475c9-fb99-5117-8e19-6a42c0298c49',
      reason: 'If this fails, the namespace constant or the v5 derivation '
              'changed since Task 3 — investigate before proceeding.',
    );
  });

  test(
      'idempotent — running twice yields identical state '
      '(partner box size + every convo.partnerId)',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    await convoBox.put('c-2', _legacyConv('c-2', '小白'));

    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
    );

    await svc.runIfNeeded();
    final firstPartnerIds = partnerBox.keys.toSet();
    final firstConvoMap = {
      for (final c in convoBox.values) c.id: c.partnerId
    };

    // Force a real second pass by clearing the perf-shortcut flags.
    // Correctness must NOT depend on those flags — only on deterministic
    // UUID v5 + per-row partnerId marker.
    await svc.resetForRedo();
    await svc.runIfNeeded();

    expect(partnerBox.keys.toSet(), firstPartnerIds);
    expect(
      {for (final c in convoBox.values) c.id: c.partnerId},
      firstConvoMap,
    );
    expect(partnerBox.length, 2); // no duplicate partners
  });

  test(
      'crash-safe — interrupted mid-loop then rerun = same final state '
      'as a single uninterrupted run',
      () async {
    // Capture box names so we can reopen with the same identity after
    // simulating process death via close.
    final convoBoxName = convoBox.name;
    final partnerBoxName = partnerBox.name;

    for (var i = 1; i <= 5; i++) {
      await convoBox.put('c-$i', _legacyConv('c-$i', 'p-$i'));
    }
    final prefs = await SharedPreferences.getInstance();

    // Round 1 — boom on the 3rd convo via the test seam.
    var calls = 0;
    final svc1 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      onBeforeSavePerConvo: (_) {
        calls++;
        if (calls == 3) throw StateError('simulated crash');
      },
    );
    await svc1.runIfNeeded();

    // Simulate process death — close both boxes so the next reads are
    // forced through disk, not in-memory aliasing of HiveObjects.
    await convoBox.close();
    await partnerBox.close();

    // Reopen with the same names. Test-suite-level state (Hive.init,
    // adapters) is still live; only the box handles are fresh.
    convoBox = await Hive.openBox<Conversation>(convoBoxName);
    partnerBox = await Hive.openBox<Partner>(partnerBoxName);
    repo = PartnerRepository(box: partnerBox);

    // After the close+reopen, the on-disk state is what we see. The
    // service's per-row try/catch swallowed the seam throw and let
    // runIfNeeded complete, so the done flag is set — but per-row failure
    // means the 3rd convo's `partnerId` was NEVER persisted to disk.
    final partial = convoBox.values
        .where((c) => c.partnerId != null)
        .length;
    expect(partial, lessThan(5),
        reason: 'At least one row must remain unmigrated on disk after '
                'a mid-loop crash — proves the test models real process '
                'death, not in-memory HiveObject aliasing.');

    // Round 2 — fresh service, no crash. Correctness must NOT depend on
    // the done flag. Force a real second pass.
    await svc1.resetForRedo();
    final svc2 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
    );
    await svc2.runIfNeeded();

    // Every convo has the deterministic partnerId, partnerBox holds 5,
    // partnerIds are byte-identical to a single uninterrupted run.
    for (var i = 1; i <= 5; i++) {
      final c = convoBox.get('c-$i')!;
      expect(c.partnerId,
          PartnerIdFactory.deriveFromConversationId('c-$i'));
    }
    expect(partnerBox.length, 5);
  });

  test('backup throw → service rethrows → both flags stay false, loop never ran',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async {
        throw StateError('simulated disk full during backup');
      },
    );

    await expectLater(svc.runIfNeeded(), throwsA(isA<StateError>()));

    expect(prefs.getBool('partner_migration_v1_done'), isNot(true));
    expect(prefs.getBool('partner_migration_v1_backup_done'), isNot(true));
    expect(convoBox.get('c-1')!.partnerId, isNull,
        reason: 'Loop must not have run if backup failed');
    expect(partnerBox.length, 0);
  });

  test(
      'redo re-takes the backup (HS2 hot spot — Codex review will judge '
      'whether redo should overwrite the prior backup)',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    final prefs = await SharedPreferences.getInstance();
    var backupCalls = 0;

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async => backupCalls++,
    );
    await svc.runIfNeeded();
    expect(backupCalls, 1, reason: 'Backup runs once per first migration');

    await svc.resetForRedo();
    await svc.runIfNeeded();
    expect(backupCalls, 2,
        reason: 'Current policy (HS2): redo re-runs backup, overwriting '
                'prior backup file. Codex may flip this to one-shot. If '
                'this assertion ever changes from 2 to 1, also flip the '
                'resetForRedo dartdoc and the plan HS2 description.');
  });
}
