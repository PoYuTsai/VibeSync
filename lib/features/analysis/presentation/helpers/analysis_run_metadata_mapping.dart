/// presentation 端的 reactive state → 最小 run metadata 映射。
///
/// application 的 session controller 只認 [AnalysisRunMetadata]；完整
/// [StreamingAnalysisState]（phase／retry／error／quota／stream contents）
/// 停留在 presentation 與 data notifier。
library;

import '../../application/analysis_run_metadata.dart';
import '../../data/notifiers/streaming_analyze_notifier.dart';

extension StreamingAnalysisStateRunMetadata on StreamingAnalysisState {
  AnalysisRunMetadata toRunMetadata() => AnalysisRunMetadata(
        runId: analysisRunId,
        previousAnalyzedCount: previousAnalyzedCount,
        conversationMessageCount: conversationMessageCount,
        contentRevision: conversationContentRevision,
        conversationPartnerId: conversationPartnerId,
        isReconnectContext: isReconnectContext,
      );
}
