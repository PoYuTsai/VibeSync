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
    AiDataSharingConsent.debugSetConsentBoolOverride = null;
    AiDataSharingConsent.debugSetConsentStringOverride = null;
  });

  testWidgets('shows the third-party AI disclosure before accepting',
      (tester) async {
    await pumpConsentLauncher(tester);

    expect(find.text('資料使用說明'), findsOneWidget);
    expect(find.text('你選擇分享的內容'), findsOneWidget);
    expect(find.text('VibeSync 如何幫你'), findsOneWidget);
    expect(find.text('資料如何處理'), findsOneWidget);
    expect(find.textContaining('Anthropic'), findsAtLeastNWidgets(1));
    expect(find.textContaining('聊天文字'), findsOneWidget);
    expect(find.textContaining('《服務條款》'), findsOneWidget);
    expect(find.textContaining('《隱私權政策》'), findsOneWidget);
    expect(find.textContaining('我已閱讀並同意'), findsOneWidget);
    expect(find.textContaining('若資料用途或服務供應商變更'), findsOneWidget);
    expect(find.text('同意並繼續'), findsOneWidget);
  });

  testWidgets('requires explicit checkbox agreement before accepting',
      (tester) async {
    await pumpConsentLauncher(tester);

    final acceptButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '同意並繼續'),
    );
    expect(acceptButton.onPressed, isNull);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final enabledAcceptButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '同意並繼續'),
    );
    expect(enabledAcceptButton.onPressed, isNotNull);
  });

  testWidgets('accepting persists consent', (tester) async {
    var result = await pumpConsentLauncher(tester);
    expect(result, isNull);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
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

    await tester.tap(find.text('暫不同意'));
    await tester.pumpAndSettle();

    result = await AiDataSharingConsent.hasAccepted();

    expect(result, isFalse);
  });

  testWidgets('keyboard screenshot consent persists a timestamped receipt',
      (tester) async {
    AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AiDataSharingConsent.ensure(
                context,
                featureLabel: 'AI 鍵盤截圖回覆',
                consentKey: AiDataSharingConsent.keyboardScreenshotConsentKey,
                dataDescription:
                    AiDataSharingConsent.keyboardScreenshotDataDescription,
                purposeText: AiDataSharingConsent.keyboardScreenshotPurposeText,
              ),
              child: const Text('start keyboard consent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start keyboard consent'));
    await tester.pumpAndSettle();
    expect(find.textContaining('一張聊天截圖'), findsOneWidget);
    expect(find.textContaining('不會自動讀取其他聊天紀錄'), findsOneWidget);
    expect(find.textContaining('預設關閉'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
    await tester.pumpAndSettle();

    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isTrue);
    expect(
      await AiDataSharingConsent.keyboardScreenshotConsentAcceptedAt(),
      isNotNull,
    );
    expect(
      await AiDataSharingConsent.hasKeyboardPartnerContextSharingEnabled(),
      isFalse,
    );
  });

  testWidgets(
      'keyboard consent boolean with a future receipt cannot bypass prompt',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::user-a': true,
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::user-a':
          DateTime.utc(2999, 1, 1).toIso8601String(),
    });
    AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 鍵盤截圖回覆',
                  consentKey: AiDataSharingConsent.keyboardScreenshotConsentKey,
                  dataDescription:
                      AiDataSharingConsent.keyboardScreenshotDataDescription,
                  purposeText:
                      AiDataSharingConsent.keyboardScreenshotPurposeText,
                );
              },
              child: const Text('start keyboard consent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start keyboard consent'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(result, isNull);
    expect(find.text('資料使用說明'), findsOneWidget);
    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::user-a',
      ),
      isNull,
    );
    expect(
      prefs.getString(
        '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::user-a',
      ),
      isNull,
    );
  });

  testWidgets(
      'keyboard screenshot consent fails closed when the boolean write fails',
      (tester) async {
    AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
    AiDataSharingConsent.debugSetConsentBoolOverride =
        (preferences, key, value) async => false;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 鍵盤截圖回覆',
                  consentKey: AiDataSharingConsent.keyboardScreenshotConsentKey,
                  dataDescription:
                      AiDataSharingConsent.keyboardScreenshotDataDescription,
                  purposeText:
                      AiDataSharingConsent.keyboardScreenshotPurposeText,
                );
              },
              child: const Text('start keyboard consent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start keyboard consent'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(result, isFalse);
    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::user-a',
      ),
      isNull,
    );
    expect(
      prefs.getString(
        '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::user-a',
      ),
      isNull,
    );
  });

  testWidgets(
      'account switch during the boolean write removes the stale consent pair',
      (tester) async {
    var currentUserId = 'user-a';
    AiDataSharingConsent.debugUserIdOverride = () => currentUserId;
    AiDataSharingConsent.debugSetConsentBoolOverride =
        (preferences, key, value) async {
      final written = await preferences.setBool(key, value);
      currentUserId = 'user-b';
      return written;
    };
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 鍵盤截圖回覆',
                  consentKey: AiDataSharingConsent.keyboardScreenshotConsentKey,
                  dataDescription:
                      AiDataSharingConsent.keyboardScreenshotDataDescription,
                  purposeText:
                      AiDataSharingConsent.keyboardScreenshotPurposeText,
                );
              },
              child: const Text('start keyboard consent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start keyboard consent'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(result, isFalse);
    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::user-a',
      ),
      isNull,
    );
    expect(
      prefs.getString(
        '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::user-a',
      ),
      isNull,
    );
    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::user-b',
      ),
      isNull,
    );
  });

  testWidgets(
      'account switch during receipt write is rejected before boolean write',
      (tester) async {
    var currentUserId = 'user-a';
    var booleanWriteCalls = 0;
    AiDataSharingConsent.debugUserIdOverride = () => currentUserId;
    AiDataSharingConsent.debugSetConsentStringOverride =
        (preferences, key, value) async {
      final written = await preferences.setString(key, value);
      currentUserId = 'user-b';
      return written;
    };
    AiDataSharingConsent.debugSetConsentBoolOverride =
        (preferences, key, value) async {
      booleanWriteCalls++;
      return preferences.setBool(key, value);
    };
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 鍵盤截圖回覆',
                  consentKey: AiDataSharingConsent.keyboardScreenshotConsentKey,
                  dataDescription:
                      AiDataSharingConsent.keyboardScreenshotDataDescription,
                  purposeText:
                      AiDataSharingConsent.keyboardScreenshotPurposeText,
                );
              },
              child: const Text('start keyboard consent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start keyboard consent'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(result, isFalse);
    expect(booleanWriteCalls, 0);
    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::user-a',
      ),
      isNull,
    );
    expect(
      prefs.getString(
        '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::user-a',
      ),
      isNull,
    );
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
    expect(find.textContaining('Anthropic'), findsNothing);
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

    expect(find.textContaining('不另存原始草稿、微調指令或完整對話輸入'), findsOneWidget);
    expect(find.textContaining('可用重播資料保留 7 天'), findsOneWidget);
    expect(find.textContaining('生成文字仍可能重述或反映'), findsOneWidget);
    expect(find.textContaining('備份副本依 Supabase'), findsOneWidget);
  });

  testWidgets('同一把 key 的揭露必須同時涵蓋潤飾與微調兩個入口', (tester) async {
    // 兩個入口共用 optimizeReplayConsentKey，所以任一入口看到的文案都必須
    // 對兩者都成立。只說「草稿潤飾」的話，從微調進來的人會看到名不符實的
    // 用途說明——這和 server 錯誤碼寫死「草稿潤飾」是同一類問題。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: '回覆微調',
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

    expect(find.textContaining('草稿潤飾或回覆微調'), findsOneWidget);
    expect(find.textContaining('你輸入的微調指令'), findsOneWidget);
    // 保留期與備份週期兩個入口一致，不得因為換入口就消失。
    expect(find.textContaining('可用重播資料保留 7 天'), findsOneWidget);
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
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('同意並繼續'));
      await tester.tap(find.text('同意並繼續'));
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

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('同意並繼續'));
      await tester.tap(find.text('同意並繼續'));
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

  // 2026-10-02 v3：練習室供應商補上 Anthropic，換 key 讓舊版同意的人重看一次。
  testWidgets('已同意快速放行前重查帳號：讀設定期間換成另一個帳號就不放行（Codex R2 P1）', (tester) async {
    final v3KeyA = '${AiDataSharingConsent.practiceConsentKey}::user-a';
    SharedPreferences.setMockInitialValues({v3KeyA: true});
    // 第一次解析帳號是 A（決定查哪個 key），之後都是 B：模擬等設定期間換帳號。
    var calls = 0;
    AiDataSharingConsent.debugUserIdOverride =
        () => calls++ == 0 ? 'user-a' : 'user-b';

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 實戰練習室',
                  consentKey: AiDataSharingConsent.practiceConsentKey,
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
    expect(result, isFalse, reason: 'A 的同意不能放行 B');
    expect(find.text('資料使用說明'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('${AiDataSharingConsent.practiceConsentKey}::user-b'),
        isNull);
    expect(prefs.getBool(v3KeyA), isTrue);

    // 帳號沒變時照常快速放行。
    AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
    result = null;
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('練習室：舊版 v2 同意不算數，重問、拒絕不寫、同意後不再問、別的功能不受影響', (tester) async {
    const legacyV2Key = 'ai_data_sharing_consent_practice_20260706_v2';
    expect(AiDataSharingConsent.practiceConsentKey, isNot(legacyV2Key));
    AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
    final otherKeys = <String, Object>{
      '$legacyV2Key::user-a': true,
      '${AiDataSharingConsent.acceptedKeyForTesting}::user-a': true,
      '${AiDataSharingConsent.optimizeReplayConsentKey}::user-a': true,
    };
    SharedPreferences.setMockInitialValues(otherKeys);
    final v3Key = '${AiDataSharingConsent.practiceConsentKey}::user-a';

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiDataSharingConsent.ensure(
                  context,
                  featureLabel: 'AI 實戰練習室',
                  consentKey: AiDataSharingConsent.practiceConsentKey,
                  destinationLabel:
                      AiDataSharingConsent.practiceDestinationLabel,
                  dataDescription: AiDataSharingConsent.practiceDataDescription,
                  purposeText: AiDataSharingConsent.practicePurposeText,
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );

    // 1) 只有 v2：照樣跳同意框，框裡點名兩家供應商；拒絕回 false、v3 不寫。
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('資料使用說明'), findsOneWidget);
    expect(find.textContaining('DeepSeek、Anthropic'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('暫不同意'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(v3Key), isNull);

    // 2) 再按一次又跳框；勾選同意後回 true，寫入 v3。
    result = null;
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('資料使用說明'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(prefs.getBool(v3Key), isTrue);

    // 3) 之後直接放行，不再跳框。
    result = null;
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('資料使用說明'), findsNothing);
    expect(result, isTrue);

    // 4) 其他功能（含舊 v2 本身）的同意紀錄原封不動。
    for (final entry in otherKeys.entries) {
      expect(prefs.getBool(entry.key), entry.value, reason: entry.key);
    }
  });
}
