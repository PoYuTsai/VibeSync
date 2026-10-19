import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/domain/services/latest_analyzed_fragment.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

Conversation _fragment(String id, DateTime updatedAt, {String? snapshot}) =>
    Conversation(
      id: id,
      name: '小雲',
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
      partnerId: 'p-1',
      lastAnalysisSnapshotJson: snapshot,
    );

final _v2 = jsonEncode({
  'enthusiasm': {'score': 61},
  'gameStage': {'current': 'premise', 'status': 'normal', 'nextStep': '繼續'},
});

String _v3({
  String decision = 'hold',
  String light = 'yellow',
  Map<String, dynamic>? relation,
}) =>
    jsonEncode({
      'guideVersion': 'v3.6',
      'read': {
        'guideVersion': 'v3.6',
        'decision': decision,
        'light': light,
        'judgment': '球在她那邊。',
        if (relation != null) 'relation': relation,
        'plannedCards': const [],
      },
      'cards': const [],
    });

const _dims = {
  'heat': 72,
  'engagement': 70,
  'topicDepth': 45,
  'replyWillingness': 78,
  'emotionalConnection': 60,
};

void main() {
  test('取最近分析過的那段：還沒分析的新片段不算，照上一次的分析', () {
    final latest = LatestAnalyzedFragment.of([
      _fragment('old-v2', DateTime(2026, 10, 1), snapshot: _v2),
      _fragment('v3', DateTime(2026, 10, 18), snapshot: _v3()),
      _fragment('blank', DateTime(2026, 10, 19)),
    ])!;

    expect(latest.conversation.id, 'v3');
    expect(latest.isGuideV3, isTrue);
    expect(latest.guideV3Read!.decision, GuideV3Decision.hold);
    expect(latest.guideV3Result!.read.light, GuideV3Light.yellow);
  });

  test('最近分析的是 v2 就不是 v3，更早的 v3 不算數', () {
    final latest = LatestAnalyzedFragment.of([
      _fragment('v3', DateTime(2026, 10, 18), snapshot: _v3()),
      _fragment('v2', DateTime(2026, 10, 19), snapshot: _v2),
    ])!;

    expect(latest.conversation.id, 'v2');
    expect(latest.isGuideV3, isFalse);
    expect(latest.guideV3Read, isNull);
    expect(latest.guideV3Result, isNull);
    expect(latest.payload['enthusiasm'], {'score': 61});
  });

  test('不靠傳進來的順序：照 updatedAt 新到舊', () {
    final latest = LatestAnalyzedFragment.of([
      _fragment('v3-new', DateTime(2026, 10, 19), snapshot: _v3()),
      _fragment('v2-old', DateTime(2026, 10, 1), snapshot: _v2),
    ])!;
    expect(latest.conversation.id, 'v3-new');
  });

  test('壞掉的快照跳過；都沒分析過回 null', () {
    final latest = LatestAnalyzedFragment.of([
      _fragment('v2', DateTime(2026, 10, 1), snapshot: _v2),
      _fragment('broken', DateTime(2026, 10, 18), snapshot: '{not json'),
      _fragment('array', DateTime(2026, 10, 19), snapshot: '[]'),
    ])!;
    expect(latest.conversation.id, 'v2');

    expect(
      LatestAnalyzedFragment.of([
        _fragment('blank', DateTime(2026, 10, 19)),
        _fragment('spaces', DateTime(2026, 10, 18), snapshot: '  '),
      ]),
      isNull,
    );
    expect(LatestAnalyzedFragment.of(const []), isNull);
  });

  group('關係狀態（Bruce 2026-10-19 路線二）：v3 帶了就跟 v2 一樣顯示', () {
    LatestAnalyzedFragment latest(String snapshot) => LatestAnalyzedFragment.of(
          [_fragment('c', DateTime(2026, 10, 19), snapshot: snapshot)],
        )!;

    test('v3 帶了熱度與雷達：不收起，雷達讀關係狀態的', () {
      final v3 = latest(_v3(
        relation: const {'stage': 'premise', 'heat': 72, 'dimensions': _dims},
      ));
      expect(v3.lacksHeat, isFalse);
      expect(v3.lacksRadar, isFalse);
      expect(v3.dimensionScores, _dims);
      expect(v3.relation!.visibleHeat, 65);
    });

    test('改版前的 v3（沒帶）：熱度、雷達都收起', () {
      final v3 = latest(_v3());
      expect(v3.lacksHeat, isTrue);
      expect(v3.lacksRadar, isTrue);
      expect(v3.dimensionScores, isNull);
    });

    test('只帶了一部分：各自看', () {
      final v3 = latest(_v3(relation: const {'stage': 'close', 'heat': 50}));
      expect(v3.lacksHeat, isFalse);
      expect(v3.lacksRadar, isTrue);
    });

    test('v2 照舊：不收起，雷達照 AnalysisResult 的解析', () {
      final withRadar = latest(jsonEncode({
        'enthusiasm': {'score': 61},
        'dimensions': {'heat': 70, 'engagement': 65},
      }));
      expect(withRadar.lacksHeat, isFalse);
      expect(withRadar.lacksRadar, isFalse);
      // 缺的鍵照舊補 50（跟原本雷達卡一樣）。
      expect(withRadar.dimensionScores, {
        'heat': 70,
        'engagement': 65,
        'topicDepth': 50,
        'replyWillingness': 50,
        'emotionalConnection': 50,
      });
      expect(latest(_v2).dimensionScores, isNull);
    });
  });

  test('v3 形狀但判讀讀不懂：還是 v3，只是沒有判讀', () {
    final latest = LatestAnalyzedFragment.of([
      _fragment('odd', DateTime(2026, 10, 19),
          snapshot: _v3(decision: 'maybe')),
    ])!;
    expect(latest.isGuideV3, isTrue);
    expect(latest.guideV3Read, isNull);
    expect(latest.guideV3Result, isNull);
  });
}
