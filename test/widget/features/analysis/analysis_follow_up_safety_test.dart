// 48 小時跟進提醒的安全閘（P1）：v3 判成關心（自傷、未成年）或停（她拒絕或封鎖）
// 之後，不問軟卡、不排提醒，這位對象先前排好的那則也收回；先別回與出卡照舊。
// 走真的 AnalysisScreen：分析完成（hydrate 補寫）→ 存檔協調器 → 畫面的跟進掛點。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/follow_up_notification/domain/notification_id.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';

import '../../../features/follow_up_notification/fake_notification_gateway.dart';
import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

const _conversationId = 'follow-up-safety';
const _partnerId = 'partner-follow-up';
const _softCardTitle = '要我提醒你跟進嗎？';

class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

class _InertAnalyzeStreamClient extends AnalyzeStreamClient {
  _InertAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) =>
      const Stream.empty();
}

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);
  Conversation _conversation;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  List<Conversation> listByPartner(String partnerId) =>
      _conversation.partnerId == partnerId ? [_conversation] : const [];

  @override
  Future<void> updateConversation(Conversation c) async {
    _conversation = c;
  }
}

class _StubPartnerRepository implements PartnerRepository {
  _StubPartnerRepository(this.partner);

  final Partner partner;

  @override
  Partner? getById(String id) => id == partner.id ? partner : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryConversationArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
      contentRevision: analyzedContentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {}

  @override
  Future<void> remove(Conversation conversation) async {}
}

class _EmptyCoachChatRepository extends CoachChatRepository {
  @override
  List<CoachChatResult> listByConversation(String conversationId) => const [];
  @override
  CoachChatResult? latestForConversation(String conversationId) => null;
  @override
  Future<void> put(CoachChatResult result) async {}
  @override
  Future<ConversationDeleteOutcome> deleteConversation(
    String conversationId,
  ) async =>
      const ConversationDeleteOutcome(
        deleted: true,
        deletedOwnerUserId: 'stub-owner',
      );
  @override
  Future<void> clearAll() async {}
  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) =>
      const [];
  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) => null;
  @override
  Future<void> putUnified(UnifiedCoachResult result) async {}
  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {}
  @override
  Future<bool> deleteUnified(String id) async => false;
}

class _MemoryOptInStore extends FollowUpOptInStore {
  _MemoryOptInStore(this.value);
  FollowUpOptIn value;

  @override
  FollowUpOptIn read() => value;

  @override
  Future<void> write(FollowUpOptIn v) async => value = v;
}

Conversation _conversation() => Conversation(
      id: _conversationId,
      name: '小雲',
      partnerId: _partnerId,
      messages: [
        Message(
          id: 'm1',
          content: '我今天去吃了你說的那家拉麵',
          isFromMe: false,
          timestamp: DateTime(2026, 10, 19, 20),
        ),
      ],
      createdAt: DateTime(2026, 10, 19, 20),
      updatedAt: DateTime(2026, 10, 19, 20),
    );

/// 形狀照伺服器 guide_v3/wire.ts 的 finalResult（已剝掉伺服器專用欄位）。
GuideV3Result _result(String decision, {String? careKind}) {
  final hasCards = decision == 'send' || decision == 'close';
  return GuideV3Result.fromJson({
    'guideVersion': 'v3.6',
    'read': {
      'guideVersion': 'v3.6',
      'decision': decision,
      'light': decision == 'care' ? null : 'green',
      'judgment': decision == 'care' ? '' : '她有在接你的話。',
      if (decision == 'hold') 'waitFor': '等她回你，再看她怎麼接',
      if (decision == 'care') 'careMessage': '先把安全放在第一位。',
      if (careKind != null) 'careKind': careKind,
      'plannedCards': hasCards
          ? [
              {'slot': 1, 'task': 'accept', 'locked': false},
            ]
          : const [],
    },
    'cards': hasCards
        ? [
            {
              'slot': 1,
              'task': 'accept',
              'method': 'reaction',
              'voice': 'default',
              'messages': ['那家我也想吃吃看'],
              'hasInventedDetail': false,
              'hasBlank': false,
            },
          ]
        : const [],
    'partial': false,
    'usage': {
      'messagesUsed': decision == 'care' ? 0 : 1,
      'shouldChargeQuota': decision != 'care',
    },
  })!;
}

class _Harness {
  _Harness(this.gateway, this.optInStore);

  final FakeNotificationGateway gateway;
  final _MemoryOptInStore optInStore;
}

/// 分析完成（done）落地的那一刻：畫面 hydrate 時補寫快照，存檔協調器存好後呼叫跟進掛點。
Future<_Harness> _pumpCompletedAnalysis(
  WidgetTester tester, {
  required GuideV3Result result,
  required FollowUpOptIn optIn,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final conversation = _conversation();
  final gateway = FakeNotificationGateway();
  final optInStore = _MemoryOptInStore(optIn);
  final seed = StreamingAnalysisState(
    phase: StreamingAnalyzePhase.done,
    analysisRunId: 'run_follow_up',
    isGuideV3Run: true,
    guideV3Read: result.read,
    guideV3Cards: result.cards,
    guideV3Result: result,
    previousAnalyzedCount: 0,
    analyzedMessageCount: conversation.messages.length,
    conversationMessageCount: conversation.messages.length,
    conversationContentRevision: conversationContentRevision(conversation),
    conversationPartnerId: _partnerId,
    isReconnectContext: false,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider
            .overrideWithValue(MemoryAnalysisHistoryRepository()),
        conversationArchiveStoreProvider
            .overrideWithValue(_MemoryConversationArchiveStore()),
        conversationRepositoryProvider
            .overrideWithValue(_StubConversationRepository(conversation)),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analyzeStreamClientProvider
            .overrideWithValue(_InertAnalyzeStreamClient()),
        coachChatRepositoryProvider
            .overrideWithValue(_EmptyCoachChatRepository()),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        partnerRepositoryProvider.overrideWithValue(
          _StubPartnerRepository(
            Partner(
              id: _partnerId,
              name: '小雲',
              createdAt: DateTime(2026, 10, 1),
              updatedAt: DateTime(2026, 10, 1),
            ),
          ),
        ),
        followUpNotificationServiceProvider.overrideWithValue(
          FollowUpNotificationService(
            gateway: gateway,
            optInStore: optInStore,
            now: () => DateTime(2026, 10, 19, 21),
          ),
        ),
        streamingAnalyzeProvider
            .overrideWith(() => _SeededStreamingAnalyzeNotifier(seed)),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  // hydrate 的 post-frame callback、存檔協調器的非同步寫入與跟進掛點都跑完。
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  tester.takeException();
  return _Harness(gateway, optInStore);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final partnerNotificationId = followUpNotificationId(_partnerId);

  group('不催他回去找她：關心與停不問、不排，已排的收回', () {
    testWidgets('自傷關心：第一次也不問軟卡，選擇留到下一次正常的分析', (tester) async {
      final harness = await _pumpCompletedAnalysis(
        tester,
        result: _result('care'),
        optIn: FollowUpOptIn.unknown,
      );

      expect(find.text(_softCardTitle), findsNothing);
      expect(harness.optInStore.value, FollowUpOptIn.unknown);
      expect(harness.gateway.scheduled, isEmpty);
      expect(harness.gateway.cancelled, contains(partnerNotificationId));
    });

    testWidgets('涉及未成年：已同意提醒也不排，先前那則收回', (tester) async {
      final harness = await _pumpCompletedAnalysis(
        tester,
        result: _result('care', careKind: 'minor'),
        optIn: FollowUpOptIn.granted,
      );

      expect(find.text(_softCardTitle), findsNothing);
      expect(harness.gateway.scheduled, isEmpty);
      expect(harness.gateway.cancelled, contains(partnerNotificationId));
    });

    testWidgets('停（她拒絕或封鎖）：已同意提醒也不排，先前那則收回', (tester) async {
      final harness = await _pumpCompletedAnalysis(
        tester,
        result: _result('stop'),
        optIn: FollowUpOptIn.granted,
      );

      expect(find.text(_softCardTitle), findsNothing);
      expect(harness.gateway.scheduled, isEmpty);
      expect(harness.gateway.cancelled, contains(partnerNotificationId));
    });

    testWidgets('停：第一次也不問軟卡', (tester) async {
      final harness = await _pumpCompletedAnalysis(
        tester,
        result: _result('stop'),
        optIn: FollowUpOptIn.unknown,
      );

      expect(find.text(_softCardTitle), findsNothing);
      expect(harness.optInStore.value, FollowUpOptIn.unknown);
      expect(harness.gateway.scheduled, isEmpty);
    });
  });

  group('其他決定照舊', () {
    testWidgets('先別回：第一次照舊問軟卡', (tester) async {
      await _pumpCompletedAnalysis(
        tester,
        result: _result('hold'),
        optIn: FollowUpOptIn.unknown,
      );

      expect(find.text(_softCardTitle), findsOneWidget);
    });

    testWidgets('先別回：已同意提醒就照舊排 48 小時後那則', (tester) async {
      final harness = await _pumpCompletedAnalysis(
        tester,
        result: _result('hold'),
        optIn: FollowUpOptIn.granted,
      );

      expect(harness.gateway.scheduled.single.id, partnerNotificationId);
      expect(
        harness.gateway.scheduled.single.fireAt,
        DateTime(2026, 10, 19, 21).add(const Duration(hours: 48)),
      );
    });

    testWidgets('出卡：已同意提醒就照舊排', (tester) async {
      final harness = await _pumpCompletedAnalysis(
        tester,
        result: _result('send'),
        optIn: FollowUpOptIn.granted,
      );

      expect(find.text(_softCardTitle), findsNothing);
      expect(harness.gateway.scheduled.single.payload, _partnerId);
    });
  });
}
