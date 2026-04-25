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

Future<void> _setUp() async {
  Hive.init('./.dart_tool/test_hive_partner_integration');
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
  convoBox = await Hive.openBox<Conversation>('integ_conv_$ts');
  partnerBox = await Hive.openBox<Partner>('integ_partner_$ts');
  repo = PartnerRepository(box: partnerBox);
}

Future<void> _tearDown() async {
  await convoBox.deleteFromDisk();
  await partnerBox.deleteFromDisk();
}

Conversation _bruceConv({
  required String id,
  required String name,
  required String ownerUserId,
  int messageCount = 4,
  int? heat,
}) {
  final t = DateTime(2026, 4, 25, 18, 0).add(Duration(minutes: id.hashCode % 60));
  final messages = <Message>[
    for (var i = 0; i < messageCount; i++)
      Message(
        id: '$id-msg-$i',
        content: i.isEven ? '她說 $i' : '我說 $i',
        timestamp: t.add(Duration(minutes: i)),
        isFromMe: i.isOdd,
      ),
  ];
  return Conversation(
    id: id,
    name: name,
    messages: messages,
    createdAt: t,
    updatedAt: t,
    ownerUserId: ownerUserId,
    lastEnthusiasmScore: heat,
    summaries: const [],
    currentRound: 2,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _setUp();
  });

  tearDown(_tearDown);

  test(
      'Bruce scenario — 5 legacy conversations (2 named 糖糖) → 5 distinct '
      'Partners with deterministic ids, Migration B preserved',
      () async {
    // Bruce's real shape: same owner, 2 same-name conversations + 3 others.
    await convoBox.put('c-1',
        _bruceConv(id: 'c-1', name: '糖糖', ownerUserId: 'bruce', heat: 95));
    await convoBox.put('c-2',
        _bruceConv(id: 'c-2', name: '糖糖', ownerUserId: 'bruce', heat: 85));
    await convoBox.put('c-3',
        _bruceConv(id: 'c-3', name: '小白', ownerUserId: 'bruce', heat: 60));
    await convoBox.put('c-4',
        _bruceConv(id: 'c-4', name: '阿狗', ownerUserId: 'bruce', heat: 45));
    await convoBox.put('c-5',
        _bruceConv(id: 'c-5', name: '貓貓', ownerUserId: 'bruce', heat: 70));

    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async {},
    );
    await svc.runIfNeeded();

    // Migration B: each conversation = its own Partner. 5 conversations
    // → 5 distinct Partners, even when names collide.
    expect(partnerBox.length, 5,
        reason: 'Migration B: 2 同名糖糖 stays separate, no name-based merge');

    // Every convo has its deterministic partnerId set.
    for (final id in ['c-1', 'c-2', 'c-3', 'c-4', 'c-5']) {
      final expected = PartnerIdFactory.deriveFromConversationId(id);
      expect(convoBox.get(id)!.partnerId, expected);
      expect(partnerBox.get(expected), isNotNull);
    }

    // The 2 糖糖 partners have distinct ids.
    final tangtangIds = ['c-1', 'c-2']
        .map(PartnerIdFactory.deriveFromConversationId)
        .toList();
    expect(tangtangIds[0], isNot(tangtangIds[1]));
    expect(partnerBox.get(tangtangIds[0])?.name, '糖糖');
    expect(partnerBox.get(tangtangIds[1])?.name, '糖糖');

    // Round-trip preserves payload — pick c-1 and verify message count + heat.
    final c1 = convoBox.get('c-1')!;
    expect(c1.messages.length, 4);
    expect(c1.lastEnthusiasmScore, 95);
    expect(c1.ownerUserId, 'bruce');
  });

  test(
      'Bruce scenario — rerun migration is a no-op (production-shaped data)',
      () async {
    await convoBox.put('c-1',
        _bruceConv(id: 'c-1', name: '糖糖', ownerUserId: 'bruce'));
    await convoBox.put('c-2',
        _bruceConv(id: 'c-2', name: '糖糖', ownerUserId: 'bruce'));

    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async {},
    );

    await svc.runIfNeeded();
    final firstKeys = partnerBox.keys.toSet();
    final firstMap = {
      for (final c in convoBox.values) c.id: c.partnerId,
    };

    await svc.resetForRedo();
    await svc.runIfNeeded();

    expect(partnerBox.keys.toSet(), firstKeys);
    expect({for (final c in convoBox.values) c.id: c.partnerId}, firstMap);
    expect(partnerBox.length, 2);
  });

  test(
      'Bruce scenario — process death mid-loop then rerun converges '
      '(close + reopen disk-backed boxes)',
      () async {
    final convoBoxName = convoBox.name;
    final partnerBoxName = partnerBox.name;

    for (final tuple in const [
      ('c-1', '糖糖'),
      ('c-2', '糖糖'),
      ('c-3', '小白'),
      ('c-4', '阿狗'),
      ('c-5', '貓貓'),
    ]) {
      await convoBox.put(tuple.$1,
          _bruceConv(id: tuple.$1, name: tuple.$2, ownerUserId: 'bruce'));
    }

    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final svc1 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async {},
      onBeforeSavePerConvo: (_) {
        calls++;
        if (calls == 3) throw StateError('process death simulated');
      },
    );
    await svc1.runIfNeeded();

    // Simulate process death.
    await convoBox.close();
    await partnerBox.close();
    convoBox = await Hive.openBox<Conversation>(convoBoxName);
    partnerBox = await Hive.openBox<Partner>(partnerBoxName);
    repo = PartnerRepository(box: partnerBox);

    final partial =
        convoBox.values.where((c) => c.partnerId != null).length;
    expect(partial, lessThan(5),
        reason: 'On disk, the 3rd save did not run');

    await svc1.resetForRedo();
    final svc2 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async {},
    );
    await svc2.runIfNeeded();

    for (final id in ['c-1', 'c-2', 'c-3', 'c-4', 'c-5']) {
      expect(convoBox.get(id)!.partnerId,
          PartnerIdFactory.deriveFromConversationId(id));
    }
    expect(partnerBox.length, 5);
  });
}
