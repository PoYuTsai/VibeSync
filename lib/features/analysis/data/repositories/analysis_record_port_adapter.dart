/// data 端 adapter：以既有 AnalysisRecordStore 實作 application 的
/// AnalysisRecordPort。store 以 accessor 注入、每次呼叫解析，維持與
/// 原 per-call `ref.read` 相同的新鮮度。
library;

import '../../../conversation/domain/entities/conversation.dart';
import '../../application/ports/analysis_record_port.dart';
import '../../domain/entities/analysis_record.dart';
import 'analysis_record_store.dart';

class AnalysisRecordPortAdapter implements AnalysisRecordPort {
  AnalysisRecordPortAdapter({required AnalysisRecordStore Function() store})
      : _store = store;

  final AnalysisRecordStore Function() _store;

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      _store().currentFor(
        ownerUserId: ownerUserId,
        conversationId: conversationId,
      );

  @override
  Future<AnalysisRecordSaveOutcome> saveSuccessfulAnalysis({
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
  }) async {
    final result = await _store().saveSuccessfulAnalysis(
      ownerUserId: ownerUserId,
      conversation: conversation,
      completionKey: completionKey,
      runStartPreviousCount: runStartPreviousCount,
      analyzedMessageCount: analyzedMessageCount,
      analyzedContentRevision: analyzedContentRevision,
      analysisSnapshotJson: analysisSnapshotJson,
      enthusiasmScore: enthusiasmScore,
      gameStageLabel: gameStageLabel,
      allowArchivedRefresh: allowArchivedRefresh,
      sourcePlatform: sourcePlatform,
    );
    return AnalysisRecordSaveOutcome(
      accepted: result.accepted,
      rejectionReason: result.rejectionReason,
    );
  }

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) =>
      _store().archiveCurrentRecord(
        ownerUserId: ownerUserId,
        conversationId: conversationId,
      );

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) =>
      _store().conversationSource(
        ownerUserId: ownerUserId,
        conversationId: conversationId,
      );
}
