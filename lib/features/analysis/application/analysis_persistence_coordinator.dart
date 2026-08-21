/// AnalyzeChat 分析結果持久化協調器：冷啟動還原（restore）、canonical
/// snapshot 寫入與補償回滾（persist）、分析紀錄修復（repair）、離場前
/// 等待落定（awaitSettled）。所有寫入語意逐字沿用拆分前
/// AnalysisScreen 的實作。
///
/// 依賴方向：這裡只收具名注入的 callable／repository 介面，不解析
/// Riverpod provider、不 import presentation；組裝在
/// `analysis_providers.dart` 的 composition root。UI 重繪與 provider
/// 失效透過注入的 callback 回到畫面層。
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../analysis_history/domain/repositories/analysis_history_repository.dart';
import '../../conversation/data/providers/conversation_write_controller.dart'
    show ConversationSaveIntent;
import '../../conversation/data/repositories/conversation_archive_store.dart'
    show
        ConversationArchiveEntry,
        ConversationArchiveStatus,
        conversationContentRevision;
import '../../conversation/domain/entities/conversation.dart';
import '../data/repositories/analysis_record_store.dart';
import '../data/services/analysis_transport_support.dart' show analysisDebugLog;
import '../domain/entities/analysis_models.dart';
import '../domain/entities/analysis_record.dart';

/// canonical 對話存檔（含 analysisCompleted 的修訂前置檢查與補償路徑）。
typedef SaveConversation = Future<void> Function(
  Conversation conversation, {
  required ConversationSaveIntent intent,
  String? expectedContentRevision,
});

/// [AnalysisPersistenceCoordinator.restore] 的結果：畫面據此套用本地鏡像。
class AnalysisRestoreOutcome {
  final AnalysisResult result;
  final int analyzedMessageCount;

  const AnalysisRestoreOutcome({
    required this.result,
    required this.analyzedMessageCount,
  });
}

class AnalysisPersistenceCoordinator {
  static const _snapshotClientMetaKey = '__vibesync_snapshot_meta_v1';
  static const _snapshotRevisionKey = 'contentRevision';
  static const _snapshotMessageCountKey = 'messageCount';

  AnalysisPersistenceCoordinator({
    required this.conversationId,
    required Conversation? Function(String conversationId) getConversation,
    required SaveConversation saveConversation,
    required Future<void> Function(Conversation conversation)
        markConversationActive,
    required ConversationArchiveEntry? Function(Conversation conversation)
        archiveEntryFor,
    required AnalysisRecordStore Function() recordStore,
    required String? Function() currentRecordOwnerUserId,
    required AnalysisHistoryRepository Function() historyRepository,
    required Future<void> Function(String eventKey) trackFunnelOnce,
    required int? Function() lastPayloadCharCount,
    required void Function() notifyStateChanged,
    required void Function(Conversation conversation) invalidateRecordViews,
    required Future<void> Function(Conversation conversation)
        afterAnalysisPersisted,
  })  : _getConversation = getConversation,
        _saveConversation = saveConversation,
        _markConversationActive = markConversationActive,
        _archiveEntryFor = archiveEntryFor,
        _recordStore = recordStore,
        _currentRecordOwnerUserId = currentRecordOwnerUserId,
        _historyRepository = historyRepository,
        _trackFunnelOnce = trackFunnelOnce,
        _lastPayloadCharCount = lastPayloadCharCount,
        _notifyStateChanged = notifyStateChanged,
        _invalidateRecordViews = invalidateRecordViews,
        _afterAnalysisPersisted = afterAnalysisPersisted;

  final String conversationId;
  final Conversation? Function(String conversationId) _getConversation;
  final SaveConversation _saveConversation;
  final Future<void> Function(Conversation conversation)
      _markConversationActive;
  final ConversationArchiveEntry? Function(Conversation conversation)
      _archiveEntryFor;

  /// 紀錄存放層每次呼叫時解析（維持與原 per-call `ref.read` 相同的新鮮度）。
  final AnalysisRecordStore Function() _recordStore;
  final String? Function() _currentRecordOwnerUserId;
  final AnalysisHistoryRepository Function() _historyRepository;
  final Future<void> Function(String eventKey) _trackFunnelOnce;

  /// ADR #19 規格 #8：最近一次 start 實際送出 payload 的計費字數
  /// （真相在 streaming notifier，這裡以 callable 注入避免鏡射）。
  final int? Function() _lastPayloadCharCount;

  /// in-flight 計數或修復旗標翻動時通知畫面重繪（畫面自行守 mounted）。
  final void Function() _notifyStateChanged;

  /// 紀錄成功落地後讓畫面失效 archive 計數快取與 partner 紀錄 provider。
  final void Function(Conversation conversation) _invalidateRecordViews;

  /// canonical snapshot 落地後的畫面層跟進（48h 跟進通知軟卡）。
  final Future<void> Function(Conversation conversation)
      _afterAnalysisPersisted;

  int _inFlightCount = 0;
  final Set<Future<void>> _pendingTasks = {};
  bool _recordNeedsRepair = false;
  Future<void>? _recordRepairFuture;

  /// 進行中的持久化工作數（畫面用來擋來源改標與顯示保存中狀態）。
  int get inFlightCount => _inFlightCount;

  /// 上一筆分析紀錄是否尚未安全落地（畫面渲染修復提示、擋新分析）。
  bool get recordNeedsRepair => _recordNeedsRepair;

  /// 最近一次排程的紀錄修復；新分析開跑前要先等它。
  Future<void>? get recordRepairFuture => _recordRepairFuture;

  /// 冷啟動還原：讀 durable snapshot、驗證修訂、就地升級 legacy meta，
  /// 需要時排程紀錄修復。回傳畫面要套用的結果；不可還原時回 null。
  AnalysisRestoreOutcome? restore({required bool repairRecord}) {
    final conversation = _getConversation(conversationId);
    if (conversation == null) {
      return null;
    }

    final snapshotJson = conversation.lastAnalysisSnapshotJson;
    if (snapshotJson == null || snapshotJson.trim().isEmpty) {
      return null;
    }

    try {
      final snapshot = _normalizeJsonMap(jsonDecode(snapshotJson));
      if (snapshot == null) {
        return null;
      }
      if (!_canRestorePersistedAnalysis(conversation, snapshot)) {
        return null;
      }

      if (!snapshot.containsKey(_snapshotClientMetaKey)) {
        final analyzedCount = conversation.lastAnalyzedMessageCount!;
        snapshot[_snapshotClientMetaKey] = <String, Object>{
          _snapshotRevisionKey: conversationContentRevision(
            conversation,
            messageCount: analyzedCount,
          ),
          _snapshotMessageCountKey: analyzedCount,
        };
        // Upgrade legacy snapshots in memory immediately. The next normal
        // conversation save carries this metadata even if the archive marker
        // write fails, closing same-count edit restores without a Hive schema.
        conversation.lastAnalysisSnapshotJson = jsonEncode(snapshot);
      }

      final analysisPayload = Map<String, dynamic>.from(snapshot)
        ..remove(_snapshotClientMetaKey);
      final restoredResult = AnalysisResult.fromJson(analysisPayload);
      if (repairRecord) {
        final analyzedCount = conversation.lastAnalyzedMessageCount!;
        final current = currentRecordFor(conversation);
        scheduleRecordRepair(
          conversation: conversation,
          result: restoredResult,
          completionKey: null,
          previousAnalyzedCount: current?.segmentEnd ?? 0,
          analyzedMessageCount: analyzedCount,
          analyzedContentRevision: conversationContentRevision(conversation),
        );
      }
      return AnalysisRestoreOutcome(
        result: restoredResult,
        analyzedMessageCount: conversation.lastAnalyzedMessageCount!,
      );
    } catch (error) {
      analysisDebugLog(
        '[AnalysisPersistenceCoordinator] Failed to restore persisted '
        'analysis for $conversationId: $error',
      );
      return null;
    }
  }

  /// 把一次紀錄修復排進追蹤佇列並記為當前 repairFuture。
  void scheduleRecordRepair({
    required Conversation conversation,
    required AnalysisResult result,
    required String? completionKey,
    required int? previousAnalyzedCount,
    required int analyzedMessageCount,
    required String? analyzedContentRevision,
  }) {
    _recordRepairFuture = _trackTask(
      _repairAnalysisRecord(
        conversation: conversation,
        result: result,
        completionKey: completionKey,
        previousAnalyzedCount: previousAnalyzedCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedContentRevision,
      ),
    );
  }

  bool _canRestorePersistedAnalysis(
    Conversation conversation,
    Map<String, dynamic> snapshot,
  ) {
    final analyzedCount = conversation.lastAnalyzedMessageCount;
    if (analyzedCount == null ||
        analyzedCount < 0 ||
        analyzedCount > conversation.messages.length) {
      return false;
    }
    if (snapshot.containsKey(_snapshotClientMetaKey)) {
      final rawMeta = snapshot[_snapshotClientMetaKey];
      if (rawMeta is! Map) return false;
      final embeddedRevision = rawMeta[_snapshotRevisionKey];
      final embeddedCount = rawMeta[_snapshotMessageCountKey];
      if (embeddedRevision is! String ||
          embeddedRevision.trim().isEmpty ||
          embeddedCount is! int ||
          embeddedCount != analyzedCount) {
        return false;
      }
      return embeddedRevision ==
          conversationContentRevision(
            conversation,
            messageCount: embeddedCount,
          );
    }

    final archiveEntry = _archiveEntryFor(conversation);
    if (archiveEntry != null) {
      final analyzedRevision = archiveEntry.contentRevision;
      if (archiveEntry.status == ConversationArchiveStatus.archived &&
          analyzedCount != conversation.messages.length) {
        return false;
      }
      return analyzedRevision != null &&
          analyzedRevision ==
              conversationContentRevision(
                conversation,
                messageCount: analyzedCount,
              );
    }

    // Snapshot persistence predates both embedded revisions and archive
    // markers. A markerless payload without client metadata is therefore true
    // legacy compatibility. Every new snapshot embeds its own revision, so a
    // failed marker write can no longer make a post-feature row look legacy.
    return true;
  }

  String? _encodeAnalysisSnapshot(
    Map<String, dynamic>? rawResponse, {
    required String contentRevision,
    required int messageCount,
  }) {
    if (rawResponse == null || rawResponse.isEmpty) {
      return null;
    }
    final snapshot = Map<String, dynamic>.from(rawResponse)
      ..[_snapshotClientMetaKey] = <String, Object>{
        _snapshotRevisionKey: contentRevision,
        _snapshotMessageCountKey: messageCount,
      };
    return jsonEncode(snapshot);
  }

  bool snapshotMatches({
    required Conversation conversation,
    required String? snapshotJson,
    required Map<String, dynamic>? rawResponse,
    required int messageCount,
    required String? analyzedContentRevision,
  }) {
    if (snapshotJson == null ||
        snapshotJson.trim().isEmpty ||
        rawResponse == null ||
        rawResponse.isEmpty ||
        messageCount < 0 ||
        messageCount > conversation.messages.length ||
        analyzedContentRevision == null ||
        conversationContentRevision(conversation) != analyzedContentRevision) {
      return false;
    }
    try {
      final snapshot = _normalizeJsonMap(jsonDecode(snapshotJson));
      if (snapshot == null) {
        return false;
      }
      final rawMeta = snapshot[_snapshotClientMetaKey];
      if (rawMeta is! Map ||
          rawMeta[_snapshotMessageCountKey] != messageCount ||
          rawMeta[_snapshotRevisionKey] !=
              conversationContentRevision(
                conversation,
                messageCount: messageCount,
              )) {
        return false;
      }
      snapshot.remove(_snapshotClientMetaKey);
      return jsonEncode(snapshot) == jsonEncode(rawResponse);
    } catch (_) {
      // A corrupt durable snapshot must not suppress a replacement write.
      return false;
    }
  }

  Map<String, dynamic>? _normalizeJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return null;
  }

  Future<void> persistLatestSnapshot(
    AnalysisResult result, {
    String? completionKey,
    int? previousAnalyzedCount,
    int? analyzedMessageCount,
    String? analyzedContentRevision,
    bool allowArchivedRecordRefresh = false,
  }) {
    return _trackTask(
      _runPersistLatestAnalysisSnapshot(
        result,
        completionKey: completionKey,
        previousAnalyzedCount: previousAnalyzedCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedContentRevision,
        allowArchivedRecordRefresh: allowArchivedRecordRefresh,
      ),
    );
  }

  Future<void> _trackTask(Future<void> task) {
    _pendingTasks.add(task);
    unawaited(
      task.then<void>(
        (_) => _pendingTasks.remove(task),
        onError: (Object _, StackTrace __) {
          _pendingTasks.remove(task);
        },
      ),
    );
    return task;
  }

  Future<void> awaitSettled() async {
    while (_pendingTasks.isNotEmpty) {
      final pending = List<Future<void>>.of(_pendingTasks);
      await Future.wait(
        pending.map((task) async {
          try {
            await task;
          } catch (_) {
            // The existing repair path remains responsible for a failed
            // best-effort record write; leaving must never become a dead end.
          }
        }),
      );
      _pendingTasks.removeAll(pending);
    }
  }

  Future<void> _runPersistLatestAnalysisSnapshot(
    AnalysisResult result, {
    String? completionKey,
    int? previousAnalyzedCount,
    int? analyzedMessageCount,
    String? analyzedContentRevision,
    bool allowArchivedRecordRefresh = false,
  }) async {
    _inFlightCount++;
    _notifyStateChanged();
    try {
      await _persistLatestAnalysisSnapshotCore(
        result,
        completionKey: completionKey,
        previousAnalyzedCount: previousAnalyzedCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedContentRevision,
        allowArchivedRecordRefresh: allowArchivedRecordRefresh,
      );
    } finally {
      if (_inFlightCount > 0) {
        _inFlightCount--;
      }
      _notifyStateChanged();
    }
  }

  Future<void> _persistLatestAnalysisSnapshotCore(
    AnalysisResult result, {
    String? completionKey,
    int? previousAnalyzedCount,
    int? analyzedMessageCount,
    String? analyzedContentRevision,
    bool allowArchivedRecordRefresh = false,
  }) async {
    final conv = _getConversation(conversationId);
    if (conv == null) {
      return;
    }
    if (analyzedContentRevision == null ||
        conversationContentRevision(conv) != analyzedContentRevision) {
      return;
    }

    final previousAnalysis = (
      enthusiasmScore: conv.lastEnthusiasmScore,
      analyzedMessageCount: conv.lastAnalyzedMessageCount,
      analyzedCharCount: conv.lastAnalyzedCharCount,
      gameStage: conv.currentGameStage,
      snapshotJson: conv.lastAnalysisSnapshotJson,
    );
    final targetAnalyzedMessageCount =
        analyzedMessageCount ?? conv.messages.length;
    final targetSnapshotJson = _encodeAnalysisSnapshot(
      result.rawResponse,
      contentRevision: conversationContentRevision(
        conv,
        messageCount: targetAnalyzedMessageCount,
      ),
      messageCount: targetAnalyzedMessageCount,
    );

    conv.lastEnthusiasmScore = result.enthusiasmScore;
    conv.lastAnalyzedMessageCount = targetAnalyzedMessageCount;
    // ADR #19 規格 #8：char baseline 對應「實際送出的 requestMessages」
    //（notifier 在 start 時計），不是完成時 repository 裡的最新 messages
    //（避免分析中新進訊息造成 baseline 漂移）。
    final payloadCharCount = _lastPayloadCharCount();
    if (payloadCharCount != null) {
      conv.lastAnalyzedCharCount = payloadCharCount;
    }
    conv.currentGameStage = result.gameStage.current.name;
    conv.lastAnalysisSnapshotJson = targetSnapshotJson;

    await _saveConversation(
      conv,
      intent: ConversationSaveIntent.analysisCompleted,
      expectedContentRevision: analyzedContentRevision,
    );

    if (conversationContentRevision(conv) != analyzedContentRevision) {
      // Content changed while the snapshot write was in flight. Roll back this
      // run's analysis fields only if they are still the values we wrote; a
      // genuinely newer, different analysis must win. Then persist the latest
      // messages as active and avoid creating fresh legacy-history evidence.
      if (conv.lastAnalysisSnapshotJson == targetSnapshotJson &&
          conv.lastAnalyzedMessageCount == targetAnalyzedMessageCount) {
        conv.lastEnthusiasmScore = previousAnalysis.enthusiasmScore;
        conv.lastAnalyzedMessageCount = previousAnalysis.analyzedMessageCount;
        conv.lastAnalyzedCharCount = previousAnalysis.analyzedCharCount;
        conv.currentGameStage = previousAnalysis.gameStage;
        conv.lastAnalysisSnapshotJson = previousAnalysis.snapshotJson;
        try {
          await _saveConversation(
            conv,
            intent: ConversationSaveIntent.contentChanged,
          );
        } catch (_) {
          // The compensating conversation write can fail independently. Still
          // leave an explicit active marker when settings storage is healthy,
          // so cold restore cannot treat this post-feature row as legacy.
          await _markConversationActive(conv);
          rethrow;
        }
      }
      return;
    }

    final recordSaved = await _ensureAnalysisRecord(
      conversation: conv,
      result: result,
      completionKey: completionKey,
      previousAnalyzedCount: previousAnalyzedCount,
      analyzedMessageCount: targetAnalyzedMessageCount,
      analyzedContentRevision: analyzedContentRevision,
      allowArchivedRefresh: allowArchivedRecordRefresh,
    );
    _setAnalysisRecordNeedsRepair(!recordSaved);

    // 案2：analyze 歷史事件（best-effort：失敗只 debugPrint，絕不 rethrow，
    // 分析呈現完全不受影響）。去重靠呼叫端既有 gate（hydrate 路徑
    // _maybePersistAndSyncOnHydrate 的 alreadyPersisted 比對＋listener 路徑
    // 一次性觸發），同一次分析絕不重複記錄，這裡不另做冪等。
    try {
      await _historyRepository().append(
        AnalysisHistoryEvent.analyze(
          id: const Uuid().v4(),
          createdAt: DateTime.now(),
          conversationId: conversationId,
          partnerId: conv.partnerId,
          subjectName: conv.name,
          enthusiasmScore: result.enthusiasmScore,
          gameStageLabel: result.gameStage.current.name,
        ),
      );
    } catch (e) {
      debugPrint('AnalysisHistory analyze append failed: $e');
    }

    // Tier 2 批 1.5：首次分析完成漏斗事件（once-flag 去重，best-effort）。
    unawaited(
      _trackFunnelOnce('first_analysis_completed'),
    );

    // 案4：48h 跟進提醒 — 綁 partner 的分析完成後，首次詢問軟卡並排程。
    // best-effort：失敗只 debugPrint，絕不影響分析呈現與快照持久化。
    await _afterAnalysisPersisted(conv);
  }

  void _setAnalysisRecordNeedsRepair(bool value) {
    if (_recordNeedsRepair == value) return;
    _recordNeedsRepair = value;
    _notifyStateChanged();
  }

  Future<void> _repairAnalysisRecord({
    required Conversation conversation,
    required AnalysisResult result,
    required String? completionKey,
    required int? previousAnalyzedCount,
    required int analyzedMessageCount,
    required String? analyzedContentRevision,
  }) async {
    _inFlightCount++;
    _notifyStateChanged();
    try {
      final prefixRevision = analyzedMessageCount > 0 &&
              analyzedMessageCount <= conversation.messages.length
          ? conversationContentRevision(
              conversation,
              messageCount: analyzedMessageCount,
            )
          : null;
      final rawResponse = result.rawResponse;
      final current = currentRecordFor(conversation);
      final canonicalSnapshotMatches = snapshotMatches(
        conversation: conversation,
        snapshotJson: conversation.lastAnalysisSnapshotJson,
        rawResponse: rawResponse,
        messageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedContentRevision,
      );
      if (!_recordNeedsRepair &&
          prefixRevision != null &&
          rawResponse != null &&
          current != null &&
          current.segmentEnd == analyzedMessageCount &&
          current.analyzedContentRevision == prefixRevision &&
          current.analysisSnapshotJson == jsonEncode(rawResponse)) {
        final archived = await _recordStore().archiveCurrentRecord(
          ownerUserId: recordOwnerFor(conversation) ?? '',
          conversationId: conversation.id,
        );
        _setAnalysisRecordNeedsRepair(!archived);
        if (archived) _invalidateRecordViews(conversation);
        return;
      }
      final saved = await _ensureAnalysisRecord(
        conversation: conversation,
        result: result,
        completionKey: completionKey,
        previousAnalyzedCount: previousAnalyzedCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedContentRevision,
        allowArchivedRefresh: canonicalSnapshotMatches,
      );
      _setAnalysisRecordNeedsRepair(!saved);
    } finally {
      if (_inFlightCount > 0) {
        _inFlightCount--;
      }
      _notifyStateChanged();
    }
  }

  Future<bool> _ensureAnalysisRecord({
    required Conversation conversation,
    required AnalysisResult result,
    required String? completionKey,
    required int? previousAnalyzedCount,
    required int analyzedMessageCount,
    required String? analyzedContentRevision,
    bool allowArchivedRefresh = false,
  }) async {
    final ownerUserId = recordOwnerFor(conversation);
    final rawResponse = result.rawResponse;
    if (ownerUserId == null ||
        rawResponse == null ||
        rawResponse.isEmpty ||
        analyzedContentRevision == null ||
        analyzedMessageCount <= 0 ||
        analyzedMessageCount > conversation.messages.length ||
        conversationContentRevision(conversation) != analyzedContentRevision) {
      return false;
    }

    final analyzedPrefixRevision = conversationContentRevision(
      conversation,
      messageCount: analyzedMessageCount,
    );
    final snapshotJson = jsonEncode(rawResponse);
    final snapshotDigest = sha256.convert(utf8.encode(snapshotJson));
    final stableCompletionKey = completionKey?.trim().isNotEmpty == true
        ? completionKey!.trim()
        : 'snapshot:$analyzedPrefixRevision:$analyzedMessageCount:'
            '$snapshotDigest';
    final runStartPreviousCount =
        (previousAnalyzedCount ?? 0).clamp(0, analyzedMessageCount).toInt();
    final store = _recordStore();
    try {
      final saveResult = await store.saveSuccessfulAnalysis(
        ownerUserId: ownerUserId,
        conversation: conversation,
        completionKey: stableCompletionKey,
        runStartPreviousCount: runStartPreviousCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedPrefixRevision,
        analysisSnapshotJson: snapshotJson,
        enthusiasmScore: result.enthusiasmScore,
        gameStageLabel: result.gameStage.current.label,
        allowArchivedRefresh: allowArchivedRefresh,
        sourcePlatform: store.conversationSource(
          ownerUserId: ownerUserId,
          conversationId: conversation.id,
        ),
      );
      if (!saveResult.accepted) {
        debugPrint(
          'Analysis record save rejected: ${saveResult.rejectionReason}',
        );
        return false;
      }
      final archived = await store.archiveCurrentRecord(
        ownerUserId: ownerUserId,
        conversationId: conversation.id,
      );
      if (!archived) {
        debugPrint('Analysis record archive rejected: ${conversation.id}');
        return false;
      }
      _invalidateRecordViews(conversation);
      return true;
    } catch (error) {
      // The canonical analysis snapshot already succeeded. Keep the result
      // usable and let hydrate retry this idempotent record write later.
      debugPrint('Analysis record save failed: $error');
      return false;
    }
  }

  String? recordOwnerFor(Conversation conversation) {
    final currentUserId = _currentRecordOwnerUserId()?.trim();
    if (currentUserId == null || currentUserId.isEmpty) return null;
    final conversationOwner = conversation.ownerUserId?.trim();
    if (conversationOwner != null &&
        conversationOwner.isNotEmpty &&
        conversationOwner != currentUserId) {
      return null;
    }
    return currentUserId;
  }

  AnalysisRecord? currentRecordFor(Conversation conversation) {
    final ownerUserId = recordOwnerFor(conversation);
    if (ownerUserId == null) return null;
    return _recordStore().currentFor(
      ownerUserId: ownerUserId,
      conversationId: conversation.id,
    );
  }
}
