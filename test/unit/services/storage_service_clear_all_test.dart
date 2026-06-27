import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_storage_clear_all');
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
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(TopicSeedAdapter());
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
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(CoachChatResultAdapter());
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
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(PracticeMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(23)) {
      Hive.registerAdapter(PracticeSessionAdapter());
    }
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.conversationsBox);
    await Hive.deleteBoxFromDisk(AppConstants.partnersBox);
    await Hive.deleteBoxFromDisk('user_profile');
    await Hive.deleteBoxFromDisk('partner_style_overrides');
    await Hive.deleteBoxFromDisk('partner_data_quality_states');
    await Hive.deleteBoxFromDisk('coach_follow_up_results');
    await Hive.deleteBoxFromDisk('coach_chat_results');
    await Hive.deleteBoxFromDisk(AppConstants.coachingOutcomeEventsBox);
    await Hive.deleteBoxFromDisk('practice_sessions');
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
    await Hive.deleteBoxFromDisk(AppConstants.usageBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('clearAll clears the About Me user_profile box too', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    final now = DateTime.utc(2026, 4, 30);
    await StorageService.userProfileBox.put(
      'profile:user-a',
      UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        notes: 'private About Me memo',
        updatedAt: now,
      ),
    );
    await StorageService.settingsBox.put('seen_onboarding', true);
    await StorageService.usageBox.put('monthly_count', 3);

    await StorageService.clearAll();

    expect(StorageService.userProfileBox.isEmpty, isTrue);
    expect(StorageService.settingsBox.isEmpty, isTrue);
    expect(StorageService.usageBox.isEmpty, isTrue);
  });

  test('clearAll also clears the partner_style_overrides box (Spec 2)',
      () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.partnerStyleOverridesBox.put(
      'p1',
      PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.steady,
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
    expect(StorageService.partnerStyleOverridesBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.partnerStyleOverridesBox.isEmpty, isTrue);
  });

  test('clearAll() purges partner_data_quality_states box', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.partnerDataQualityStatesBox.put(
      'p1',
      PartnerDataQualityState.empty(
        'p1',
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
    expect(StorageService.partnerDataQualityStatesBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.partnerDataQualityStatesBox.isEmpty, isTrue);
  });

  test('clearAll() purges coach_follow_up_results box (Spec 5)', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.coachFollowUpResultsBox.put(
      'p1',
      CoachFollowUpResult(
        partnerId: 'p1',
        phase: 'postDateReflection',
        headline: 'h',
        observation: 'o',
        task: 't',
        boundaryReminder: 'b',
        generatedAt: DateTime.utc(2026, 5, 2, 16),
        modelUsed: 'claude-sonnet-4-20250514',
      ),
    );
    expect(StorageService.coachFollowUpResultsBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.coachFollowUpResultsBox.isEmpty, isTrue);
  });

  test('clearAll() purges coach_chat_results box (Spec 6A)', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.coachChatResultsBox.put(
      'c1-1',
      CoachChatResult(
        id: 'c1-1',
        conversationId: 'c1',
        partnerId: 'p1',
        question: '她這句話是真的有興趣嗎？',
        mode: 'replyCraft',
        headline: '先接球',
        answer: '她是在丟觀察，不是要你證明自己。',
        userState: '你可能急著解釋。',
        nextStep: '承認一半再反問。',
        suggestedLine: '被妳發現了。妳也是亂逛派嗎？',
        boundaryReminder: '不要把一句觀察放大成考試。',
        needsReflection: false,
        generatedAt: DateTime.utc(2026, 5, 7, 12),
        provider: 'claude',
        modelUsed: 'claude-sonnet-4-20250514',
      ),
    );
    expect(StorageService.coachChatResultsBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.coachChatResultsBox.isEmpty, isTrue);
  });

  test('clearAll() purges coaching_outcome_events box', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.coachingOutcomeEventsBox.put(
      'event-1',
      CoachingOutcomeEvent.create(
        id: 'event-1',
        partnerId: 'p1',
        source: CoachingOutcomeSource.coach,
        suggestedMoveSummary: '低壓接球',
        userAction: CoachingUserAction.sentAsIs,
        outcome: CoachingOutcomeSignal.engaged,
        createdAt: DateTime.utc(2026, 5, 15),
      ),
    );
    expect(StorageService.coachingOutcomeEventsBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.coachingOutcomeEventsBox.isEmpty, isTrue);
  });

  test('clearPracticeRoomState() purges practice sessions and draw draft only',
      () async {
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);

    await StorageService.practiceSessionsBox.put(
      'practice-1',
      PracticeSession(
        id: 'practice-1',
        createdAt: DateTime.utc(2026, 6, 28, 10),
        messages: const [PracticeMessage(role: 'user', text: 'hi')],
      ),
    );
    await StorageService.settingsBox.put(
      HivePracticeDrawDraftStore.storageKey,
      '{"sessionId":"draft-1"}',
    );
    await StorageService.settingsBox.put('seen_onboarding', true);

    await StorageService.clearPracticeRoomState();

    expect(StorageService.practiceSessionsBox.isEmpty, isTrue);
    expect(
      StorageService.settingsBox.get(HivePracticeDrawDraftStore.storageKey),
      isNull,
    );
    expect(StorageService.settingsBox.get('seen_onboarding'), isTrue);
  });

  test('clearAll() purges practice sessions and draw draft', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox<CoachFollowUpResult>('coach_follow_up_results');
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
    );
    await Hive.openBox<PracticeSession>('practice_sessions');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.practiceSessionsBox.put(
      'practice-1',
      PracticeSession(
        id: 'practice-1',
        createdAt: DateTime.utc(2026, 6, 28, 10),
        messages: const [PracticeMessage(role: 'user', text: 'hi')],
      ),
    );
    await StorageService.settingsBox.put(
      HivePracticeDrawDraftStore.storageKey,
      '{"sessionId":"draft-1"}',
    );

    await StorageService.clearAll();

    expect(StorageService.practiceSessionsBox.isEmpty, isTrue);
    expect(
      StorageService.settingsBox.get(HivePracticeDrawDraftStore.storageKey),
      isNull,
    );
  });
}
