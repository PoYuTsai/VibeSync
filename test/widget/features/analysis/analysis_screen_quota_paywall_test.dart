// 額度不夠時打開付費頁的入口（Eric 2026-10-18：審查留下的殘餘風險「不接受，先處理」）。
// 走畫面上真的呼叫點，不直接造入口：
// - 分析前確認框的升級鈕：付費頁換額度大標、漏斗記 quota_exhausted（之前是一般入口）。
// - Essential 已經是最高方案：確認框不叫他升級，付費頁大標只說什麼時候恢復。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/ports/conversation_memory_port.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
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
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/services/partner_summary_builder.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repo_view.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';

import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

const _conversationId = 'quota-paywall-test';

const _free = SubscriptionTierHelper.free;
const _starter = SubscriptionTierHelper.starter;
const _essential = SubscriptionTierHelper.essential;

/// 漏斗字典裡額度不夠的入口值（docs/integrations/funnel-events-v1.md）。
const _quotaFunnelEntry = {'entry': 'quota_exhausted'};

class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

/// 指定的方案與用量；重新整理、同步都回到同一份（不打 RevenueCat）。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(this._seed) {
    state = _seed;
  }

  final SubscriptionState _seed;

  void restoreSeed() => state = _seed;

  @override
  Future<void> refresh() async => restoreSeed();

  @override
  Future<void> syncWithRevenueCat() async => restoreSeed();

  @override
  Future<void> ensureServerEntitlementSyncedForAnalysis() async =>
      restoreSeed();

  @override
  void syncUsageFromServer({
    required int monthlyRemaining,
    required int dailyRemaining,
    bool isTestAccount = false,
  }) {}
}

/// 記下送出幾次分析：按升級鈕不能開始分析。
class _RecordingAnalyzeStreamClient extends AnalyzeStreamClient {
  _RecordingAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  int streamCalls = 0;

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) {
    streamCalls++;
    return const Stream.empty();
  }
}

/// 已送出的漏斗事件。
class _SentFunnel {
  final events = <Map<String, dynamic>>[];

  List<Object?> propsOf(String name) => [
        for (final event in events)
          if (event['event'] == name) event['properties'],
      ];
}

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);
  Conversation _conversation;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  Future<void> updateConversation(Conversation c) async {
    _conversation = c;
  }
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

class _NoopConversationMemory implements ConversationMemoryPort {
  @override
  String? persistedHistoricalSummary(Conversation conversation) => null;

  @override
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  ) async =>
      '';

  @override
  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds) =>
      messages;

  @override
  int get maxRecentRounds => 15;

  @override
  int get minRoundsPerSummary => 3;
}

class _NoPartnerRepo implements PartnerRepoView {
  @override
  Partner? getById(String id) => null;
}

class _NoPartnerConversationList implements ConversationListByPartnerView {
  @override
  List<Conversation> listByPartner(String partnerId) => const [];
}

class _NoPartnerDataQualityRepo implements PartnerDataQualityRepoView {
  @override
  bool isFlaggedUnresolved(String partnerId) => false;
}

/// [tier] 方案，上限照方案常數；[dailyUsed]／[monthlyUsed] 是已經用掉的則數。
SubscriptionState _plan(
  String tier, {
  int dailyUsed = 0,
  int monthlyUsed = 0,
}) {
  final limits = SubscriptionTierHelper.limitsFor(tier);
  return SubscriptionState(
    tier: tier,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
    dailyMessagesUsed: dailyUsed,
    monthlyMessagesUsed: monthlyUsed,
  );
}

int _dailyLimitOf(String tier) => SubscriptionTierHelper.limitsFor(tier).daily;

int _monthlyLimitOf(String tier) =>
    SubscriptionTierHelper.limitsFor(tier).monthly;

/// 她最後說了一則 [content]（預設很短，一則額度就夠）。
Conversation _conversation({String content = '今天加班好累喔'}) {
  return Conversation(
    id: _conversationId,
    name: '小雲',
    messages: [
      Message(
        id: 'm1',
        content: content,
        isFromMe: false,
        timestamp: DateTime(2026, 10, 18, 12),
      ),
    ],
    createdAt: DateTime(2026, 10, 18, 12),
    updatedAt: DateTime(2026, 10, 18, 12),
  );
}

class _Harness {
  _Harness({required this.recorder, required this.funnel});

  final _RecordingAnalyzeStreamClient recorder;
  final _SentFunnel funnel;
}

Future<_Harness> _pumpScreen(
  WidgetTester tester, {
  required SubscriptionState plan,
  StreamingAnalysisState seed = const StreamingAnalysisState.idle(),
  Conversation? conversation,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    AiDataSharingConsent.acceptedKeyForTesting: true,
  });

  final conv = conversation ?? _conversation();
  final recorder = _RecordingAnalyzeStreamClient();
  final funnel = _SentFunnel();
  late final _SeededSubscriptionNotifier subscription;

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
            .overrideWithValue(_StubConversationRepository(conv)),
        conversationProvider(_conversationId).overrideWithValue(conv),
        // 分析紀錄不落 Hive。
        analysisRecordOwnerProvider.overrideWithValue(null),
        analyzeStreamClientProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider
            .overrideWithValue(_EmptyCoachChatRepository()),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider.overrideWith(
          () => _SeededStreamingAnalyzeNotifier(seed),
        ),
        analysisRunPreparerProvider.overrideWithValue(
          AnalysisRunPreparer(
            memory: _NoopConversationMemory(),
            resolvePartnerSummary: (_) => null,
            resolveEffectiveStyleContext: (_) => null,
          ),
        ),
        partnerContextResolverProvider.overrideWithValue(
          PartnerContextResolver(
            partnerRepo: _NoPartnerRepo(),
            conversationRepo: _NoPartnerConversationList(),
            summaryBuilder: PartnerSummaryBuilder(),
            dataQualityRepo: _NoPartnerDataQualityRepo(),
          ),
        ),
        subscriptionProvider.overrideWith(
          (ref) => subscription = _SeededSubscriptionNotifier(plan),
        ),
        usageDataProvider.overrideWithValue(
          UsageData(
            monthlyUsed: plan.monthlyMessagesUsed,
            monthlyLimit: plan.monthlyLimit,
            dailyUsed: plan.dailyMessagesUsed,
            dailyLimit: plan.dailyLimit,
            dailyResetAt: DateTime(2026, 10, 19),
            tier: plan.tier,
          ),
        ),
        funnelTrackerProvider.overrideWithValue(
          FunnelTracker(
            invoker: (fn, {required body}) async {
              funnel.events.add(body['event'] as Map<String, dynamic>);
              return 200;
            },
          ),
        ),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  const AnalysisScreen(conversationId: _conversationId),
            ),
            GoRoute(
              path: '/paywall',
              // 跟 lib/app/routes.dart 一樣從 extra 取入口。
              builder: (_, state) => PaywallScreen(
                entry: PaywallEntry.fromRouteExtra(state.extra),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  // initState 的 post-frame hydration callback 落地。
  await tester.pump();
  await tester.pump();
  // 詳細分析樹的既知 Hive 例外（同 hydration 測試）。
  tester.takeException();
  subscription.restoreSeed();
  await tester.pump();
  // 「長按訊息泡泡」的提示蓋在畫面上時先關掉。
  final gotIt = find.text('知道了');
  if (gotIt.evaluate().isNotEmpty) {
    await tester.tap(gotIt);
    await tester.pump();
  }
  return _Harness(recorder: recorder, funnel: funnel);
}

Future<void> _tapOrb(WidgetTester tester) async {
  await tester.tap(find.byKey(FloatingAnalysisActionButton.buttonKey));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _inPreviewDialog(Finder finder) =>
    find.descendant(of: find.byType(AnalysisPreviewDialog), matching: finder);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('分析前確認框的升級鈕（Eric 2026-10-18）：付費頁換額度大標，漏斗記 quota_exhausted', () {
    for (final tier in [_free, _starter, _essential]) {
      final plan = SubscriptionTierHelper.displayName(tier);
      testWidgets('$plan 今天的額度用完：付費頁是「今天用完」照方案的大標，不開始分析', (tester) async {
        final harness = await _pumpScreen(
          tester,
          plan: _plan(tier, dailyUsed: _dailyLimitOf(tier)),
        );
        await _tapOrb(tester);
        expect(find.text('開始分析前'), findsOneWidget);

        // Essential 已經是最高方案：確認框不叫他升級，鈕只寫「查看方案」。
        final upgradeLabel = tier == _essential ? '查看方案' : '查看升級方案';
        if (tier == _essential) {
          expect(_inPreviewDialog(find.textContaining('升級')), findsNothing);
        }
        await tester.tap(_inPreviewDialog(find.text(upgradeLabel)));
        await tester.pumpAndSettle();

        expect(
          find.text(PaywallEntry.dailyQuotaUsedUp.headlineFor(tier)),
          findsOneWidget,
        );
        expect(
          harness.funnel.propsOf('paywall_opened'),
          [_quotaFunnelEntry],
        );
        expect(harness.recorder.streamCalls, 0);
      });
    }

    testWidgets('Starter 這個月的額度用完（今天還有）：跟伺服器一樣先看本月，付費頁是每月的大標', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_starter, monthlyUsed: _monthlyLimitOf(_starter)),
      );
      await _tapOrb(tester);
      await tester.tap(_inPreviewDialog(find.text('查看升級方案')));
      await tester.pumpAndSettle();

      expect(
        find.text(PaywallEntry.monthlyQuotaUsedUp.headlineFor(_starter)),
        findsOneWidget,
      );
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });

    testWidgets('今天還剩 1 則、這次要 2 則：是「不夠這次用」不是「用完」', (tester) async {
      // 比一則額度多 1 字＝2 則（照常數組，不寫死字數）。
      final twoUnits = '好' * (MessageCalculator.charsPerMessageUnit + 1);
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_free, dailyUsed: _dailyLimitOf(_free) - 1),
        conversation: _conversation(content: twoUnits),
      );
      await _tapOrb(tester);
      await tester.tap(_inPreviewDialog(find.text('查看升級方案')));
      await tester.pumpAndSettle();

      expect(
        find.text(PaywallEntry.dailyQuotaShort.headlineFor(_free)),
        findsOneWidget,
      );
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });
  });
}
