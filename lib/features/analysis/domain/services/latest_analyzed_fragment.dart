import 'dart:convert';

import '../../../conversation/domain/entities/conversation.dart';
import '../entities/analysis_models.dart';
import '../entities/guide_v3_result.dart';

/// 一位對象「最近分析過的那段片段」：「這位對象現在是不是 v3（任務卡）」與「現在怎麼做」
/// （首頁卡狀態、對象頁、作戰板的下一步與關心、教練開場）各頁都用這一條規則判斷（Bruce
/// 2026-10-19 路線二；10/17–18 各頁各自看最新一段或任一段，會互相打架）。
///
/// 存了分析快照（JSON 物件）的片段裡，最後完成分析的那段（快照 meta 的 analyzedAt）；
/// 還沒分析的新片段不算，所以剛加了截圖、還沒分析時，各頁照上一次的分析顯示。重跑較舊的
/// 片段時，重跑那次算數（主審第 1 輪 finding 2：紀錄沿用第一次的建立時間，改名也會改
/// updatedAt）。改版前存的快照沒有這個時間，比有記的都舊（有記的一定是改版後才分析的），
/// 彼此照 updatedAt 比。壞掉的快照跳過，跟對象頁的最近洞察同一個做法。
class LatestAnalyzedFragment {
  LatestAnalyzedFragment._(
    this.conversation,
    this.payload, {
    required this.analyzedAt,
    required this.hasRecordedCompletion,
  });

  /// 都沒分析過（或快照都壞掉）回 null。
  static LatestAnalyzedFragment? of(Iterable<Conversation> conversations) {
    LatestAnalyzedFragment? latest;
    for (final conversation in conversations) {
      final payload = _decodeSnapshot(conversation.lastAnalysisSnapshotJson);
      if (payload == null) continue;
      final recorded = _recordedAnalyzedAt(payload);
      final candidate = LatestAnalyzedFragment._(
        conversation,
        payload,
        analyzedAt: recorded ?? conversation.updatedAt,
        hasRecordedCompletion: recorded != null,
      );
      if (latest == null || candidate._isLaterThan(latest)) {
        latest = candidate;
      }
    }
    return latest;
  }

  /// 最近分析過的那段對話。
  final Conversation conversation;

  /// 那段完成分析的時間；改版前存的快照沒記，是那段的 updatedAt。
  final DateTime analyzedAt;

  /// 快照有記完成分析的時間（[analyzedAt] 不是退回的 updatedAt）。
  final bool hasRecordedCompletion;

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

  bool _isLaterThan(LatestAnalyzedFragment other) {
    if (hasRecordedCompletion != other.hasRecordedCompletion) {
      return hasRecordedCompletion;
    }
    return analyzedAt.isAfter(other.analyzedAt);
  }

  static const _snapshotClientMetaKey = '__vibesync_snapshot_meta_v1';
  static const _snapshotAnalyzedAtKey = 'analyzedAt';

  static DateTime? _recordedAnalyzedAt(Map<String, dynamic> snapshot) {
    final meta = snapshot[_snapshotClientMetaKey];
    final raw = meta is Map ? meta[_snapshotAnalyzedAtKey] : null;
    return raw is String ? DateTime.tryParse(raw) : null;
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
