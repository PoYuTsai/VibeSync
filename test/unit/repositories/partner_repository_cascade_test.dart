import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

Partner _partner(String id) {
  final now = DateTime(2026, 5, 1);
  return Partner(
    id: id,
    name: 'A',
    ownerUserId: 'u1',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Box<Partner> partnerBox;
  late Box<Conversation> conversationBox;
  late Box<PartnerStyleOverride> styleBox;
  late PartnerStyleRepository styleRepo;
  late PartnerRepository repo;

  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo_cascade');
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MessageAdapter());
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ConversationSummaryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(MeetingContextAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(AcquaintanceDurationAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(SessionContextAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(UserStyleAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PartnerAdapter());
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    partnerBox = await Hive.openBox<Partner>('partners_cascade_$ts');
    conversationBox =
        await Hive.openBox<Conversation>('conversations_cascade_$ts');
    styleBox = await Hive.openBox<PartnerStyleOverride>('pso_cascade_$ts');
    styleRepo = PartnerStyleRepository(box: styleBox);
    repo = PartnerRepository(
      box: partnerBox,
      conversationBox: conversationBox,
      styleRepo: styleRepo,
    );
  });

  tearDown(() async {
    await styleBox.deleteFromDisk();
    await conversationBox.deleteFromDisk();
    await partnerBox.deleteFromDisk();
  });

  test('delete cascades to clear partner style override', () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);
    await styleRepo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      notes: '對方慢熟',
      updatedAt: DateTime.utc(2026, 5, 1),
    ));
    expect(await styleRepo.load('p1'), isNotNull);

    await repo.delete('p1');

    expect(partnerBox.containsKey('p1'), isFalse);
    expect(await styleRepo.load('p1'), isNull);
  });

  test(
      'delete does NOT touch other partners style overrides',
      () async {
    final p1 = _partner('p1');
    final p2 = _partner('p2');
    await partnerBox.put(p1.id, p1);
    await partnerBox.put(p2.id, p2);
    await styleRepo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: DateTime.utc(2026, 5, 1),
    ));
    await styleRepo.save(PartnerStyleOverride.create(
      partnerId: 'p2',
      interactionStyle: InteractionStyle.gentle,
      updatedAt: DateTime.utc(2026, 5, 1),
    ));

    await repo.delete('p1');

    expect(await styleRepo.load('p1'), isNull);
    expect((await styleRepo.load('p2'))?.interactionStyle,
        InteractionStyle.gentle);
  });

  test('delete blocked by conversations does NOT clear style override',
      () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);
    final c = Conversation(
      id: 'c1',
      name: 'conv',
      messages: const [],
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
      ownerUserId: 'u1',
      partnerId: 'p1',
    );
    c.currentRound = 1;
    await conversationBox.put(c.id, c);
    await styleRepo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: DateTime.utc(2026, 5, 1),
    ));

    expect(
      () => repo.delete('p1'),
      throwsA(isA<PartnerHasConversationsException>()),
    );
    // Override survives the failed delete — atomic-failure semantics.
    expect(await styleRepo.load('p1'), isNotNull);
  });
}
