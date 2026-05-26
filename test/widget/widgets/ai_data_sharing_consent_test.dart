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
    expect(find.textContaining('Anthropic Claude API'), findsOneWidget);
    expect(find.textContaining('聊天文字'), findsOneWidget);
    expect(find.text('我同意並送出'), findsOneWidget);
  });

  testWidgets('accepting persists consent', (tester) async {
    var result = await pumpConsentLauncher(tester);
    expect(result, isNull);

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
}
