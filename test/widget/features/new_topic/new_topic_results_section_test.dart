// 新話題結果區排序（2026-08-19：公式區已下架）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_view.dart';

Map<String, dynamic> _topic(int n) => {
      'id': 'nt_$n',
      'direction': '方向$n',
      'openingLine': '開場句$n',
      'whyItWorks': '因為$n',
      'nextMove': '下一步$n',
    };


Future<void> _pump(
  WidgetTester t,
  NewTopicResult result,
) async {
  await t.binding.setSurfaceSize(const Size(400, 4000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NewTopicResultsSection(
            result: result,
            onCopyIdeaOpeningLine: (_) {},
            onUpgrade: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('v2：AI 推薦題（nt_3）排第一，其餘維持原序', (t) async {
    final parsed = NewTopicResult.tryParse(
      {
        'topics': [for (var n = 1; n <= 5; n++) _topic(n)],
        'recommendation': {'topicId': 'nt_3', 'reason': '最貼近近況'},
        'access': {
          'servedTier': 'essential',
          'limited': false,
          'totalCount': 5,
          'unlockedCount': 5,
          'lockedCount': 0,
        },
        'usage': {'cost': 3},
      },
      requestId: '123e4567-e89b-42d3-a456-426614174000',
    );
    expect(parsed, isNotNull);
    await _pump(t, parsed!);
    await t.pumpAndSettle();

    final dys = {
      for (var n = 1; n <= 5; n++) n: t.getTopLeft(find.text('開場句$n')).dy,
    };
    expect(dys[3]! < dys[1]!, isTrue, reason: '推薦題必須排第一');
    expect(dys[1]! < dys[2]!, isTrue);
    expect(dys[2]! < dys[4]!, isTrue);
    expect(dys[4]! < dys[5]!, isTrue, reason: '其餘維持原序');
  });
}
