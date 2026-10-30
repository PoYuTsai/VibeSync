import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/ports/conversation_memory_port.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/data/services/conversation_memory_adapter.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/screens/partner_analysis_records_screen.dart';
import 'package:vibesync/features/analysis/presentation/sections/analysis_error_card.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/analysis/presentation/widgets/app_update_required_dialog.dart';
import 'package:vibesync/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
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

/// Records streaming calls so tests can assert the screen did not re-trigger
/// an analysis after hydrating.
class _RecordingAnalyzeStreamClient extends AnalyzeStreamClient {
  _RecordingAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  int streamCalls = 0;
  List<Message>? streamMessages;
  int? streamPreviousAnalyzedCount;
  int? streamPreviousAnalyzedCharCount;
  bool? streamHasOverchargeConfirmation;
  AnalysisResult? streamResult;

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) async* {
    streamCalls++;
    streamMessages = List<Message>.from(request.messages);
    streamHasOverchargeConfirmation = request.confirmedOvercharge != null;
    streamPreviousAnalyzedCount = request.previousAnalyzedCount;
    streamPreviousAnalyzedCharCount = request.previousAnalyzedCharCount;
    yield AnalysisStreamUpdate.done(
      result: streamResult ?? _analysisResult(),
      runId: request.analysisRunId ?? 'stream-premium-refresh',
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

  @override
  Future<bool> deleteUnified(String id) async => false;
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
    estimatedReportSeconds: eta,
  );
}

AnalysisResult _analysisResult() {
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
AnalysisResult _analysisResultWithRawResponse(
    Map<String, dynamic> rawResponse) {
  final base = _analysisResult();
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

Map<String, dynamic> _analysisRawResponse() {
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
  final raw = _analysisRawResponse();
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
  final raw = _analysisRawResponse();
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
  String? partnerId,
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
    partnerId: partnerId,
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

class _BlockingConversationRepository extends _StubConversationRepository {
  _BlockingConversationRepository(super.conversation);

  final saveStarted = Completer<void>();
  final allowSave = Completer<void>();

  @override
  Future<void> updateConversation(Conversation conversation) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await allowSave.future;
    await super.updateConversation(conversation);
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
    required int? enthusiasmScore,
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
/// numbers/labels intentionally differ from `_analysisResult()` so a stale value
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

Future<_RecordingAnalyzeStreamClient> _pumpHydratedAnalysisScreen(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  List<Override> extraOverrides = const <Override>[],
}) async {
  return (await _pumpHydratedAnalysisScreenWithRepo(
    tester,
    seed: seed,
    conversation: _conversation(),
    extraOverrides: extraOverrides,
  ))
      .recorder;
}

/// 不讀 Hive 的對話記憶：讓「重新分析」能在 widget test 裡走到額度確認框。
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

/// 組請求時卡在摘要這一步，直到測試放行（主審 r1 P1：測「前置還沒做完又按一次」）。
/// 每輪都做摘要（門檻 0）；裁切照原樣回傳，算出來的則數跟沒裁一樣。
class _GatedConversationMemory implements ConversationMemoryPort {
  final gates = <Completer<String>>[];

  @override
  String? persistedHistoricalSummary(Conversation conversation) => null;

  @override
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  ) {
    final gate = Completer<String>();
    gates.add(gate);
    return gate.future;
  }

  @override
  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds) =>
      messages;

  @override
  int get maxRecentRounds => 0;

  @override
  int get minRoundsPerSummary => 0;
}

/// 摘要做不出來（回空字串）：實際組請求整段照送，同步預覽卻以為要裁成最近 15 輪
///（主審 r1 P2：兩邊算的不一樣時確認框一定要跳）。
class _EmptySummaryMemory extends ConversationMemoryAdapter {
  @override
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  ) async =>
      '';
}

class _HydrationHarness {
  _HydrationHarness({
    required this.recorder,
    required this.repo,
    required this.history,
    required this.archiveStore,
    this.subscription,
  });
  final _RecordingAnalyzeStreamClient recorder;
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

class _NavigationPersistenceHarness {
  const _NavigationPersistenceHarness({
    required this.notifier,
    required this.repository,
    required this.recordStore,
    required this.history,
    required this.router,
  });

  final _MutableStreamingAnalyzeNotifier notifier;
  final _BlockingConversationRepository repository;
  final AnalysisRecordStore recordStore;
  final MemoryAnalysisHistoryRepository history;
  final GoRouter router;
}

Future<_HydrationHarness> _pumpHydratedAnalysisScreenWithRepo(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  required Conversation conversation,
  _MemoryConversationArchiveStore? archiveStore,
  AnalysisRecordStore? analysisRecordStore,
  String? analysisRecordOwnerUserId,
  List<Override> extraOverrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalyzeStreamClient();
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
        analyzeStreamClientProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider
            .overrideWith(() => _SeededStreamingAnalyzeNotifier(seed)),
        ...extraOverrides,
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
  List<Override> extraOverrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalyzeStreamClient();
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
        analyzeStreamClientProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider.overrideWith(() {
          notifier = _MutableStreamingAnalyzeNotifier(seed);
          return notifier;
        }),
        ...extraOverrides,
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

Future<_NavigationPersistenceHarness> _pumpAnalysisScreenWithBlockedPersistence(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  required Conversation conversation,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalyzeStreamClient();
  final repository = _BlockingConversationRepository(conversation);
  final history = MemoryAnalysisHistoryRepository();
  final archiveStore = _defaultArchiveStore(conversation);
  final recordBox = _MemoryBox();
  final recordStore = HiveAnalysisRecordStore(() => recordBox);
  late final _MutableStreamingAnalyzeNotifier notifier;
  final testRouter = GoRouter(
    initialLocation: '/conversation',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('測試首頁')),
        ),
      ),
      GoRoute(
        path: '/conversation',
        builder: (_, __) =>
            const AnalysisScreen(conversationId: _conversationId),
      ),
    ],
  );
  addTearDown(testRouter.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider.overrideWithValue(history),
        conversationArchiveStoreProvider.overrideWithValue(archiveStore),
        conversationRepositoryProvider.overrideWithValue(repository),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analysisRecordStoreProvider.overrideWithValue(recordStore),
        analysisRecordOwnerProvider.overrideWithValue('record-owner'),
        analyzeStreamClientProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider.overrideWith(() {
          notifier = _MutableStreamingAnalyzeNotifier(seed);
          return notifier;
        }),
      ],
      child: MaterialApp.router(routerConfig: testRouter),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _NavigationPersistenceHarness(
    notifier: notifier,
    repository: repository,
    recordStore: recordStore,
    history: history,
    router: testRouter,
  );
}

Future<_NavigationPersistenceHarness> _completeAnalysisWithBlockedPersistence(
  WidgetTester tester, {
  required String runId,
}) async {
  final conversation = _conversation()..ownerUserId = 'record-owner';
  final revision = conversationContentRevision(conversation);
  final preview = _preview(runId: runId);
  final harness = await _pumpAnalysisScreenWithBlockedPersistence(
    tester,
    seed: StreamingAnalysisState(
      phase: StreamingAnalyzePhase.streamingReport,
      recommendationPreview: preview,
      analysisRunId: preview.analysisRunId,
      previousAnalyzedCount: 0,
      analyzedMessageCount: conversation.messages.length,
      conversationMessageCount: conversation.messages.length,
      conversationContentRevision: revision,
    ),
    conversation: conversation,
  );

  harness.notifier.emit(
    StreamingAnalysisState(
      phase: StreamingAnalyzePhase.done,
      recommendationPreview: preview,
      result: _analysisResultWithRawResponse(_analysisRawResponse()),
      analysisRunId: preview.analysisRunId,
      previousAnalyzedCount: 0,
      analyzedMessageCount: conversation.messages.length,
      conversationMessageCount: conversation.messages.length,
      conversationContentRevision: revision,
    ),
  );
  await tester.pump();
  tester.takeException();
  for (var i = 0; i < 10 && !harness.repository.saveStarted.isCompleted; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(harness.repository.saveStarted.isCompleted, isTrue);
  return harness;
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

  final recorder = _RecordingAnalyzeStreamClient()..streamResult = streamResult;
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
        analyzeStreamClientProvider.overrideWithValue(recorder),
        partnerContextResolverProvider.overrideWithValue(
          _emptyPartnerContextResolver(),
        ),
        coachChatRepositoryProvider.overrideWithValue(
          _EmptyCoachChatRepository(),
        ),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
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
      'streamingReport preview hydrates → streaming loader, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: _preview(runId: 'run_qr'),
            analysisRunId: 'run_qr',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(AnalysisScrollHint), findsOneWidget);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(StreamingAnalysisRetryCard), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'A hydrated full-streaming run must not re-open the pre-analysis upload card.');
        expect(recorder.streamCalls, 0,
            reason: 'Hydration must not start another streaming request.');

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
        expect(recorder.streamCalls, 0);
        expect(find.byType(StreamingAnalysisRetryCard), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'Running full analysis should show streaming progress, not the upload/start-analysis card.');
        expect(find.text('建立本次片段'), findsNothing);
        expect(find.text('貼上或輸入新的一則訊息…'), findsNothing,
            reason:
                'Manual composer should collapse while full analysis is streaming so it does not cover the result area.');
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
            streamErrorMessage: '完整分析失敗，可以重試。',
            streamErrorCode: 'FULL_FAILED',
            retriesRemaining: 2,
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(StreamingAnalysisRetryCard), findsOneWidget);
        expect(find.text('查看中斷'), findsOneWidget);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'Full retry state should not insert the upload/start-analysis card above retry.');
        expect(recorder.streamCalls, 0);
      },
    );

    testWidgets(
      'F13：重試用完 → 顯示原因與能按的「重新分析」，按下走一般開始流程',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.failedAfterRecommendation,
            analysisRunId: 'run_exhausted',
            streamErrorMessage: '原本的分析沒有完成，請重新分析一次。',
            streamErrorCode: 'STREAM_RUN_RETRY_UNAVAILABLE',
            retriesRemaining: 0,
          ),
          extraOverrides: [
            analysisRunPreparerProvider.overrideWithValue(
              AnalysisRunPreparer(
                memory: _NoopConversationMemory(),
                resolvePartnerSummary: (_) => null,
                resolveEffectiveStyleContext: (_) => null,
              ),
            ),
            usageDataProvider.overrideWithValue(
              UsageData(
                monthlyUsed: 0,
                monthlyLimit: 30,
                dailyUsed: 0,
                dailyLimit: 15,
                dailyResetAt: DateTime(2026, 10, 4),
              ),
            ),
          ],
        );

        expect(find.text('原本的分析沒有完成，請重新分析一次。'), findsOneWidget);
        final reanalyze = find.widgetWithText(FilledButton, '重新分析');
        expect(reanalyze, findsOneWidget);

        final dismissCoachMark = find.text('知道了');
        if (dismissCoachMark.evaluate().isNotEmpty) {
          await tester.tap(dismissCoachMark);
          await tester.pump();
        }
        await tester.ensureVisible(reanalyze);
        await tester.pump();
        await tester.tap(reanalyze);
        await tester.pump();
        await tester.pump();

        // 重新分析是新的一次：先出現一般的額度確認框，確認前不會送出。
        expect(find.text('開始分析前'), findsOneWidget);
        expect(recorder.streamCalls, 0);
      },
    );

    // 分析圓鈕（Eric 2026-10-18）：額度夠的一般長度不跳確認框，圓鈕下寫一行。
    Future<_HydrationHarness> pumpOrbScreen(
      WidgetTester tester, {
      required SubscriptionState subscription,
      Conversation? conversation,
      ConversationMemoryPort? memory,
      bool consentAccepted = true,
      UsageData? localUsage,
      void Function(_SeededSubscriptionNotifier notifier)? onSubscription,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (consentAccepted) AiDataSharingConsent.acceptedKeyForTesting: true,
      });
      late final _SeededSubscriptionNotifier notifier;
      final harness = await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: const StreamingAnalysisState.idle(),
        conversation: conversation ?? _conversation(),
        extraOverrides: [
          analysisRunPreparerProvider.overrideWithValue(
            AnalysisRunPreparer(
              memory: memory ?? _NoopConversationMemory(),
              resolvePartnerSummary: (_) => null,
              resolveEffectiveStyleContext: (_) => null,
            ),
          ),
          partnerContextResolverProvider.overrideWithValue(
            _emptyPartnerContextResolver(),
          ),
          subscriptionProvider.overrideWith((ref) {
            notifier = _SeededSubscriptionNotifier(subscription);
            return notifier;
          }),
          // 確認流程照舊讀本機用量（只拿重置時間；方案載好時數字以方案為準）。
          usageDataProvider.overrideWithValue(
            localUsage ??
                UsageData(
                  monthlyUsed: subscription.monthlyMessagesUsed,
                  monthlyLimit: subscription.monthlyLimit,
                  dailyUsed: subscription.dailyMessagesUsed,
                  dailyLimit: subscription.dailyLimit,
                  dailyResetAt: DateTime(2026, 10, 19),
                ),
          ),
        ],
      );
      notifier.restoreSeed();
      onSubscription?.call(notifier);
      await tester.pump();
      final dismissCoachMark = find.text('知道了');
      if (dismissCoachMark.evaluate().isNotEmpty) {
        await tester.tap(dismissCoachMark);
        await tester.pump();
      }
      return harness;
    }

    /// 免費方案（[SubscriptionState] 預設值）用掉 [units] 則之後剩幾則：本月、今日取少的。
    /// 照額度常數算，免費額度再調整（例：30／15 → 50／20，Eric 2026-10-18）也不用改測試。
    int freeLeftAfter({int dailyUsed = 0, required int units}) =>
        math.min(
          AppConstants.freeMonthlyLimit,
          AppConstants.freeDailyLimit - dailyUsed,
        ) -
        units;

    Future<void> tapOrb(WidgetTester tester) async {
      await tester.tap(find.byKey(FloatingAnalysisActionButton.buttonKey));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets(
      '分析圓鈕：額度夠的一般長度，圓鈕下寫這次會用幾則，按下去不跳確認框直接開始',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(dailyMessagesUsed: 3),
        );

        // 「今天加班好累喔」7 字 → 1 則；今天已用 3 則，用完再少 1 則。
        expect(
          find.text('這次會用 1 則，剩 ${freeLeftAfter(dailyUsed: 3, units: 1)} 則'),
          findsOneWidget,
        );
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    testWidgets(
      '分析圓鈕：今天額度不夠就不寫那一行，按下去照舊跳確認框、不送出',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(
            dailyMessagesUsed: AppConstants.freeDailyLimit,
          ),
        );

        expect(
            find.byKey(FloatingAnalysisActionButton.captionKey), findsNothing);
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);
      },
    );

    // 額度那一行（主審 r1 P2）：跟按下去時同一份請求算；兩邊完全一樣才跳過確認框。
    /// [rounds] 輪，每輪他一則、她一則，各 10 字，最後是她。
    Conversation roundsConversation(int rounds) {
      final messages = <Message>[];
      for (var i = 1; i <= rounds; i++) {
        final n = i.toString().padLeft(2, '0');
        messages
          ..add(Message(
            id: 'me-$i',
            content: '第$n輪他說的那些話',
            isFromMe: true,
            timestamp: DateTime(2026, 10, 18, 9, i),
          ))
          ..add(Message(
            id: 'her-$i',
            content: '第$n輪她回的那些話',
            isFromMe: false,
            timestamp: DateTime(2026, 10, 18, 10, i),
          ));
      }
      return Conversation(
        id: _conversationId,
        name: '小雲',
        messages: messages,
        createdAt: DateTime(2026, 10, 18),
        updatedAt: DateTime(2026, 10, 18),
        currentRound: rounds,
      );
    }

    /// 她傳的 [count] 則，各 [chars] 字（最後一則多 [extra] 字）。
    Conversation charsConversation({
      required int count,
      required int chars,
      int extra = 0,
    }) =>
        Conversation(
          id: _conversationId,
          name: '小雲',
          messages: [
            for (var i = 0; i < count; i++)
              Message(
                id: 'her-$i',
                content: '好' * (chars + (i == count - 1 ? extra : 0)),
                isFromMe: false,
                timestamp: DateTime(2026, 10, 18, 10, i),
              ),
          ],
          createdAt: DateTime(2026, 10, 18),
          updatedAt: DateTime(2026, 10, 18),
          currentRound: count,
        );

    testWidgets(
      '額度那一行：有摘要時照實際送出的最近 15 輪算（25 輪 500 字 → 300 字 8 則），按下去不跳框',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          conversation: roundsConversation(25),
          memory: ConversationMemoryAdapter(),
        );
        // 用 8 則（照整段算會寫成 10 則）。
        expect(
          find.text('這次會用 8 則，剩 ${freeLeftAfter(units: 8)} 則'),
          findsOneWidget,
        );
        await tapOrb(tester);
        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
        expect(harness.recorder.streamMessages, hasLength(30));
      },
    );

    testWidgets(
      '額度那一行跟按下去時算的不一樣（摘要沒做出來、實際整段送）：照舊跳確認框、不送出',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          conversation: roundsConversation(25),
          memory: _EmptySummaryMemory(),
        );
        expect(
          find.text('這次會用 8 則，剩 ${freeLeftAfter(units: 8)} 則'),
          findsOneWidget,
        );
        await tapOrb(tester);
        expect(find.text('開始分析前'), findsOneWidget);
        expect(find.text('10 則'), findsOneWidget, reason: '確認框寫實際的則數');
        expect(harness.recorder.streamCalls, 0);
      },
    );

    testWidgets(
      '按下去時剩的則數跟那一行不一樣：照舊跳確認框、不送出',
      (tester) async {
        late _SeededSubscriptionNotifier subscription;
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(dailyMessagesUsed: 3),
          // 方案重新載入中，按下去時改看本機用量：今天已經用了 5 則。
          localUsage: UsageData(
            monthlyUsed: 0,
            monthlyLimit: 30,
            dailyUsed: 5,
            dailyLimit: 15,
            dailyResetAt: DateTime(2026, 10, 19),
          ),
          onSubscription: (notifier) => subscription = notifier,
        );
        expect(
          find.text('這次會用 1 則，剩 ${freeLeftAfter(dailyUsed: 3, units: 1)} 則'),
          findsOneWidget,
        );
        // 還沒重畫就按：圓鈕帶的是剛才那一行。
        subscription.state = const SubscriptionState(
          dailyMessagesUsed: 3,
          isLoading: true,
        );
        await tapOrb(tester);
        expect(find.text('開始分析前'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);
      },
    );

    SubscriptionState essentialPlan() {
      final limits =
          SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);
      return SubscriptionState(
        tier: SubscriptionTierHelper.essential,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      );
    }

    // 額度提示（Eric 2026-10-18；主審 r1 P2-2）：用完這次之後剩的不到兩次一般長度
    // 分析（每次最多扣 MessageCalculator.softCapUnits 則），那一行下面再寫一句，只說
    // 保證做得到的。這裡的片段只扣 1 則，正好說明短的片段扣得少。
    Future<void> pumpWithLeftAfter(WidgetTester tester, int leftAfter) async {
      final limits =
          SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);
      // 「今天加班好累喔」7 字 → 1 則。
      await pumpOrbScreen(
        tester,
        subscription: SubscriptionState(
          tier: SubscriptionTierHelper.essential,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          dailyMessagesUsed: limits.daily - 1 - leftAfter,
        ),
      );
      expect(find.text('這次會用 1 則，剩 $leftAfter 則'), findsOneWidget);
    }

    testWidgets('額度提示：用完這次後還夠兩次完整分析，不寫', (tester) async {
      await pumpWithLeftAfter(tester, MessageCalculator.softCapUnits * 2);
      expect(
        find.byKey(FloatingAnalysisActionButton.captionHintKey),
        findsNothing,
      );
    });

    testWidgets('額度提示：用完這次後夠一次一般長度，寫至少還能分析 1 次', (tester) async {
      await pumpWithLeftAfter(tester, MessageCalculator.softCapUnits * 2 - 1);
      expect(
        find.text(
          '至少還能分析 1 次（${MessageCalculator.softCapBandMaxChars} 字以內）',
        ),
        findsOneWidget,
      );
    });

    testWidgets('額度提示：用完這次後不到一次一般長度，短的片段還能分析', (tester) async {
      await pumpWithLeftAfter(tester, MessageCalculator.softCapUnits - 1);
      expect(find.text('短的片段還能分析，長一點的可能不夠'), findsOneWidget);
    });

    testWidgets('額度提示：用完這次後剩 0，那一行已經寫了，不另外寫', (tester) async {
      await pumpWithLeftAfter(tester, 0);
      expect(
        find.byKey(FloatingAnalysisActionButton.captionHintKey),
        findsNothing,
      );
    });

    testWidgets(
      '一般長度的上限：剛好 2000 字照樣一行就開始，不跳框',
      (tester) async {
        final plan = essentialPlan();
        final remaining = plan.monthlyRemaining < plan.dailyRemaining
            ? plan.monthlyRemaining
            : plan.dailyRemaining;
        final harness = await pumpOrbScreen(
          tester,
          subscription: plan,
          conversation: charsConversation(count: 4, chars: 500),
        );
        expect(find.text('這次會用 10 則，剩 ${remaining - 10} 則'), findsOneWidget);
        await tapOrb(tester);
        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    testWidgets(
      '一般長度的上限：2001 字不寫那一行，跳「內容較長」確認框、不送出',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: essentialPlan(),
          conversation: charsConversation(count: 4, chars: 500, extra: 1),
        );
        expect(
            find.byKey(FloatingAnalysisActionButton.captionKey), findsNothing);
        await tapOrb(tester);
        expect(find.text('內容較長，確認後才會扣'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);
      },
    );

    testWidgets(
      '第一次用：額度那一行照樣跳過確認框，但資料分享同意框照舊要先同意才送出',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          consentAccepted: false,
        );
        expect(
          find.text('這次會用 1 則，剩 ${freeLeftAfter(units: 1)} 則'),
          findsOneWidget,
        );
        await tapOrb(tester);
        expect(find.text('開始分析前'), findsNothing);
        expect(find.text('同意並繼續'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);

        await tester.tap(find.byType(Checkbox).last);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('同意並繼續').last);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(harness.recorder.streamCalls, 1);
      },
    );

    // 連點（主審 r1 P1）：開始前有好幾段等待，確認框又可能跳過，第二下不能再開一次。
    Future<void> pumpFrames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets(
      '連點兩下：前置還沒做完又按一次、兩邊前置完成順序顛倒，也只送出一次',
      (tester) async {
        final memory = _GatedConversationMemory();
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          memory: memory,
        );
        final orb = find.byKey(FloatingAnalysisActionButton.buttonKey);
        await tester.tap(orb);
        await tester.pump();
        await tester.tap(orb, warnIfMissed: false);
        await tester.pump();

        // 後按的先做完、先按的後做完。
        for (final gate in memory.gates.reversed.toList()) {
          gate.complete('較早的對話摘要');
          await pumpFrames(tester);
        }
        expect(harness.recorder.streamCalls, 1);
        expect(memory.gates, hasLength(1), reason: '第二下在入口就擋下，連組請求都沒開始');
      },
    );

    testWidgets(
      '開始失敗之後鎖會放掉：按重試照樣能再開始',
      (tester) async {
        final memory = _GatedConversationMemory();
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          memory: memory,
        );
        await tester.tap(find.byKey(FloatingAnalysisActionButton.buttonKey));
        await tester.pump();
        memory.gates.single.completeError(StateError('組請求失敗'));
        await pumpFrames(tester);
        expect(find.text('分析暫時失敗，請稍後再試。'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);

        final retry = find.widgetWithText(ElevatedButton, '重新分析');
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pump();
        expect(memory.gates, hasLength(2));
        memory.gates.last.complete('較早的對話摘要');
        await pumpFrames(tester);
        // 重試看不到圓鈕下那一行，照舊跳確認框。
        expect(find.text('開始分析前'), findsOneWidget);
        await tester.tap(find.text('開始分析').last);
        await pumpFrames(tester);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    // 最後一則是他傳的（Eric 2026-10-18）：開始前先問，先不要就什麼都不送。
    Conversation endsWithHisMessage() => _conversation(extraMessages: [
          Message(
            id: 'm2',
            content: '那要不要早點睡',
            isFromMe: true,
            timestamp: DateTime(2026, 5, 28, 12, 1),
          ),
        ]);

    testWidgets(
      '最後一則是他傳的：按分析先跳「最後一則是你傳的」，先不要就不送出、也不跳確認框',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          conversation: endsWithHisMessage(),
        );
        await tapOrb(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('最後一則是你傳的'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('his-last-message-cancel')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('最後一則是你傳的'), findsNothing);
        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 0);

        // 先不要之後開始鎖已放掉：再按一次照樣會問。
        await tapOrb(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('最後一則是你傳的'), findsOneWidget);
      },
    );

    testWidgets(
      '最後一則是他傳的：還是要分析就照常開始（額度夠的一般長度一樣不跳確認框）',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          conversation: endsWithHisMessage(),
        );
        await tapOrb(tester);
        await tester.pump(const Duration(milliseconds: 400));
        await tester
            .tap(find.byKey(const ValueKey('his-last-message-proceed')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
        expect(harness.recorder.streamMessages!.last.isFromMe, isTrue,
            reason: '他傳的那則照樣送去分析');
      },
    );

    testWidgets(
      '最後一則是她傳的：不問，直接照一般流程',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
        );
        await tapOrb(tester);
        expect(find.text('最後一則是你傳的'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    // 額度不夠時的自傷關心（Eric 2026-10-18）：她的訊息有那五個字（含簡體寫法）就不跳
    // 額度不足的框，照常送出；伺服器只回關心訊息與專線，不扣、不打模型。
    /// 他問一句、她回一句（她那句 [her]）。
    Conversation selfHarmConversation({
      required String her,
      String his = '最近工作還順利嗎？上次你說新主管很難搞',
    }) =>
        Conversation(
          id: _conversationId,
          name: '小雲',
          messages: [
            Message(
              id: 'his-1',
              content: his,
              isFromMe: true,
              timestamp: DateTime(2026, 10, 18, 9),
            ),
            Message(
              id: 'her-1',
              content: her,
              isFromMe: false,
              timestamp: DateTime(2026, 10, 18, 10),
            ),
          ],
          createdAt: DateTime(2026, 10, 18),
          updatedAt: DateTime(2026, 10, 18),
          currentRound: 1,
        );
    const herSelfHarm = '其實壓力大到每天都睡不好，有時候會覺得不想活了，也不知道能跟誰說';
    const herPlain = '其實壓力大到每天都睡不好，下班只想躺著，也不知道能跟誰說這些事情';

    /// 這段對話要扣幾則（跟按下去時同一個算法）。
    int unitsOf(Conversation conversation) =>
        MessageCalculator.previewAnalysisRequest(conversation.messages)
            .band
            .units!;

    /// 今天剩的比這段要扣的少一則（還沒用完）。
    SubscriptionState oneShortToday(Conversation conversation) {
      final units = unitsOf(conversation);
      expect(units, greaterThanOrEqualTo(2), reason: '要扣 2 則以上才測得到剩的不夠');
      return SubscriptionState(
        dailyMessagesUsed: AppConstants.freeDailyLimit - (units - 1),
      );
    }

    testWidgets(
      '自傷關心：今天額度用完、她說不想活了，不跳額度不足的框，直接送出',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(
            dailyMessagesUsed: AppConstants.freeDailyLimit,
          ),
          conversation: selfHarmConversation(her: herSelfHarm),
        );
        expect(
            find.byKey(FloatingAnalysisActionButton.captionKey), findsNothing);
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    testWidgets(
      '自傷關心：剩的比這段要扣的少（簡體「自杀」），一樣直接送出',
      (tester) async {
        final conversation = selfHarmConversation(
          her: '其實壓力大到每天都睡不好，有時候真的會想自杀，也不知道能跟誰說',
        );
        final harness = await pumpOrbScreen(
          tester,
          subscription: oneShortToday(conversation),
          conversation: conversation,
        );
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    testWidgets(
      '自傷關心：剩的不夠、沒有那五個字，照舊跳額度不足的框、不送出',
      (tester) async {
        final conversation = selfHarmConversation(her: herPlain);
        final harness = await pumpOrbScreen(
          tester,
          subscription: oneShortToday(conversation),
          conversation: conversation,
        );
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);
      },
    );

    testWidgets(
      '自傷關心：那些字只在他的訊息，照舊跳額度不足的框、不送出',
      (tester) async {
        final conversation = selfHarmConversation(
          his: '我最近真的累到覺得不想活了，工作一直出包',
          her: herPlain,
        );
        final harness = await pumpOrbScreen(
          tester,
          subscription: oneShortToday(conversation),
          conversation: conversation,
        );
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);
      },
    );

    testWidgets(
      '自傷關心：額度夠時不變，照舊寫那一行、按下去直接開始',
      (tester) async {
        final conversation = selfHarmConversation(her: herSelfHarm);
        final units = unitsOf(conversation);
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(),
          conversation: conversation,
        );
        expect(
          find.text('這次會用 $units 則，剩 ${freeLeftAfter(units: units)} 則'),
          findsOneWidget,
        );
        await tapOrb(tester);

        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
      },
    );

    testWidgets(
      '自傷關心：第一次用，不跳額度框，但資料分享同意框照舊要先同意才送出',
      (tester) async {
        final harness = await pumpOrbScreen(
          tester,
          subscription: const SubscriptionState(
            dailyMessagesUsed: AppConstants.freeDailyLimit,
          ),
          conversation: selfHarmConversation(her: herSelfHarm),
          consentAccepted: false,
        );
        await tapOrb(tester);
        expect(find.text('開始分析前'), findsNothing);
        expect(find.text('同意並繼續'), findsOneWidget);
        expect(harness.recorder.streamCalls, 0);

        await tester.tap(find.byType(Checkbox).last);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('同意並繼續').last);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(harness.recorder.streamCalls, 1);
      },
    );

    testWidgets(
      '自傷關心：超過 2000 字、剩的不夠，不跳「內容較長」確認框，送出時也不帶長內容確認',
      (tester) async {
        final long = Conversation(
          id: _conversationId,
          name: '小雲',
          messages: [
            for (var i = 0; i < 4; i++)
              Message(
                id: 'her-long-$i',
                content: i == 0 ? '我真的不想活了${'好' * 493}' : '好' * 501,
                isFromMe: false,
                timestamp: DateTime(2026, 10, 18, 10, i),
              ),
          ],
          createdAt: DateTime(2026, 10, 18),
          updatedAt: DateTime(2026, 10, 18),
          currentRound: 4,
        );
        final preview = MessageCalculator.previewAnalysisRequest(long.messages);
        expect(preview.band.kind, BillingBandKind.overcharge);
        final harness = await pumpOrbScreen(
          tester,
          // 今天剩的比長內容要扣的少一則。
          subscription: SubscriptionState(
            dailyMessagesUsed:
                AppConstants.freeDailyLimit - (preview.band.units! - 1),
          ),
          conversation: long,
        );
        await tapOrb(tester);

        expect(find.text('內容較長，確認後才會扣'), findsNothing);
        expect(find.text('開始分析前'), findsNothing);
        expect(harness.recorder.streamCalls, 1);
        expect(harness.recorder.streamHasOverchargeConfirmation, isFalse);
      },
    );

    testWidgets(
      'F13：片段更新後的過期結果 → 顯示原因與能按的「重新分析」',
      (tester) async {
        await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            result: _analysisResult(),
            analysisRunId: 'run_stale',
            conversationMessageCount: 5,
          ),
        );

        expect(
          find.text('你剛剛更新了本次片段，這份完整分析先不套用，請重新分析。'),
          findsOneWidget,
        );
        final reanalyze = find.widgetWithText(FilledButton, '重新分析');
        expect(reanalyze, findsOneWidget);
        expect(tester.widget<FilledButton>(reanalyze).onPressed, isNotNull);
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
            result: _analysisResult(),
            analysisRunId: 'run_fr',
          ),
        );

        // The detailed-analysis tree contains widgets (CoachSurface) that
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
        expect(recorder.streamCalls, 0);
        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(find.byType(StreamingAnalysisRetryCard), findsNothing);
      },
    );

    testWidgets(
      'live streamingReport to done does not render rollback preview/Core comparison',
      (tester) async {
        final recommendationPreview = _preview(runId: 'run_live_compare');
        final raw = _analysisRawResponse();
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

        harness.notifier.emit(
          StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: recommendationPreview,
            result: _analysisResultWithRawResponse(raw),
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
      },
    );
  });

  // 2026-08-04: reason/psychology 在串流組裝路徑上會被回填成同一個字串
  // （reframer.ts absorbReply 的 psychology: reason），AI 推薦回覆卡因此
  // 曾出現「📝」「🧠」兩行逐字相同的重複內容。UI 端補上比照
  // analysis_record_detail_screen.dart 的既有防呆：psychology == reason
  // 時不顯示第二行。
  group('AnalysisScreen final recommendation duplicate reason/psychology', () {
    testWidgets(
      'psychology equals reason → 🧠 line is hidden, only 📝 renders',
      (tester) async {
        final full = AnalysisResult(
          enthusiasmScore: _analysisResult().enthusiasmScore,
          strategy: _analysisResult().strategy,
          gameStage: _analysisResult().gameStage,
          psychology: _analysisResult().psychology,
          topicDepth: _analysisResult().topicDepth,
          replies: _analysisResult().replies,
          replyOptions: _analysisResult().replyOptions,
          recommendation: const FinalRecommendation(
            pick: 'tease',
            content: 'c',
            reason: '順著她主動分享的內容延伸，回覆壓力比較低。',
            psychology: '順著她主動分享的內容延伸，回覆壓力比較低。',
          ),
          reminder: _analysisResult().reminder,
        );

        await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_dup'),
            result: full,
            analysisRunId: 'run_dup',
          ),
        );
        // ignore: avoid_dynamic_calls
        tester.takeException();

        // 2026-08-14 對標批：emoji 前綴改為說明卡純文字。
        expect(
          find.text('順著她主動分享的內容延伸，回覆壓力比較低。'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'psychology differs from reason → both 📝 and 🧠 render',
      (tester) async {
        final full = AnalysisResult(
          enthusiasmScore: _analysisResult().enthusiasmScore,
          strategy: _analysisResult().strategy,
          gameStage: _analysisResult().gameStage,
          psychology: _analysisResult().psychology,
          topicDepth: _analysisResult().topicDepth,
          replies: _analysisResult().replies,
          replyOptions: _analysisResult().replyOptions,
          recommendation: const FinalRecommendation(
            pick: 'tease',
            content: 'c',
            reason: '順著她主動分享的內容延伸，回覆壓力比較低。',
            psychology: '讓她感覺你真的有在聽，而不是急著換話題。',
          ),
          reminder: _analysisResult().reminder,
        );

        await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_distinct'),
            result: full,
            analysisRunId: 'run_distinct',
          ),
        );
        // ignore: avoid_dynamic_calls
        tester.takeException();

        expect(
          find.text('順著她主動分享的內容延伸，回覆壓力比較低。'),
          findsOneWidget,
        );
        expect(
          find.text('讓她感覺你真的有在聽，而不是急著換話題。'),
          findsOneWidget,
        );
      },
    );
  });

  // Codex round-2 P1: when a conversation already has a persisted detailed
  // analysis (`lastAnalysisSnapshotJson`), `_restorePersistedAnalysis()` seeds
  // `_enthusiasmScore` and the rest of the detailed-analysis local mirrors in
  // initState. If hydration of a partial phase (streamingReport /
  // failedAfterRecommendation / failedBeforeRecommendation) doesn't clear
  // those mirrors, the
  // build tree keeps showing the stale detailed analysis on top of (or instead
  // of) the live streaming loader / retry state. I-P1-c.
  group(
    'AnalysisScreen hydration with stale persisted snapshot (Codex round-2 P1)',
    () {
      testWidgets(
        'streamingReport preview over stale snapshot → loader, no stale detailed analysis',
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
              recommendationPreview: _preview(runId: 'run_qr_stale'),
              analysisRunId: 'run_qr_stale',
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(StreamingAnalysisRetryCard), findsNothing);
          // Stale detailed copy must not bleed through.
          expect(find.text('舊建議內容'), findsNothing);
          expect(find.text('舊策略：保守'), findsNothing);
          expect(harness.recorder.streamCalls, 0);
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
          expect(find.byType(StreamingAnalysisRetryCard), findsNothing);
          expect(find.text('舊建議內容'), findsNothing);
          expect(harness.recorder.streamCalls, 0);
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
              streamErrorMessage: '完整分析失敗，可以重試。',
              streamErrorCode: 'FULL_FAILED',
              retriesRemaining: 2,
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(harness.recorder.streamCalls, 0);
          expect(find.byType(StreamingAnalysisRetryCard), findsOneWidget);
          expect(find.text('舊建議內容'), findsNothing);
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
          final raw = _analysisRawResponse();
          // No prior snapshot, listener never ran for this run.
          final conv = _conversation();

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_off_screen'),
              result: _analysisResultWithRawResponse(raw),
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
          final raw = _analysisRawResponse();
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
              result: _analysisResultWithRawResponse(raw),
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
          final raw = _analysisRawResponse();
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
          final raw = _analysisRawResponse();
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
          final raw = _analysisRawResponse();
          // Listener already ran during the original streamingReport→done
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
              result: _analysisResultWithRawResponse(raw),
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
          final raw = _analysisRawResponse();
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
              result: _analysisResultWithRawResponse(raw),
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
              result: _analysisResultWithRawResponse(raw),
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
          final raw = _analysisRawResponse();
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
              result: _analysisResultWithRawResponse(raw),
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
      '回覆區合併：推薦卡是橫滑第一張、同型風格卡去重、折疊區不再含回覆',
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

        // 推薦卡在橫滑回覆區裡，且整個畫面只有這一張推薦卡。
        expect(
            find.byKey(const ValueKey('analysis-reply-zone')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('analysis-reply-zone')),
            matching:
                find.byKey(const ValueKey('analysis-recommended-reply-card')),
          ),
          findsOneWidget,
        );
        expect(find.text('回覆建議'), findsOneWidget);

        // pick=extend：延展風格卡與推薦卡同內容，去重不再出現；
        // 下一張是共鳴（在視口內會被 mount）。
        expect(find.text('延展', skipOffstage: false), findsNothing);
        expect(find.text('共鳴', skipOffstage: false), findsOneWidget);

        // 折疊區改名且不再帶回覆相關文案。
        expect(find.text('詳細分析'), findsOneWidget);
        expect(find.text('詳細分析與更多回覆'), findsNothing);
        expect(find.textContaining('接法建議'), findsNothing);
        expect(find.textContaining('種回覆'), findsNothing);
      },
    );

    testWidgets(
      'done for an older message count shows stale-result retry and skips stale persist',
      (tester) async {
        final raw = _analysisRawResponse();
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
            result: _analysisResultWithRawResponse(raw),
            analysisRunId: 'run_stale_message_count',
            conversationMessageCount: 1,
          ),
          conversation: conversationWithNewMessage,
        );

        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(StreamingAnalysisRetryCard), findsOneWidget,
            reason:
                'Older full result must not render as the current detailed report after the user adds messages.');
        expect(harness.repo.updateCalls, 0,
            reason:
                'Stale full result must not persist or advance analyzed count.');
      },
    );

    testWidgets(
      'done for an older same-count content revision skips stale persist',
      (tester) async {
        final raw = _analysisRawResponse();
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
            result: _analysisResultWithRawResponse(raw),
            analysisRunId: 'run_stale_revision',
            conversationMessageCount: 1,
            conversationContentRevision: analyzedRevision,
          ),
          conversation: conversation,
        );

        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(StreamingAnalysisRetryCard), findsOneWidget);
        expect(harness.repo.updateCalls, 0,
            reason:
                'Same-count edits must invalidate an older full result before persistence.');
      },
    );

    testWidgets(
      'same-count edit during snapshot write skips new history evidence',
      (tester) async {
        final raw = _analysisRawResponse();
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
            result: _analysisResultWithRawResponse(raw),
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
          streamResult: _analysisResultWithRawResponse(_paidRawResponse()),
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
          streamResult: _analysisResultWithRawResponse(_paidRawResponse()),
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
          streamResult: _analysisResultWithRawResponse(_paidRawResponse()),
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
          streamResult: _analysisResultWithRawResponse(paidRaw),
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

  group('完成後立即離頁仍要保存本輪分析', () {
    testWidgets('返回會等快照、獨立紀錄與報告事件全部落盤', (tester) async {
      final harness = await _completeAnalysisWithBlockedPersistence(
        tester,
        runId: 'run_immediate_leave',
      );

      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_back).first,
          )
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 500));
      final stayedUntilSaved =
          find.byType(AnalysisScreen).evaluate().isNotEmpty &&
              find.text('測試首頁').evaluate().isEmpty &&
              harness.router.routeInformationProvider.value.uri.path ==
                  '/conversation';

      harness.repository.allowSave.complete();
      await tester.pumpAndSettle();

      expect(
        stayedUntilSaved,
        isTrue,
        reason: '畫面顯示完成後，返回仍須等待本輪持久化，不能先 dispose。',
      );
      expect(find.text('測試首頁'), findsOneWidget);
      expect(
        harness.recordStore.listArchived(
          ownerUserId: 'record-owner',
          conversationIds: const [_conversationId],
        ),
        hasLength(1),
      );
      expect(harness.history.events, hasLength(1));
    });

    testWidgets('分析紀錄按鈕也會等本輪落盤後才開啟', (tester) async {
      final harness = await _completeAnalysisWithBlockedPersistence(
        tester,
        runId: 'run_immediate_records',
      );

      tester
          .widget<AnalysisRecordsEntryButton>(
            find.byKey(const ValueKey('analysis-records-entry')),
          )
          .onPressed();
      await tester.pump(const Duration(milliseconds: 500));
      final openedBeforeSave = find
          .byKey(const ValueKey('partner-analysis-records-list'))
          .evaluate()
          .isNotEmpty;

      harness.repository.allowSave.complete();
      await tester.pumpAndSettle();

      expect(
        openedBeforeSave,
        isFalse,
        reason: '紀錄頁不能在本輪尚未寫入時先顯示舊資料。',
      );
      expect(
        find.byKey(const ValueKey('partner-analysis-records-list')),
        findsOneWidget,
      );
      expect(
        harness.recordStore.listArchived(
          ownerUserId: 'record-owner',
          conversationIds: const [_conversationId],
        ),
        hasLength(1),
      );
      expect(harness.history.events, hasLength(1));
    });
  });

  group('案2：analyze 歷史事件 hook', () {
    testWidgets('hydrate persist 成功 → 寫入一筆 analyze 歷史事件', (tester) async {
      final raw = _analysisRawResponse();
      final conv = _conversation(
        partnerId: 'partner-history',
      ); // 無既有 snapshot → 會走 persist

      final harness = await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: StreamingAnalysisState(
          phase: StreamingAnalyzePhase.done,
          recommendationPreview: _preview(runId: 'run_history_write'),
          result: _analysisResultWithRawResponse(raw),
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
      expect(event.partnerId, 'partner-history');
      expect(event.subjectName, '小雲');
      expect(event.enthusiasmScore, 72);
      expect(event.gameStageLabel, 'premise');
    });

    testWidgets('alreadyPersisted gate 命中 → 不寫歷史事件（去重繼承）', (tester) async {
      final raw = _analysisRawResponse();
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
          result: _analysisResultWithRawResponse(raw),
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

  // 最低 App 版本閘門（Eric 2026-10-18）：被擋是「只能更新」，不是內容錯誤，
  // 也不給重新分析；更新視窗只在當下的轉場跳一次。
  group('最低 App 版本閘門（APP_UPDATE_REQUIRED）', () {
    const updateMessage = '這個版本已經停止支援，請到 App Store 更新到最新版。';

    StreamingAnalysisState blocked(Conversation conversation) {
      return StreamingAnalysisState(
        phase: StreamingAnalyzePhase.failedBeforeRecommendation,
        recommendationPreviewErrorMessage: updateMessage,
        recommendationPreviewErrorCode: 'APP_UPDATE_REQUIRED',
        conversationMessageCount: conversation.messages.length,
        previousAnalyzedCount: 0,
        analyzedMessageCount: conversation.messages.length,
        conversationContentRevision: conversationContentRevision(conversation),
      );
    }

    testWidgets('新分析被擋 → 跳更新視窗；錯誤卡只給前往更新，不給重新分析', (tester) async {
      final launched = <Uri>[];
      final conversation = _conversation();
      final harness = await _pumpMutableAnalysisScreenWithRepo(
        tester,
        seed: const StreamingAnalysisState.idle(),
        conversation: conversation,
        extraOverrides: [
          appStoreLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ],
      );

      // 開畫面時會先蓋上「可以改訊息」的提示（debug 一律顯示，而且疊在
      // 對話框上面）；真實使用時按下分析前早就關掉了，這裡先關。
      await tester.pump();
      final coachMarkGotIt = find.text('知道了');
      if (coachMarkGotIt.evaluate().isNotEmpty) {
        await tester.tap(coachMarkGotIt);
        await tester.pump();
      }

      harness.notifier.emit(blocked(conversation));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('請更新 VibeSync')),
        findsOneWidget,
      );
      final card = find.byType(AnalysisErrorCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text(updateMessage)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('前往更新')),
        findsOneWidget,
      );
      expect(find.text('重新分析'), findsNothing);

      await tester.tap(
        find.descendant(of: dialog, matching: find.text('前往更新')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(launched, [Uri.parse(appStoreUpdateUrl)]);
      expect(find.byType(AlertDialog), findsNothing);

      // 卡片留著；按卡片上的前往更新也直接開商店，不會重送分析。
      final cardButton = find.descendant(of: card, matching: find.text('前往更新'));
      await tester.ensureVisible(cardButton);
      await tester.tap(cardButton);
      await tester.pump();
      expect(launched, hasLength(2));
      expect(find.byType(AnalysisErrorCard), findsOneWidget);
      expect(harness.recorder.streamCalls, 0);
    });

    testWidgets('回到畫面（hydrate）只顯示錯誤卡，不再跳視窗', (tester) async {
      final conversation = _conversation();
      await _pumpHydratedAnalysisScreenWithRepo(
        tester,
        seed: blocked(conversation),
        conversation: conversation,
        extraOverrides: [
          appStoreLauncherProvider.overrideWithValue((_) async => true),
        ],
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
      final card = find.byType(AnalysisErrorCard);
      expect(
        find.descendant(of: card, matching: find.text(updateMessage)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('前往更新')),
        findsOneWidget,
      );
      expect(find.text('重新分析'), findsNothing);
    });
  });
}
