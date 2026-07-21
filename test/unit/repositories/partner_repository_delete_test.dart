import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
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

UnifiedCoachResult _unifiedRow(
  String id, {
  required String scopeType,
  required String scopeId,
}) {
  return UnifiedCoachResult(
    id: id,
    conversationId: scopeType == 'conversation' ? scopeId : null,
    partnerId: scopeType == 'partner' ? scopeId : null,
    question: '接下來怎麼推進？',
    mode: 'partnerFollowUp',
    headline: '維持輕鬆節奏',
    answer: '她回覆變快。',
    userState: '你可能太急。',
    nextStep: '丟一個開放式問題。',
    boundaryReminder: '不要連發三則。',
    needsReflection: false,
    generatedAt: DateTime(2026, 7, 21, 11),
    provider: 'claude',
    modelUsed: 'claude-sonnet-5',
    scopeType: scopeType,
    scopeId: scopeId,
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
    if (!Hive.isAdapterRegistered(26)) {
      Hive.registerAdapter(UnifiedCoachResultAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    // delete() cascades opener drafts, which live in the shared settings box.
    await Hive.openBox(AppConstants.settingsBox);
    // delete() also cascades unified coach rows (Phase D), which the repo
    // reaches through the real box name via StorageService.
    await Hive.openBox<UnifiedCoachResult>('unified_coach_results');
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
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
    await Hive.deleteBoxFromDisk('unified_coach_results');
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

  test(
      'delete 清掉該對象的 unified partner rows，'
      '其他 partner 與 conversation scope 保留', () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);

    final unifiedBox =
        Hive.box<UnifiedCoachResult>('unified_coach_results');
    await unifiedBox.put(
      'u-p1-a',
      _unifiedRow('u-p1-a', scopeType: 'partner', scopeId: 'p1'),
    );
    await unifiedBox.put(
      'u-p1-b',
      _unifiedRow('u-p1-b', scopeType: 'partner', scopeId: 'p1'),
    );
    await unifiedBox.put(
      'u-p2',
      _unifiedRow('u-p2', scopeType: 'partner', scopeId: 'p2'),
    );
    await unifiedBox.put(
      'u-c1',
      _unifiedRow('u-c1', scopeType: 'conversation', scopeId: 'c1'),
    );

    await repo.delete('p1');

    expect(partnerBox.containsKey('p1'), isFalse);
    expect(
      unifiedBox.values.where(
        (r) => r.scopeType == 'partner' && r.scopeId == 'p1',
      ),
      isEmpty,
    );
    expect(unifiedBox.keys, containsAll(['u-p2', 'u-c1']));
    expect(unifiedBox.length, 2);
  });

  test('unified box 未開時 delete 不炸，其餘 cascade 照舊', () async {
    final p = _partner('p1');
    await partnerBox.put(p.id, p);
    await Hive.box<UnifiedCoachResult>('unified_coach_results').close();

    await repo.delete('p1');

    expect(partnerBox.containsKey('p1'), isFalse);
  });
}
