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

late Box<Conversation> convoBox;
late Box<Partner> partnerBox;
late Box<PartnerStyleOverride> styleBox;
late Box<PartnerDataQualityState> qualityBox;
late Box<CoachFollowUpResult> followUpBox;
late Box<CoachingOutcomeEvent> outcomeBox;
late PartnerDataQualityRepository qualityRepo;
late PartnerRepository repo;

Partner _partner({
  required String id,
  String name = 'p',
  String? ownerUserId = 'u-1',
  String? customNote,
}) {
  final now = DateTime(2026, 4, 26, 10, 0);
  return Partner(
    id: id,
    name: name,
    createdAt: now,
    updatedAt: now,
    ownerUserId: ownerUserId,
    customNote: customNote,
  );
}

Conversation _convo({
  required String id,
  String? partnerId,
  String? ownerUserId = 'u-1',
}) {
  final now = DateTime(2026, 4, 26, 10, 0);
  return Conversation(
    id: id,
    name: 'c-$id',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    ownerUserId: ownerUserId,
    partnerId: partnerId,
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

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo_merge');
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
    // merge() reassigns opener drafts, which live in the shared settings box.
    await Hive.openBox(AppConstants.settingsBox);
    // merge() also cascades the source partner's unified coach rows (Phase D),
    // reached through the real box name via StorageService.
    await Hive.openBox<UnifiedCoachResult>('unified_coach_results');
    convoBox = await Hive.openBox<Conversation>('merge_conv_$ts');
    partnerBox = await Hive.openBox<Partner>('merge_partner_$ts');
    styleBox = await Hive.openBox<PartnerStyleOverride>('merge_style_$ts');
    qualityBox =
        await Hive.openBox<PartnerDataQualityState>('merge_quality_$ts');
    followUpBox = await Hive.openBox<CoachFollowUpResult>('merge_followup_$ts');
    outcomeBox = await Hive.openBox<CoachingOutcomeEvent>('merge_outcome_$ts');
    qualityRepo = PartnerDataQualityRepository(injectedBox: qualityBox);
    repo = PartnerRepository(
      box: partnerBox,
      conversationBox: convoBox,
      styleRepo: PartnerStyleRepository(box: styleBox),
      qualityRepo: qualityRepo,
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
    await convoBox.deleteFromDisk();
    await partnerBox.deleteFromDisk();
  });

  group('PartnerRepository.listByOwner', () {
    test('returns only partners with matching ownerUserId', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', ownerUserId: 'u-1'));
      await partnerBox.put('p-b', _partner(id: 'p-b', ownerUserId: 'u-2'));
      await partnerBox.put('p-c', _partner(id: 'p-c', ownerUserId: 'u-1'));

      final result = repo.listByOwner('u-1');

      expect(result.map((p) => p.id).toSet(), {'p-a', 'p-c'});
    });

    test('returns empty list for unknown owner', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', ownerUserId: 'u-1'));
      expect(repo.listByOwner('u-stranger'), isEmpty);
    });

    test('null ownerUserId rows are excluded (defensive)', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', ownerUserId: null));
      await partnerBox.put('p-b', _partner(id: 'p-b', ownerUserId: 'u-1'));
      expect(repo.listByOwner('u-1').map((p) => p.id), ['p-b']);
    });
  });

  group('PartnerRepository.merge', () {
    test('re-points all conversations from A to B', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', name: 'A'));
      await partnerBox.put('p-b', _partner(id: 'p-b', name: 'B'));
      await convoBox.put('c-1', _convo(id: 'c-1', partnerId: 'p-a'));
      await convoBox.put('c-2', _convo(id: 'c-2', partnerId: 'p-a'));
      await convoBox.put('c-3', _convo(id: 'c-3', partnerId: 'p-b'));

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(convoBox.get('c-1')!.partnerId, 'p-b');
      expect(convoBox.get('c-2')!.partnerId, 'p-b');
      expect(convoBox.get('c-3')!.partnerId, 'p-b');
    });

    test('deletes Partner A after re-pointing', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', name: 'A'));
      await partnerBox.put('p-b', _partner(id: 'p-b', name: 'B'));
      await convoBox.put('c-1', _convo(id: 'c-1', partnerId: 'p-a'));

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(partnerBox.get('p-a'), isNull);
      expect(partnerBox.get('p-b'), isNotNull);
    });

    test(
        'appends A.customNote into B.customNote with [from A] tag '
        '(B already has note → join with newline)', () async {
      await partnerBox.put(
          'p-a', _partner(id: 'p-a', name: 'A', customNote: '永春附近'));
      await partnerBox.put(
          'p-b', _partner(id: 'p-b', name: 'B', customNote: '台大附近'));

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(partnerBox.get('p-b')!.customNote, '台大附近\n[from A] 永春附近');
    });

    test('B has no note → tag + A.customNote becomes the new note', () async {
      await partnerBox.put(
          'p-a', _partner(id: 'p-a', name: 'A', customNote: '永春附近'));
      await partnerBox.put(
          'p-b', _partner(id: 'p-b', name: 'B', customNote: null));

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(partnerBox.get('p-b')!.customNote, '[from A] 永春附近');
    });

    test('A has no note → B.customNote unchanged', () async {
      await partnerBox.put(
          'p-a', _partner(id: 'p-a', name: 'A', customNote: null));
      await partnerBox.put(
          'p-b', _partner(id: 'p-b', name: 'B', customNote: '台大附近'));

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(partnerBox.get('p-b')!.customNote, '台大附近');
    });

    test('merge is no-op when from and to are the same id', () async {
      await partnerBox.put(
          'p-a', _partner(id: 'p-a', name: 'A', customNote: 'note'));
      await convoBox.put('c-1', _convo(id: 'c-1', partnerId: 'p-a'));

      await repo.merge(fromId: 'p-a', toId: 'p-a');

      expect(partnerBox.get('p-a'), isNotNull);
      expect(convoBox.get('c-1')!.partnerId, 'p-a');
    });

    test('throws ArgumentError when source partner missing (no partial state)',
        () async {
      await partnerBox.put('p-b', _partner(id: 'p-b', name: 'B'));
      await convoBox.put('c-1', _convo(id: 'c-1', partnerId: 'p-a'));

      await expectLater(
        repo.merge(fromId: 'p-a', toId: 'p-b'),
        throwsArgumentError,
      );
      expect(convoBox.get('c-1')!.partnerId, 'p-a',
          reason: 'no conversations re-pointed when merge throws');
    });

    test('throws ArgumentError when target partner missing', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', name: 'A'));
      await expectLater(
        repo.merge(fromId: 'p-a', toId: 'p-missing'),
        throwsArgumentError,
      );
      expect(partnerBox.get('p-a'), isNotNull,
          reason: 'source partner not deleted when merge throws');
    });

    test('updates B.updatedAt to reflect the merge', () async {
      final old = DateTime(2026, 1, 1);
      await partnerBox.put(
        'p-a',
        Partner(
            id: 'p-a',
            name: 'A',
            createdAt: old,
            updatedAt: old,
            ownerUserId: 'u-1'),
      );
      await partnerBox.put(
        'p-b',
        Partner(
            id: 'p-b',
            name: 'B',
            createdAt: old,
            updatedAt: old,
            ownerUserId: 'u-1'),
      );

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(partnerBox.get('p-b')!.updatedAt.isAfter(old), isTrue);
    });

    test('cascades quality state cleanup on source partner only', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a', name: 'A'));
      await partnerBox.put('p-b', _partner(id: 'p-b', name: 'B'));
      await qualityRepo.markSamePerson(
        'p-a',
        NamePair.canonical('May', 'Anna'),
      );
      await qualityRepo.markSamePerson(
        'p-b',
        NamePair.canonical('Bob', 'Robert'),
      );
      expect(qualityBox.get('p-a'), isNotNull);
      expect(qualityBox.get('p-b'), isNotNull);

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      // Source A's quality state cleared.
      expect(qualityBox.get('p-a'), isNull);
      // Target B's quality state preserved (B survives the merge).
      final pBState = qualityBox.get('p-b');
      expect(pBState, isNotNull);
      expect(
        pBState!.confirmsSamePerson(NamePair.canonical('Bob', 'Robert')),
        isTrue,
      );
    });

    test('merge 清掉來源對象的 unified partner rows，目標與 conversation 保留',
        () async {
      await partnerBox.put('p-a', _partner(id: 'p-a'));
      await partnerBox.put('p-b', _partner(id: 'p-b'));

      final unifiedBox =
          Hive.box<UnifiedCoachResult>('unified_coach_results');
      await unifiedBox.put(
        'u-from',
        _unifiedRow('u-from', scopeType: 'partner', scopeId: 'p-a'),
      );
      await unifiedBox.put(
        'u-to',
        _unifiedRow('u-to', scopeType: 'partner', scopeId: 'p-b'),
      );
      await unifiedBox.put(
        'u-c1',
        _unifiedRow('u-c1', scopeType: 'conversation', scopeId: 'c-1'),
      );

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(
        unifiedBox.values.where(
          (r) => r.scopeType == 'partner' && r.scopeId == 'p-a',
        ),
        isEmpty,
      );
      expect(unifiedBox.keys, containsAll(['u-to', 'u-c1']));
      expect(unifiedBox.length, 2);
    });

    test('unified box 未開時 merge 不炸，其餘 cascade 照舊', () async {
      await partnerBox.put('p-a', _partner(id: 'p-a'));
      await partnerBox.put('p-b', _partner(id: 'p-b'));
      await Hive.box<UnifiedCoachResult>('unified_coach_results').close();

      await repo.merge(fromId: 'p-a', toId: 'p-b');

      expect(partnerBox.containsKey('p-a'), isFalse);
      expect(partnerBox.containsKey('p-b'), isTrue);
    });
  });
}
