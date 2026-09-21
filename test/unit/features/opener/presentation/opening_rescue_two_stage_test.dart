// 開場救星畫面的兩段式接線：真的停下來等用戶、分析卡／回答區／生成／結果／
// 再生成入口、舊 Edge 退回舊單段、到期草稿只能看（附件 §4、§9.3）。
// Pump idiom 同 opening_rescue_field_limits_test；OpenerService 只替換兩個網路方法。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_view.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/opener/data/services/opener_request_session.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';
import 'package:vibesync/features/opener/domain/opener_flow_models.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/opener/presentation/widgets/opener_flow_sections.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';
import '../../../../visual_proof/proof_support.dart';

final _proofRoot = GlobalKey();

Future<void> _captureStage(WidgetTester t, String name) async {
  await _settleBounded(t);
  expect(t.takeException(), isNull);
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(find.byKey(_proofRoot))
        .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/visual_proof/v3/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _FakeOpenerService extends OpenerService {
  _FakeOpenerService() : super(accessTokenProvider: () => 'token');

  int analyzeCalls = 0;
  String? lastAnalysisRequestId;
  int generateCalls = 0;
  int legacyCalls = 0;
  Object? analyzeError;
  Completer<void>? analyzeGate;
  Completer<void>? generateGate;
  void Function(String, String?)? generationProgress;
  String? lastFreeText;
  String? lastState;

  @override
  Future<OpenerAnalysis> analyzeProfileStreaming({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
    String? expectedTier,
    String? revenueCatAppUserId,
    required String analysisRequestId,
    String? initialUserNote,
    void Function(String label, String? phase)? onProgress,
  }) async {
    analyzeCalls += 1;
    lastAnalysisRequestId = analysisRequestId;
    if (analyzeError != null) throw analyzeError!;
    await analyzeGate?.future;
    return OpenerAnalysis.tryParse({
      'sessionId': 'sess-1',
      'analysisRevision': 1,
      'expiresAt': '2099-01-01T00:00:00Z',
      'approach': {
        'mode': 'anchor_hooks',
        'summary': '可以從她的狗開，但先確認你想聊哪個部分',
        'avoid': ['不用證明自己符合條件']
      },
      'cues': [
        {
          'id': 'cue_1',
          'label': '養狗',
          'source': 'profile_text',
          'evidence': {'field': 'bio', 'quote': '有養一隻狗'}
        },
      ],
      'question': {
        'id': 'question_1',
        'affects': 'sender_fact',
        'text': '你跟養狗這件事比較接近哪種？',
        'options': [
          {
            'id': 'option_1',
            'label': '我自己有養',
            'meaning': 'assert_sender_fact',
            'cueId': 'cue_1',
            'statement': '我有養狗'
          },
          {
            'id': 'option_2',
            'label': '沒養，但有興趣',
            'meaning': 'curious_without_experience',
            'cueId': 'cue_1'
          },
          {'id': 'option_3', 'label': '其實想聊別的', 'meaning': 'change_direction'},
        ],
      },
      'usage': {
        'firstGenerationCost': 3,
        'includedGenerationCount': 3,
        'generationsUsed': 0,
        'quotaCharged': false
      },
    })!;
  }

  @override
  Future<OpenerGeneration> generateFromAnalysisStreaming({
    required String sessionId,
    required int analysisRevision,
    required String generationId,
    required OpenerContribution contribution,
    String? expectedTier,
    String? revenueCatAppUserId,
    void Function(String label, String? phase)? onProgress,
  }) async {
    generateCalls += 1;
    lastFreeText = contribution.freeText;
    lastState = contribution.stateWire;
    generationProgress = onProgress;
    await generateGate?.future;
    return OpenerGeneration.fromServerBody({
      'sessionId': sessionId,
      'generationId': generationId,
      'expiresAt': '2099-01-01T00:00:00Z',
      'openers': {
        'extend': '牠散步會自己選路嗎',
        'humor': '妳家狗是導航派還是隨機派',
        'tease': '妳家狗看起來比妳會安排行程'
      },
      'recommendation': {'pick': 'extend', 'reason': '直接問你想知道的事，也沒有寫成你養過狗'},
      'cardReasons': {'extend': '直接問你想知道的事，也沒有寫成你養過狗'},
      'materialUse': {
        'inputState': contribution.stateWire,
        'references': [
          {
            'style': 'extend',
            'materialId': 'material_1',
            'outputSpan': '散步會自己選路'
          }
        ],
        'traceStatus':
            contribution.stateWire == 'answered' ? 'matched' : 'no_input',
        'displayNote':
            contribution.stateWire == 'answered' ? '這句接的是你想知道的散步習慣' : null
      },
      'access': {
        'contractVersion': 2,
        'servedTier': 'free',
        'visibleTypes': ['extend', 'humor', 'tease'],
        'lockedTypes': ['resonate', 'coldRead']
      },
      'usage': {
        'chargedNow': generateCalls == 1 ? 3 : 0,
        'sessionChargedTotal': 3,
        'generationsUsed': generateCalls,
        'generationsRemaining': 3 - generateCalls,
        'replayed': false
      },
    }, contribution: contribution)!;
  }

  @override
  Future<OpenerResult> generateOpenersStreaming({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
    String? expectedTier,
    String? revenueCatAppUserId,
    String? requestId,
    String? effectiveStyleContext,
    void Function(String label, String? phase)? onProgress,
  }) async {
    legacyCalls += 1;
    return const OpenerResult(
        openers: {'extend': '舊單段句'}, recommendedPick: 'extend');
  }
}

Widget _screen() => ProviderScope(
      overrides: [
        authConversationScopeProvider.overrideWith((_) => const Stream.empty()),
        partnerListProvider.overrideWith((_) => const []),
        // 結果區的回報列會讀 coaching outcome Hive box；本測試不開那個 box。
        coachingOutcomeEventProvider.overrideWith((ref, id) => null),
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(
            const SubscriptionState(
                tier: SubscriptionTierHelper.free,
                monthlyLimit: 30,
                dailyLimit: 10),
          ),
        ),
      ],
      child: const OpeningRescueScreen(),
    );

Future<void> _pumpManual(WidgetTester tester) async {
  // 畫布拉高到不需要捲動：捲動動畫在有長駐動畫的頁面等不到完成（會死鎖）。
  await tester.binding.setSurfaceSize(const Size(390, 4200));
  await tester.pumpWidget(MaterialApp(home: _screen()));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('手動輸入'));
  await tester.pumpAndSettle();
}

/// 結果區有長駐動畫（SwipeHintNudge repeat 34 輪），不能 pumpAndSettle；
/// 用有界 pump 讓非同步結果落地。
Future<void> _settleBounded(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// 生成／回看會寫 Hive 草稿（真實檔案 I/O）：在 fake async 裡那個 put 永遠完成不了，
/// tearDownAll 的 Hive.close() 會等到天荒地老。用 runAsync 讓 I/O 真的完成。
/// [until] 給了就等到那個 widget 出現（上限 5 秒）再回來：分析／生成路徑現在有多次排隊的
/// Hive 寫入，固定 50ms 在全套並行跑時不夠（第三輪全套一次 F01 flake），要等真正的條件。
Future<void> _tapAndSettleAsync(WidgetTester tester, Finder finder,
    {Finder? until}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await _settleBounded(tester);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _settleBounded(tester);
    if (until != null) {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (until.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _settleBounded(tester);
    }
  });
}

Future<void> _analyze(WidgetTester tester, {Finder? until}) async {
  await tester.enterText(
      find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'),
      '有養一隻狗，假日會去河堤');
  await tester.pump();
  // R2a 後分析完成就會寫 Hive 草稿：同樣要在 runAsync 裡讓 I/O 完成；預設等到分析摘要出現。
  await _tapAndSettleAsync(
    tester,
    find.byKey(const ValueKey('opener-analyze-button')),
    until: until ?? find.byKey(const ValueKey('opener-approach-summary')),
  );
}

/// controller 用「對方資料指紋＋初稿」鑄 analysisRequestId；種子草稿要給同一個值。
final String _analysisFingerprint = jsonEncode([
  OpenerRequestIdSession.fingerprintFor(bio: '有養一隻狗，假日會去河堤'),
  '想從狗開',
]);

void main() {
  late _FakeOpenerService service;

  setUpAll(() async {
    await loadProofFonts();
    await (FontLoader('packages/flutter_tabler_icons/tabler-icons')
          ..addFont(rootBundle.load(
              'packages/flutter_tabler_icons/assets/fonts/tabler-icons.ttf')))
        .load();
    Hive.init(Directory.systemTemp.createTempSync('opener_two_stage').path);
    if (!Hive.isBoxOpen(AppConstants.settingsBox)) {
      await Hive.openBox(AppConstants.settingsBox);
    }
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('real viewport analysis and result at 320 width scale=$scale',
        (t) async {
      await t.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(RepaintBoundary(
          key: _proofRoot,
          child: MaterialApp(
              theme: ThemeData(fontFamily: 'AppTC'),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: _screen())));
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.text('手動輸入'));
      await t.pump();
      await t.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'),
          '有養一隻狗，假日會去河堤');
      await t.pump();
      await t
          .ensureVisible(find.byKey(const ValueKey('opener-analyze-button')));
      await _tapAndSettleAsync(
          t, find.byKey(const ValueKey('opener-analyze-button')),
          until: find.byKey(const ValueKey('opener-approach-summary')));
      await t
          .ensureVisible(find.byKey(const ValueKey('opener-approach-summary')));
      await _captureStage(t, 'opener-analysis-320-$scale');
      await t
          .ensureVisible(find.byKey(const ValueKey('opener-generate-button')));
      await _captureStage(t, 'opener-contribution-320-$scale');
      await _tapAndSettleAsync(
          t, find.byKey(const ValueKey('opener-generate-button')),
          until: find.text('開場白建議'));
      await t.ensureVisible(find.text('開場白建議'));
      await _captureStage(t, 'opener-result-320-$scale');
      expect(find.text('牠散步會自己選路嗎'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('opener-adjust-button')));
      expect(t.takeException(), isNull);
    });
  }

  setUp(() async {
    service = _FakeOpenerService();
    OpeningRescueScreen.debugOpenerServiceFactory = () => service;
    OpeningRescueScreen.debugOwnerIdOverride = () => 'user-a';
    OpenerResultCacheService.debugDefaultOwnerIdOverride = () => 'user-a';
    AiDataSharingConsent.debugUserIdOverride = () => 'user-a';
    SharedPreferences.setMockInitialValues({
      '${AiDataSharingConsent.acceptedKeyForTesting}::user-a': true,
    });
    await Hive.box(AppConstants.settingsBox).clear();
  });

  tearDown(() {
    OpeningRescueScreen.debugOpenerServiceFactory = null;
    OpeningRescueScreen.debugOwnerIdOverride = null;
    OpenerResultCacheService.debugDefaultOwnerIdOverride = null;
    AiDataSharingConsent.debugUserIdOverride = null;
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets(
      'v3 R1 draft action appears after save and disappears after deleting last draft',
      (tester) async {
    await _pumpManual(tester);
    expect(find.text('草稿'), findsNothing);
    await _analyze(tester);
    expect(find.text('草稿'), findsOneWidget);
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    await _tapAndSettleAsync(tester, find.byTooltip('刪除草稿'));
    expect(
        OpenerResultCacheService(ownerIdResolver: () => 'user-a').loadDrafts(),
        isEmpty);
    expect(find.text('草稿'), findsNothing);
    expect(service.analyzeCalls, 1);
  });

  testWidgets(
      'UI-13 delayed analysis finishes offstage without resend or duplicate CTA',
      (tester) async {
    service.analyzeGate = Completer<void>();
    await _pumpManual(tester);
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'),
        '有養一隻狗，假日會去河堤');
    await tester.pump();
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-analyze-button')));
    expect(service.analyzeCalls, 1);
    final requestId = service.lastAnalysisRequestId;
    await tester.tap(find.text('新話題'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NewTopicView), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-analyze-button')), findsNothing);
    expect(find.byKey(const ValueKey('new-topic-generate')), findsOneWidget);
    await tester.runAsync(() async {
      service.analyzeGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _settleBounded(tester);
    });
    expect(find.byType(NewTopicView), findsOneWidget,
        reason: 'completion does not switch mode');
    expect(find.byKey(const ValueKey('opener-approach-summary')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('開場白'));
    await _settleBounded(tester);
    expect(
        find.byKey(const ValueKey('opener-approach-summary')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('opener-generate-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-topic-generate')), findsNothing);
    expect(service.analyzeCalls, 1);
    expect(service.lastAnalysisRequestId, requestId);
    expect(service.generateCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F01：按「分析對方資料」只分析、畫面停在回答區；沒有五句、沒有第二段呼叫', (tester) async {
    await _pumpManual(tester);
    expect(find.byKey(const ValueKey('opener-initial-note')), findsOneWidget);
    expect(find.text('先加入截圖或輸入她的資料'), findsOneWidget);
    expect(find.text('生成開場白'), findsNothing, reason: '兩段式下主按鈕是「分析對方資料」');
    await _analyze(tester);

    expect(service.analyzeCalls, 1);
    expect(service.generateCalls, 0);
    expect(
        find.byKey(const ValueKey('opener-approach-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-cue-cue_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-question-text')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('opener-generate-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-skip-button')), findsOneWidget);
    expect(find.text('開場白建議'), findsNothing);
    expect(find.textContaining('第一次生成扣 3 則'), findsOneWidget);
  });

  testWidgets('開場欄位進度不打完成勾勾，最後確認後才交付正式結果', (tester) async {
    service.generateGate = Completer<void>();
    await _pumpManual(tester);
    await _analyze(tester);
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-skip-button')));
    expect(service.generateCalls, 1);
    service.generationProgress?.call('正在寫延展', 'style_extend');
    await tester.pump();
    expect(find.byKey(const ValueKey('opener-skeleton-extend-started')),
        findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    service.generationProgress?.call('正在確認最後結果', 'finalizing');
    await tester.pump();
    expect(find.byKey(const ValueKey('opener-skeleton-extend-started')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('stream-progress-ticker')), findsOneWidget);
    expect(find.text('開場白建議'), findsNothing);
    await tester.runAsync(() async {
      service.generateGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await _settleBounded(tester);
    expect(find.byKey(const ValueKey('stream-progress-ticker')), findsNothing);
    expect(find.text('開場白建議'), findsOneWidget);
  });

  testWidgets('略過補充提示獨立呈現，不冒充來源採用，舊結果仍隱藏未知說明', (tester) async {
    final use = OpenerMaterialUse.tryParse({
      'inputState': 'answered',
      'references': [],
      'traceStatus': 'uncertain',
      'displayNote': '未核對的採用說明',
      'handlingNote': '這段補充先不放進開場，改用容易接話的方向。',
    })!;
    expect(OpenerMaterialUse.tryParse(use.toJson())!.handlingNote,
        use.handlingNote);
    expect(use.matched, isFalse);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: OpenerMaterialUseNote(materialUse: use))));
    expect(find.text(use.handlingNote!), findsOneWidget);
    expect(find.text('未核對的採用說明'), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: OpenerMaterialUseNote(
                materialUse: OpenerMaterialUse(
                    inputState: 'answered',
                    references: [],
                    traceStatus: 'uncertain')))));
    expect(
        find.byKey(const ValueKey('opener-material-use-note')), findsNothing);
  });

  testWidgets('回答後按生成→結果與採用說明；調整想法再生成保留原回答；第二次不再扣', (tester) async {
    await _pumpManual(tester);
    await _analyze(tester);

    // R2a-2 後回答區每次修改都寫 Hive：要在 runAsync 裡讓 I/O 完成。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('opener-option-option_2')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('opener-free-text')), '沒養過，只想知道牠散步會不會自己選路');
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(find.byKey(const ValueKey('opener-contribution-summary')),
        findsOneWidget);
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-generate-button')));

    expect(service.generateCalls, 1);
    expect(service.lastFreeText, '沒養過，只想知道牠散步會不會自己選路');
    expect(find.text('開場白建議'), findsOneWidget);
    expect(find.text('牠散步會自己選路嗎'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('opener-material-use-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-generations-remaining')),
        findsOneWidget);
    expect(find.textContaining('還可以再生成 2 組'), findsOneWidget);
    expect(find.text('養這種狗的人假日應該都在外面'), findsNothing, reason: '鎖卡內容不在畫面');

    await tester.tap(find.byKey(const ValueKey('opener-adjust-button')));
    await _settleBounded(tester);
    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('opener-free-text')));
    expect(field.controller!.text, '沒養過，只想知道牠散步會不會自己選路', reason: '保留上次的文字');
    expect(find.textContaining('本局已扣費'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-skip-button')), findsNothing,
        reason: '調整模式不提供略過');
  });

  testWidgets('略過，直接生成：送出 skipped、結果沒有採用說明', (tester) async {
    await _pumpManual(tester);
    await _analyze(tester);
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-skip-button')));
    expect(service.lastState, 'skipped');
    expect(
        find.byKey(const ValueKey('opener-material-use-note')), findsNothing);
  });

  testWidgets('F15：分析後改對方資料→原分析失效、回到編輯（不拿舊快照生成）', (tester) async {
    await _pumpManual(tester);
    await _analyze(tester);
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'),
        '改成另一個人的自介');
    await _settleBounded(tester);
    expect(find.byKey(const ValueKey('opener-question-text')), findsNothing);
    expect(find.byKey(const ValueKey('opener-analyze-button')), findsOneWidget);
  });

  testWidgets('舊 Edge 不支援→退回舊單段 CTA，輸入保留', (tester) async {
    service.analyzeError = const OpenerFlowException(
        code: OpenerFlowErrorCode.flowUnsupported, message: 'x', status: 400);
    await _pumpManual(tester);
    await _analyze(tester, until: find.text('生成開場白'));
    expect(find.text('生成開場白'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-analyze-button')), findsNothing);
    final bio = tester.widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'));
    expect(bio.controller!.text, '有養一隻狗，假日會去河堤');
    expect(service.legacyCalls, 0, reason: '不會在同一下點擊偷偷改走舊單段扣費');
  });

  testWidgets('兩段式草稿回看：到期只能看結果、不能續生成', (tester) async {
    // 預先種一份到期的兩段式草稿：Hive 寫入是真實 I/O，要在 runAsync 裡做。
    await tester.runAsync(() async {
      final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
      final generation = await service.generateFromAnalysisStreaming(
        sessionId: 'sess-1',
        analysisRevision: 1,
        generationId: 'gen-1',
        contribution: const OpenerContribution(
            state: OpenerContributionState.answered, freeText: '沒養過'),
      );
      final analysis =
          await service.analyzeProfileStreaming(analysisRequestId: 'r');
      final expiredAnalysis = OpenerAnalysis.tryParse(
          {...analysis.toJson(), 'expiresAt': '2020-01-01T00:00:00Z'})!;
      await cache.saveDraft(
        result: generation.result,
        sourceLabel: '截圖自介', // 別跟 tab 標籤「手動輸入」撞名，tap 會找到兩個
        flow: OpenerDraftFlow(
            stage: OpenerDraftFlowStage.result,
            analysis: expiredAnalysis,
            generation: generation,
            contributionDraft: const OpenerContributionDraft(freeText: '沒養過')),
      );
    });
    await _pumpManual(tester);
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    await _tapAndSettleAsync(tester, find.text('回看'));
    expect(find.text('牠散步會自己選路嗎'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-expired-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-adjust-button')), findsNothing);
    expect(service.generateCalls, 1, reason: '回看不會在背景重新扣費');
  });

  // ── 第一輪獨立複核回歸（R4a／R4b）

  testWidgets('R4a：舊單段草稿（flow=null）在兩段式畫面回看仍看得到卡片、可複製；不觸發新分析', (tester) async {
    await tester.runAsync(() async {
      final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
      await cache.saveDraft(
        result: const OpenerResult(
            openers: {'extend': '舊單段的句子'},
            recommendedPick: 'extend',
            requestId: 'req-old'),
        sourceLabel: '截圖自介',
      );
    });
    await _pumpManual(tester);
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    await _tapAndSettleAsync(tester, find.text('回看'));
    expect(find.text('舊單段的句子'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-legacy-draft-notice')),
        findsOneWidget);
    expect(find.text('複製'), findsWidgets);
    expect(service.analyzeCalls, 0);
    expect(service.generateCalls, 0);
    expect(find.byKey(const ValueKey('opener-adjust-button')), findsNothing,
        reason: '舊草稿沒有兩段式再生成入口');
  });

  testWidgets('R4b：初稿貼 301 字→原文保留、顯示錯誤、分析按鈕禁用；300 字可分析', (tester) async {
    await _pumpManual(tester);
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'),
        '有效對方資料');
    final over = '🐶' * 301;
    await tester.enterText(
        find.byKey(const ValueKey('opener-initial-note')), over);
    await tester.pump();
    final note = tester
        .widget<TextField>(find.byKey(const ValueKey('opener-initial-note')));
    expect(note.controller!.text, over, reason: '不得靜默截斷貼上的原文');
    expect(find.byKey(const ValueKey('opener-initial-note-error')),
        findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('opener-analyze-button')))
            .onPressed,
        isNull);

    await tester.enterText(
        find.byKey(const ValueKey('opener-initial-note')), '字' * 300);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('opener-initial-note-error')), findsNothing);
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('opener-analyze-button')))
            .onPressed,
        isNotNull);
  });

  testWidgets('R4b：回答欄貼 301 字（含 emoji）→原文保留、計數變紅、生成禁用；刪到 300 恢復',
      (tester) async {
    await _pumpManual(tester);
    await _analyze(tester);
    final over = '${'字' * 300}😀';
    // R2a-2 後回答區每次修改都寫 Hive：要在 runAsync 裡讓 I/O 完成。
    await tester.runAsync(() async {
      await tester.enterText(
          find.byKey(const ValueKey('opener-free-text')), over);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('opener-free-text')));
    expect(field.controller!.text, over);
    expect(find.textContaining('超過 1 字'), findsOneWidget);
    expect(
        tester
            .widget<BrandPrimaryButton>(
                find.byKey(const ValueKey('opener-generate-button')))
            .onPressed,
        isNull);
    expect(service.generateCalls, 0);

    await tester.runAsync(() async {
      await tester.enterText(
          find.byKey(const ValueKey('opener-free-text')), '字' * 300);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(find.textContaining('超過'), findsNothing);
    expect(
        tester
            .widget<BrandPrimaryButton>(
                find.byKey(const ValueKey('opener-generate-button')))
            .onPressed,
        isNotNull);
  });

  // ── 第二輪獨立複核回歸（R2a-2：分析尚未返回就離頁的實際重建）

  testWidgets('R2a-2：停在 analyzing 的草稿回看→欄位填回、用同 analysisRequestId 續分析、停在回答區',
      (tester) async {
    await tester.runAsync(() async {
      final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
      await cache.saveDraft(
        sourceLabel: '截圖自介',
        flow: OpenerDraftFlow(
          stage: OpenerDraftFlowStage.analyzing,
          contributionDraft: const OpenerContributionDraft(freeText: '想從狗開'),
          analysisRequestId: 'req-pending-1',
          // 指紋要和 controller 由輸入快照重算的一致（同 analysisRequestId 才會沿用）。
          inputFingerprint: _analysisFingerprint,
          pendingAnalysis: const OpenerPendingAnalysis(
              bio: '有養一隻狗，假日會去河堤', initialNote: '想從狗開'),
        ),
      );
    });
    await _pumpManual(tester);
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    expect(find.text('分析中，尚未取得分析'), findsOneWidget);
    await _tapAndSettleAsync(tester, find.text('回看'),
        until: find.byKey(const ValueKey('opener-approach-summary')));
    expect(service.analyzeCalls, 1, reason: '沒截圖的 analyzing 草稿回看後自動續分析（免費）');
    expect(service.lastAnalysisRequestId, 'req-pending-1',
        reason: '同輸入沿用原 analysisRequestId');
    expect(service.generateCalls, 0);
    expect(
        find.byKey(const ValueKey('opener-approach-summary')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('opener-generate-button')), findsOneWidget);
    final bioField = tester.widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'));
    expect(bioField.controller!.text, '有養一隻狗，假日會去河堤', reason: '輸入欄位填回');
    final drafts =
        OpenerResultCacheService(ownerIdResolver: () => 'user-a').loadDrafts();
    expect(drafts.length, 1, reason: '同一份紀錄由 analyzing 升到 analyzed');
    expect(drafts.single.flow!.stage, OpenerDraftFlowStage.analyzed);
  });

  testWidgets('R2a-2：分析後只改回答再離頁（重建畫面）→回看回到同一份回答，不打第二段', (tester) async {
    await _pumpManual(tester);
    await _analyze(tester);
    await tester.runAsync(() async {
      await tester.enterText(
          find.byKey(const ValueKey('opener-free-text')), '沒養過，只想問散步');
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    final saved = OpenerResultCacheService(ownerIdResolver: () => 'user-a')
        .loadDrafts()
        .single;
    expect(saved.flow!.stage, OpenerDraftFlowStage.analyzed);
    expect(saved.flow!.contributionDraft.freeText, '沒養過，只想問散步');

    // 重建畫面（離頁再回來）；草稿卡在任一分頁都看得到，不用再切「手動輸入」分頁
    //（草稿卡的來源標籤也叫「手動輸入」，tap 會找到兩個）。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: _screen()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    await _tapAndSettleAsync(tester, find.text('回看'),
        until: find.byKey(const ValueKey('opener-free-text')));
    final freeText = tester
        .widget<TextField>(find.byKey(const ValueKey('opener-free-text')));
    expect(freeText.controller!.text, '沒養過，只想問散步');
    expect(service.generateCalls, 0);
    expect(service.analyzeCalls, 1, reason: '回看 analyzed 草稿不重新分析');
  });
}
