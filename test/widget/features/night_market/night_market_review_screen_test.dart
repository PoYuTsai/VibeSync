import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_theme.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_review_screen.dart';
import 'package:vibesync/shared/widgets/reveal_pill.dart';

Future<void> _show(WidgetTester tester, {double scale = 1}) async {
  await tester.binding.setSurfaceSize(Size(scale == 1 ? 390 : 320, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: NightMarketReviewScreen(
      scenario: buildNightMarketScenario(),
      onRestart: () {},
      onExit: () {},
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all 27 entries are reachable through the existing disclosure',
      (tester) async {
    await _show(tester);
    expect(find.text('廢物測試'), findsNothing);
    final pill = find.ancestor(
        of: find.text('所有知識點（27）'), matching: find.byType(RevealPill));
    expect(pill, findsOneWidget);
    await _tap(tester, find.text('所有知識點（27）'));
    for (final item in buildNightMarketScenario().review) {
      expect(find.text(item.term), findsWidgets, reason: item.id);
    }
    await _tap(tester, find.text('廢物測試'));
    expect(find.text('知識詳解'), findsOneWidget);
    expect(find.text('延伸情境 · 本次主線未明確示範'), findsOneWidget);
    await _tap(tester, find.text('下一步怎麼做'));
    expect(
        find.text(buildNightMarketScenario().reviewById('shit_test').practice),
        findsOneWidget);
    expect(find.text('課程來源'), findsNothing);
    expect(find.textContaining('Chris'), findsNothing);
    expect(find.textContaining('解惑篇'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'centered pill reveals left-aligned text and back keeps reading position',
      (tester) async {
    await _show(tester);
    await _tap(tester, find.text('接住感受，建立信任'));
    await _tap(tester, find.text('看完整解析'));
    final scenario = buildNightMarketScenario();
    for (final explanation in scenario.reviewChapters[1].explanations) {
      expect(find.text(explanation.detail), findsOneWidget);
    }
    expect(find.text(scenario.reviewById('empathy_background').plain),
        findsNothing);
    await tester.ensureVisible(find.text('同理心陳述＋背景介紹'));
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    await _tap(tester, find.text('同理心陳述＋背景介紹'));
    final button = find.ancestor(
        of: find.text('下一步怎麼做'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton));
    expect(tester.getCenter(button).dx, closeTo(195, 1));
    await _tap(tester, find.text('下一步怎麼做'));
    final practice =
        buildNightMarketScenario().reviewById('empathy_background').practice;
    final text = tester.widget<Text>(find.text(practice));
    expect(text.textAlign, TextAlign.start);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('片段解析 2／6'), findsOneWidget);
    expect(find.text('看完整解析'), findsNothing);
    expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'related chapters and next chapter return directly to the overview',
      (tester) async {
    await _show(tester);
    await _tap(tester, find.text('掌控感／控制力'));
    await _tap(tester, find.text('有根據地欣賞，適時退開'));
    expect(find.text('片段解析 5／6'), findsOneWidget);
    await _tap(tester, find.text('下一段解析'));
    expect(find.text('片段解析 6／6'), findsOneWidget);
    await _tap(tester, find.text('回復盤總覽'));
    expect(find.text('把這段互動看懂'), findsOneWidget);
    expect(find.text('知識詳解'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen with large text can expand and read detailed copy',
      (tester) async {
    await _show(tester, scale: 2);
    await _tap(tester, find.text('接住感受，建立信任'));
    await _tap(tester, find.text('看完整解析'));
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('同理心陳述＋背景介紹'));
    await _tap(tester, find.text('下一步怎麼做'));
    await tester.ensureVisible(find.text(
        buildNightMarketScenario().reviewById('empathy_background').practice));
    expect(tester.takeException(), isNull);
  });
}
