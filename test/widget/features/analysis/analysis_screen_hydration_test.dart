import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/services/partner_summary_builder.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repo_view.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import 'package:vibesync/shared/widgets/coach_action_card.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';

const _conversationId = 'hydration-test';
const _snapshotClientMetaKey = '__vibesync_snapshot_meta_v1';
const _snapshotRevisionKey = 'contentRevision';
const _snapshotMessageCountKey = 'messageCount';

/// Notifier that starts in a pre-seeded state, simulating a remount of
/// AnalysisScreen onto an already-running provider. Critically, [build] is the
/// override hook for the initial state — no analyze calls are needed to land
/// the screen in the target phase.
class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

class _MutableStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _MutableStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;

  void emit(StreamingAnalysisState next) {
    state = next;
  }
}

/// Records any call to analyzeQuick/analyzeFull so tests can assert the
/// screen did not re-trigger an analyze after hydrating.
class _RecordingAnalysisService extends AnalysisService {
  int recommendationPreviewCalls = 0;
  int fullCalls = 0;
  int streamCalls = 0;
  List<Message>? streamMessages;
  int? streamPreviousAnalyzedCount;
  int? streamPreviousAnalyzedCharCount;
  AnalysisResult? streamResult;

  @override
  Future<AnalysisRecommendationPreview> analyzeQuick({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
  }) async {
    recommendationPreviewCalls++;
    throw StateError('analyzeQuick must not be called on remount');
  }

  @override
  Future<AnalysisResult> analyzeFull({
    required String analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
  }) async {
    fullCalls++;
    throw StateError('analyzeFull must not be called on remount');
  }

  @override
  Stream<AnalysisStreamUpdate> analyzeStream({
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
  }) async* {
    streamCalls++;
    streamMessages = List<Message>.from(messages);
    streamPreviousAnalyzedCount = previousAnalyzedCount;
    streamPreviousAnalyzedCharCount = previousAnalyzedCharCount;
    yield AnalysisStreamUpdate.done(
      result: streamResult ?? _full(),
      runId: analysisRunId ?? 'stream-premium-refresh',
    );
  }
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(this._seed) {
    state = _seed;
  }

  final SubscriptionState _seed;
  int refreshCalls = 0;
  int syncWithRevenueCatCalls = 0;
  int ensureEntitlementCalls = 0;

  void restoreSeed() {
    state = _seed;
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
    restoreSeed();
  }

  @override
  Future<void> syncWithRevenueCat() async {
    syncWithRevenueCatCalls++;
    restoreSeed();
  }

  @override
  Future<void> ensureServerEntitlementSyncedForAnalysis() async {
    ensureEntitlementCalls++;
    restoreSeed();
  }

  @override
  void syncUsageFromServer({
    required int monthlyRemaining,
    required int dailyRemaining,
    bool isTestAccount = false,
  }) {}
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

PartnerContextResolver _emptyPartnerContextResolver() {
  return PartnerContextResolver(
    partnerRepo: _NoPartnerRepo(),
    conversationRepo: _NoPartnerConversationList(),
    summaryBuilder: PartnerSummaryBuilder(),
    dataQualityRepo: _NoPartnerDataQualityRepo(),
  );
}

AnalysisRecommendationPreview _preview({
  String runId = 'run_hydrate',
  int? eta = 17,
}) {
  return AnalysisRecommendationPreview(
    analysisRunId: runId,
    pick: 'resonate',
    nextStep: '先接住情緒再延伸',
    recommendedReply: '聽起來累，要不要週末喝杯咖啡？',
    shortReason: '情緒先接住',
    insufficientContext: false,
    confidence: 'high',
    estimatedFullSeconds: eta,
  );
}

AnalysisResult _full() {
  return const AnalysisResult(
    enthusiasmScore: 72,
    strategy: '保持沉穩',
    gameStage: GameStageInfo(
      current: GameStage.premise,
      status: GameStageStatus.normal,
      nextStep: '繼續',
    ),
    psychology: PsychologyAnalysis(
      subtext: '有興趣',
      qualificationSignal: true,
    ),
    topicDepth: TopicDepth(
      current: TopicDepthLevel.personal,
      suggestion: '可深入',
    ),
    replies: {
      'extend': 'a',
      'resonate': 'b',
      'tease': 'c',
      'humor': 'd',
      'coldRead': 'e',
    },
    replyOptions: {},
    recommendation: FinalRecommendation(
      pick: 'tease',
      content: 'c',
      reason: 'r',
      psychology: 'p',
    ),
    dogfoodRawFullRecommendation: FinalRecommendation(
      pick: 'resonate',
      content: 'Full 原始推薦回覆',
      reason: '完整 prompt 原始理由',
      psychology: '完整 prompt 原始判斷',
    ),
    dogfoodOfficialFullRecommendation: FinalRecommendation(
      pick: 'tease',
      content: '正式顯示推薦回覆',
      reason: '正式顯示理由',
      psychology: '正式顯示判斷',
    ),
    dogfoodEntitlementAdjusted: true,
    dogfoodTierUsed: 'free',
    reminder: '記得用你的方式說',
  );
}

/// Full result variant that carries a `rawResponse` so the P2 dedup signal can
/// compare the analysis payload while ignoring reserved client metadata. The
/// fields below mirror what the Edge `analyze-chat` shape returns for the
/// persistence path.
AnalysisResult _fullWithRawResponse(Map<String, dynamic> rawResponse) {
  final base = _full();
  return AnalysisResult(
    enthusiasmScore: base.enthusiasmScore,
    strategy: base.strategy,
    gameStage: base.gameStage,
    psychology: base.psychology,
    topicDepth: base.topicDepth,
    replies: base.replies,
    replyOptions: base.replyOptions,
    recommendation: base.recommendation,
    dogfoodRawFullRecommendation: base.dogfoodRawFullRecommendation,
    dogfoodOfficialFullRecommendation: base.dogfoodOfficialFullRecommendation,
    dogfoodEntitlementAdjusted: base.dogfoodEntitlementAdjusted,
    dogfoodTierUsed: base.dogfoodTierUsed,
    reminder: base.reminder,
    rawResponse: rawResponse,
  );
}

Map<String, dynamic> _fullRawResponse() {
  return <String, dynamic>{
    'enthusiasm': {'score': 72},
    'strategy': '保持沉穩',
    'gameStage': {
      'current': 'premise',
      'status': 'normal',
      'nextStep': '繼續',
    },
    'psychology': {
      'subtext': '有興趣',
      'qualificationSignal': true,
    },
    'topicDepth': {
      'current': 'personal',
      'suggestion': '可深入',
    },
    'replies': {
      'extend': 'a',
      'resonate': 'b',
      'tease': 'c',
      'humor': 'd',
      'coldRead': 'e',
    },
    'recommendation': {
      'pick': 'tease',
      'content': 'c',
      'reason': 'r',
      'psychology': 'p',
    },
    'reminder': '記得用你的方式說',
    // Intentionally omit 'usage' so _syncSubscriptionUsageFromResult early-
    // returns and the test doesn't have to wire a subscriptionProvider stub.
  };
}

Map<String, dynamic> _freeDualReplyRawResponse() {
  final raw = _fullRawResponse();
  raw['replies'] = <String, dynamic>{
    'extend': 'free extend reply',
    'tease': 'free tease reply',
  };
  raw['recommendation'] = <String, dynamic>{
    'pick': 'extend',
    'content': 'free extend reply',
    'reason': 'free tier',
    'psychology': 'free tier',
  };
  raw['usage'] = <String, dynamic>{
    'tierUsed': SubscriptionTierHelper.free,
  };
  return raw;
}

Map<String, dynamic> _paidRawResponse() {
  final raw = _fullRawResponse();
  raw['usage'] = <String, dynamic>{
    'tierUsed': SubscriptionTierHelper.essential,
  };
  return raw;
}

Map<String, dynamic> _decodeSnapshot(String? encoded) {
  if (encoded == null) {
    throw StateError('Expected an encoded analysis snapshot.');
  }
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw StateError('Expected the analysis snapshot to decode to a map.');
  }
  return Map<String, dynamic>.from(decoded);
}

Map<String, dynamic> _snapshotPayload(String? encoded) {
  return _decodeSnapshot(encoded)..remove(_snapshotClientMetaKey);
}

Map<String, dynamic>? _snapshotClientMeta(String? encoded) {
  final rawMeta = _decodeSnapshot(encoded)[_snapshotClientMetaKey];
  if (rawMeta is! Map) return null;
  return Map<String, dynamic>.from(rawMeta);
}

String _encodeSnapshotWithClientMeta(
  Map<String, dynamic> payload, {
  required Conversation conversation,
  required int messageCount,
}) {
  final snapshot = Map<String, dynamic>.from(payload)
    ..[_snapshotClientMetaKey] = <String, Object>{
      _snapshotRevisionKey: conversationContentRevision(
        conversation,
        messageCount: messageCount,
      ),
      _snapshotMessageCountKey: messageCount,
    };
  return jsonEncode(snapshot);
}

Conversation _conversation({
  String? lastAnalysisSnapshotJson,
  int? lastAnalyzedMessageCount,
  int? lastEnthusiasmScore,
  List<Message>? extraMessages,
}) {
  return Conversation(
    id: _conversationId,
    name: '小雲',
    messages: [
      Message(
        id: 'm1',
        content: '今天加班好累喔',
        isFromMe: false,
        timestamp: DateTime(2026, 5, 28, 12),
      ),
      ...?extraMessages,
    ],
    createdAt: DateTime(2026, 5, 28, 12),
    updatedAt: DateTime(2026, 5, 28, 12),
    lastAnalysisSnapshotJson: lastAnalysisSnapshotJson,
    lastAnalyzedMessageCount: lastAnalyzedMessageCount,
    lastEnthusiasmScore: lastEnthusiasmScore,
  );
}

/// Stub repository so `_restorePersistedAnalysis()` and
/// `_persistLatestAnalysisSnapshot()` flow through a controllable source.
/// Records `updateConversation` calls so P2 idempotency tests can assert
/// whether persist actually ran on hydrate.
class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);

  Conversation _conversation;
  int updateCalls = 0;
  Conversation? lastSaved;
  void Function(Conversation)? onUpdate;

  @override
  Conversation? getConversation(String id) {
    if (id != _conversation.id) return null;
    return _conversation;
  }

  @override
  Future<void> updateConversation(Conversation c) async {
    updateCalls++;
    lastSaved = c;
    _conversation = c;
    onUpdate?.call(c);
  }
}

class _MemoryConversationArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  void seedRestorable(Conversation conversation) {
    final analyzedCount = conversation.lastAnalyzedMessageCount;
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: conversation.updatedAt,
      contentRevision: conversationContentRevision(
        conversation,
        messageCount: analyzedCount,
      ),
    );
  }

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
      contentRevision:
          analyzedContentRevision ?? entries[conversation.id]?.contentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.archived(
      archivedAt: archivedAt,
      contentRevision: conversationContentRevision(conversation),
    );
  }

  @override
  Future<void> remove(Conversation conversation) async {
    entries.remove(conversation.id);
  }
}

class _MemoryBox implements Box<dynamic> {
  final Map<dynamic, dynamic> _values = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values.containsKey(key) ? _values[key] : defaultValue;

  @override
  Iterable<dynamic> get keys => _values.keys;

  @override
  bool containsKey(dynamic key) => _values.containsKey(key);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    _values.addAll(entries);
  }

  @override
  Future<void> delete(dynamic key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) async {
    for (final key in keys) {
      _values.remove(key);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAnalysisRecordStore implements AnalysisRecordStore {
  int saveCalls = 0;
  AnalysisRecord? currentRecord;
  String? savedOwnerUserId;
  String? savedCompletionKey;
  int? savedRunStartPreviousCount;
  int? savedAnalyzedMessageCount;
  String? savedAnalyzedContentRevision;

  @override
  Future<AnalysisRecordSaveResult> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
    DateTime? completedAt,
  }) async {
    saveCalls++;
    savedOwnerUserId = ownerUserId;
    savedCompletionKey = completionKey;
    savedRunStartPreviousCount = runStartPreviousCount;
    savedAnalyzedMessageCount = analyzedMessageCount;
    savedAnalyzedContentRevision = analyzedContentRevision;
    return const AnalysisRecordSaveResult.rejected('recorded_by_test');
  }

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      currentRecord;

  @override
  AnalysisRecord? recordById({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  }) =>
      null;

  @override
  List<AnalysisRecord> listArchived({
    required String ownerUserId,
    required Iterable<String> conversationIds,
  }) =>
      const [];

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  Future<bool> deleteRecord({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  }) async =>
      false;

  @override
  Future<int> removeConversation({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      0;

  @override
  Future<bool> prepareConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  Future<bool> cancelConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  bool hasPendingConversationRemovals({required String ownerUserId}) => false;

  @override
  Future<int> recoverPendingConversationRemovals({
    required String ownerUserId,
    required Iterable<String> liveConversationIds,
  }) async =>
      0;

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;

  @override
  Future<bool> setConversationSource({
    required String ownerUserId,
    required String conversationId,
    required String? sourcePlatform,
    bool relabelCurrent = false,
  }) async =>
      false;

  @override
  String? partnerMetVia({
    required String ownerUserId,
    required String partnerId,
  }) =>
      null;

  @override
  Future<bool> setPartnerMetVia({
    required String ownerUserId,
    required String partnerId,
    required String? sourcePlatform,
  }) async =>
      false;

  @override
  Future<bool> removePartnerMetadata({
    required String ownerUserId,
    required String partnerId,
  }) async =>
      false;

  @override
  Future<bool> mergePartnerMetadata({
    required String ownerUserId,
    required String fromPartnerId,
    required String toPartnerId,
  }) async =>
      false;
}

_MemoryConversationArchiveStore _defaultArchiveStore(
  Conversation conversation,
) {
  final store = _MemoryConversationArchiveStore();
  if (conversation.lastAnalysisSnapshotJson?.trim().isNotEmpty == true) {
    store.seedRestorable(conversation);
  }
  return store;
}

/// Old-run analysis snapshot used to seed `lastAnalysisSnapshotJson` so
/// `_restorePersistedAnalysis()` populates `_enthusiasmScore` etc. The
/// numbers/labels intentionally differ from `_full()` so a stale value
/// would be visually distinguishable from a freshly hydrated full result.
Map<String, dynamic> _staleSnapshotJson() {
  return <String, dynamic>{
    'enthusiasm': {'score': 33},
    'strategy': '舊策略：保守',
    'gameStage': {
      'current': 'opening',
      'status': 'normal',
      'nextStep': '舊 next step',
    },
    'psychology': {
      'subtext': '舊推論',
      'qualificationSignal': false,
    },
    'topicDepth': {
      'current': 'small_talk',
      'suggestion': '舊 suggestion',
    },
    'replies': {
      'extend': '舊 extend',
      'resonate': '舊 resonate',
      'tease': '舊 tease',
      'humor': '舊 humor',
      'coldRead': '舊 coldRead',
    },
    'recommendation': {
      'pick': 'extend',
      'content': '舊建議內容',
      'reason': '舊理由',
      'psychology': '舊心理',
    },
    'reminder': '舊提醒',
  };
}

Future<_RecordingAnalysisService> _pumpHydratedAnalysisScreen(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
}) async {
  return (await _pumpHydratedAnalysisScreenWithRepo(
    tester,
    seed: seed,
    conversation: _conversation(),
  ))
      .recorder;
}

class _HydrationHarness {
  _HydrationHarness({
    required this.recorder,
    required this.repo,
    required this.history,
    required this.archiveStore,
    this.subscription,
  });
  final _RecordingAnalysisService recorder;
  final _StubConversationRepository repo;
  final MemoryAnalysisHistoryRepository history;
  final _MemoryConversationArchiveStore archiveStore;
  final _SeededSubscriptionNotifier? subscription;
}

class _MutableHydrationHarness extends _HydrationHarness {
  _MutableHydrationHarness({
    required super.recorder,
    required super.repo,
    required super.history,
    required super.archiveStore,
    required this.notifier,
  });

  final _MutableStreamingAnalyzeNotifier notifier;
}

Future<_HydrationHarness> _pumpHydratedAnalysisScreenWithRepo(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  required Conversation conversation,
  _MemoryConversationArchiveStore? archiveStore,
  AnalysisRecordStore? analysisRecordStore,
  String? analysisRecordOwnerUserId,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalysisService();
  final repo = _StubConversationRepository(conversation);
  final history = MemoryAnalysisHistoryRepository();
  final resolvedArchiveStore =
      archiveStore ?? _defaultArchiveStore(conversation);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider.overrideWithValue(history),
        conversationArchiveStoreProvider.overrideWithValue(
          resolvedArchiveStore,
        ),
        conversationRepositoryProvider.overrideWithValue(repo),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        if (analysisRecordStore != null)
          analysisRecordStoreProvider.overrideWithValue(analysisRecordStore),
        if (analysisRecordOwnerUserId != null)
          analysisRecordOwnerProvider
              .overrideWithValue(analysisRecordOwnerUserId),
        analysisServiceProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(_conversationId).overrideWithValue(const []),
        streamingAnalyzeProvider
            .overrideWith(() => _SeededStreamingAnalyzeNotifier(seed)),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  // Let initState's post-frame hydration callback land.
  await tester.pump();
  await tester.pump();
  return _HydrationHarness(
    recorder: recorder,
    repo: repo,
    history: history,
    archiveStore: resolvedArchiveStore,
  );
}

Future<_MutableHydrationHarness> _pumpMutableAnalysisScreenWithRepo(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  required Conversation conversation,
  _MemoryConversationArchiveStore? archiveStore,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalysisService();
  final repo = _StubConversationRepository(conversation);
  final history = MemoryAnalysisHistoryRepository();
  final resolvedArchiveStore =
      archiveStore ?? _defaultArchiveStore(conversation);
  late final _MutableStreamingAnalyzeNotifier notifier;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider.overrideWithValue(history),
        conversationArchiveStoreProvider.overrideWithValue(
          resolvedArchiveStore,
        ),
        conversationRepositoryProvider.overrideWithValue(repo),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analysisServiceProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(_conversationId).overrideWithValue(const []),
        streamingAnalyzeProvider.overrideWith(() {
          notifier = _MutableStreamingAnalyzeNotifier(seed);
          return notifier;
        }),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _MutableHydrationHarness(
    recorder: recorder,
    repo: repo,
    history: history,
    archiveStore: resolvedArchiveStore,
    notifier: notifier,
  );
}

Future<_HydrationHarness> _pumpAnalysisScreenForPremiumRefresh(
  WidgetTester tester, {
  required Conversation conversation,
  required AnalysisResult streamResult,
  AnalysisRecordStore? analysisRecordStore,
  String? analysisRecordOwnerUserId,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalysisService()..streamResult = streamResult;
  final repo = _StubConversationRepository(conversation);
  final history = MemoryAnalysisHistoryRepository();
  final archiveStore = _defaultArchiveStore(conversation);
  final limits =
      SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);
  late final _SeededSubscriptionNotifier subscriptionNotifier;
  final paidSubscription = SubscriptionState(
    tier: SubscriptionTierHelper.essential,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider.overrideWithValue(history),
        conversationArchiveStoreProvider.overrideWithValue(archiveStore),
        conversationRepositoryProvider.overrideWithValue(repo),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        if (analysisRecordStore != null)
          analysisRecordStoreProvider.overrideWithValue(analysisRecordStore),
        if (analysisRecordOwnerUserId != null)
          analysisRecordOwnerProvider
              .overrideWithValue(analysisRecordOwnerUserId),
        analysisServiceProvider.overrideWithValue(recorder),
        partnerContextResolverProvider.overrideWithValue(
          _emptyPartnerContextResolver(),
        ),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(_conversationId).overrideWithValue(const []),
        subscriptionProvider.overrideWith(
          (ref) {
            subscriptionNotifier =
                _SeededSubscriptionNotifier(paidSubscription);
            return subscriptionNotifier;
          },
        ),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  subscriptionNotifier.restoreSeed();
  await tester.pump();
  return _HydrationHarness(
    recorder: recorder,
    repo: repo,
    history: history,
    archiveStore: archiveStore,
    subscription: subscriptionNotifier,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalysisScreen hydration on remount (P1)', () {
    testWidgets(
      'recommendationReady state hydrates → streaming loader, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.recommendationReady,
            recommendationPreview: _preview(runId: 'run_qr'),
            analysisRunId: 'run_qr',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(AnalysisScrollHint), findsOneWidget);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'A hydrated full-streaming run must not re-open the pre-analysis upload card.');
        expect(recorder.recommendationPreviewCalls, 0,
            reason: 'I-P1-a: must not re-fire analyzeQuick on hydration');
        expect(recorder.fullCalls, 0);

        await tester.pump(const Duration(seconds: 30));
        expect(find.byType(AnalysisScrollHint), findsOneWidget,
            reason:
                'Progress navigation must remain available for the stream.');
      },
    );

    testWidgets(
      'progress action jumps to the live tail, follows new content, and user scroll cancels follow',
      (tester) async {
        final extraMessages = List<Message>.generate(
          24,
          (index) => Message(
            id: 'long-$index',
            content: '這是長對話第 $index 則，讓目前分析位置落在畫面下方。',
            isFromMe: index.isEven,
            timestamp: DateTime(2026, 5, 28, 12, index + 1),
          ),
        );
        final conversation = _conversation(extraMessages: extraMessages);
        const firstContent = AnalysisStreamContent(
          kind: AnalysisStreamContentKind.decision,
          title: '下一步策略',
          body: '先承接情緒，再自然延伸。',
          rawEvent: {'type': 'analysis.decision'},
        );
        final seed = StreamingAnalysisState(
          phase: StreamingAnalyzePhase.streamingReport,
          recommendationPreview: _preview(runId: 'run_follow'),
          analysisRunId: 'run_follow',
          streamContents: const [firstContent],
          conversationMessageCount: conversation.messages.length,
          conversationContentRevision: conversationContentRevision(
            conversation,
          ),
        );
        final harness = await _pumpMutableAnalysisScreenWithRepo(
          tester,
          seed: seed,
          conversation: conversation,
        );

        final scrollView = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('analysis-primary-scroll')),
        );
        final controller = scrollView.controller!;
        expect(controller.position.maxScrollExtent, greaterThan(0));

        tester
            .widget<FilledButton>(find.byKey(AnalysisScrollHint.hintKey))
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('跟隨進度'), findsOneWidget);
        expect(
          controller.offset,
          closeTo(controller.position.maxScrollExtent, 1),
        );

        harness.notifier.emit(
          seed.copyWith(
            streamContents: const [
              firstContent,
              AnalysisStreamContent(
                kind: AnalysisStreamContentKind.reportSection,
                title: '語意分析',
                body: '新增一段足以讓串流卡片繼續往下長的完整內容。',
                rawEvent: {'type': 'analysis.report_section'},
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          controller.offset,
          closeTo(controller.position.maxScrollExtent, 1),
        );

        harness.notifier.emit(
          seed.copyWith(
            streamContents: const [
              firstContent,
              AnalysisStreamContent(
                kind: AnalysisStreamContentKind.reportSection,
                title: '語意分析',
                body: '新增一段足以讓串流卡片繼續往下長的完整內容。',
                rawEvent: {'type': 'analysis.report_section'},
              ),
              AnalysisStreamContent(
                kind: AnalysisStreamContentKind.reportSection,
                title: '互動節奏',
                body: '第三段內容進場時，使用者仍可立刻往回滑並中止自動跟隨。',
                rawEvent: {'type': 'analysis.report_section'},
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));

        final offsetBeforeGesture = controller.offset;
        final drag =
            (controller.position as ScrollPositionWithSingleContext).drag(
          DragStartDetails(globalPosition: const Offset(215, 700)),
          () {},
        );
        drag.update(
          DragUpdateDetails(
            delta: const Offset(0, 300),
            primaryDelta: 300,
            globalPosition: const Offset(215, 1000),
          ),
        );
        drag.end(
          DragEndDetails(velocity: Velocity.zero, primaryVelocity: 0),
        );
        await tester.pump();
        expect(controller.offset, lessThan(offsetBeforeGesture));
        expect(find.text('跟到最新'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          controller.offset,
          lessThan(controller.position.maxScrollExtent - 1),
          reason: 'A real upward review gesture must cancel live follow.',
        );

        final offsetAfterUserScroll = controller.offset;
        harness.notifier.emit(
          seed.copyWith(
            streamContents: const [
              firstContent,
              AnalysisStreamContent(
                kind: AnalysisStreamContentKind.reportSection,
                title: '語意分析',
                body: '新增一段足以讓串流卡片繼續往下長的完整內容。',
                rawEvent: {'type': 'analysis.report_section'},
              ),
              AnalysisStreamContent(
                kind: AnalysisStreamContentKind.reportSection,
                title: '互動節奏',
                body: '第三段內容進場時，使用者仍可立刻往回滑並中止自動跟隨。',
                rawEvent: {'type': 'analysis.report_section'},
              ),
              AnalysisStreamContent(
                kind: AnalysisStreamContentKind.reportSection,
                title: '後續建議',
                body: '解除跟隨後的新內容不應再把使用者強制拉回最下方。',
                rawEvent: {'type': 'analysis.report_section'},
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.offset, closeTo(offsetAfterUserScroll, 1));
      },
    );

    testWidgets(
      'streamingReport state hydrates → streaming loader visible',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: _preview(runId: 'run_rf'),
            analysisRunId: 'run_rf',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'Running full analysis should show streaming progress, not the upload/start-analysis card.');
        expect(find.text('建立本次片段'), findsNothing);
        expect(find.text('貼上或輸入新的一則訊息…'), findsNothing,
            reason:
                'Manual composer should collapse while full analysis is streaming so it does not cover the result area.');
        expect(recorder.recommendationPreviewCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'streamingReport 期間鎖住訊息編輯，避免同數量內容變更套用舊分析',
      (tester) async {
        await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: _preview(runId: 'run_edit_lock'),
            analysisRunId: 'run_edit_lock',
          ),
        );

        final bubble = tester.widget<MessageBubble>(
          find.byType(MessageBubble).first,
        );
        expect(bubble.onEdit, isNull);
        expect(bubble.onSwapSide, isNull);
        expect(bubble.onDelete, isNull);
      },
    );

    testWidgets(
      'failedAfterRecommendation state hydrates → retry card with retry count',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.failedAfterRecommendation,
            recommendationPreview: _preview(runId: 'run_ff'),
            analysisRunId: 'run_ff',
            fullErrorMessage: '完整分析失敗，可以重試。',
            fullErrorCode: 'FULL_FAILED',
            retriesRemaining: 2,
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsOneWidget);
        expect(find.text('查看中斷'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'Full retry state should not insert the upload/start-analysis card above retry.');
        expect(recorder.recommendationPreviewCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'done state hydrates → detailed analysis gate flips, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_fr'),
            full: _full(),
            analysisRunId: 'run_fr',
          ),
        );

        // The detailed-analysis tree contains widgets (CoachChatCard) that
        // depend on a live Hive box, which is not initialised in this widget
        // test. Drain the expected Hive build exception so the test framework
        // does not flag it.
        // ignore: avoid_dynamic_calls
        tester.takeException();
        expect(find.text('1 快速建議（先回來的版本）'), findsNothing);
        expect(find.text('2 完整分析後建議'), findsNothing);
        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.text('Core / Full 回覆對照'), findsNothing);
        expect(find.text('Core 先行'), findsNothing);
        expect(find.text('Full 原始判斷'), findsNothing);
        expect(find.text('完整分析推薦回覆'), findsNothing);
        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(recorder.recommendationPreviewCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'live streamingReport to done does not render rollback preview/Core comparison',
      (tester) async {
        final recommendationPreview = _preview(runId: 'run_live_compare');
        final raw = _fullRawResponse();
        final conv = _conversation();

        final harness = await _pumpMutableAnalysisScreenWithRepo(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: recommendationPreview,
            analysisRunId: recommendationPreview.analysisRunId,
            conversationMessageCount: conv.messages.length,
            conversationContentRevision: conversationContentRevision(conv),
          ),
          conversation: conv,
        );

        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);

        harness.notifier.emit(
          StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: recommendationPreview,
            full: _fullWithRawResponse(raw),
            analysisRunId: recommendationPreview.analysisRunId,
            conversationMessageCount: conv.messages.length,
            conversationContentRevision: conversationContentRevision(conv),
          ),
        );
        await tester.pump();

        // Drain the expected Hive build exception from the detailed tree.
        // ignore: avoid_dynamic_calls
        tester.takeException();

        expect(find.text('2 完整分析後建議'), findsNothing);
        expect(find.text('Core / Full 回覆對照'), findsNothing);
        expect(find.text('Core 先行'), findsNothing);
        expect(find.text('Full 原始判斷'), findsNothing);
        expect(find.text(recommendationPreview.recommendedReply), findsNothing);
        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(harness.recorder.recommendationPreviewCalls, 0);
        expect(harness.recorder.fullCalls, 0);
      },
    );
  });

  // Codex round-2 P1: when a conversation already has a persisted detailed
  // analysis (`lastAnalysisSnapshotJson`), `_restorePersistedAnalysis()` seeds
  // `_enthusiasmScore` and the rest of the detailed-analysis local mirrors in
  // initState. If hydration of a *partial* streaming phase (recommendationReady /
  // streamingReport / failedAfterRecommendation / failedBeforeRecommendation) doesn't clear those mirrors, the
  // build tree keeps showing the stale detailed analysis on top of (or instead
  // of) the live streaming loader / retry state. I-P1-c.
  group(
    'AnalysisScreen hydration with stale persisted snapshot (Codex round-2 P1)',
    () {
      testWidgets(
        'recommendationReady hydrate over stale snapshot → streaming loader, no stale detailed analysis',
        (tester) async {
          final convWithStaleSnapshot = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.recommendationReady,
              recommendationPreview: _preview(runId: 'run_qr_stale'),
              analysisRunId: 'run_qr_stale',
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(FullAnalysisPlaceholder), findsNothing,
              reason:
                  'I-P1-c: stale _enthusiasmScore from persisted snapshot must be cleared so the render tree flips to streaming.');
          expect(find.byType(FullAnalysisRetryCard), findsNothing);
          // Stale detailed copy must not bleed through.
          expect(find.text('舊建議內容'), findsNothing);
          expect(find.text('舊策略：保守'), findsNothing);
          expect(harness.recorder.recommendationPreviewCalls, 0);
          expect(harness.recorder.fullCalls, 0);
        },
      );

      testWidgets(
        'streamingReport hydrate over stale snapshot → streaming loader, no stale detailed analysis',
        (tester) async {
          final convWithStaleSnapshot = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.streamingReport,
              recommendationPreview: _preview(runId: 'run_rf_stale'),
              analysisRunId: 'run_rf_stale',
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(FullAnalysisPlaceholder), findsNothing);
          expect(find.byType(FullAnalysisRetryCard), findsNothing);
          expect(find.text('舊建議內容'), findsNothing);
          expect(harness.recorder.recommendationPreviewCalls, 0);
          expect(harness.recorder.fullCalls, 0);
        },
      );

      testWidgets(
        'failedAfterRecommendation hydrate over stale snapshot → retry card, no stale detailed analysis',
        (tester) async {
          final convWithStaleSnapshot = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.failedAfterRecommendation,
              recommendationPreview: _preview(runId: 'run_ff_stale'),
              analysisRunId: 'run_ff_stale',
              fullErrorMessage: '完整分析失敗，可以重試。',
              fullErrorCode: 'FULL_FAILED',
              retriesRemaining: 2,
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(FullAnalysisRetryCard), findsOneWidget);
          expect(find.byType(FullAnalysisPlaceholder), findsNothing);
          expect(find.text('舊建議內容'), findsNothing);
          expect(harness.recorder.recommendationPreviewCalls, 0);
          expect(harness.recorder.fullCalls, 0);
        },
      );
    },
  );

  // Codex round-2 P2: if full completes while the user is off-screen, the
  // `_onStreamingAnalyzeStateChanged` listener never fires for done. Until the
  // P2 fix, `_hydrateStreamingAnalyzeState(done)` applied the result but
  // intentionally skipped `_persistLatestAnalysisSnapshot` +
  // `_syncSubscriptionUsageFromResult` on the theory that the live listener
  // already ran them — false for off-screen completion. I-P2-e/f.
  group(
    'AnalysisScreen done hydrate persists when listener missed it (Codex round-2 P2)',
    () {
      testWidgets(
        'off-screen completion (no matching snapshot) → hydrate persists + updates conv snapshot',
        (tester) async {
          final raw = _fullRawResponse();
          // No prior snapshot, listener never ran for this run.
          final conv = _conversation();

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_off_screen'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_off_screen',
              conversationContentRevision: conversationContentRevision(conv),
            ),
            conversation: conv,
          );

          // Drain expected Hive build error from the detailed-analysis tree —
          // same workaround as the existing done hydration test.
          // ignore: avoid_dynamic_calls
          tester.takeException();
          // Let the fire-and-forget save() future land.
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 1,
              reason:
                  'I-P2-e: off-screen done completion must persist the snapshot on hydrate; listener missed it.');
          expect(
            _snapshotPayload(
              harness.repo.lastSaved?.lastAnalysisSnapshotJson,
            ),
            equals(raw),
          );
          final snapshotMeta = _snapshotClientMeta(
            harness.repo.lastSaved?.lastAnalysisSnapshotJson,
          );
          expect(snapshotMeta?[_snapshotMessageCountKey], conv.messages.length);
          expect(
            snapshotMeta?[_snapshotRevisionKey],
            conversationContentRevision(conv),
          );
          expect(harness.repo.lastSaved?.lastAnalyzedMessageCount,
              conv.messages.length);
          expect(harness.repo.lastSaved?.lastEnthusiasmScore, 72);
        },
      );

      testWidgets(
        'matching snapshot still ensures one owner-scoped analysis record',
        (tester) async {
          final raw = _fullRawResponse();
          final conv = _conversation(
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
          )..ownerUserId = 'record-owner';
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            raw,
            conversation: conv,
            messageCount: 1,
          );
          final recordStore = _RecordingAnalysisRecordStore();

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run-record-ensure',
              previousAnalyzedCount: 0,
              analyzedMessageCount: 1,
              conversationContentRevision: conversationContentRevision(conv),
            ),
            conversation: conv,
            analysisRecordStore: recordStore,
            analysisRecordOwnerUserId: 'record-owner',
          );

          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 0);
          expect(recordStore.saveCalls, 1);
          expect(recordStore.savedOwnerUserId, 'record-owner');
          expect(recordStore.savedCompletionKey, 'run-record-ensure');
          expect(recordStore.savedRunStartPreviousCount, 0);
          expect(recordStore.savedAnalyzedMessageCount, 1);
          expect(
            recordStore.savedAnalyzedContentRevision,
            conversationContentRevision(conv, messageCount: 1),
          );
        },
      );

      testWidgets(
        'cold idle restore retries a missing record from canonical snapshot metadata',
        (tester) async {
          final raw = _fullRawResponse();
          final conv = _conversation(
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
          )..ownerUserId = 'record-owner';
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            raw,
            conversation: conv,
            messageCount: 1,
          );
          final recordStore = _RecordingAnalysisRecordStore();

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: const StreamingAnalysisState(
              phase: StreamingAnalyzePhase.idle,
            ),
            conversation: conv,
            analysisRecordStore: recordStore,
            analysisRecordOwnerUserId: 'record-owner',
          );

          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 0);
          expect(recordStore.saveCalls, 1);
          expect(
            recordStore.savedCompletionKey,
            startsWith(
              'snapshot:${conversationContentRevision(conv, messageCount: 1)}:1:',
            ),
          );
          expect(
            find.byKey(
              const ValueKey('analysis-record-repair-warning'),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'cold repair finishes an interrupted paid refresh in the archive',
        (tester) async {
          final freeRaw = _freeDualReplyRawResponse();
          final paidRaw = _paidRawResponse();
          final conv = _conversation(
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
          )..ownerUserId = 'record-owner';
          final box = _MemoryBox();
          final recordStore = HiveAnalysisRecordStore(() => box);
          await recordStore.saveSuccessfulAnalysis(
            ownerUserId: 'record-owner',
            conversation: conv,
            completionKey: 'free-run',
            runStartPreviousCount: 0,
            analyzedMessageCount: 1,
            analyzedContentRevision: conversationContentRevision(conv),
            analysisSnapshotJson: jsonEncode(freeRaw),
            enthusiasmScore: 72,
            gameStageLabel: 'opening',
          );
          await recordStore.archiveCurrentRecord(
            ownerUserId: 'record-owner',
            conversationId: conv.id,
          );

          // Simulate process death after the canonical conversation write but
          // before its archived record was refreshed.
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            paidRaw,
            conversation: conv,
            messageCount: 1,
          );

          await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: const StreamingAnalysisState(
              phase: StreamingAnalyzePhase.idle,
            ),
            conversation: conv,
            analysisRecordStore: recordStore,
            analysisRecordOwnerUserId: 'record-owner',
          );
          tester.takeException();
          for (var i = 0; i < 20; i++) {
            final records = recordStore.listArchived(
              ownerUserId: 'record-owner',
              conversationIds: [conv.id],
            );
            if (records.isNotEmpty &&
                records.single.analysisSnapshotJson == jsonEncode(paidRaw)) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 20));
          }

          final repaired = recordStore.listArchived(
            ownerUserId: 'record-owner',
            conversationIds: [conv.id],
          );
          expect(repaired, hasLength(1));
          expect(
            jsonDecode(repaired.single.analysisSnapshotJson),
            equals(paidRaw),
          );
          expect(
            find.byKey(
              const ValueKey('analysis-record-repair-warning'),
            ),
            findsNothing,
          );
        },
      );

      testWidgets(
        'cold idle restore shows canonical newer fragment while old current repair fails',
        (tester) async {
          final raw = _fullRawResponse();
          final conv = _conversation(
            lastAnalyzedMessageCount: 4,
            lastEnthusiasmScore: 72,
            extraMessages: [
              Message(
                id: 'm2',
                content: '舊片段最後一則',
                isFromMe: true,
                timestamp: DateTime(2026, 5, 28, 12, 1),
              ),
              Message(
                id: 'm3',
                content: '新的片段第一則',
                isFromMe: false,
                timestamp: DateTime(2026, 5, 28, 12, 2),
              ),
              Message(
                id: 'm4',
                content: '新的片段第二則',
                isFromMe: true,
                timestamp: DateTime(2026, 5, 28, 12, 3),
              ),
            ],
          )..ownerUserId = 'record-owner';
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            raw,
            conversation: conv,
            messageCount: 4,
          );
          final recordStore = _RecordingAnalysisRecordStore()
            ..currentRecord = AnalysisRecord(
              id: 'old-current',
              ownerUserId: 'record-owner',
              conversationId: conv.id,
              partnerId: conv.partnerId,
              subjectName: conv.name,
              segmentStart: 0,
              segmentEnd: 2,
              createdAt: DateTime(2026, 5, 28, 12),
              messages: conv.messages
                  .take(2)
                  .map(AnalysisRecordMessage.fromMessage)
                  .toList(growable: false),
              analysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
              analyzedContentRevision: conversationContentRevision(
                conv,
                messageCount: 2,
              ),
              completionKey: 'old-run',
              sourcePlatform: 'LINE',
              enthusiasmScore: 33,
              gameStageLabel: 'opening',
            );

          await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: const StreamingAnalysisState(
              phase: StreamingAnalyzePhase.idle,
            ),
            conversation: conv,
            analysisRecordStore: recordStore,
            analysisRecordOwnerUserId: 'record-owner',
          );
          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(recordStore.saveCalls, 1);
          expect(recordStore.savedRunStartPreviousCount, 2);
          expect(find.text('本次分析片段'), findsOneWidget);
          expect(find.text('新的片段第一則'), findsOneWidget);
          expect(find.text('新的片段第二則'), findsOneWidget);
          expect(find.text('今天加班好累喔'), findsNothing);
          expect(find.text('舊片段最後一則'), findsNothing);
        },
      );

      testWidgets(
        'listener already persisted matching snapshot → hydrate must not double-write',
        (tester) async {
          final raw = _fullRawResponse();
          // Listener already ran during the original recommendationReady→done
          // transition, persisted the snapshot, then user navigated away and
          // came back. Payload + metadata equality must short-circuit hydrate
          // persist.
          final conv = _conversation(
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
          );
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            raw,
            conversation: conv,
            messageCount: 1,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_already_persisted'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_already_persisted',
              conversationContentRevision: conversationContentRevision(conv),
            ),
            conversation: conv,
          );

          // ignore: avoid_dynamic_calls
          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 0,
              reason:
                  'I-P2-f: when conv snapshot already matches result, hydrate must skip persist to avoid double-write.');
        },
      );

      testWidgets(
        'matching payload with stale metadata rewrites hydrate snapshot',
        (tester) async {
          final raw = _fullRawResponse();
          final conv = _conversation(
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
          );
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            raw,
            conversation: conv,
            messageCount: 1,
          );
          final staleRevision = _snapshotClientMeta(
            conv.lastAnalysisSnapshotJson,
          )?[_snapshotRevisionKey];
          conv.messages = [
            Message(
              id: 'm1',
              content: '同訊息數的新內容必須產生新快照版本',
              isFromMe: false,
              timestamp: DateTime(2026, 5, 28, 12),
            ),
          ];
          final currentRevision = conversationContentRevision(conv);

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_stale_metadata'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_stale_metadata',
              conversationMessageCount: 1,
              analyzedMessageCount: 1,
              conversationContentRevision: currentRevision,
            ),
            conversation: conv,
            archiveStore: _MemoryConversationArchiveStore(),
          );

          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 1);
          expect(
            _snapshotPayload(
              harness.repo.lastSaved?.lastAnalysisSnapshotJson,
            ),
            equals(raw),
          );
          final rewrittenMeta = _snapshotClientMeta(
            harness.repo.lastSaved?.lastAnalysisSnapshotJson,
          );
          expect(rewrittenMeta?[_snapshotMessageCountKey], 1);
          expect(rewrittenMeta?[_snapshotRevisionKey], currentRevision);
          expect(rewrittenMeta?[_snapshotRevisionKey], isNot(staleRevision));
        },
      );

      testWidgets(
        'matching premium prefix metadata still dedups with pending messages',
        (tester) async {
          final raw = _paidRawResponse();
          final conv = _conversation(
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
            extraMessages: [
              Message(
                id: 'm2',
                content: '尚未納入 premium refresh 的待處理訊息',
                isFromMe: true,
                timestamp: DateTime(2026, 5, 28, 12, 1),
              ),
            ],
          );
          conv.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
            raw,
            conversation: conv,
            messageCount: 1,
          );
          final currentRevision = conversationContentRevision(conv);

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_prefix_dedupe'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_prefix_dedupe',
              conversationMessageCount: conv.messages.length,
              analyzedMessageCount: 1,
              conversationContentRevision: currentRevision,
            ),
            conversation: conv,
          );

          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(
            harness.repo.updateCalls,
            0,
            reason:
                'A valid analyzed-prefix snapshot must dedup even while later messages remain pending.',
          );
        },
      );

      testWidgets(
        'stale snapshot from a prior run does not count as matching → hydrate still persists',
        (tester) async {
          final raw = _fullRawResponse();
          // Snapshot exists but it's from a different (older) run.
          final conv = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_after_stale'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_after_stale',
              conversationContentRevision: conversationContentRevision(conv),
            ),
            conversation: conv,
          );

          // ignore: avoid_dynamic_calls
          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 1,
              reason:
                  'I-P2-e: stale snapshot from a prior run must not be treated as matching; persist must run.');
          expect(
            _snapshotPayload(
              harness.repo.lastSaved?.lastAnalysisSnapshotJson,
            ),
            equals(raw),
          );
        },
      );
    },
  );

  group('AnalysisScreen streaming stale result guard for newly added messages',
      () {
    testWidgets(
      'cold remount skips snapshot whose stored content revision is stale',
      (tester) async {
        final conversation = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
        );
        final analyzedRevision = conversationContentRevision(conversation);
        conversation.messages = [
          Message(
            id: 'm1',
            content: '冷啟動前已改成新內容',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 28, 12),
          ),
        ];
        final archiveStore = _MemoryConversationArchiveStore();
        archiveStore.entries[conversation.id] = ConversationArchiveEntry.active(
          changedAt: DateTime(2026, 5, 28, 12, 1),
          contentRevision: analyzedRevision,
        );

        final harness = await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: const StreamingAnalysisState.idle(),
          conversation: conversation,
          archiveStore: archiveStore,
        );

        expect(find.text('舊建議內容'), findsNothing);
        expect(find.text('舊策略：保守'), findsNothing);
        expect(find.text('AI 推薦回覆'), findsNothing);
        expect(harness.repo.updateCalls, 0);
      },
    );

    testWidgets('markerless legacy snapshot still restores without history',
        (tester) async {
      final conversation = _conversation(
        lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
        lastAnalyzedMessageCount: 1,
        lastEnthusiasmScore: 33,
      );
      final analyzedRevision = conversationContentRevision(
        conversation,
        messageCount: 1,
      );

      final firstHarness = await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: const StreamingAnalysisState.idle(),
        conversation: conversation,
        archiveStore: _MemoryConversationArchiveStore(),
      );
      tester.takeException();

      expect(find.text('AI 推薦回覆'), findsOneWidget);
      expect(firstHarness.repo.updateCalls, 0);
      expect(
        _snapshotPayload(conversation.lastAnalysisSnapshotJson),
        equals(_staleSnapshotJson()),
      );
      final upgradedMeta =
          _snapshotClientMeta(conversation.lastAnalysisSnapshotJson);
      expect(upgradedMeta?[_snapshotRevisionKey], analyzedRevision);
      expect(upgradedMeta?[_snapshotMessageCountKey], 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      conversation.messages = [
        Message(
          id: 'm1',
          content: '相同訊息數但內容已改變',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 28, 12),
        ),
      ];

      await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: const StreamingAnalysisState.idle(),
        conversation: conversation,
        archiveStore: _MemoryConversationArchiveStore(),
      );
      tester.takeException();

      expect(find.text('舊建議內容'), findsNothing);
      expect(find.text('舊策略：保守'), findsNothing);
      expect(find.text('AI 推薦回覆'), findsNothing);
    });

    testWidgets(
      'markerless post-feature snapshot rejects same-count content edit',
      (tester) async {
        final conversation = _conversation(
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
        );
        conversation.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
          _staleSnapshotJson(),
          conversation: conversation,
          messageCount: 1,
        );
        conversation.messages = [
          Message(
            id: 'm1',
            content: 'post-feature 快照後改成同數量的新內容',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 28, 12),
          ),
        ];

        final harness = await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: const StreamingAnalysisState.idle(),
          conversation: conversation,
          archiveStore: _MemoryConversationArchiveStore(),
        );
        tester.takeException();

        expect(find.text('舊建議內容'), findsNothing);
        expect(find.text('舊策略：保守'), findsNothing);
        expect(find.text('AI 推薦回覆'), findsNothing);
        expect(harness.repo.updateCalls, 0);
      },
    );

    testWidgets(
      'cold remount keeps completed fragment closed when legacy tail exists',
      (tester) async {
        final conversation = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
        );

        await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: const StreamingAnalysisState.idle(),
          conversation: conversation,
          archiveStore: _MemoryConversationArchiveStore(),
        );
        tester.takeException();

        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(
          _snapshotClientMeta(conversation.lastAnalysisSnapshotJson),
          isNotNull,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        conversation.messages = [
          ...conversation.messages,
          Message(
            id: 'm2',
            content: '分析後新增的待處理訊息',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 28, 12, 1),
          ),
        ];

        await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: const StreamingAnalysisState.idle(),
          conversation: conversation,
          archiveStore: _MemoryConversationArchiveStore(),
        );
        tester.takeException();

        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(
          find.text('有 1 則新訊息，可以更新下一步建議。'),
          findsNothing,
        );
        expect(find.text('分析新增內容'), findsNothing);
        expect(find.text('分析新片段'), findsOneWidget);
      },
    );

    testWidgets(
      'done for an older message count shows stale-result retry and skips stale persist',
      (tester) async {
        final raw = _fullRawResponse();
        final conversationWithNewMessage = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
          extraMessages: [
            Message(
              id: 'm2',
              content: '我剛剛回她了',
              isFromMe: true,
              timestamp: DateTime(2026, 5, 28, 12, 1),
            ),
          ],
        );

        final harness = await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_stale_message_count'),
            full: _fullWithRawResponse(raw),
            analysisRunId: 'run_stale_message_count',
            conversationMessageCount: 1,
          ),
          conversation: conversationWithNewMessage,
        );

        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsOneWidget,
            reason:
                'Older full result must not render as the current detailed report after the user adds messages.');
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(harness.repo.updateCalls, 0,
            reason:
                'Stale full result must not persist or advance analyzed count.');
        expect(harness.recorder.recommendationPreviewCalls, 0);
        expect(harness.recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'done for an older same-count content revision skips stale persist',
      (tester) async {
        final raw = _fullRawResponse();
        final conversation = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
        );
        final analyzedRevision = conversationContentRevision(conversation);
        conversation.messages = [
          Message(
            id: 'm1',
            content: '分析進行中把同一則訊息改掉',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 28, 12),
          ),
        ];

        final harness = await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_stale_revision'),
            full: _fullWithRawResponse(raw),
            analysisRunId: 'run_stale_revision',
            conversationMessageCount: 1,
            conversationContentRevision: analyzedRevision,
          ),
          conversation: conversation,
        );

        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsOneWidget);
        expect(harness.repo.updateCalls, 0,
            reason:
                'Same-count edits must invalidate an older full result before persistence.');
      },
    );

    testWidgets(
      'same-count edit during snapshot write skips new history evidence',
      (tester) async {
        final raw = _fullRawResponse();
        final previousRaw = _staleSnapshotJson();
        final conversation = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(previousRaw),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
        );
        final analyzedRevision = conversationContentRevision(conversation);
        final preview = _preview(runId: 'run_write_interleave');
        final harness = await _pumpMutableAnalysisScreenWithRepo(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: preview,
            analysisRunId: preview.analysisRunId,
            conversationMessageCount: conversation.messages.length,
            conversationContentRevision: analyzedRevision,
          ),
          conversation: conversation,
        );
        harness.repo.onUpdate = (saved) {
          saved.messages = [
            Message(
              id: 'm1',
              content: '快照寫入途中改成新內容',
              isFromMe: false,
              timestamp: DateTime(2026, 5, 28, 12),
            ),
          ];
        };

        harness.notifier.emit(
          StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: preview,
            full: _fullWithRawResponse(raw),
            analysisRunId: preview.analysisRunId,
            conversationMessageCount: conversation.messages.length,
            conversationContentRevision: analyzedRevision,
          ),
        );
        await tester.pump();
        tester.takeException();
        await tester.pump(const Duration(milliseconds: 1));

        expect(harness.repo.updateCalls, 2,
            reason:
                'The stale snapshot write is followed by a compensating active save.');
        expect(
          _snapshotPayload(
            harness.repo.lastSaved?.lastAnalysisSnapshotJson,
          ),
          equals(previousRaw),
        );
        expect(
          _snapshotClientMeta(
            harness.repo.lastSaved?.lastAnalysisSnapshotJson,
          )?[_snapshotRevisionKey],
          analyzedRevision,
        );
        expect(harness.repo.lastSaved?.lastAnalyzedMessageCount, 1);
        expect(
          harness.archiveStore.entryFor(conversation)?.contentRevision,
          analyzedRevision,
        );
        expect(
          analyzedRevision,
          isNot(conversationContentRevision(conversation)),
        );
        expect(harness.history.events, isEmpty,
            reason:
                'A stale completion must not create fresh legacy-inference evidence.');
      },
    );
  });

  group('AnalysisScreen legacy pending fragment recovery', () {
    testWidgets(
      'never offers to append-analyze legacy pending messages',
      (tester) async {
        final conversationWithMixedPending = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
          extraMessages: [
            Message(
              id: 'm2',
              content: 'new incoming reply',
              isFromMe: false,
              timestamp: DateTime(2026, 5, 28, 12, 1),
            ),
            Message(
              id: 'm3',
              content: 'latest outgoing follow-up',
              isFromMe: true,
              timestamp: DateTime(2026, 5, 28, 12, 2),
            ),
          ],
        );

        await _pumpAnalysisScreenForPremiumRefresh(
          tester,
          conversation: conversationWithMixedPending,
          streamResult: _fullWithRawResponse(_paidRawResponse()),
        );
        tester.takeException();

        expect(find.text('分析新增內容'), findsNothing);
        expect(find.textContaining('有 2 則新訊息'), findsNothing);
        expect(find.text('分析新片段'), findsOneWidget);
      },
    );

    testWidgets(
      'does not revive append UI for outgoing-only legacy data',
      (tester) async {
        final conversationWithOutgoingOnlyPending = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
          extraMessages: [
            Message(
              id: 'm2',
              content: 'pending outgoing only',
              isFromMe: true,
              timestamp: DateTime(2026, 5, 28, 12, 1),
            ),
          ],
        );

        await _pumpAnalysisScreenForPremiumRefresh(
          tester,
          conversation: conversationWithOutgoingOnlyPending,
          streamResult: _fullWithRawResponse(_paidRawResponse()),
        );
        tester.takeException();

        expect(
          find.text('分析新增內容'),
          findsNothing,
        );
        expect(find.textContaining('有 1 則新訊息'), findsNothing);
        expect(find.text('分析新片段'), findsOneWidget);
      },
    );
  });

  group('AnalysisScreen premium reply refresh after upgrade', () {
    testWidgets(
      'repeated record repair failure blocks reanalysis and preserves canonical snapshot',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          AiDataSharingConsent.acceptedKeyForTesting: true,
        });

        final canonicalRaw = _freeDualReplyRawResponse();
        final conversation = _conversation(
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 72,
        )..ownerUserId = 'record-owner';
        conversation.lastAnalysisSnapshotJson = _encodeSnapshotWithClientMeta(
          canonicalRaw,
          conversation: conversation,
          messageCount: 1,
        );
        final canonicalSnapshot = conversation.lastAnalysisSnapshotJson;
        final recordStore = _RecordingAnalysisRecordStore();

        final harness = await _pumpAnalysisScreenForPremiumRefresh(
          tester,
          conversation: conversation,
          streamResult: _fullWithRawResponse(_paidRawResponse()),
          analysisRecordStore: recordStore,
          analysisRecordOwnerUserId: 'record-owner',
        );
        tester.takeException();
        await tester.pump(const Duration(milliseconds: 1));
        expect(recordStore.saveCalls, 1,
            reason: 'Cold restore must make the first repair attempt.');

        final dismissCoachMark = find.text('知道了');
        if (dismissCoachMark.evaluate().isNotEmpty) {
          await tester.tap(dismissCoachMark);
          await tester.pump();
        }
        await tester.tap(find.text('展開'));
        await tester.pump();

        final refreshButton = find.text('重新產生完整分析');
        await tester.ensureVisible(refreshButton);
        await tester.pump();
        final refreshOutlinedButton = find.ancestor(
          of: refreshButton,
          matching: find.byType(OutlinedButton),
        );
        final onRefreshPressed =
            tester.widget<OutlinedButton>(refreshOutlinedButton).onPressed;
        expect(onRefreshPressed, isNotNull);
        onRefreshPressed!();
        for (var i = 0; i < 40 && recordStore.saveCalls < 2; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();

        expect(recordStore.saveCalls, 2,
            reason:
                'Starting another analysis must retry the missing record once.');
        expect(harness.recorder.recommendationPreviewCalls, 0);
        expect(harness.recorder.fullCalls, 0);
        expect(harness.recorder.streamCalls, 0,
            reason:
                'A fresh analysis must not start while the canonical record still needs repair.');
        expect(harness.repo.updateCalls, 0);
        expect(
          harness.repo
              .getConversation(_conversationId)
              ?.lastAnalysisSnapshotJson,
          canonicalSnapshot,
          reason:
              'The last canonical snapshot must survive repeated record repair failures.',
        );
        expect(
          _snapshotPayload(
            harness.repo
                .getConversation(_conversationId)
                ?.lastAnalysisSnapshotJson,
          ),
          equals(canonicalRaw),
        );
      },
    );

    testWidgets(
      'reanalyzes the previously analyzed slice and keeps pending outgoing messages pending',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          AiDataSharingConsent.acceptedKeyForTesting: true,
        });

        final freeRaw = _freeDualReplyRawResponse();
        final paidRaw = _paidRawResponse();
        final conversationWithPendingOutgoing = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(freeRaw),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 72,
          extraMessages: [
            Message(
              id: 'm2',
              content: 'pending outgoing',
              isFromMe: true,
              timestamp: DateTime(2026, 5, 28, 12, 1),
            ),
          ],
        )..ownerUserId = 'premium-refresh-owner';
        final analysisRecordBox = _MemoryBox();
        final successfulRecordStore = HiveAnalysisRecordStore(
          () => analysisRecordBox,
        );

        final harness = await _pumpAnalysisScreenForPremiumRefresh(
          tester,
          conversation: conversationWithPendingOutgoing,
          streamResult: _fullWithRawResponse(paidRaw),
          analysisRecordStore: successfulRecordStore,
          analysisRecordOwnerUserId: 'premium-refresh-owner',
        );
        tester.takeException();

        final dismissCoachMark = find.text('知道了');
        if (dismissCoachMark.evaluate().isNotEmpty) {
          await tester.tap(dismissCoachMark);
          await tester.pump();
        }

        await tester.tap(find.text('展開'));
        await tester.pump();
        final refreshButton = find.text('重新產生完整分析');
        expect(refreshButton, findsOneWidget);

        await tester.ensureVisible(refreshButton);
        await tester.pump();
        final refreshOutlinedButton = find.ancestor(
          of: refreshButton,
          matching: find.byType(OutlinedButton),
        );
        final onRefreshPressed =
            tester.widget<OutlinedButton>(refreshOutlinedButton).onPressed;
        expect(onRefreshPressed, isNotNull);
        onRefreshPressed!();
        for (var i = 0;
            i < 40 &&
                (harness.recorder.streamCalls == 0 ||
                    harness.repo.lastSaved == null);
            i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        tester.takeException();

        expect(
          harness.subscription?.refreshCalls,
          greaterThan(0),
          reason:
              'Premium reply refresh button should refresh entitlement state.',
        );
        expect(
          harness.subscription?.ensureEntitlementCalls,
          1,
          reason:
              'Refresh should reach the analysis path after bypassing pending outgoing guard.',
        );
        expect(
          harness.recorder.streamCalls,
          1,
          reason: 'Refresh should start a streaming paid reanalysis.',
        );
        expect(
          harness.recorder.streamMessages?.map((m) => m.id).toList(),
          <String>['m1'],
          reason:
              'Premium refresh should rerun the paid answer for the old analyzed slice only.',
        );
        expect(harness.recorder.streamPreviousAnalyzedCount, 1);
        expect(
          _snapshotPayload(
            harness.repo.lastSaved?.lastAnalysisSnapshotJson,
          ),
          equals(paidRaw),
        );
        expect(harness.repo.lastSaved?.lastAnalyzedMessageCount, 1,
            reason:
                'The pending outgoing message must stay pending after paid reply refresh.');
        AnalysisRecord? refreshedArchive;
        for (var i = 0; i < 40 && refreshedArchive == null; i++) {
          final records = successfulRecordStore.listArchived(
            ownerUserId: 'premium-refresh-owner',
            conversationIds: const [_conversationId],
          );
          if (records.isNotEmpty &&
              records.single.analysisSnapshotJson == jsonEncode(paidRaw)) {
            refreshedArchive = records.single;
            break;
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          jsonDecode(refreshedArchive!.analysisSnapshotJson),
          equals(paidRaw),
          reason:
              'The archived fragment must show the refreshed paid analysis.',
        );
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });

  group('案2：analyze 歷史事件 hook', () {
    testWidgets('hydrate persist 成功 → 寫入一筆 analyze 歷史事件', (tester) async {
      final raw = _fullRawResponse();
      final conv = _conversation(); // 無既有 snapshot → 會走 persist

      final harness = await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: StreamingAnalysisState(
          phase: StreamingAnalyzePhase.done,
          recommendationPreview: _preview(runId: 'run_history_write'),
          full: _fullWithRawResponse(raw),
          analysisRunId: 'run_history_write',
          conversationContentRevision: conversationContentRevision(conv),
        ),
        conversation: conv,
      );

      tester.takeException();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.history.events.length, 1);
      final event = harness.history.events.single;
      expect(event.kind, AnalysisHistoryKind.analyze);
      expect(event.conversationId, _conversationId);
      expect(event.subjectName, '小雲');
      expect(event.enthusiasmScore, 72);
      expect(event.gameStageLabel, 'premise');
    });

    testWidgets('alreadyPersisted gate 命中 → 不寫歷史事件（去重繼承）', (tester) async {
      final raw = _fullRawResponse();
      final conv = _conversation(
        lastAnalysisSnapshotJson: jsonEncode(raw),
        lastAnalyzedMessageCount: 1,
        lastEnthusiasmScore: 72,
      );

      final harness = await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: StreamingAnalysisState(
          phase: StreamingAnalyzePhase.done,
          recommendationPreview: _preview(runId: 'run_history_dedupe'),
          full: _fullWithRawResponse(raw),
          analysisRunId: 'run_history_dedupe',
          conversationContentRevision: conversationContentRevision(conv),
        ),
        conversation: conv,
      );

      tester.takeException();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.history.events, isEmpty);
    });
  });
}
