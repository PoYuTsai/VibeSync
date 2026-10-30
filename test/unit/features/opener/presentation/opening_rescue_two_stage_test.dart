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
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/core/services/revenuecat_service.dart';
import 'package:vibesync/core/services/usage_service.dart';
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
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:vibesync/features/subscription/presentation/quota_copy.dart';
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

/// 用量不會被背景同步蓋回預設的方案（額度不夠的預檢測試用）：其他測試靠背景刷新
/// 把方案刷回免費，所以只在需要時用這個。
class _StickySubscriptionNotifier extends _SeededSubscriptionNotifier {
  _StickySubscriptionNotifier(this._seed) : super(_seed);

  final SubscriptionState _seed;

  @override
  Future<void> syncWithRevenueCat() async => state = _seed;

  @override
  Future<void> refresh() async => state = _seed;
}

/// 付費頁按「購買」會帶 essential 回來：訂閱跟著變成付費，背景刷新不把它刷回免費。
class _PurchasableSubscriptionNotifier extends _SeededSubscriptionNotifier {
  _PurchasableSubscriptionNotifier(super.seed);

  @override
  Future<void> forceSyncTier(String tier) async =>
      state = state.copyWith(tier: tier);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> syncWithRevenueCat() async {}
}

/// 有設就讓生成走真的 OpenerService 傳輸（伺服器回這個 client 給的回應），
/// 錯誤對映與說法從真的 service 一路走到畫面。
http.Client? _generateTransport;

class _FakeOpenerService extends OpenerService {
  _FakeOpenerService()
      : super(
            accessTokenProvider: () => 'token',
            streamClientFactory: () => _generateTransport!);

  int analyzeCalls = 0;
  String? lastAnalysisRequestId;
  String? lastInitialUserNote;
  int generateCalls = 0;
  int legacyCalls = 0;
  Object? analyzeError;
  Completer<void>? analyzeGate;
  Completer<void>? generateGate;
  void Function(String, String?)? generationProgress;
  String? lastFreeText;
  String? lastState;
  Object? generateError;
  String? lastExpectedTier;

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
    lastInitialUserNote = initialUserNote;
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
    lastExpectedTier = expectedTier;
    generationProgress = onProgress;
    if (_generateTransport != null) {
      return super.generateFromAnalysisStreaming(
        sessionId: sessionId,
        analysisRevision: analysisRevision,
        generationId: generationId,
        contribution: contribution,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
        onProgress: onProgress,
      );
    }
    await generateGate?.future;
    if (generateError != null) throw generateError!;
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

/// 送出的漏斗事件（額度不足事件 quota_block_shown 用）；每個測試開始時清空。
final _funnelEvents = <Map<String, dynamic>>[];

List<Object?> _quotaBlocks() => [
      for (final e in _funnelEvents)
        if (e['event'] == 'quota_block_shown') e['properties'],
    ];

List<Override> _screenOverrides(String tier,
        {SubscriptionState? stickySubscription}) =>
    [
      authConversationScopeProvider.overrideWith((_) => const Stream.empty()),
      partnerListProvider.overrideWith((_) => const []),
      // 結果區的回報列會讀 coaching outcome Hive box；本測試不開那個 box。
      coachingOutcomeEventProvider.overrideWith((ref, id) => null),
      subscriptionProvider.overrideWith(
        (ref) => stickySubscription != null
            ? _StickySubscriptionNotifier(stickySubscription)
            : _SeededSubscriptionNotifier(
                SubscriptionState(tier: tier, monthlyLimit: 30, dailyLimit: 10),
              ),
      ),
      // 漏斗事件只記在記憶體，不打網路。
      funnelTrackerProvider.overrideWithValue(FunnelTracker(
        invoker: (_, {required body}) async {
          _funnelEvents.add(body['event'] as Map<String, dynamic>);
          return 200;
        },
        currentUserId: () => 'user-a',
      )),
    ];

Widget _screen({String tier = SubscriptionTierHelper.free}) => ProviderScope(
      overrides: _screenOverrides(tier),
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

/// 有 /paywall 路由的版本：記開了幾次付費牆、依序帶的入口，付費牆有一顆關閉鈕。
int _paywallOpens = 0;
final _paywallExtras = <Object?>[];

Future<void> _pumpManualWithPaywall(WidgetTester tester,
    {String tier = SubscriptionTierHelper.free}) async {
  await tester.binding.setSurfaceSize(const Size(390, 4200));
  await tester.pumpWidget(MaterialApp.router(
      routerConfig: GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => _screen(tier: tier)),
    GoRoute(
        path: '/paywall',
        builder: (context, state) {
          _paywallOpens++;
          _paywallExtras.add(state.extra);
          return Scaffold(
              body: Center(
                  child: TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('關閉付費牆'))));
        }),
  ])));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('手動輸入'));
  await tester.pumpAndSettle();
}

/// 付費頁有「購買」鈕（帶 essential 回來）：測付款回來之後的畫面。
Future<void> _pumpManualWithPurchase(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 4200));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._screenOverrides(SubscriptionTierHelper.free),
        subscriptionProvider.overrideWith((ref) =>
            _PurchasableSubscriptionNotifier(const SubscriptionState(
                tier: SubscriptionTierHelper.free,
                monthlyLimit: 30,
                dailyLimit: 10))),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      ],
      child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const OpeningRescueScreen()),
        GoRoute(
            path: '/paywall',
            builder: (context, state) {
              _paywallOpens++;
              return Scaffold(
                  body: Center(
                      child: TextButton(
                          onPressed: () =>
                              context.pop(SubscriptionTierHelper.essential),
                          child: const Text('購買'))));
            }),
      ]))));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('手動輸入'));
  await tester.pumpAndSettle();
}

/// 付費頁換成真的 PaywallScreen（大標照訂閱方案）。訂閱刷新換成不動狀態：這個測試樹
/// 沒登入，真的刷新會把方案刷成免費。
Future<void> _pumpManualWithRealPaywall(WidgetTester tester,
    {required String tier}) async {
  await tester.binding.setSurfaceSize(const Size(390, 4200));
  // 付費頁跟開場救星要在同一個 ProviderScope：大標讀的是同一份訂閱狀態。
  await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._screenOverrides(tier),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      ],
      child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const OpeningRescueScreen()),
        GoRoute(
            path: '/paywall',
            builder: (context, state) {
              _paywallOpens++;
              _paywallExtras.add(state.extra);
              return PaywallScreen(
                  entry: PaywallEntry.fromRouteExtra(state.extra));
            }),
      ]))));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('手動輸入'));
  await tester.pumpAndSettle();
}

/// RevenueCat 那邊已經是 Essential（訂閱快照可能還沒跟上）。
CustomerInfo _essentialCustomerInfo() {
  final now = DateTime.now().toIso8601String();
  final entitlements = {
    SubscriptionTierHelper.essential: EntitlementInfo(
      SubscriptionTierHelper.essential,
      true,
      true,
      now,
      now,
      'essential_monthly',
      true,
    ),
  };
  return CustomerInfo(
    EntitlementInfos(entitlements, entitlements),
    const {},
    const ['essential_monthly'],
    const ['essential_monthly'],
    const [],
    now,
    'rc-user',
    const {},
    now,
  );
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
    _funnelEvents.clear();
    await Hive.box(AppConstants.settingsBox).clear();
  });

  tearDown(() {
    OpeningRescueScreen.debugOpenerServiceFactory = null;
    OpeningRescueScreen.debugOwnerIdOverride = null;
    OpenerResultCacheService.debugDefaultOwnerIdOverride = null;
    AiDataSharingConsent.debugUserIdOverride = null;
    _generateTransport = null;
    _paywallExtras.clear();
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
    // 分析完成後的 Hive 寫入在全套並行時可能比固定 80ms 慢（2026-10-27 全套一次 UI-13 flake）：
    // 切回開場白時等到分析摘要真的出現（上限 5 秒），斷言本身不變。
    await _tapAndSettleAsync(tester, find.text('開場白'),
        until: find.byKey(const ValueKey('opener-approach-summary')));
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
    expect(find.textContaining('這次分析已扣過'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-skip-button')), findsNothing,
        reason: '調整模式不提供略過');
  });

  // 伺服器第一段額度關卡（OPENER_ANALYZE_QUOTA_GATE，2026-10-31）：分析被額度擋下會
  // 自動開付費頁；付款回來「分析」鈕要能再按，重新分析沿用同一筆請求（預審 P2）。
  testWidgets('第一段額度不足：付款回來後分析鈕可以再按，重新分析成功', (tester) async {
    _paywallOpens = 0;
    await _pumpManualWithPurchase(tester);
    service.analyzeError = const OpenerQuotaExceededException(
        message: '今日額度不足。',
        dailyRemaining: 1,
        quotaNeeded: 3,
        isMonthly: false);
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == '例如：喜歡爬山、養了一隻貓，週末常去咖啡店'),
        '有養一隻狗，假日會去河堤');
    await tester.pump();
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-analyze-button')),
        until: find.text('購買'));
    expect(_paywallOpens, 1, reason: '分析被額度擋下，自動開一次付費頁');
    final firstRequestId = service.lastAnalysisRequestId;

    service.analyzeError = null;
    await _tapAndSettleAsync(tester, find.text('購買'),
        until: find.byKey(const ValueKey('opener-analyze-button')));
    await _settleBounded(tester);
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-analyze-button')),
        until: find.byKey(const ValueKey('opener-approach-summary')));

    expect(
        find.byKey(const ValueKey('opener-approach-summary')), findsOneWidget,
        reason: '付款回來按得到分析，重新分析成功');
    expect(service.analyzeCalls, 2);
    expect(service.lastAnalysisRequestId, firstRequestId,
        reason: '重新分析沿用同一筆請求');
    expect(_paywallOpens, 1);
  });

  testWidgets('第一段額度不足：重開「分析中」草稿自動續分析撞到額度，不自動開付費頁，按升級才開', (tester) async {
    await tester.runAsync(() async {
      final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
      await cache.saveDraft(
        sourceLabel: '截圖自介',
        flow: OpenerDraftFlow(
          stage: OpenerDraftFlowStage.analyzing,
          contributionDraft: const OpenerContributionDraft(freeText: '想從狗開'),
          analysisRequestId: 'req-pending-quota',
          inputFingerprint: _analysisFingerprint,
          pendingAnalysis: const OpenerPendingAnalysis(
              bio: '有養一隻狗，假日會去河堤', initialNote: '想從狗開'),
        ),
      );
    });
    _paywallOpens = 0;
    await _pumpManualWithPaywall(tester);
    service.analyzeError = const OpenerQuotaExceededException(
        message: '今日額度不足。',
        dailyRemaining: 1,
        quotaNeeded: 3,
        isMonthly: false);
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    await _tapAndSettleAsync(tester, find.text('回看'),
        until: find.byKey(const ValueKey('opener-upgrade-button')));

    expect(service.analyzeCalls, 1, reason: '回看照舊自動續分析');
    expect(_paywallOpens, 0, reason: '自動續分析撞到額度不自動開付費頁');
    expect(find.byKey(const ValueKey('opener-upgrade-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opener-upgrade-button')));
    await _settleBounded(tester);
    expect(_paywallOpens, 1, reason: '自己按升級才開');
  });

  testWidgets('額度不足：生成被伺服器擋下、關掉付費牆後，錯誤下方給「升級方案」不給「再試一次」', (tester) async {
    _paywallOpens = 0;
    await _pumpManualWithPaywall(tester);
    await _analyze(tester);
    // service 只帶結構化資料；說明由畫面照方案組（免費：照舊說升級）。
    service.generateError = const OpenerQuotaExceededException(
        message: '本月額度不足。', monthlyRemaining: 0);
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-generate-button')),
        until: find.text('關閉付費牆'));
    expect(_paywallOpens, 1, reason: '伺服器擋下後自動開一次付費牆');
    await tester.tap(find.text('關閉付費牆'));
    await _settleBounded(tester);
    expect(
        find.text('本月額度不足，每月 1 號早上 8 點恢復；也可以升級取得更多開場與分析額度。'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-retry-button')), findsNothing,
        reason: '同一筆再試只會再被擋');
    expect(find.byKey(const ValueKey('opener-upgrade-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opener-upgrade-button')));
    await _settleBounded(tester);
    expect(_paywallOpens, 2);
    expect(service.generateCalls, 1);
  });

  // 額度說法照方案（Eric 2026-10-18）：生成走真的 OpenerService 傳輸，伺服器回額度
  // 429（它的 message 不分方案、一律叫人升級），畫面要照目前方案說。payload 照伺服器
  // 帶 quotaScope（本月或今日只看它，主審第 1 輪 P2-1）。
  Map<String, dynamic> quota429({required bool monthly}) => {
        'error': '額度不足',
        'message': monthly
            ? '本月額度不足，升級方案可取得更多開場與分析額度。'
            : '今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。',
        'quotaScope': monthly ? 'monthly' : 'daily',
        'quotaNeeded': 3,
        'monthlyRemaining': monthly ? 1 : 500,
        'dailyRemaining': monthly ? 20 : 1,
        'monthlyLimit': 800,
        'dailyLimit': 50,
      };

  /// 生成撞到伺服器額度 429：付費牆自動打開時，讀底下錯誤列的說明與按鈕，再關掉付費牆。
  /// 趁付費牆蓋著時讀：這個測試樹的訂閱刷新沒登入，關掉付費牆後方案會被刷成免費。
  Future<({String message, String button})> generateIntoQuota(
      WidgetTester tester,
      {required String tier,
      required bool monthly,
      Map<String, dynamic>? payload}) async {
    _paywallOpens = 0;
    await _pumpManualWithPaywall(tester, tier: tier);
    await _analyze(tester);
    final body = payload ?? quota429(monthly: monthly);
    _generateTransport = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(body))), 429,
          headers: {'content-type': 'application/json'});
    });
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-generate-button')),
        until: find.text('關閉付費牆'));
    expect(_paywallOpens, 1, reason: '伺服器擋下後自動開一次付費牆');
    final shown = (
      message: tester
          .widget<Text>(find.byKey(const ValueKey('opener-flow-error'),
              skipOffstage: false))
          .data!,
      button: tester
          .widget<Text>(find.descendant(
              of: find.byKey(const ValueKey('opener-upgrade-button'),
                  skipOffstage: false),
              matching: find.byType(Text, skipOffstage: false),
              skipOffstage: false))
          .data!,
    );
    await tester.tap(find.text('關閉付費牆'));
    await _settleBounded(tester);
    return shown;
  }

  /// 錯誤下方的鈕再開一次付費頁；兩次都照每月或每日換大標。本月或今日都還剩 1 則、
  /// 不夠這次的 3 則：付費頁說「不夠這次用」。
  Future<void> reopenPaywall(WidgetTester tester,
      {required bool monthly}) async {
    await tester.tap(find.byKey(const ValueKey('opener-upgrade-button')));
    await _settleBounded(tester);
    final entry = PaywallEntry.forQuota(isMonthly: monthly, remaining: 1);
    expect(_paywallExtras, [entry, entry]);
  }

  for (final monthly in [false, true]) {
    final period = monthly ? '本月' : '今日';
    final resetLine = monthly ? kMonthlyQuotaResetLine : kDailyQuotaResetLine;
    final otherResetLine =
        monthly ? kDailyQuotaResetLine : kMonthlyQuotaResetLine;
    testWidgets('$period額度不足：Essential 不叫他升級，只說什麼時候恢復，鈕寫「查看方案」',
        (tester) async {
      final shown = await generateIntoQuota(tester,
          tier: SubscriptionTierHelper.essential, monthly: monthly);
      expect(shown.message, isNot(contains('升級')));
      expect(shown.message, contains(resetLine));
      expect(shown.message, isNot(contains(otherResetLine)));
      expect(shown.button, '查看方案');
      await reopenPaywall(tester, monthly: monthly);
    });

    for (final tier in [
      SubscriptionTierHelper.free,
      SubscriptionTierHelper.starter,
    ]) {
      testWidgets('$period額度不足：$tier 先說恢復時間再說升級能多用，不點名升級到 Starter',
          (tester) async {
        final shown =
            await generateIntoQuota(tester, tier: tier, monthly: monthly);
        expect(
            shown.message,
            monthly
                ? '本月額度不足，$kMonthlyQuotaResetLine；也可以升級取得更多開場與分析額度。'
                : '今日額度不足，$kDailyQuotaResetLine；也可以升級取得更多額度。');
        expect(shown.message, isNot(contains('Starter')));
        expect(shown.button, '升級方案');
        await reopenPaywall(tester, monthly: monthly);
      });
    }
  }

  // 結算競態（主審第 1 輪 P2-1）：剩餘數是預查時的舊值（本月剩 3、這次要 3，看起來還夠），
  // 只有伺服器的 quotaScope 說是本月擋下。Essential 要看到每月恢復、付費頁開本月入口。
  testWidgets('結算競態：quotaScope 說本月、剩餘數是舊值，Essential 看到每月恢復、付費頁開本月入口',
      (tester) async {
    final shown = await generateIntoQuota(tester,
        tier: SubscriptionTierHelper.essential,
        monthly: true,
        payload: {
          'error': '額度不足',
          'message': '本月額度不足，升級方案可取得更多開場與分析額度。',
          'quotaScope': 'monthly',
          'quotaNeeded': 3,
          'monthlyRemaining': 3,
          'dailyRemaining': 10,
          'monthlyLimit': 800,
          'dailyLimit': 50,
        });
    expect(shown.message, contains(kMonthlyQuotaResetLine));
    expect(shown.message, isNot(contains(kDailyQuotaResetLine)));
    expect(shown.message, isNot(contains('升級')));
    expect(
        _paywallExtras, [PaywallEntry.forQuota(isMonthly: true, remaining: 3)]);
  });

  // 方案來源不一致（主審第 1 輪 P2-3）：RevenueCat 已是 Essential、訂閱快照還是 Starter。
  // 請求照舊帶 RevenueCat 較高的方案；說明、按鈕跟真的付費頁大標都照訂閱方案，三者一致。
  testWidgets('RevenueCat 是 Essential、訂閱快照是 Starter：說明、按鈕跟真的付費頁大標都照訂閱方案',
      (tester) async {
    RevenueCatService.debugGetCustomerInfoOverride =
        () async => _essentialCustomerInfo();
    addTearDown(() => RevenueCatService.debugGetCustomerInfoOverride = null);
    await _pumpManualWithRealPaywall(tester,
        tier: SubscriptionTierHelper.starter);
    await _analyze(tester);
    _generateTransport = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(quota429(monthly: false)))), 429,
          headers: {'content-type': 'application/json'});
    });
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-generate-button')),
        until: find.byType(PaywallScreen));
    expect(service.lastExpectedTier, SubscriptionTierHelper.essential,
        reason: '請求照舊帶 RevenueCat 較高的方案');
    expect(_paywallExtras,
        [PaywallEntry.forQuota(isMonthly: false, remaining: 1)]);
    expect(
        find.text(PaywallEntry.dailyQuotaShort
            .headlineFor(SubscriptionTierHelper.starter)),
        findsOneWidget,
        reason: '真的付費頁照訂閱方案出大標');
    final message = tester
        .widget<Text>(find.byKey(const ValueKey('opener-flow-error'),
            skipOffstage: false))
        .data!;
    expect(message, '今日額度不足，$kDailyQuotaResetLine；也可以升級取得更多額度。');
    final button = tester
        .widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('opener-upgrade-button'),
                skipOffstage: false),
            matching: find.byType(Text, skipOffstage: false),
            skipOffstage: false))
        .data!;
    expect(button, '升級方案');
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

  Future<void> failAnalysisWithNote(WidgetTester tester) async {
    service.analyzeError = Exception('network');
    await _pumpManual(tester);
    await tester.enterText(
        find.byKey(const ValueKey('opener-initial-note')), '想從狗開');
    await _analyze(tester, until: find.text('重新分析'));
    expect(service.lastInitialUserNote, '想從狗開');
    service.analyzeError = null;
  }

  testWidgets('分析失敗後改補充再按「重新分析」→送出改過的補充', (tester) async {
    await failAnalysisWithNote(tester);
    final failedRequestId = service.lastAnalysisRequestId;
    await tester.enterText(
        find.byKey(const ValueKey('opener-initial-note')), '想聊河堤散步');
    await tester.pump();
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-analyze-button')),
        until: find.byKey(const ValueKey('opener-approach-summary')));
    expect(service.analyzeCalls, 2);
    expect(service.lastInitialUserNote, '想聊河堤散步', reason: '不再重送舊補充');
    expect(service.lastAnalysisRequestId, isNot(failedRequestId),
        reason: '補充變了是新的一次分析');
  });

  testWidgets('分析失敗後補充沒改再按「重新分析」→沿用同一個 analysisRequestId', (tester) async {
    await failAnalysisWithNote(tester);
    final failedRequestId = service.lastAnalysisRequestId;
    await _tapAndSettleAsync(
        tester, find.byKey(const ValueKey('opener-analyze-button')),
        until: find.byKey(const ValueKey('opener-approach-summary')));
    expect(service.analyzeCalls, 2);
    expect(service.lastInitialUserNote, '想從狗開');
    expect(service.lastAnalysisRequestId, failedRequestId);
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

  // onboarding 轉換第 6 步：告訴使用者「額度不夠」的那一刻記一筆 quota_block_shown，
  // 只是記錄；付費牆與錯誤列照舊。
  for (final monthly in [false, true]) {
    final scope = monthly ? 'monthly' : 'daily';
    testWidgets('額度不足事件：生成撞到伺服器額度（429）記一筆 opener／$scope／server；再開付費頁不重記',
        (tester) async {
      await generateIntoQuota(tester,
          tier: SubscriptionTierHelper.free, monthly: monthly);
      expect(_quotaBlocks(), [
        {'feature': 'opener', 'scope': scope, 'block_source': 'server'},
      ]);

      await tester.tap(find.byKey(const ValueKey('opener-upgrade-button')));
      await _settleBounded(tester);
      expect(_paywallOpens, 2);
      expect(_quotaBlocks(), hasLength(1));
    });
  }

  testWidgets('額度不足事件：舊單段生成前 App 先擋（今天用完）記一筆 opener／daily／precheck，不送出',
      (tester) async {
    service.analyzeError = const OpenerFlowException(
        code: OpenerFlowErrorCode.flowUnsupported, message: 'x', status: 400);
    _paywallOpens = 0;
    await tester.binding.setSurfaceSize(const Size(390, 4200));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._screenOverrides(SubscriptionTierHelper.free,
              stickySubscription: const SubscriptionState(
                  monthlyLimit: 30, dailyLimit: 10, dailyMessagesUsed: 10)),
          subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          // 本機用量預設讀 Hive usage box（這個測試沒開）。
          usageDataProvider.overrideWithValue(UsageData(
              monthlyUsed: 0,
              monthlyLimit: 30,
              dailyUsed: 10,
              dailyLimit: 10,
              dailyResetAt: DateTime(2026, 10, 28),
              tier: SubscriptionTierHelper.free)),
        ],
        child: MaterialApp.router(
            routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const OpeningRescueScreen()),
          GoRoute(
              path: '/paywall',
              builder: (context, state) {
                _paywallOpens++;
                return Scaffold(
                    body: Center(
                        child: TextButton(
                            onPressed: () => context.pop(),
                            child: const Text('關閉付費牆'))));
              }),
        ]))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('手動輸入'));
    await tester.pumpAndSettle();
    await _analyze(tester, until: find.text('生成開場白'));

    await _tapAndSettleAsync(tester, find.text('生成開場白'),
        until: find.text('關閉付費牆'));

    expect(_paywallOpens, 1);
    expect(_quotaBlocks(), [
      {'feature': 'opener', 'scope': 'daily', 'block_source': 'precheck'},
    ]);
    expect(service.legacyCalls, 0);
  });
}
