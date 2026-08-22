/// AnalyzeChat 主分析 session 的應用層控制器：組合唯一的
/// [StreamingAnalyzeNotifier]（reactive 進度／錯誤／runId／結果真相，
/// 這裡不鏡射任何一份）與 [AnalysisPersistenceCoordinator] 的落地結果。
/// 畫面層只負責 UI 鏡像、對話框與提示；行為逐字沿用拆分前實作。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../conversation/domain/entities/conversation.dart';
import '../../conversation/domain/services/conversation_content_revision.dart';
import '../domain/entities/analysis_models.dart';
import '../domain/entities/overcharge_confirmation.dart';
import 'analysis_persistence_coordinator.dart';
import 'analysis_run_metadata.dart';
import 'analysis_run_preparer.dart';
import 'ports/streaming_run_port.dart';

class AnalysisSessionController {
  // 訂閱同步屬 best-effort 前置：卡住不得凍結分析/刷新 spinner（2.1(b)）。
  static const _subscriptionSyncTimeout = Duration(seconds: 20);

  AnalysisSessionController({
    required this.conversationId,
    required StartAnalysisRun startRun,
    required RetryAnalysisRun retryRun,
    required Future<void> Function() ensureServerEntitlementSynced,
    required Conversation? Function() currentConversation,
    required AnalysisPersistenceCoordinator persistence,
  })  : _startRun = startRun,
        _retryRun = retryRun,
        _ensureServerEntitlementSynced = ensureServerEntitlementSynced,
        _currentConversation = currentConversation,
        _persistence = persistence;

  final String conversationId;

  /// 唯一 reactive 真相（StreamingAnalyzeNotifier）只透過這兩個 port
  /// callable 觸碰；composition root 逐次解析 autoDispose family。
  final StartAnalysisRun _startRun;
  final RetryAnalysisRun _retryRun;
  final Future<void> Function() _ensureServerEntitlementSynced;
  final Conversation? Function() _currentConversation;
  final AnalysisPersistenceCoordinator _persistence;

  /// 啟動主分析：best-effort 訂閱權益預同步（逾時放行，額度由 server 最終
  /// 把關）→ [shouldProceed] 守門（畫面傳 mounted）→ fire 唯一串流 run。
  /// notifier 快取 payload 供 retryStream，並跨畫面導航存活。
  Future<void> start({
    required Conversation conversation,
    required AnalysisRunPreparation preparation,
    OverchargeConfirmationPayload? confirmedOvercharge,
    required bool waitForCompletion,
    required bool Function() shouldProceed,
  }) async {
    try {
      await _ensureServerEntitlementSynced().timeout(_subscriptionSyncTimeout);
    } on TimeoutException catch (error) {
      // 該方法內部已 catch-all（只剩卡住這一種失敗模式）；逾時放行，
      // 額度/權益由 server 端最終把關，不得讓分析卡在「開始完整分析」。
      debugPrint('Analysis entitlement pre-sync timeout: $error');
    }
    if (!shouldProceed()) {
      return;
    }

    final analysisFuture = _startRun(
      messages: preparation.requestMessages,
      sessionContext: conversation.sessionContext,
      conversationSummary: preparation.conversationSummary,
      partnerSummary: preparation.partnerSummary,
      effectiveStyleContext: preparation.effectiveStyleContext,
      knownContactName: preparation.knownContactName,
      previousAnalyzedCount: conversation.lastAnalyzedMessageCount,
      previousAnalyzedCharCount: conversation.lastAnalyzedCharCount,
      confirmedOvercharge: confirmedOvercharge,
      conversationMessageCount: conversation.messages.length,
      analyzedMessageCount: preparation.analyzedMessageCount,
      conversationContentRevision: preparation.contentRevision,
    );
    if (waitForCompletion) {
      await analysisFuture;
    } else {
      unawaited(analysisFuture);
    }
  }

  /// 以 notifier 快取的 runId＋payload 續跑同一個串流 run（不重扣額度）。
  /// 沒有可續跑的 run 時 no-op。
  Future<void> retry() => _retryRun();

  /// 完成結果是否已對不上目前對話內容（同數量編輯靠 contentRevision 認出；
  /// 舊 run 無修訂時退回訊息數比對）。
  bool isResultStaleForCurrentConversation(AnalysisRunMetadata run) {
    final conversation = _currentConversation();
    if (conversation == null) return false;
    final expectedRevision = run.contentRevision;
    if (expectedRevision != null) {
      return conversationContentRevision(conversation) != expectedRevision;
    }
    // Backward-compatible guard for runs created before content revisions
    // were added (and for narrowly-scoped widget test seeds).
    final expectedCount = run.conversationMessageCount;
    if (expectedCount == null) return false;
    return conversation.messages.length != expectedCount;
  }

  /// live 完成轉場的持久化排程（fire-and-forget；測試環境的 Hive 失敗
  /// 不得變成 unhandled future）。
  void persistCompletedRun(
    AnalysisRunMetadata run,
    AnalysisResult result, {
    required int? analyzedMessageCount,
    required bool allowArchivedRecordRefresh,
  }) {
    _persistence
        .persistLatestSnapshot(
      result,
      completionKey: run.runId,
      previousAnalyzedCount: run.previousAnalyzedCount,
      analyzedMessageCount: analyzedMessageCount,
      analyzedContentRevision: run.contentRevision,
      allowArchivedRecordRefresh: allowArchivedRecordRefresh,
    )
        .catchError((_) {
      // Ignore errors in test environment.
    });
  }

  /// hydrate 時的補寫決策：listener 已寫過同一份 snapshot（dedup 訊號全中）
  /// 就只補紀錄修復並回 false；否則排程持久化並回 true，畫面據此更新
  /// 本地 count 鏡像與 usage 同步。
  bool persistHydratedResultIfNeeded(
    AnalysisRunMetadata run,
    AnalysisResult result, {
    required int expectedAnalyzedCount,
    required Conversation conversation,
  }) {
    final alreadyPersisted = _persistence.snapshotMatches(
      conversation: conversation,
      snapshotJson: conversation.lastAnalysisSnapshotJson,
      rawResponse: result.rawResponse,
      messageCount: expectedAnalyzedCount,
      analyzedContentRevision: run.contentRevision,
    );
    if (alreadyPersisted) {
      _persistence.scheduleRecordRepair(
        conversation: conversation,
        result: result,
        completionKey: run.runId,
        previousAnalyzedCount: run.previousAnalyzedCount,
        analyzedMessageCount: expectedAnalyzedCount,
        analyzedContentRevision: run.contentRevision,
      );
      return false;
    }

    _persistence
        .persistLatestSnapshot(
      result,
      completionKey: run.runId,
      previousAnalyzedCount: run.previousAnalyzedCount,
      analyzedMessageCount: expectedAnalyzedCount,
      analyzedContentRevision: run.contentRevision,
    )
        .catchError((_) {
      // Same fire-and-forget contract as the listener path — Hive failures in
      // tests must not surface as unhandled futures.
    });
    return true;
  }
}
