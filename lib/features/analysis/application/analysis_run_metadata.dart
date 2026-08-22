/// 一次主分析 run 的最小 metadata（application-owned、immutable）。
///
/// 這是 session controller 對外的唯一 run 識別視角：只有 staleness／
/// 持久化決策真正需要的四個欄位。reactive 串流狀態（phase、retry／
/// error／quota、stream contents、wire schema）屬 data notifier 與
/// presentation，application 不得知道；presentation 在呼叫點自行由
/// reactive state 映射成本型別。
library;

class AnalysisRunMetadata {
  /// server 端 run 識別；resume 同一 run 不重扣額度的鍵。
  final String? runId;

  /// run 起點的已分析訊息數（分析紀錄 segment 起點）。
  final int? previousAnalyzedCount;

  /// run 起點的對話總訊息數（無修訂之舊 state 的 staleness 後備比對）。
  final int? conversationMessageCount;

  /// run 起點同步擷取的內容修訂（同數量編輯的 staleness／持久化守門）。
  final String? contentRevision;

  const AnalysisRunMetadata({
    this.runId,
    this.previousAnalyzedCount,
    this.conversationMessageCount,
    this.contentRevision,
  });
}
