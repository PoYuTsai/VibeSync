// 額度不夠時打開付費頁的入口，以及額度說明照目前方案（Eric 2026-10-18：審查留下的
// 殘餘風險「不接受，先處理」）。全部走畫面上真的呼叫點，不直接造入口：
// - 分析前確認框的升級鈕：付費頁換額度大標、漏斗記 quota_exhausted（之前是一般入口）。
// - 每月額度：升級卡的查看方案、分析途中撞到每月額度自動打開。
// - 草稿潤飾撞到每日／每月額度；回覆微調撞到額度時面板上的說明。
// - Essential 已經是最高方案：不叫他升級，只說什麼時候恢復；免費、Starter 照舊有升級那句。
// - 回覆微調上一輪失敗、或送出後還沒回來就關掉重開：免費次數照樣標待確認（主審第 1、2 輪 P2）。
// - 這個月和今天都不夠：跟伺服器一樣先看本月（主審第 1 輪 P3）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/supabase_service.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/ports/conversation_memory_port.dart';
import 'package:vibesync/features/analysis/application/reply_iteration_coordinator.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/data/services/optimize_billing_adapter.dart';
import 'package:vibesync/features/analysis/data/services/optimize_message_request_session.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/analysis/data/services/reply_refine_draft_adapter.dart';
import 'package:vibesync/features/analysis/data/services/reply_refine_draft_store.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_telemetry.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/domain/errors/analysis_exceptions.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/analysis/presentation/widgets/reply_refine_sheet.dart';
import 'package:vibesync/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart';
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
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
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
const _userId = 'quota-paywall-user';

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

  /// 模擬分析途中狀態改變（走畫面的即時 listener，不是回頁 hydrate）。
  void emit(StreamingAnalysisState next) => state = next;
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

/// 潤飾、微調的傳輸假件：潤飾預設成功；設了錯誤就照伺服器回 429 時 client 丟出的
/// 額度例外丟出（同 quotaExceptionFrom429 的型別）。
class _FakeOptimizeTransport {
  AnalysisException? polishError;
  AnalysisException? refineError;

  /// 依序給每一輪微調的結果（成功、丟出，或等放行才回）；排完才看 [refineError]。
  final refineRounds = <FutureOr<AnalysisResult> Function()>[];

  Future<AnalysisResult> optimizeDraft({
    required List<Message> messages,
    required String userDraft,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? requestId,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    final error = polishError;
    if (error != null) throw error;
    return AnalysisResult.fromJson(_polishedBody(userDraft));
  }

  Future<AnalysisResult> refineReply({
    required List<Message> messages,
    required String userDraft,
    required String refineInstruction,
    String? refineAnchorText,
    GuideV3RefineSpec? guideV3Card,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? requestId,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    if (refineRounds.isNotEmpty) return refineRounds.removeAt(0)();
    throw refineError ?? StateError('這個測試沒有設定微調結果');
  }
}

Map<String, dynamic> _polishedBody(String draft) => {
      'enthusiasm': {'score': 70, 'level': 'warm'},
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '繼續',
      },
      'psychology': {'subtext': '有興趣'},
      'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
      'replies': {'extend': '延展回覆內容'},
      'finalRecommendation': {
        'pick': 'extend',
        'content': '延展回覆內容',
        'reason': '理由',
        'psychology': '心理',
      },
      'strategy': '保持沉穩',
      'optimizedMessage': {
        'original': draft,
        'optimized': '這週要不要一起喝杯咖啡？',
        'reason': '更自然',
      },
    };

/// 一輪微調成功；[freeRemaining] 是伺服器帶回來的今天剩幾次免費微調。
Map<String, dynamic> _refinedBody({required int freeRemaining}) =>
    _polishedBody('這週要不要一起喝杯咖啡？')
      ..['optimizedMessage'] = {
        'original': '這週要不要一起喝杯咖啡？',
        'optimized': '週末要不要喝杯咖啡？',
        'reason': '更短',
      }
      ..['usage'] = {
        'refineFreeRemaining': freeRemaining,
        'refineFreeDailyLimit': kRefineFreeDailyLimit,
        'shouldChargeQuota': false,
      };

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

User _fakeUser() => User(
      id: _userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime(2026, 10, 18).toIso8601String(),
    );

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

/// 分析完成的結果（草稿潤飾的入口只在有結果時出現）。
StreamingAnalysisState _doneSeed() {
  const runId = 'run_quota_paywall';
  return const StreamingAnalysisState(
    phase: StreamingAnalyzePhase.done,
    recommendationPreview: AnalysisRecommendationPreview(
      analysisRunId: runId,
      pick: 'resonate',
      nextStep: '先接住情緒再延伸',
      recommendedReply: '聽起來累，要不要週末喝杯咖啡？',
      shortReason: '情緒先接住',
      insufficientContext: false,
      confidence: 'high',
      estimatedReportSeconds: 17,
    ),
    result: AnalysisResult(
      enthusiasmScore: 72,
      strategy: '保持沉穩',
      gameStage: GameStageInfo(
        current: GameStage.premise,
        status: GameStageStatus.normal,
        nextStep: '繼續',
      ),
      psychology: PsychologyAnalysis(subtext: '有興趣'),
      topicDepth: TopicDepth(
        current: TopicDepthLevel.personal,
        suggestion: '可深入',
      ),
      replies: {
        'extend': '延展回覆內容',
        'resonate': '共鳴回覆內容',
      },
      replyOptions: {},
      recommendation: FinalRecommendation(
        pick: 'resonate',
        content: '共鳴回覆內容',
        reason: '推薦理由文案',
        psychology: '推薦心理判斷',
      ),
    ),
    analysisRunId: runId,
  );
}

class _Harness {
  _Harness({
    required this.recorder,
    required this.funnel,
    required this.transport,
    required this.streaming,
  });

  final _RecordingAnalyzeStreamClient recorder;
  final _SentFunnel funnel;
  final _FakeOptimizeTransport transport;
  final _SeededStreamingAnalyzeNotifier Function() streaming;
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
    // 潤飾／微調的同意是帳號級的 key。
    '${AiDataSharingConsent.optimizeReplayConsentKey}::$_userId': true,
  });

  final conv = conversation ?? _conversation();
  final recorder = _RecordingAnalyzeStreamClient();
  final funnel = _SentFunnel();
  final transport = _FakeOptimizeTransport();
  late final _SeededSubscriptionNotifier subscription;
  late final _SeededStreamingAnalyzeNotifier streaming;

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
          () => streaming = _SeededStreamingAnalyzeNotifier(seed),
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
        // 潤飾、微調走真的協調器與計費順序，只換掉 Hive 與網路。
        replyIterationCoordinatorFactoryProvider.overrideWithValue(
          () => ReplyIterationCoordinator(
            billing: OptimizeBillingAdapter(
              session: OptimizeMessageRequestIdSession(
                store: InMemoryOptimizeMessagePendingRequestStore(),
              ),
            ),
            draftStore: ReplyRefineDraftAdapter(
              store: InMemoryReplyRefineDraftStore(),
            ),
            optimizeDraft: transport.optimizeDraft,
            refineReply: transport.refineReply,
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
  return _Harness(
    recorder: recorder,
    funnel: funnel,
    transport: transport,
    streaming: () => streaming,
  );
}

Future<void> _tapOrb(WidgetTester tester) async {
  await tester.tap(find.byKey(FloatingAnalysisActionButton.buttonKey));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _inPreviewDialog(Finder finder) =>
    find.descendant(of: find.byType(AnalysisPreviewDialog), matching: finder);

/// 打開草稿潤飾面板、送出一段草稿。潤飾要登入（帳號是同意與計費的 key）；畫面
/// 先載好才登入，訂閱狀態就不會去讀伺服器和 Hive。
Future<void> _polishDraft(WidgetTester tester) async {
  SupabaseService.debugCurrentUserOverride = _fakeUser;
  addTearDown(SupabaseService.debugResetForTesting);
  final entry = find.byKey(const ValueKey('draft-polish-entry'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('draft-polish-input')),
    '要不要喝咖啡',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('draft-polish-submit')));
  await tester.pumpAndSettle();
}

/// 潤飾結果上的「再調一下」：打開回覆微調面板。
Future<void> _openRefineSheet(WidgetTester tester) async {
  final refine = find.byKey(const ValueKey('draft-polish-refine'));
  await tester.ensureVisible(refine);
  await tester.tap(refine);
  await tester.pumpAndSettle();
}

/// 在微調面板按一顆快捷指令送出。
Future<void> _tapRefineQuick(WidgetTester tester, String instruction) async {
  final quick = find.byKey(ValueKey('reply-refine-quick-$instruction'));
  await tester.ensureVisible(quick);
  await tester.tap(quick);
  await tester.pumpAndSettle();
}

/// 微調面板標題下那一行免費次數說明。
String _refineQuotaLine(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('reply-refine-quota-line')))
    .data!;

/// 跟使用者一樣點面板外面（上方空白處）關掉微調面板。
Future<void> _closeRefineSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(215, 40));
  await tester.pumpAndSettle();
  expect(find.byType(ReplyRefineSheet), findsNothing);
}

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

    testWidgets('這個月剩 1 則、今天剩 0 則、這次要 2 則：先看本月，付費頁是每月不夠這次用；關掉付費頁也不會開始分析',
        (tester) async {
      final twoUnits = '好' * (MessageCalculator.charsPerMessageUnit + 1);
      final harness = await _pumpScreen(
        tester,
        plan: _plan(
          _free,
          dailyUsed: _dailyLimitOf(_free),
          monthlyUsed: _monthlyLimitOf(_free) - 1,
        ),
        conversation: _conversation(content: twoUnits),
      );
      await _tapOrb(tester);
      // 前提：這次要 2 則，本月剩 1、今天剩 0，兩邊都不夠。
      expect(_inPreviewDialog(find.text('2 則')), findsOneWidget);
      expect(
        _inPreviewDialog(find.text('1 / ${_monthlyLimitOf(_free)} 則')),
        findsOneWidget,
      );
      expect(
        _inPreviewDialog(find.text('0 / ${_dailyLimitOf(_free)} 則')),
        findsOneWidget,
      );
      // 確認框的提醒也先講本月：需要幾則、剩幾則，再講每月 1 號恢復（Onboarding
      // 第 3 步）。
      expect(
        _inPreviewDialog(find.text('這個月的額度不夠這次用（需要 2 則，剩 1 則）。'
            '每月 1 號早上 8 點恢復；也可以升級取得更多額度。')),
        findsOneWidget,
      );

      await tester.tap(_inPreviewDialog(find.text('查看升級方案')));
      await tester.pumpAndSettle();
      expect(
        find.text(PaywallEntry.monthlyQuotaShort.headlineFor(_free)),
        findsOneWidget,
      );

      await tester.tap(find.descendant(
        of: find.byType(PaywallScreen),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
      expect(harness.recorder.streamCalls, 0);
    });
  });

  group('每月額度：走真的呼叫點帶每月的入口', () {
    testWidgets('升級卡的查看方案：這個月剩 2 則、這次要 5 則 → 每月「不夠這次用」的大標', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_free),
        seed: const StreamingAnalysisState(
          phase: StreamingAnalyzePhase.failedBeforeRecommendation,
          recommendationPreviewErrorCode: 'MONTHLY_LIMIT_EXCEEDED',
          recommendationPreviewErrorMessage: '本月額度已用完',
          quotaExceeded: QuotaExceededInfo(
            isMonthly: true,
            remaining: 2,
            quotaNeeded: 5,
          ),
        ),
      );
      final viewPlans = find.descendant(
        of: find.byType(QuotaExceededUpgradeCard),
        matching: find.text('查看方案'),
      );
      await tester.ensureVisible(viewPlans);
      await tester.tap(viewPlans);
      await tester.pumpAndSettle();

      expect(
        find.text(PaywallEntry.monthlyQuotaShort.headlineFor(_free)),
        findsOneWidget,
      );
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });

    testWidgets('分析途中撞到每月額度（429）：自動打開付費頁；Essential 只說每月 1 號早上 8 點恢復',
        (tester) async {
      final harness = await _pumpScreen(tester, plan: _plan(_essential));

      harness.streaming().emit(const StreamingAnalysisState(
            phase: StreamingAnalyzePhase.failedBeforeRecommendation,
            recommendationPreviewErrorCode: 'MONTHLY_LIMIT_EXCEEDED',
            recommendationPreviewErrorMessage: '本月額度已用完',
            quotaExceeded: QuotaExceededInfo(
              isMonthly: true,
              remaining: 0,
              quotaNeeded: 3,
            ),
          ));
      await tester.pumpAndSettle();

      final headline = PaywallEntry.monthlyQuotaUsedUp.headlineFor(_essential);
      expect(find.text(headline), findsOneWidget);
      expect(headline, contains('每月 1 號早上 8 點恢復'));
      expect(headline, isNot(contains('升級')));
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });

    testWidgets('只有每月的錯誤碼、沒有額度明細：照錯誤碼當每月、不知道剩幾則就說不夠這次用', (tester) async {
      final harness = await _pumpScreen(tester, plan: _plan(_starter));

      harness.streaming().emit(const StreamingAnalysisState(
            phase: StreamingAnalyzePhase.failedBeforeRecommendation,
            recommendationPreviewErrorCode: 'MONTHLY_LIMIT_EXCEEDED',
            recommendationPreviewErrorMessage: '本月額度已用完',
          ));
      await tester.pumpAndSettle();

      expect(
        find.text(PaywallEntry.monthlyQuotaShort.headlineFor(_starter)),
        findsOneWidget,
      );
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });
  });

  // 潤飾的額度提示在打開付費頁前就被清掉（_showPaywall 先清 snackbar），畫面上看得到
  // 的是付費頁大標；那句說明跟微調面板同一句，由下一組和單元測試驗。
  group('草稿潤飾撞到額度：走真的潤飾路徑，付費頁照每日或每月換大標', () {
    testWidgets('免費今天用完：付費頁是今天用完、升級後每天能用更多', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_free),
        seed: _doneSeed(),
      );
      harness.transport.polishError = DailyLimitExceededException(
        dailyLimit: _dailyLimitOf(_free),
        used: _dailyLimitOf(_free),
        remaining: 0,
        quotaNeeded: 1,
      );

      await _polishDraft(tester);

      expect(
        find.text(PaywallEntry.dailyQuotaUsedUp.headlineFor(_free)),
        findsOneWidget,
      );
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });

    testWidgets('Essential 這個月用完：付費頁是這個月用完、只說每月 1 號早上 8 點恢復', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_essential),
        seed: _doneSeed(),
      );
      harness.transport.polishError = MonthlyLimitExceededException(
        monthlyLimit: _monthlyLimitOf(_essential),
        used: _monthlyLimitOf(_essential),
        remaining: 0,
        quotaNeeded: 1,
      );

      await _polishDraft(tester);

      final headline = PaywallEntry.monthlyQuotaUsedUp.headlineFor(_essential);
      expect(find.text(headline), findsOneWidget);
      expect(headline, isNot(contains('升級')));
      expect(harness.funnel.propsOf('paywall_opened'), [_quotaFunnelEntry]);
    });
  });

  group('回覆微調撞到額度：面板上的說明照目前方案，跟潤飾同一句', () {
    /// 潤飾成功後按「再調一下」，用快捷指令送一次微調。
    Future<String> refineOnce(WidgetTester tester) async {
      await _polishDraft(tester);
      await _openRefineSheet(tester);
      await _tapRefineQuick(tester, kRefineQuickInstructions[1]);
      return tester
          .widget<Text>(find.byKey(const ValueKey('reply-refine-error')))
          .data!;
    }

    testWidgets('Essential 今天用完：不叫他升級，只說每天早上 8 點恢復', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_essential),
        seed: _doneSeed(),
      );
      final limit = _dailyLimitOf(_essential);
      harness.transport.refineError = DailyLimitExceededException(
        dailyLimit: limit,
        used: limit,
        remaining: 0,
        quotaNeeded: 1,
      );

      final error = await refineOnce(tester);

      expect(
        error,
        '目前方案 Essential：今日額度已用完 ($limit/$limit)，每天早上 8 點恢復。',
      );
    });

    testWidgets('Essential 這個月用完：只說每月 1 號早上 8 點恢復', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_essential),
        seed: _doneSeed(),
      );
      final limit = _monthlyLimitOf(_essential);
      harness.transport.refineError = MonthlyLimitExceededException(
        monthlyLimit: limit,
        used: limit,
        remaining: 0,
        quotaNeeded: 1,
      );

      final error = await refineOnce(tester);

      expect(
        error,
        '目前方案 Essential：本月額度已用完 ($limit/$limit)，每月 1 號早上 8 點恢復。',
      );
    });

    testWidgets('免費今天用完：保留升級那句', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_free),
        seed: _doneSeed(),
      );
      final limit = _dailyLimitOf(_free);
      harness.transport.refineError = DailyLimitExceededException(
        dailyLimit: limit,
        used: limit,
        remaining: 0,
        quotaNeeded: 1,
      );

      final error = await refineOnce(tester);

      expect(
        error,
        '目前方案 Free：今日額度已用完 ($limit/$limit)，每天早上 8 點恢復；也可以升級取得更多額度。',
      );
    });
  });

  group('回覆微調的免費次數：關掉重開時照樣標待確認（主審第 1、2 輪 P2）', () {
    testWidgets('第 1 輪成功剩 1 次、第 2 輪失敗，關掉重開：講待確認，不再說今天還有 1 次免費', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_free),
        seed: _doneSeed(),
      );
      harness.transport.refineRounds.addAll([
        () => AnalysisResult.fromJson(_refinedBody(freeRemaining: 1)),
        // 伺服器先用掉最後一次免費、結算才失敗（額度表沒有退款，已知取捨）。
        () => throw AnalysisException(
              '額度確認失敗',
              code: 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED',
              suggestedAction: AnalysisErrorAction.wait,
            ),
      ]);
      const staleLine = '免費次數待確認，下一次微調可能會使用 1 則。';

      await _polishDraft(tester);
      await _openRefineSheet(tester);
      await _tapRefineQuick(tester, kRefineQuickInstructions[1]);
      expect(_refineQuotaLine(tester), '今天還有 1 次免費微調。');

      // 換個指令再調；面板的連點擋用真實時鐘，要真的等過那個窗。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await _tapRefineQuick(tester, kRefineQuickInstructions[2]);
      expect(find.byKey(const ValueKey('reply-refine-error')), findsOneWidget);
      expect(_refineQuotaLine(tester), staleLine);

      // 點面板外面關掉，再從同一個入口打開。
      await _closeRefineSheet(tester);
      await _openRefineSheet(tester);

      expect(_refineQuotaLine(tester), staleLine);
      expect(find.text('今天還有 1 次免費微調。'), findsNothing);
    });

    testWidgets('送出後還沒回來就關掉重開：講待確認；那一輪後來成功剩 0 次，關掉再開就說免費次數用完了', (tester) async {
      final harness = await _pumpScreen(
        tester,
        plan: _plan(_free),
        seed: _doneSeed(),
      );
      final release = Completer<void>();
      harness.transport.refineRounds.addAll([
        () => AnalysisResult.fromJson(_refinedBody(freeRemaining: 1)),
        () async {
          await release.future;
          return AnalysisResult.fromJson(_refinedBody(freeRemaining: 0));
        },
      ]);
      const staleLine = '免費次數待確認，下一次微調可能會使用 1 則。';
      const noFreeLine = '今天的免費次數用完了，接下來每次微調使用 1 則。';

      await _polishDraft(tester);
      await _openRefineSheet(tester);
      await _tapRefineQuick(tester, kRefineQuickInstructions[1]);
      expect(_refineQuotaLine(tester), '今天還有 1 次免費微調。');

      // 換個指令再送（連點擋用真實時鐘，要真的等過那個窗）。還在路上就點外面關掉、
      // 馬上再開；送出中會一直轉圈，這裡只推一幀，不等畫面靜止。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      final quick = find.byKey(
        ValueKey('reply-refine-quick-${kRefineQuickInstructions[2]}'),
      );
      await tester.ensureVisible(quick);
      await tester.tap(quick);
      await tester.pump();
      expect(find.text('調整中…'), findsOneWidget);
      await _closeRefineSheet(tester);
      await _openRefineSheet(tester);

      expect(_refineQuotaLine(tester), staleLine);

      // 那一輪成功、伺服器說剩 0 次：關掉再開就照新的數字。
      release.complete();
      await tester.pumpAndSettle();
      await _closeRefineSheet(tester);
      await _openRefineSheet(tester);

      expect(_refineQuotaLine(tester), noFreeLine);
    });
  });
}
