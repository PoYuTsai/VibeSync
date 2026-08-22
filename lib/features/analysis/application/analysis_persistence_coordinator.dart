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
import '../../conversation/domain/entities/conversation.dart';
import '../../conversation/domain/entities/session_context.dart';
import '../../conversation/domain/services/conversation_content_revision.dart';
import '../domain/entities/analysis_models.dart';
import '../domain/entities/analysis_record.dart';
import '../domain/entities/game_stage.dart';
import 'ports/analysis_record_port.dart';
import 'ports/conversation_write_ports.dart';

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
  static const _snapshotHistoryEventIdKey = 'historyEventId';
  static const _snapshotIsReconnectKey = 'isReconnect';

  AnalysisPersistenceCoordinator({
    required this.conversationId,
    required GetConversation getConversation,
    required PersistAnalysisCompletedConversation persistAnalysisCompleted,
    required PersistContentChangedConversation persistContentChanged,
    required MarkConversationActive markConversationActive,
    required ArchiveMarkerLookup archiveMarkerFor,
    required AnalysisRecordPort recordPort,
    required String? Function() currentRecordOwnerUserId,
    required AnalysisHistoryRepository Function() historyRepository,
    required Future<void> Function(String eventKey) trackFunnelOnce,
    required int? Function() lastPayloadCharCount,
    required void Function() notifyStateChanged,
    required void Function(Conversation conversation) invalidateRecordViews,
    required Future<void> Function(Conversation conversation)
        afterAnalysisPersisted,
  })  : _getConversation = getConversation,
        _persistAnalysisCompleted = persistAnalysisCompleted,
        _persistContentChanged = persistContentChanged,
        _markConversationActive = markConversationActive,
        _archiveMarkerFor = archiveMarkerFor,
        _recordPort = recordPort,
        _currentRecordOwnerUserId = currentRecordOwnerUserId,
        _historyRepository = historyRepository,
        _trackFunnelOnce = trackFunnelOnce,
        _lastPayloadCharCount = lastPayloadCharCount,
        _notifyStateChanged = notifyStateChanged,
        _invalidateRecordViews = invalidateRecordViews,
        _afterAnalysisPersisted = afterAnalysisPersisted;

  final String conversationId;
  final GetConversation _getConversation;
  final PersistAnalysisCompletedConversation _persistAnalysisCompleted;
  final PersistContentChangedConversation _persistContentChanged;
  final MarkConversationActive _markConversationActive;
  final ArchiveMarkerLookup _archiveMarkerFor;

  /// 紀錄存放層 port（adapter 內部 per-call 解析，新鮮度與原 read 相同）。
  final AnalysisRecordPort _recordPort;
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
      if (kDebugMode) {
        debugPrint(
          '[AnalysisPersistenceCoordinator] Failed to restore persisted '
          'analysis for $conversationId: $error',
        );
      }
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

    final archiveEntry = _archiveMarkerFor(conversation);
    if (archiveEntry != null) {
      final analyzedRevision = archiveEntry.contentRevision;
      if (archiveEntry.isArchived &&
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
    required String historyEventId,
    bool? isReconnect,
  }) {
    if (rawResponse == null || rawResponse.isEmpty) {
      return null;
    }
    final snapshot = Map<String, dynamic>.from(rawResponse)
      ..[_snapshotClientMetaKey] = <String, Object>{
        _snapshotRevisionKey: contentRevision,
        _snapshotMessageCountKey: messageCount,
        _snapshotHistoryEventIdKey: historyEventId,
        if (isReconnect != null) _snapshotIsReconnectKey: isReconnect,
      };
    return jsonEncode(snapshot);
  }

  bool snapshotMatches({
    required Conversation conversation,
    required String? snapshotJson,
    required Map<String, dynamic>? rawResponse,
    required int messageCount,
    required String? analyzedContentRevision,
    String? analyzedPartnerId,
    bool? analyzedIsReconnect,
  }) {
    if (snapshotJson == null ||
        snapshotJson.trim().isEmpty ||
        rawResponse == null ||
        rawResponse.isEmpty ||
        messageCount < 0 ||
        messageCount > conversation.messages.length ||
        analyzedContentRevision == null ||
        !_sameCapturedPartner(
          conversation,
          analyzedPartnerId: analyzedPartnerId,
          analyzedIsReconnect: analyzedIsReconnect,
        ) ||
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
              ) ||
          (analyzedIsReconnect != null &&
              rawMeta[_snapshotIsReconnectKey] != analyzedIsReconnect)) {
        return false;
      }
      snapshot.remove(_snapshotClientMetaKey);
      return jsonEncode(snapshot) == jsonEncode(rawResponse);
    } catch (_) {
      // A corrupt durable snapshot must not suppress a replacement write.
      return false;
    }
  }

  /// 覆蓋前的 durable snapshot 是否已內嵌同一個 prefix revision＋訊息數。
  /// true＝這次是同內容重試／重新整理；legacy 無 meta 或壞 JSON 回 false。
  bool _snapshotCoversRevision(
    String? snapshotJson, {
    required String revision,
    required int messageCount,
  }) {
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return false;
    try {
      final snapshot = _normalizeJsonMap(jsonDecode(snapshotJson));
      final rawMeta = snapshot?[_snapshotClientMetaKey];
      return rawMeta is Map &&
          rawMeta[_snapshotRevisionKey] == revision &&
          rawMeta[_snapshotMessageCountKey] == messageCount;
    } catch (_) {
      return false;
    }
  }

  String? _snapshotHistoryEventId(String? snapshotJson) {
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return null;
    try {
      final snapshot = _normalizeJsonMap(jsonDecode(snapshotJson));
      final rawMeta = snapshot?[_snapshotClientMetaKey];
      final rawId = rawMeta is Map ? rawMeta[_snapshotHistoryEventIdKey] : null;
      if (rawId is! String || rawId.trim().isEmpty) return null;
      return rawId.trim();
    } catch (_) {
      return null;
    }
  }

  bool? _snapshotIsReconnect(String? snapshotJson) {
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return null;
    try {
      final snapshot = _normalizeJsonMap(jsonDecode(snapshotJson));
      final rawMeta = snapshot?[_snapshotClientMetaKey];
      final rawValue = rawMeta is Map ? rawMeta[_snapshotIsReconnectKey] : null;
      return rawValue is bool ? rawValue : null;
    } catch (_) {
      return null;
    }
  }

  AnalysisHistoryEvent? _findLegacyRerunEvent(
    AnalysisHistoryRepository repository, {
    required int? previousEnthusiasmScore,
    required String? previousGameStage,
  }) {
    if (previousEnthusiasmScore == null) return null;
    final previousStage = GameStage.tryFromString(previousGameStage);
    for (final event in repository.listByConversation(conversationId)) {
      if (event.kind != AnalysisHistoryKind.analyze ||
          event.enthusiasmScore != previousEnthusiasmScore ||
          GameStage.tryFromString(event.gameStageLabel) != previousStage) {
        continue;
      }
      return event;
    }
    return null;
  }

  String _stableHistoryEventId({
    required String revision,
    required int messageCount,
  }) {
    final digest = sha256.convert(
      utf8.encode(
          'analysis-history-v1|$conversationId|$revision|$messageCount'),
    );
    return 'analysis-${digest.toString().substring(0, 32)}';
  }

  bool _sameCapturedPartner(
    Conversation conversation, {
    required String? analyzedPartnerId,
    required bool? analyzedIsReconnect,
  }) {
    // Old in-memory/test run metadata has no marker and keeps the historical
    // revision-only behavior. Every new run sends a non-null reconnect bool,
    // including false, so an explicitly captured orphan scope is distinguishable
    // from legacy missing metadata.
    if (analyzedIsReconnect == null) return true;
    return AnalysisHistoryEvent.normalizeScope(conversation.partnerId) ==
        AnalysisHistoryEvent.normalizeScope(analyzedPartnerId);
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
    String? analyzedPartnerId,
    bool? analyzedIsReconnect,
    bool allowArchivedRecordRefresh = false,
  }) {
    return _trackTask(
      _runPersistLatestAnalysisSnapshot(
        result,
        completionKey: completionKey,
        previousAnalyzedCount: previousAnalyzedCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedContentRevision,
        analyzedPartnerId: analyzedPartnerId,
        analyzedIsReconnect: analyzedIsReconnect,
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
    String? analyzedPartnerId,
    bool? analyzedIsReconnect,
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
        analyzedPartnerId: analyzedPartnerId,
        analyzedIsReconnect: analyzedIsReconnect,
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
    String? analyzedPartnerId,
    bool? analyzedIsReconnect,
    bool allowArchivedRecordRefresh = false,
  }) async {
    final conv = _getConversation(conversationId);
    if (conv == null) {
      return;
    }
    if (analyzedContentRevision == null ||
        !_sameCapturedPartner(
          conv,
          analyzedPartnerId: analyzedPartnerId,
          analyzedIsReconnect: analyzedIsReconnect,
        ) ||
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
    final targetPrefixRevision = conversationContentRevision(
      conv,
      messageCount: targetAnalyzedMessageCount,
    );
    // 閉環驗收 16：同一 content revision 的重試／重新整理只更新同一次
    // 分析，不新增趨勢事件。以「覆蓋前的 durable snapshot 是否已內嵌同
    // prefix revision＋訊息數」判定；legacy 無 meta 一律當新分析。
    final sameRevisionRerun = _snapshotCoversRevision(
      previousAnalysis.snapshotJson,
      revision: targetPrefixRevision,
      messageCount: targetAnalyzedMessageCount,
    );
    // 新 snapshot 先綁定唯一 history event id，再依相同 id 做 best-effort
    // put。即使第一次事件寫入失敗，重跑也只會補回這次。舊版 snapshot
    // 只有 revision/count 時，先以覆蓋前的 score＋stage 找到它對應的最新
    // event；找不到才用 revision 衍生的穩定 id，避免每次重跑長新趨勢點。
    final previousHistoryEventId = sameRevisionRerun
        ? _snapshotHistoryEventId(previousAnalysis.snapshotJson)
        : null;
    AnalysisHistoryEvent? legacyRerunEvent;
    if (sameRevisionRerun && previousHistoryEventId == null) {
      try {
        legacyRerunEvent = _findLegacyRerunEvent(
          _historyRepository(),
          previousEnthusiasmScore: previousAnalysis.enthusiasmScore,
          previousGameStage: previousAnalysis.gameStage,
        );
      } catch (_) {
        // History is best-effort. Canonical snapshot persistence must remain
        // usable even if the local history box is temporarily unavailable.
      }
    }
    final historyEventId = previousHistoryEventId ??
        legacyRerunEvent?.id ??
        (sameRevisionRerun
            ? _stableHistoryEventId(
                revision: targetPrefixRevision,
                messageCount: targetAnalyzedMessageCount,
              )
            : const Uuid().v4());
    final frozenReconnectContext = analyzedIsReconnect ??
        _snapshotIsReconnect(previousAnalysis.snapshotJson) ??
        (conv.sessionContext?.meetingContext ==
            MeetingContext.committedPartner);
    final targetSnapshotJson = _encodeAnalysisSnapshot(
      result.rawResponse,
      contentRevision: targetPrefixRevision,
      messageCount: targetAnalyzedMessageCount,
      historyEventId: historyEventId,
      isReconnect: frozenReconnectContext,
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
    // 對象卡互動階段閉環規則 9：缺少或非法 stage 不得寫入新 stage
    // snapshot，保留上一個有效階段；從未有有效階段則維持 null（問號）。
    if (result.gameStage.hasValidStage) {
      conv.currentGameStage = result.gameStage.current.name;
    }
    conv.lastAnalysisSnapshotJson = targetSnapshotJson;

    await _persistAnalysisCompleted(
      conv,
      expectedContentRevision: analyzedContentRevision,
    );

    if (conversationContentRevision(conv) != analyzedContentRevision ||
        !_sameCapturedPartner(
          conv,
          analyzedPartnerId: analyzedPartnerId,
          analyzedIsReconnect: analyzedIsReconnect,
        )) {
      // Content or partner scope changed while the snapshot write was in
      // flight. Roll back this
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
          await _persistContentChanged(conv);
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
      analyzedIsReconnect: frozenReconnectContext,
      allowArchivedRefresh: allowArchivedRecordRefresh,
    );
    _setAnalysisRecordNeedsRepair(!recordSaved);

    // 案2：analyze 歷史事件（best-effort：失敗只 debugPrint，絕不 rethrow，
    // 分析呈現完全不受影響）。同 content revision 重跑時必須「更新同一
    // 事件」而不只是略過 append；否則作戰板仍會讀到重跑前的舊 stage。
    // repository 以相同 id put 覆寫，createdAt 保留原值，所以趨勢筆數與
    // 時間點都不會漂移。非法 stage 也保留該事件原本的有效 stage。
    try {
      final historyRepository = _historyRepository();
      AnalysisHistoryEvent? rerunEvent = legacyRerunEvent;
      if (sameRevisionRerun) {
        for (final event
            in historyRepository.listByConversation(conversationId)) {
          if (event.kind == AnalysisHistoryKind.analyze &&
              event.id == historyEventId) {
            rerunEvent = event;
            break;
          }
        }
      }
      final eventStageLabel = result.gameStage.hasValidStage
          ? result.gameStage.current.name
          : rerunEvent?.gameStageLabel;
      final eventIsReconnect = result.gameStage.hasValidStage
          ? result.gameStage.current == GameStage.opening &&
              frozenReconnectContext
          : rerunEvent?.isReconnect;
      await historyRepository.append(
        AnalysisHistoryEvent.analyze(
          id: historyEventId,
          createdAt: rerunEvent?.createdAt ?? DateTime.now(),
          conversationId: conversationId,
          partnerId: conv.partnerId,
          subjectName: conv.name,
          enthusiasmScore: result.enthusiasmScore,
          gameStageLabel: eventStageLabel,
          isReconnect: eventStageLabel == null ? null : eventIsReconnect,
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
        final archived = await _recordPort.archiveCurrentRecord(
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
        analyzedIsReconnect:
            _snapshotIsReconnect(conversation.lastAnalysisSnapshotJson),
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
    bool? analyzedIsReconnect,
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
    try {
      final saveResult = await _recordPort.saveSuccessfulAnalysis(
        ownerUserId: ownerUserId,
        conversation: conversation,
        completionKey: stableCompletionKey,
        runStartPreviousCount: runStartPreviousCount,
        analyzedMessageCount: analyzedMessageCount,
        analyzedContentRevision: analyzedPrefixRevision,
        analysisSnapshotJson: snapshotJson,
        enthusiasmScore: result.enthusiasmScore,
        // Missing/unknown model output must not leak the display fallback
        // opening into durable records. Reuse only the conversation's latest
        // strictly valid stage; otherwise persist a blank label.
        gameStageLabel: result.gameStage.hasValidStage
            ? _visibleRecordStageLabel(
                conversation,
                result.gameStage.current,
                isReconnectOverride: analyzedIsReconnect,
              )
            : _visibleStoredRecordStageLabel(
                conversation,
                isReconnectOverride: analyzedIsReconnect,
              ),
        allowArchivedRefresh: allowArchivedRefresh,
        sourcePlatform: _recordPort.conversationSource(
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
      final archived = await _recordPort.archiveCurrentRecord(
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

  String _visibleRecordStageLabel(Conversation conversation, GameStage stage,
      {bool? isReconnectOverride}) {
    if (stage == GameStage.opening &&
        (isReconnectOverride ??
            conversation.sessionContext?.meetingContext ==
                MeetingContext.committedPartner)) {
      return '重新連線';
    }
    return stage.label;
  }

  String _visibleStoredRecordStageLabel(
    Conversation conversation, {
    bool? isReconnectOverride,
  }) {
    final stage = GameStage.tryFromString(conversation.currentGameStage);
    if (stage == null) return '';
    return _visibleRecordStageLabel(
      conversation,
      stage,
      isReconnectOverride: isReconnectOverride,
    );
  }

  AnalysisRecord? currentRecordFor(Conversation conversation) {
    final ownerUserId = recordOwnerFor(conversation);
    if (ownerUserId == null) return null;
    return _recordPort.currentFor(
      ownerUserId: ownerUserId,
      conversationId: conversation.id,
    );
  }
}
