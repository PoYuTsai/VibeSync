// test/widget/features/onboarding/demo_preview_test.dart
//
// 轉化診斷 Tier 1-1：DemoConversation 示範卡接進 onboarding。
// 第 2 頁＝訊號示範（對話泡泡＋燈號＋局面判讀）、第 3 頁＝任務卡示範
//（對話分析 v3，Eric 2026-10-17：沒有熱度、階段、雷達，也不再是五種風格）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/data/demo_conversation.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/demo_analysis_preview.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('DemoSignalPreview 顯示三則對話、燈號與局面判讀，不顯示投入度分數', (tester) async {
    await tester.pumpWidget(_wrap(const DemoSignalPreview()));

    for (final msg in DemoConversation.messages) {
      expect(find.text(msg.content), findsOneWidget);
    }
    expect(find.text('綠燈'), findsOneWidget);
    expect(find.text('局面判讀'), findsOneWidget);
    expect(find.text(DemoConversation.demoJudgment), findsOneWidget);
    expect(find.text('示範'), findsOneWidget);
    expect(find.text('投入度'), findsNothing);
    expect(find.text('72'), findsNothing);
  });

  testWidgets('DemoCardsPreview 顯示三張任務卡，沒有五種風格與推薦標記', (tester) async {
    await tester.pumpWidget(_wrap(const DemoCardsPreview()));

    for (final card in DemoConversation.demoCards) {
      expect(find.text(card.task.label), findsOneWidget);
      expect(find.text(card.text), findsOneWidget);
    }
    for (final label in ['延展', '調情', '幽默', '冷讀']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('教練推薦'), findsNothing);
    expect(find.text('示範'), findsOneWidget);
  });

  testWidgets('OnboardingScreen 第 2、3 頁掛上示範卡', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: OnboardingScreen()),
    ));

    // 第 1 頁沒有示範卡。
    expect(find.byType(DemoSignalPreview), findsNothing);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoSignalPreview), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoCardsPreview), findsOneWidget);
  });
}
