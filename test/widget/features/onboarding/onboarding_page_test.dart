// test/widget/features/onboarding/onboarding_page_test.dart
//
// Onboarding 視覺升級（2026-08-01 轉化診斷 Tier 1）：
// - heroImageAsset 有值 → 渲染 Sydney 品牌圖取代罐頭 icon 圓盤
// - customContent 有值 → hero 整塊讓位給示範卡
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_page.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('無 heroImageAsset 時維持原本 icon 圓盤', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingPage(
      title: '不知道怎麼回她？',
      description: 'desc',
      imagePath: 'welcome',
    )));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-hero-image')), findsNothing);
  });

  testWidgets('heroImageAsset 有值時渲染品牌圖、不渲染 icon', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingPage(
      title: '不知道怎麼回她？',
      description: 'desc',
      imagePath: 'welcome',
      heroImageAsset: 'assets/images/coach/sydney_greeting.png',
    )));

    final imageFinder = find.byKey(const ValueKey('onboarding-hero-image'));
    expect(imageFinder, findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/coach/sydney_greeting.png',
    );
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('practice 頁渲染女孩照圓形拼貼＋手把 icon（2026-08-18 夥伴稿）',
      (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingPage(
      title: '還沒有對象？先練',
      description: 'desc',
      imagePath: 'practice',
    )));

    final collage = find.byKey(const ValueKey('onboarding-practice-collage'));
    expect(collage, findsOneWidget);
    expect(
      find.descendant(of: collage, matching: find.byType(Image)),
      findsNWidgets(16),
    );
    expect(
      find.descendant(
        of: collage,
        matching: find.byIcon(Icons.sports_esports_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('customContent 有值時 hero 讓位、示範內容可見', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingPage(
      title: '即時看懂她的訊號',
      description: 'desc',
      imagePath: 'analyze',
      heroImageAsset: 'assets/images/coach/sydney_thinking.png',
      customContent: Text('demo-card', key: ValueKey('demo-card')),
    )));

    expect(find.byKey(const ValueKey('demo-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-hero-image')), findsNothing);
    expect(find.byIcon(Icons.psychology_outlined), findsNothing);
  });
}
