// test/widget/features/onboarding/onboarding_finish_page_test.dart
//
// onboarding 轉換第 12 步第 4 頁：登入後先做什麼、免費額度、目標存去哪、AI 隱私。
// 這一頁取代原本獨立的隱私頁（R1-4／F5-A7 App Review 揭露）：
//   - 頁面上只有「送第三方 AI」那一句，不列廠商名（避免誤解練習室女孩＝DeepSeek）。
//   - 「看完整說明」打開的 sheet 跟設定頁「AI 與你的隱私」同一段文字，含廠商行與
//     登入前事件先存手機、登入後補送那兩句。
//   - 免費額度的數字只吃 AppConstants。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/constants/ai_privacy_disclosure.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_finish_page.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/onboarding_test_harness.dart';

Future<void> _pumpFinishPage(
  WidgetTester tester, {
  required OnboardingIntent? intent,
  bool hasGoals = false,
  Size size = const Size(390, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: OnboardingFinishPage(
            intent: intent,
            hasGoals: hasGoals,
            onOpenPrivacy: () => showOnboardingPrivacySheet(context),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

late ChatQuizCatalog _catalog;

void main() {
  setUpAll(() async {
    _catalog = await loadProductionChatQuizCatalog();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.reset();
  });

  group('依第 1 頁的路徑說下一步', () {
    for (final (intent, title, detail) in [
      (
        OnboardingIntent.analyze,
        '登入後，丟一段對話截圖',
        '先幫她建一張對象卡，建好就直接選截圖。',
      ),
      (
        OnboardingIntent.opener,
        '登入後，丟她的自介截圖',
        '自介或照片都可以，幫你想幾句開場白。',
      ),
      (
        OnboardingIntent.practice,
        '登入後，先抽一位練習夥伴',
        // 登入前不知道方案（Bruce 2026-10-30 真機）：付費方案用每天的免費翻牌。
        '免費帳號第一次進練習室會先送一次翻牌；付費方案用每天的免費翻牌。',
      ),
    ]) {
      testWidgets(intent.wire, (tester) async {
        await _pumpFinishPage(tester, intent: intent);
        expect(find.text(title), findsOneWidget);
        expect(find.text(detail), findsOneWidget);
      });
    }

    testWidgets('沒有路徑（不該發生）就用通用說法', (tester) async {
      await _pumpFinishPage(tester, intent: null);
      expect(find.text('登入後就能開始'), findsOneWidget);
    });

    test('標題壓在 12 字內（375 寬也排得進一行）', () {
      for (final intent in [...OnboardingIntent.values, null]) {
        final title = OnboardingFinishPage.nextStepCopy(intent).title;
        expect(title.runes.length, lessThanOrEqualTo(12), reason: title);
      }
    });
  });

  testWidgets('免費額度一行：數字來自 AppConstants', (tester) async {
    await _pumpFinishPage(tester, intent: OnboardingIntent.analyze);

    expect(
      find.text(
        '免費額度：每月 ${AppConstants.freeMonthlyLimit} 則、'
        '每天最多 ${AppConstants.freeDailyLimit} 則。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('有選目標才出現目標那一行，而且只說教練 1:1 會參考', (tester) async {
    await _pumpFinishPage(tester, intent: OnboardingIntent.analyze);
    expect(find.text(OnboardingFinishPage.goalsLine), findsNothing);

    await _pumpFinishPage(
      tester,
      intent: OnboardingIntent.analyze,
      hasGoals: true,
    );
    expect(find.text(OnboardingFinishPage.goalsLine), findsOneWidget);
    expect(OnboardingFinishPage.goalsLine, contains('教練 1:1'));
    expect(OnboardingFinishPage.goalsLine, isNot(contains('建議')));
  });

  group('AI 隱私一行（取代原本獨立的隱私頁）', () {
    testWidgets('頁面上是 onboardingLine＋看完整說明，不列廠商名', (tester) async {
      await _pumpFinishPage(tester, intent: OnboardingIntent.practice);

      expect(
        find.text(
          '${AiPrivacyDisclosure.onboardingLine}。'
          '${OnboardingFinishPage.privacyLinkLabel}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('第三方 AI'), findsOneWidget);
      expect(find.textContaining('Anthropic'), findsNothing);
      expect(find.textContaining('DeepSeek'), findsNothing);
    });

    testWidgets('看完整說明：sheet 跟設定頁同一段（含廠商行與登入前事件），知道了關掉', (tester) async {
      await _pumpFinishPage(tester, intent: OnboardingIntent.analyze);

      await tester.tap(find.byKey(const ValueKey('onboarding-privacy-link')));
      await tester.pumpAndSettle();

      expect(find.text(AiPrivacyDisclosure.title), findsOneWidget);
      final sheetText = tester.widget<Text>(
        find.byKey(const ValueKey('onboarding-privacy-sheet-text')),
      );
      expect(sheetText.data, AiPrivacyDisclosure.description);
      expect(sheetText.data, contains('Anthropic Claude'));
      expect(sheetText.data, contains('DeepSeek'));
      expect(sheetText.data, contains('還沒登入時的使用事件'));
      expect(sheetText.data, contains('登入後才補送'));
      expect(sheetText.data, contains('每個 AI 功能首次使用前，都會先徵求你的同意'));

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('onboarding-privacy-sheet-text')),
        findsNothing,
      );
    });

    testWidgets('讀屏：隱私一行點得到，點了打開完整說明（主審 r1 P2）', (tester) async {
      await _pumpFinishPage(tester, intent: OnboardingIntent.analyze);
      final semantics = tester.ensureSemantics();

      await semanticsTap(
        tester,
        find.byKey(const ValueKey('onboarding-privacy-link')),
      );

      expect(
        find.byKey(const ValueKey('onboarding-privacy-sheet-text')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('隱私一行整行都能點（點擊範圍至少 44 高）', (tester) async {
      await _pumpFinishPage(tester, intent: OnboardingIntent.opener);

      final size =
          tester.getSize(find.byKey(const ValueKey('onboarding-privacy-link')));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThan(200));
    });

    testWidgets('在整條流程裡也打得開（OnboardingScreen 接好了）', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await goToFinishPage(tester, OnboardingIntent.opener);

      await tester.tap(find.byKey(const ValueKey('onboarding-privacy-link')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('onboarding-privacy-sheet-text')),
        findsOneWidget,
      );
    });
  });

  testWidgets('小螢幕（375×667）不 overflow', (tester) async {
    await _pumpFinishPage(
      tester,
      intent: OnboardingIntent.practice,
      hasGoals: true,
      size: const Size(375, 667),
    );
    expect(tester.takeException(), isNull);
  });
}
