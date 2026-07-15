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

  tearDown(() {
    AiDataSharingConsent.debugUserIdOverride = null;
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

  testWidgets('custom destinationLabel 顯示於揭露文案（DeepSeek 路徑）', (tester) async {
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

  testWidgets('practice 用途文案準確（不混入 Claude 功能用途）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 實戰練習室',
                  consentKey: 'practice_consent_test_key2',
                  destinationLabel:
                      AiDataSharingConsent.practiceDestinationLabel,
                  purposeText: AiDataSharingConsent.practicePurposeText,
                  dataDescription: AiDataSharingConsent.practiceDataDescription,
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

    expect(find.textContaining('陪練女孩'), findsAtLeastNWidgets(1));
    expect(find.textContaining('截圖辨識'), findsNothing);
  });

  test('不同 consentKey 各自獨立（同意 Claude 不代表同意 DeepSeek 練習室）', () async {
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

  testWidgets('草稿潤飾獨立揭露生成結果暫存、7 天重播與備份週期', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: '草稿潤飾',
                  consentKey: AiDataSharingConsent.optimizeReplayConsentKey,
                  dataDescription:
                      AiDataSharingConsent.optimizeReplayDataDescription,
                  purposeText: AiDataSharingConsent.optimizeReplayPurposeText,
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

    expect(find.textContaining('不另存原始草稿或完整對話輸入'), findsOneWidget);
    expect(find.textContaining('可用重播資料保留 7 天'), findsOneWidget);
    expect(find.textContaining('生成文字仍可能重述或反映'), findsOneWidget);
    expect(find.textContaining('備份副本依 Supabase'), findsOneWidget);
  });

  // ── 帳號級同意（5.1.1(i)/5.1.2(i)）：consent 綁 userId，不得跨帳號沿用 ──

  group('account-scoped consent', () {
    test('登入時裝置級舊同意不沿用（必須重新取得該帳號同意）', () async {
      SharedPreferences.setMockInitialValues({
        AiDataSharingConsent.acceptedKeyForTesting: true,
      });
      AiDataSharingConsent.debugUserIdOverride = () => 'user-a';

      expect(await AiDataSharingConsent.hasAccepted(), isFalse);
    });

    testWidgets('登入時同意持久化到該帳號，換帳號不沿用、回原帳號仍有效', (tester) async {
      AiDataSharingConsent.debugUserIdOverride = () => 'user-a';

      await pumpConsentLauncher(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我同意並送出'));
      await tester.pumpAndSettle();

      expect(await AiDataSharingConsent.hasAccepted(), isTrue);

      AiDataSharingConsent.debugUserIdOverride = () => 'user-b';
      expect(await AiDataSharingConsent.hasAccepted(), isFalse);

      AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
      expect(await AiDataSharingConsent.hasAccepted(), isTrue);
    });

    test('登入時同意不寫入裝置級 key（登出後不殘留全域同意）', () async {
      AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        '${AiDataSharingConsent.acceptedKeyForTesting}::user-a',
        true,
      );

      expect(await AiDataSharingConsent.hasAccepted(), isTrue);

      AiDataSharingConsent.debugUserIdOverride = () => null;
      expect(await AiDataSharingConsent.hasAccepted(), isFalse);
    });

    test('未登入（userId 為 null）fallback 裝置級 key，行為不變', () async {
      SharedPreferences.setMockInitialValues({
        AiDataSharingConsent.acceptedKeyForTesting: true,
      });
      AiDataSharingConsent.debugUserIdOverride = () => null;

      expect(await AiDataSharingConsent.hasAccepted(), isTrue);
    });

    testWidgets('dialog 開啟期間身份變動：不寫入、不放行（Codex P2 競態）', (tester) async {
      var currentUserId = 'user-a';
      AiDataSharingConsent.debugUserIdOverride = () => currentUserId;

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

      // dialog 開著時身份換人（模擬 session 過期／換帳號）
      currentUserId = 'user-b';

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我同意並送出'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('${AiDataSharingConsent.acceptedKeyForTesting}::user-a'),
        isNull,
      );
      expect(
        prefs.getBool('${AiDataSharingConsent.acceptedKeyForTesting}::user-b'),
        isNull,
      );
    });

    test('practice consentKey 同樣帳號級隔離', () async {
      SharedPreferences.setMockInitialValues({
        '${AiDataSharingConsent.practiceConsentKey}::user-a': true,
      });
      AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
      expect(
        await AiDataSharingConsent.hasAccepted(
          consentKey: AiDataSharingConsent.practiceConsentKey,
        ),
        isTrue,
      );

      AiDataSharingConsent.debugUserIdOverride = () => 'user-b';
      expect(
        await AiDataSharingConsent.hasAccepted(
          consentKey: AiDataSharingConsent.practiceConsentKey,
        ),
        isFalse,
      );
    });
  });
}
