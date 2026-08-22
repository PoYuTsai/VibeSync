/// 一次主分析 run 的最小 metadata（application-owned、immutable）。
///
/// 這是 session controller 對外的唯一 run 識別視角：只有 staleness／
/// 持久化決策真正需要的欄位。reactive 串流狀態（phase、retry／
/// error／quota、stream contents、wire schema）屬 data notifier 與
/// presentation，application 不得知道；presentation 在呼叫點自行由
/// reactive state 映射成本型別。
library;

import '../../conversation/domain/entities/session_context.dart';

class AnalysisRunMetadata {
  /// server 端 run 識別；resume 同一 run 不重扣額度的鍵。
  final String? runId;

  /// run 起點的已分析訊息數（分析紀錄 segment 起點）。
  final int? previousAnalyzedCount;

  /// run 起點的對話總訊息數（無修訂之舊 state 的 staleness 後備比對）。
  final int? conversationMessageCount;

  /// run 起點同步擷取的內容修訂（同數量編輯的 staleness／持久化守門）。
  final String? contentRevision;

  /// run 起點的對象 scope；新 run 一律帶值（孤兒對話為 null）。
  final String? conversationPartnerId;

  /// run 起點送出的情境是否為既有伴侶，供 history/record 凍結顯示語意。
  final bool? isReconnectContext;

  /// run 起點實際送出的完整情境。只在結果通過 content/partner gate 後
  /// 才持久化，避免分析途中改派對象時把舊對象情境寫進新對象。
  final SessionContext? analyzedSessionContext;

  const AnalysisRunMetadata({
    this.runId,
    this.previousAnalyzedCount,
    this.conversationMessageCount,
    this.contentRevision,
    this.conversationPartnerId,
    this.isReconnectContext,
    this.analyzedSessionContext,
  });
}
