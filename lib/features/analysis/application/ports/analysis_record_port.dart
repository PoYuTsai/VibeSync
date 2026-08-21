/// 分析紀錄存放層的窄 port：持久化協調器只需要這四個操作。
/// data 層 AnalysisRecordStore 在 composition root 以 adapter 實作，
/// 並維持 per-call 解析的新鮮度。
library;

import '../../../conversation/domain/entities/conversation.dart';
import '../../domain/entities/analysis_record.dart';

class AnalysisRecordSaveOutcome {
  final bool accepted;
  final String? rejectionReason;

  const AnalysisRecordSaveOutcome({
    required this.accepted,
    this.rejectionReason,
  });
}

abstract class AnalysisRecordPort {
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  });

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
  });

  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  });

  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  });
}
