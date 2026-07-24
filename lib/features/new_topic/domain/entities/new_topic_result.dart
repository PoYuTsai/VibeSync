/// 新話題（破冰腦力）client entities（2026-07-24 計畫 §12.2）。
///
/// Strict validation：Free 1＋4=5、Paid 5＋0=5、totalCount 恆 5、推薦指向
/// 可見 topic、ID 唯一、四欄完整。半套 response 一律解析失敗——絕不渲染
/// 殘缺結果卻已扣 3 點。`charged`/`replayed` 是 server telemetry，不進
/// client entity；fresh 與 replay 解析成同一份成功結果。
library;

import '../../../../core/utils/formula_reply_guard.dart';

/// 一則公式新話題（2026-07-24 公式回覆計畫 §9.2）：固定結構、內容動態
/// 生成，全 tier 可見、不參與五題 counts／推薦。
class NewTopicFormulaIdea {
  const NewTopicFormulaIdea({
    required this.openingLine,
    required this.whyItWorks,
  });

  final String openingLine;
  final String whyItWorks;
}

class NewTopicIdea {
  const NewTopicIdea({
    required this.id,
    required this.direction,
    required this.openingLine,
    required this.whyItWorks,
    required this.nextMove,
  });

  final String id;
  final String direction;
  final String openingLine;
  final String whyItWorks;
  final String nextMove;
}

class NewTopicRecommendation {
  const NewTopicRecommendation({required this.topicId, this.reason});

  final String topicId;
  final String? reason;
}

class NewTopicAccess {
  const NewTopicAccess({
    required this.servedTier,
    required this.limited,
    required this.totalCount,
    required this.unlockedCount,
    required this.lockedCount,
  });

  final String servedTier;
  final bool limited;
  final int totalCount;
  final int unlockedCount;
  final int lockedCount;

  bool get isFree => servedTier == 'free';
}

class NewTopicResult {
  const NewTopicResult({
    required this.topics,
    required this.recommendation,
    required this.access,
    required this.costUsed,
    required this.requestId,
    this.formulaTopics = const [],
  });

  final List<NewTopicIdea> topics;
  final NewTopicRecommendation recommendation;
  final NewTopicAccess access;
  final int costUsed;
  final String requestId;

  /// 公式新話題（0–2 則 canonical）。legacy replay row／舊 Edge 缺欄＝
  /// 空清單；公式壞掉絕不讓 tryParse 變 null（best-effort，§9.2）。
  final List<NewTopicFormulaIdea> formulaTopics;

  NewTopicIdea get recommendedTopic =>
      topics.firstWhere((topic) => topic.id == recommendation.topicId);

  static final _topicIdPattern = RegExp(r'^nt_[1-5]$');

  static const _fieldCaps = {
    'direction': 80,
    'openingLine': 180,
    'whyItWorks': 400,
    'nextMove': 300,
  };

  /// 防禦式 strict parse：形狀不合回 null（呼叫端轉友善錯誤，不得部分
  /// 渲染）。raw JSON／code fence 洩漏視同缺欄。
  static NewTopicResult? tryParse(
    dynamic body, {
    required String requestId,
  }) {
    if (body is! Map) return null;

    final access = _parseAccess(body['access']);
    if (access == null) return null;

    final rawTopics = body['topics'];
    if (rawTopics is! List) return null;
    final expectedCount = access.isFree ? 1 : 5;
    if (rawTopics.length != expectedCount) return null;

    final topics = <NewTopicIdea>[];
    final seenIds = <String>{};
    for (final rawTopic in rawTopics) {
      if (rawTopic is! Map) return null;
      final id = rawTopic['id'];
      if (id is! String || !_topicIdPattern.hasMatch(id)) return null;
      if (!seenIds.add(id)) return null;

      final direction = _visibleText(
        rawTopic['direction'],
        _fieldCaps['direction']!,
      );
      final openingLine = _visibleText(
        rawTopic['openingLine'],
        _fieldCaps['openingLine']!,
      );
      final whyItWorks = _visibleText(
        rawTopic['whyItWorks'],
        _fieldCaps['whyItWorks']!,
      );
      final nextMove = _visibleText(
        rawTopic['nextMove'],
        _fieldCaps['nextMove']!,
      );
      if (direction == null ||
          openingLine == null ||
          whyItWorks == null ||
          nextMove == null) {
        return null;
      }

      topics.add(NewTopicIdea(
        id: id,
        direction: direction,
        openingLine: openingLine,
        whyItWorks: whyItWorks,
        nextMove: nextMove,
      ));
    }

    final rawRecommendation = body['recommendation'];
    if (rawRecommendation is! Map) return null;
    final topicId = rawRecommendation['topicId'];
    if (topicId is! String || !seenIds.contains(topicId)) return null;
    String? reason;
    final rawReason = rawRecommendation['reason'];
    if (rawReason != null) {
      reason = _visibleText(rawReason, 300);
      if (reason == null) return null;
    }

    final usage = body['usage'];
    final cost = usage is Map ? (usage['cost'] as num?)?.round() ?? 3 : 3;

    // 公式 best-effort（原 result strict parse 全過之後才碰）：缺席／壞掉
    // 一律空清單，不得讓 tryParse 變 null（§9.2 解析順序）。
    final formulaTopics = List<NewTopicFormulaIdea>.unmodifiable(
      parseFormulaReplyList(body['formulaTopics']).map(
        (item) => NewTopicFormulaIdea(
          openingLine: item.openingLine,
          whyItWorks: item.whyItWorks,
        ),
      ),
    );

    return NewTopicResult(
      topics: List.unmodifiable(topics),
      recommendation: NewTopicRecommendation(topicId: topicId, reason: reason),
      access: access,
      costUsed: cost,
      requestId: requestId,
      formulaTopics: formulaTopics,
    );
  }

  static NewTopicAccess? _parseAccess(dynamic raw) {
    if (raw is! Map) return null;
    final servedTier = raw['servedTier'];
    if (servedTier != 'free' &&
        servedTier != 'starter' &&
        servedTier != 'essential') {
      return null;
    }
    final limited = raw['limited'];
    final totalCount = raw['totalCount'];
    final unlockedCount = raw['unlockedCount'];
    final lockedCount = raw['lockedCount'];
    if (limited is! bool ||
        totalCount is! num ||
        unlockedCount is! num ||
        lockedCount is! num) {
      return null;
    }
    final isFree = servedTier == 'free';
    if (totalCount.round() != 5) return null;
    if (limited != isFree) return null;
    if (unlockedCount.round() != (isFree ? 1 : 5)) return null;
    if (lockedCount.round() != (isFree ? 4 : 0)) return null;
    return NewTopicAccess(
      servedTier: servedTier as String,
      limited: limited,
      totalCount: 5,
      unlockedCount: unlockedCount.round(),
      lockedCount: lockedCount.round(),
    );
  }

  /// raw JSON／code fence 防禦（同 opener sanitizer 精神）。
  static String? _visibleText(dynamic value, int maxLen) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLen) return null;
    if (trimmed.startsWith('```') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    if (lower.contains('"topics"') || lower.contains('"openingline"')) {
      return null;
    }
    return trimmed;
  }
}
