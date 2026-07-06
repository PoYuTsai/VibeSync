// test/widget/features/onboarding/onboarding_ai_privacy_page_test.dart
//
// R1-4 App Review 保險：onboarding 最後一頁必須是輕量「AI 與隱私」揭露，
// 交代資料外送至第三方 AI 與 per-feature 同意閘才是實際同意點。
// 廠商名（Anthropic Claude／練習室 DeepSeek）刻意不在 onboarding 揭露，
// 避免誤解練習室女孩＝DeepSeek；完整廠商揭露留在設定頁 AI 隱私頁。
// 此頁是靜態揭露非同意，「略過」行為不受影響。
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
    testWidgets('最後一頁是 AI 與隱私揭露：交代第三方 AI 與同意閘，但不列廠商名',
        (tester) async {
      await pumpOnboarding(tester);

      // 前三頁維持原樣，第一頁開場不變。
      expect(find.text('不知道怎麼回她？'), findsOneWidget);

      await _swipeToNextPage(tester); // → 2
      await _swipeToNextPage(tester); // → 3
      await _swipeToNextPage(tester); // → 4（揭露頁）

      expect(find.text('AI 與你的隱私'), findsOneWidget);
      // 保留第一句（送第三方 AI）與第三句（同意閘）。
      expect(find.textContaining('第三方 AI'), findsOneWidget);
      expect(find.textContaining('同意'), findsWidgets);
      // 廠商名刻意不在 onboarding 揭露（避免誤解練習室女孩＝DeepSeek）。
      expect(find.textContaining('Anthropic'), findsNothing);
      expect(find.textContaining('DeepSeek'), findsNothing);
    });

    // 案 3 冷啟動分流後，揭露頁不再是最終頁（第 5 頁是分流頁），
    // 「開始使用」CTA 已移除，前 4 頁一律顯示「下一步」。
    testWidgets('揭露頁不再是最終頁：CTA 仍是「下一步」，再滑一頁到分流頁',
        (tester) async {
      await pumpOnboarding(tester);

      await _swipeToNextPage(tester); // → 2
      await _swipeToNextPage(tester); // → 3
      expect(find.text('下一步'), findsOneWidget);
      expect(find.text('開始使用'), findsNothing);

      await _swipeToNextPage(tester); // → 4（揭露頁）
      expect(find.text('下一步'), findsOneWidget);
      expect(find.text('開始使用'), findsNothing);

      await _swipeToNextPage(tester); // → 5（分流頁）
      expect(find.text('你現在有正在聊的對象嗎？'), findsOneWidget);
      expect(find.text('下一步'), findsNothing);
    });
  });
}
