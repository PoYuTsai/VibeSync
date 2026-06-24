import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

void main() {
  Future<bool?> pumpConsentLauncher(WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: '對話分析',
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    return result;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the third-party AI disclosure before accepting',
      (tester) async {
    await pumpConsentLauncher(tester);

    expect(find.text('第三方 AI 資料使用同意'), findsOneWidget);
    expect(
        find.textContaining('Anthropic Claude API'), findsAtLeastNWidgets(1));
    expect(find.textContaining('聊天文字'), findsOneWidget);
    expect(find.text('查看服務條款'), findsOneWidget);
    expect(find.text('查看隱私權政策'), findsOneWidget);
    expect(find.textContaining('我已閱讀並同意服務條款與隱私權政策'), findsOneWidget);
    expect(find.text('我同意並送出'), findsOneWidget);
  });

  testWidgets('requires explicit checkbox agreement before accepting',
      (tester) async {
    await pumpConsentLauncher(tester);

    final acceptButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '我同意並送出'),
    );
    expect(acceptButton.onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final enabledAcceptButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '我同意並送出'),
    );
    expect(enabledAcceptButton.onPressed, isNotNull);
  });

  testWidgets('accepting persists consent', (tester) async {
    var result = await pumpConsentLauncher(tester);
    expect(result, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我同意並送出'));
    await tester.pumpAndSettle();

    result = await AiDataSharingConsent.ensure(
      tester.element(find.text('start')),
      featureLabel: '對話分析',
    );

    expect(result, isTrue);
    expect(await AiDataSharingConsent.hasAccepted(), isTrue);
  });

  testWidgets('declining blocks the AI request and does not persist consent',
      (tester) async {
    var result = await pumpConsentLauncher(tester);
    expect(result, isNull);

    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();

    result = await AiDataSharingConsent.hasAccepted();

    expect(result, isFalse);
  });

  // ── 參數化：practice-chat 走 DeepSeek，文案與 key 須與 Claude 路徑分離 ──

  testWidgets('custom destinationLabel 顯示於揭露文案（DeepSeek 路徑）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 實戰練習室',
                  consentKey: 'practice_consent_test_key',
                  destinationLabel: 'DeepSeek API',
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DeepSeek API'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Anthropic Claude API'), findsNothing);
  });

  test('不同 consentKey 各自獨立（同意 Claude 不代表同意 DeepSeek 練習室）',
      () async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.acceptedKeyForTesting: true,
    });
    expect(await AiDataSharingConsent.hasAccepted(), isTrue);
    expect(
      await AiDataSharingConsent.hasAccepted(
        consentKey: 'practice_consent_test_key',
      ),
      isFalse,
    );
  });
}
