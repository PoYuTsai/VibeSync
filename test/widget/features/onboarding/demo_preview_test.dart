// test/widget/features/onboarding/demo_preview_test.dart
//
// 轉化診斷 Tier 1-1：DemoConversation 示範卡接進 onboarding。
// 第 2 頁＝訊號示範（對話泡泡＋投入度）、第 3 頁＝五種風格示範回覆。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/data/demo_conversation.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/demo_analysis_preview.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('DemoSignalPreview 顯示三則對話、投入度與心理解讀', (tester) async {
    await tester.pumpWidget(_wrap(const DemoSignalPreview()));

    for (final msg in DemoConversation.messages) {
      expect(find.text(msg.content), findsOneWidget);
    }
    expect(find.text('72'), findsOneWidget);
    expect(find.text('投入明顯'), findsOneWidget);
    expect(
      find.text(DemoConversation.demoResult.psychology.subtext),
      findsOneWidget,
    );
    expect(find.text('示範'), findsOneWidget);
  });

  testWidgets('DemoStylesPreview 顯示五種風格與推薦標記', (tester) async {
    await tester.pumpWidget(_wrap(const DemoStylesPreview()));

    for (final label in ['延展', '共鳴', '調情', '幽默', '冷讀']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final reply in DemoConversation.demoResult.replies.values) {
      expect(find.text(reply), findsOneWidget);
    }
    expect(find.text('教練推薦'), findsOneWidget);
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
    expect(find.byType(DemoStylesPreview), findsOneWidget);
  });
}
