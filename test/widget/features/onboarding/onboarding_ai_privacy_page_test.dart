// test/widget/features/onboarding/onboarding_ai_privacy_page_test.dart
//
// R1-4 App Review 保險：onboarding 最後一頁必須是輕量「AI 與隱私」揭露，
// 點名第三方 AI 服務（Anthropic Claude／練習室 DeepSeek）與資料外送路徑，
// 並說明 per-feature 同意閘才是實際同意點。此頁是靜態揭露非同意，
// 「略過」行為不受影響。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';

Future<void> _swipeToNextPage(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-400, 0));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pumpAndSettle();
  }

  group('onboarding AI 與隱私揭露頁（R1-4）', () {
    testWidgets('最後一頁是 AI 與隱私揭露，點名 Anthropic 與 DeepSeek',
        (tester) async {
      await pumpOnboarding(tester);

      // 前三頁維持原樣，第一頁開場不變。
      expect(find.text('不知道怎麼回她？'), findsOneWidget);

      await _swipeToNextPage(tester); // → 2
      await _swipeToNextPage(tester); // → 3
      await _swipeToNextPage(tester); // → 4（揭露頁）

      expect(find.text('AI 與你的隱私'), findsOneWidget);
      expect(find.textContaining('Anthropic'), findsOneWidget);
      expect(find.textContaining('DeepSeek'), findsOneWidget);
      // 揭露必須交代同意閘：首次使用各 AI 功能前會再徵求同意。
      expect(find.textContaining('同意'), findsWidgets);
    });

    testWidgets('揭露頁是最終頁：CTA 顯示「開始使用」，前一頁仍是「下一步」',
        (tester) async {
      await pumpOnboarding(tester);

      await _swipeToNextPage(tester); // → 2
      await _swipeToNextPage(tester); // → 3（原最終頁，現在不是了）
      expect(find.text('下一步'), findsOneWidget);
      expect(find.text('開始使用'), findsNothing);

      await _swipeToNextPage(tester); // → 4（揭露頁＝最終頁）
      expect(find.text('開始使用'), findsOneWidget);
      expect(find.text('下一步'), findsNothing);
    });
  });
}
