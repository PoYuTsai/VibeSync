import 'dart:convert';

import '../../../conversation/domain/entities/conversation.dart';
import '../entities/analysis_models.dart';
import '../entities/guide_v3_result.dart';

/// 一位對象「最近分析過的那段片段」：「這位對象現在是不是 v3（任務卡）」各頁都用這一條
/// 規則判斷（Bruce 2026-10-19 路線二；10/17–18 各頁各自看最新一段或任一段，會互相打架）。
///
/// 片段照 updatedAt 新到舊，第一段存了分析快照（JSON 物件）的就是；還沒分析的新片段不算，
/// 所以剛加了截圖、還沒分析時，各頁照上一次的分析顯示。壞掉的快照跳過，跟對象頁的最近
/// 洞察同一個做法。
class LatestAnalyzedFragment {
  LatestAnalyzedFragment._(this.conversation, this.payload);

  /// 都沒分析過（或快照都壞掉）回 null。
  static LatestAnalyzedFragment? of(Iterable<Conversation> conversations) {
    LatestAnalyzedFragment? latest;
    for (final conversation in conversations) {
      if (latest != null &&
          !conversation.updatedAt.isAfter(latest.conversation.updatedAt)) {
        continue;
      }
      final payload = _decodeSnapshot(conversation.lastAnalysisSnapshotJson);
      if (payload != null) {
        latest = LatestAnalyzedFragment._(conversation, payload);
      }
    }
    return latest;
  }

  /// 最近分析過的那段對話。
  final Conversation conversation;

  /// 那段存的分析快照原樣（v2 是 AnalysisResult 的 JSON，v3 是任務卡結果）。
  final Map<String, dynamic> payload;

  /// 那段的分析是 v3（任務卡）。v3 快照不能交給 AnalysisResult（它會補熱度 50）。
  late final bool isGuideV3 = isGuideV3Payload(payload);

  /// v3 的判讀；不是 v3 或判讀讀不懂是 null（卡片壞掉不影響判讀）。
  late final GuideV3Read? guideV3Read =
      isGuideV3 ? GuideV3Read.fromJson(payload['read']) : null;

  /// v3 的整份結果；不是 v3 或讀不懂是 null。
  late final GuideV3Result? guideV3Result =
      isGuideV3 ? GuideV3Result.fromJson(payload) : null;

  /// v3 的關係狀態；不是 v3、改版前的結果、開關沒開或關心都是 null。
  GuideV3Relation? get relation => guideV3Read?.relation;

  /// 最近分析過的是 v3 卻沒有熱度（改版前的結果）：熱度卡、熱度狀態、「改用新版不算分數」
  /// 的說法照 10/17–18 的做法收起來；v3 帶了熱度就跟 v2 一樣顯示（Bruce 2026-10-19 路線二）。
  bool get lacksHeat => isGuideV3 && relation?.heat == null;

  /// 同 [lacksHeat]，看的是五維雷達。
  bool get lacksRadar => isGuideV3 && relation?.dimensions == null;

  /// 那段的五維雷達：v2 照 `AnalysisResult` 的解析（跟原本一樣，缺的鍵補 50），v3 是關係
  /// 狀態的雷達；沒有就是 null。
  late final Map<String, int>? dimensionScores = _dimensionScores();

  Map<String, int>? _dimensionScores() {
    if (isGuideV3) return relation?.dimensions;
    try {
      return AnalysisResult.fromJson(payload).dimensionScores;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeSnapshot(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return null;
    }
  }
}
