import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coaching_memory/data/repositories/coaching_outcome_repository_impl.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

Partner _partner(String id) {
  final now = DateTime(2026, 4, 28);
  return Partner(
    id: id,
    name: 'A',
    ownerUserId: 'u1',
    createdAt: now,
    updatedAt: now,
  );
}

Conversation _conversation(
  String id, {
  required String partnerId,
  int rounds = 1,
}) {
  final now = DateTime(2026, 4, 28);
  final c = Conversation(
    id: id,
    name: '對話 $id',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    ownerUserId: 'u1',
    partnerId: partnerId,
  );
  c.currentRound = rounds;
  return c;
}

void main() {
  late Box<Partner> partnerBox;
  late Box<Conversation> conversationBox;
  late Box<PartnerStyleOverride> styleBox;
  late Box<PartnerDataQualityState> qualityBox;
  late Box<CoachFollowUpResult> followUpBox;
  late Box<CoachingOutcomeEvent> outcomeBox;
  late PartnerRepository repo;

  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo_delete');
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
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(PartnerDataQualityStateAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(NamePairAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(CoachFollowUpResultAdapter());
    }
    if (!Hive.isAdapterRegistered(18)) {
      Hive.registerAdapter(CoachingOutcomeEventAdapter());
    }
    if (!Hive.isAdapterRegistered(19)) {
      Hive.registerAdapter(CoachingOutcomeSourceAdapter());
    }
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(CoachingUserActionAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(CoachingOutcomeSignalAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    partnerBox = await Hive.openBox<Partner>('partners_$ts');
    conversationBox = await Hive.openBox<Conversation>('conversations_$ts');
    styleBox = await Hive.openBox<PartnerStyleOverride>('pso_$ts');
    qualityBox = await Hive.openBox<PartnerDataQualityState>('pdq_$ts');
    followUpBox = await Hive.openBox<CoachFollowUpResult>('cfu_$ts');
    outcomeBox = await Hive.openBox<CoachingOutcomeEvent>('outcome_$ts');
    repo = PartnerRepository(
      box: partnerBox,
      conversationBox: conversationBox,
      styleRepo: PartnerStyleRepository(box: styleBox),
      qualityRepo: PartnerDataQualityRepository(injectedBox: qualityBox),
      followUpRepo: CoachFollowUpRepositoryImpl(followUpBox),
      outcomeRepo: CoachingOutcomeRepositoryImpl(outcomeBox),
    );
  });

  tearDown(() async {
    await outcomeBox.deleteFromDisk();
    await followUpBox.deleteFromDisk();
    await qualityBox.deleteFromDisk();
    await styleBox.deleteFromDisk();
    await conversationBox.deleteFromDisk();
    await partnerBox.deleteFromDisk();
  });

  test('delete removes partner from box when no conversations linked',
      () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);

    await repo.delete('p1');

    expect(partnerBox.containsKey('p1'), isFalse);
  });

  test(
      'delete throws PartnerHasConversationsException when conversations exist',
      () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);
    final c = _conversation('c1', partnerId: 'p1');
    await conversationBox.put(c.id, c);

    expect(
      () => repo.delete('p1'),
      throwsA(isA<PartnerHasConversationsException>()
          .having((e) => e.conversationCount, 'count', 1)),
    );
    expect(partnerBox.containsKey('p1'), isTrue);
  });

  test('delete blocks even when conversation has currentRound == 0', () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);
    final c = _conversation('c0', partnerId: 'p1', rounds: 0);
    await conversationBox.put(c.id, c);

    expect(
      () => repo.delete('p1'),
      throwsA(isA<PartnerHasConversationsException>()),
    );
  });
}
