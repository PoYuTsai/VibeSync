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
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(ConversationSummaryAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(MeetingContextAdapter());
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter(AcquaintanceDurationAdapter());
  }
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
  if (!Hive.isAdapterRegistered(6)) {
    Hive.registerAdapter(SessionContextAdapter());
  }
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

  test('happy path maps N legacy conversations to N partners', () async {
    await convoBox.put('c-1', _legacyConv('c-1', 'alpha'));
    await convoBox.put('c-2', _legacyConv('c-2', 'beta'));
    await convoBox.put('c-3', _legacyConv('c-3', 'gamma'));

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: await SharedPreferences.getInstance(),
    );
    await svc.runIfNeeded();

    expect(partnerBox.length, 3);
    for (final id in ['c-1', 'c-2', 'c-3']) {
      final expectedPartnerId = PartnerIdFactory.deriveFromConversationId(id);
      expect(convoBox.get(id)!.partnerId, expectedPartnerId);
      expect(partnerBox.get(expectedPartnerId)?.name, convoBox.get(id)!.name);
    }
  });

  test('continuity keeps conv-abc mapped to the recorded UUID', () async {
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
      reason: 'If this fails, the namespace constant or v5 derivation drifted.',
    );
  });

  test(
      'idempotent rerun yields identical state after resetForRedo clears perf flags',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', 'alpha'));
    await convoBox.put('c-2', _legacyConv('c-2', 'beta'));

    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
    );

    await svc.runIfNeeded();
    final firstPartnerIds = partnerBox.keys.toSet();
    final firstConvoMap = {for (final c in convoBox.values) c.id: c.partnerId};

    await svc.resetForRedo();
    await svc.runIfNeeded();

    expect(partnerBox.keys.toSet(), firstPartnerIds);
    expect({for (final c in convoBox.values) c.id: c.partnerId}, firstConvoMap);
    expect(partnerBox.length, 2);
  });

  test(
      'crash-safe rerun auto-retries unfinished rows without manual reset',
      () async {
    final convoBoxName = convoBox.name;
    final partnerBoxName = partnerBox.name;

    for (var i = 1; i <= 5; i++) {
      await convoBox.put('c-$i', _legacyConv('c-$i', 'p-$i'));
    }
    final prefs = await SharedPreferences.getInstance();

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
    expect(
      prefs.getBool('partner_migration_v1_done'),
      isNot(true),
      reason: 'A partial-failure pass must stay retryable on next cold boot.',
    );

    await convoBox.close();
    await partnerBox.close();

    convoBox = await Hive.openBox<Conversation>(convoBoxName);
    partnerBox = await Hive.openBox<Partner>(partnerBoxName);
    repo = PartnerRepository(box: partnerBox);

    final partial = convoBox.values.where((c) => c.partnerId != null).length;
    expect(
      partial,
      lessThan(5),
      reason:
          'At least one row must remain unfinished on disk after mid-loop crash.',
    );

    final svc2 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
    );
    await svc2.runIfNeeded();
    expect(prefs.getBool('partner_migration_v1_done'), true);

    for (var i = 1; i <= 5; i++) {
      final c = convoBox.get('c-$i')!;
      expect(c.partnerId, PartnerIdFactory.deriveFromConversationId('c-$i'));
    }
    expect(partnerBox.length, 5);
  });

  test('backup throw rethrows and keeps both flags false', () async {
    await convoBox.put('c-1', _legacyConv('c-1', 'alpha'));
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
    expect(
      convoBox.get('c-1')!.partnerId,
      isNull,
      reason: 'Loop must not have run if backup failed.',
    );
    expect(partnerBox.length, 0);
  });

  test('redo re-takes the backup under current HS2 policy', () async {
    await convoBox.put('c-1', _legacyConv('c-1', 'alpha'));
    final prefs = await SharedPreferences.getInstance();
    var backupCalls = 0;

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async => backupCalls++,
    );
    await svc.runIfNeeded();
    expect(backupCalls, 1, reason: 'Backup runs once per first migration.');

    await svc.resetForRedo();
    await svc.runIfNeeded();
    expect(
      backupCalls,
      2,
      reason:
          'Current policy re-runs backup on redo. Update tests/docs if policy flips.',
    );
  });
}
