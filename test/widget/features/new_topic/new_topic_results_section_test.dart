// 新話題結果區排序與公式可見性（2026-07-24 公式回覆計畫 §12）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_view.dart';
import 'package:vibesync/shared/widgets/formula_reply_section.dart';

Map<String, dynamic> _topic(int n) => {
      'id': 'nt_$n',
      'direction': '方向$n',
      'openingLine': '開場句$n',
      'whyItWorks': '因為$n',
      'nextMove': '下一步$n',
    };

Map<String, dynamic> _formulaItem(int n) => {
      'openingLine': '公式新話題$n：抓她一個具體線索加一點我的反應。',
      'whyItWorks': '因為她只要補一個細節就能回（$n）。',
    };

NewTopicResult _result({
  required bool free,
  required int formulaCount,
}) {
  final body = {
    'topics': free ? [_topic(1)] : [for (var n = 1; n <= 5; n++) _topic(n)],
    'recommendation': {'topicId': 'nt_1', 'reason': '最貼近近況'},
    'access': {
      'servedTier': free ? 'free' : 'essential',
      'limited': free,
      'totalCount': 5,
      'unlockedCount': free ? 1 : 5,
      'lockedCount': free ? 4 : 0,
    },
    'usage': {'cost': 3},
    'formulaTopics': [for (var n = 1; n <= formulaCount; n++) _formulaItem(n)],
  };
  final parsed = NewTopicResult.tryParse(
    body,
    requestId: '123e4567-e89b-42d3-a456-426614174000',
  );
  expect(parsed, isNotNull);
  return parsed!;
}

Future<void> _pump(
  WidgetTester t,
  NewTopicResult result, {
  ValueChanged<FormulaReplyEntry>? onCopyFormula,
}) async {
  await t.binding.setSurfaceSize(const Size(400, 4000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NewTopicResultsSection(
            result: result,
            onCopyIdeaOpeningLine: (_) {},
            onCopyFormulaOpeningLine: onCopyFormula ?? (_) {},
            onUpgrade: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Free：公式區在原 topics 之後、升級 CTA 之前（公式不像被鎖）', (t) async {
    await _pump(t, _result(free: true, formulaCount: 2));

    expect(find.text('公式新話題'), findsOneWidget);
    expect(find.text(NewTopicView.freeUpsellHeadline), findsOneWidget);

    final topicDy = t.getTopLeft(find.text('開場句1')).dy;
    final formulaDy = t.getTopLeft(find.text('公式新話題')).dy;
    final upsellDy =
        t.getTopLeft(find.text(NewTopicView.freeUpsellHeadline)).dy;
    expect(topicDy < formulaDy, isTrue, reason: '原 topics 先顯示');
    expect(formulaDy < upsellDy, isTrue, reason: 'Free upsell 必須在公式之後');

    // 原 Free 1 題不因公式改變；公式兩則全渲染。
    expect(find.text('開場句1'), findsOneWidget);
    expect(find.text('開場句2'), findsNothing);
    expect(find.text('為什麼好接'), findsNWidgets(2));
  });

  testWidgets('Paid：五題全在、公式在最後、無升級 CTA', (t) async {
    await _pump(t, _result(free: false, formulaCount: 2));
    for (var n = 1; n <= 5; n++) {
      expect(find.text('開場句$n'), findsOneWidget);
    }
    expect(find.text('公式新話題'), findsOneWidget);
    expect(find.text(NewTopicView.freeUpsellHeadline), findsNothing);
    final lastTopicDy = t.getTopLeft(find.text('開場句5')).dy;
    final formulaDy = t.getTopLeft(find.text('公式新話題')).dy;
    expect(lastTopicDy < formulaDy, isTrue);
  });

  testWidgets('公式 0 則整區不渲染；1 則只渲染一張', (t) async {
    await _pump(t, _result(free: true, formulaCount: 0));
    expect(find.text('公式新話題'), findsNothing);
    expect(
      find.text(NewTopicView.freeUpsellHeadline),
      findsOneWidget,
      reason: '公式缺席不影響原 upsell',
    );

    await _pump(t, _result(free: true, formulaCount: 1));
    expect(find.text('公式新話題'), findsOneWidget);
    expect(find.text('為什麼好接'), findsNWidgets(1));
  });

  testWidgets('公式複製回呼只帶 openingLine；窄螢幕（320）不 overflow', (t) async {
    final copied = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await t.binding.setSurfaceSize(const Size(320, 4000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NewTopicResultsSection(
              result: _result(free: false, formulaCount: 2),
              onCopyIdeaOpeningLine: (_) {},
              onCopyFormulaOpeningLine: (entry) =>
                  Clipboard.setData(ClipboardData(text: entry.openingLine)),
              onUpgrade: () {},
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull, reason: '窄螢幕不得 overflow');

    // 公式卡的複製鍵在 FormulaReplySection 內（topics 卡也有複製鍵，
    // 用 descendant 限定範圍）。
    final formulaCopy = find.descendant(
      of: find.byType(FormulaReplySection),
      matching: find.text('複製'),
    );
    expect(formulaCopy, findsNWidgets(2));
    await t.tap(formulaCopy.first, warnIfMissed: false);
    await t.pump();
    expect(copied, [(_formulaItem(1)['openingLine'])]);
    expect(
      copied.single.contains(_formulaItem(1)['whyItWorks'] as String),
      isFalse,
      reason: '複製只複製 openingLine',
    );
  });
}
