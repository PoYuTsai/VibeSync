import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/new_topic/data/providers/new_topic_providers.dart';
import 'package:vibesync/features/new_topic/data/services/new_topic_service.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';
import 'package:vibesync/features/new_topic/domain/new_topic_two_stage_copy.dart';
import 'package:vibesync/features/new_topic/domain/services/new_topic_partner_context_builder.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_view.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';
import 'package:vibesync/shared/widgets/brand/opener_home_components.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/quota_copy.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import '../../../visual_proof/proof_support.dart';

/// 這次測試的方案（預設免費）。
String subTier = 'free';

class _Sub extends SubscriptionNotifier {
  _Sub() {
    state = SubscriptionState(tier: subTier, monthlyLimit: 30, dailyLimit: 15);
  }

  /// 伺服器回額度不足後，刷新拿到的用量：今日只剩 1 則。
  void exhaustDaily() => state = SubscriptionState(
      tier: subTier, monthlyLimit: 30, dailyLimit: 15, dailyMessagesUsed: 14);

  /// 同上，換成本月只剩 2 則。
  void exhaustMonthly() => state = SubscriptionState(
      tier: subTier, monthlyLimit: 30, dailyLimit: 15, monthlyMessagesUsed: 28);

  /// 訂閱狀態同步成另一個方案（例如用戶剛升級）。
  void setTier(String tier) {
    subTier = tier;
    state = SubscriptionState(tier: tier, monthlyLimit: 30, dailyLimit: 15);
  }
}

class _FakeService extends NewTopicService {
  final calls = <Map<String, String?>>[];
  final replies = <Completer<NewTopicResult>>[];
  void Function(String, String?)? progress;
  @override
  Future<NewTopicResult> generateTopicsStreaming(
      {required String requestId,
      String? partnerSummary,
      String? effectiveStyleContext,
      String? situation,
      Map<String, dynamic>? topicContext,
      String? expectedTier,
      String? revenueCatAppUserId,
      void Function(String, String?)? onProgress}) {
    progress = onProgress;
    calls.add({
      'id': requestId,
      'summary': partnerSummary,
      'style': effectiveStyleContext,
      'situation': situation,
      'topicContext': topicContext == null ? null : jsonEncode(topicContext),
      'tier': expectedTier,
      'rc': revenueCatAppUserId
    });
    final reply = Completer<NewTopicResult>();
    replies.add(reply);
    return reply.future;
  }
}

NewTopicResult _result(String id) => NewTopicResult(
        topics: const [
          NewTopicIdea(
              id: 'nt_1',
              direction: '從週末的散步聊起',
              openingLine: '最近有找到喜歡的散步路線嗎？',
              whyItWorks: '延續你們已聊過的興趣。',
              nextMove: '先接住她的分享。')
        ],
        recommendation: const NewTopicRecommendation(topicId: 'nt_1'),
        access: const NewTopicAccess(
            servedTier: 'free',
            limited: true,
            totalCount: 5,
            unlockedCount: 1,
            lockedCount: 4),
        costUsed: 3,
        requestId: id);
Partner _partner(String id, {String? avatar}) => Partner(
    id: id,
    name: '合成對象 $id',
    avatarPath: avatar,
    ownerUserId: 'a',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026));

final _root = GlobalKey();
final _active = ValueNotifier(true);
final _visible = ValueNotifier(true);
late _FakeService _service;
late StreamController<String?> ownerEvents;
String owner = 'a';
List<Partner> partners = [];
String? style;

/// 對象作戰板有沒有可用的訊號（預設沒有）。測試要「素材夠、可以生成」時設 true；
/// 「關於我」只給 Coach 1:1，style 不算新話題素材（2026-10-20）。
bool signals = false;

/// 對象作戰板脈絡（預設空的）；要看送出的 partnerSummary 時換成 [_contextWith]。
NewTopicPartnerContext partnerContext = NewTopicPartnerContext.empty;

NewTopicPartnerContext _contextWith(String promptText) => NewTopicPartnerContext(
    promptText: promptText,
    hasActionableSignals: true,
    hasHeatSignal: false,
    hasInterestSignals: true,
    hasTraitSignals: false,
    hasNoteSignals: false);
bool blocked = false;
bool refreshFails = false;
Completer<void>? refreshGate;
Future<String?> Function()? styleLoader;

/// 有 /paywall 路由時（[_pump] 的 paywallRoute）記開了幾次付費牆、依序帶的入口。
int paywallOpens = 0;
final paywallExtras = <Object?>[];

/// 送出的去識別化漏斗事件（submit-feedback 的 body）。
final funnelBodies = <Map<String, dynamic>>[];

/// 額度不足事件（quota_block_shown）帶的屬性，照送出順序。
List<Object?> _quotaBlocks() => [
      for (final body in funnelBodies)
        if ((body['event'] as Map)['event'] == 'quota_block_shown')
          (body['event'] as Map)['properties'],
    ];

Future<ProviderContainer> _pump(WidgetTester t,
    {String? selected = 'p',
    double scale = 1,
    Size size = const Size(390, 844),
    bool paywallRoute = false}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  Widget app(Widget home) => paywallRoute
      ? MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC'),
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => home),
            GoRoute(
                path: '/paywall',
                builder: (context, state) {
                  paywallOpens++;
                  paywallExtras.add(state.extra);
                  return Scaffold(
                      body: Center(
                          child: TextButton(
                              onPressed: () => context.pop(),
                              child: const Text('關閉付費牆'))));
                }),
          ]))
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC'),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: home);
  await t.pumpWidget(ProviderScope(
      overrides: [
        authConversationScopeProvider.overrideWith((_) => ownerEvents.stream),
        partnerListProvider.overrideWith((_) => partners),
        partnerByIdProvider.overrideWith(
            (_, id) => partners.where((p) => p.id == id).firstOrNull),
        conversationsByPartnerProvider.overrideWith((_, id) => []),
        newTopicPartnerContextProvider.overrideWith((_, id) => partnerContext),
        newTopicReadinessProvider.overrideWith((_, id) => blocked
            ? NewTopicReadiness.dataQualityBlocked
            : signals
                ? NewTopicReadiness.readyWithPartnerSignals
                : NewTopicReadiness.readyWithoutPartnerSignals),
        newTopicStyleContextProvider.overrideWith(
            (_, id) => styleLoader?.call() ?? Future.value(style)),
        subscriptionProvider.overrideWith((_) => _Sub()),
        funnelTrackerProvider.overrideWithValue(FunnelTracker(
            currentUserId: () => 'u1',
            invoker: (_, {required body}) async {
              funnelBodies.add(body);
              return 200;
            })),
        subscriptionScreenRefreshProvider.overrideWith((_) => () async {
              if (refreshFails) throw StateError('offline');
              await refreshGate?.future;
            }),
      ],
      child: RepaintBoundary(
          key: _root,
          child: app(Scaffold(
              backgroundColor: OpenerHomeStyle.canvas,
              body: SafeArea(
                  child: ValueListenableBuilder<bool>(
                      valueListenable: _active,
                      builder: (_, active, __) =>
                          IndexedStack(index: active ? 0 : 1, children: [
                            ValueListenableBuilder<bool>(
                                valueListenable: _visible,
                                builder: (_, visible, __) => visible
                                    ? NewTopicView(
                                        initialPartnerId: selected,
                                        isActive: active)
                                    : const SizedBox.shrink()),
                            const Center(child: Text('另一個模式'))
                          ]))))))));
  await t.pump(const Duration(milliseconds: 250));
  ownerEvents.add(owner);
  await t.pump();
  return ProviderScope.containerOf(
      t.element(find.byType(NewTopicView, skipOffstage: false)));
}

ElevatedButton _button(WidgetTester t) =>
    t.widget<ElevatedButton>(find.byKey(const ValueKey('new-topic-generate')));
Future<void> _tapGenerate(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('new-topic-generate')));
  await t.tap(find.byKey(const ValueKey('new-topic-generate')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _tapVisible(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pump();
}

Finder _key(String key) => find.byKey(ValueKey(key));
final _materialField = _key('new-topic-material-text');
bool _chipSelected(WidgetTester t, String key) =>
    t.widget<BrandChoiceChip>(_key(key)).selected;
String _materialText(WidgetTester t) =>
    t.widget<TextField>(_materialField).controller!.text;
Future<void> _typeMaterial(WidgetTester t, String text) async {
  await t.ensureVisible(_materialField);
  await t.enterText(_materialField, text);
  await t.pump();
}

Future<void> _capture(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 250));
  expect(t.takeException(), isNull);
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(find.byKey(_root))
        .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/visual_proof/v3/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadProofFonts);
  setUp(() {
    paywallOpens = 0;
    paywallExtras.clear();
    subTier = 'free';
    funnelBodies.clear();
    owner = 'a';
    partners = [_partner('p')];
    style = null;
    signals = false;
    partnerContext = NewTopicPartnerContext.empty;
    blocked = false;
    refreshFails = false;
    refreshGate = null;
    styleLoader = null;
    _active.value = true;
    _visible.value = true;
    ownerEvents = StreamController<String?>.broadcast();
    _service = _FakeService();
    NewTopicView.debugOwnerIdOverride = () => owner;
    NewTopicView.debugServiceFactory = () => _service;
    AiDataSharingConsent.debugUserIdOverride = () => owner;
    SharedPreferences.setMockInitialValues(
        {'${AiDataSharingConsent.acceptedKeyForTesting}::a': true});
  });
  tearDown(() async {
    NewTopicView.debugOwnerIdOverride = null;
    NewTopicView.debugServiceFactory = null;
    AiDataSharingConsent.debugUserIdOverride = null;
    await ownerEvents.close();
  });


  testWidgets('額度不足：伺服器回過額度不足的那筆不再顯示「重試／將使用 3 則」，主按鈕改成升級方案', (t) async {
    signals = true;
    final container = await _pump(t, paywallRoute: true);
    await _tapGenerate(t);
    // 擋下的是今日額度：畫面照目前方案（免費）組說明（主審第 1 輪 P2-2）。
    _service.replies.single.completeError(const NewTopicQuotaExceededException(
        message: '今日額度不足。',
        dailyRemaining: 1,
        quotaNeeded: 3,
        isMonthly: false));
    // 伺服器擋下後會自動開一次付費牆；刷新拿到今日只剩 1 則。
    (container.read(subscriptionProvider.notifier) as _Sub).exhaustDaily();
    await t.pumpAndSettle();
    expect(paywallOpens, 1);
    await t.tap(find.text('關閉付費牆'));
    await t.pumpAndSettle();
    expect(find.text('今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。'), findsOneWidget);
    expect(find.text('重試'), findsNothing);
    expect(find.text('將使用 3 則額度'), findsNothing);
    expect(find.text(NewTopicView.upgradeButtonLabel), findsOneWidget);
    expect(find.text('本次需要 3 則，目前可用額度不足。'), findsOneWidget);
    expect(_button(t).onPressed, isNotNull);
    await _tapGenerate(t);
    await t.pumpAndSettle();
    expect(paywallOpens, 2, reason: '升級方案直接開付費牆');
    expect(_service.calls, hasLength(1), reason: '不會再送同一筆去撞額度');
  });

  // 額度說法照方案（Eric 2026-10-18）：生成走真的 NewTopicService 傳輸，伺服器回額度
  // 429（它的 message 不分方案、一律叫人升級），畫面照目前方案說。payload 照伺服器帶
  // quotaScope（本月或今日只看它，主審第 1 輪 P2-1）。
  Map<String, dynamic> quota429({required bool monthly}) => {
        'error': '額度不足',
        'message': monthly
            ? '本月額度不足，升級方案可取得更多新話題與分析額度。'
            : '今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。',
        'quotaScope': monthly ? 'monthly' : 'daily',
        'quotaNeeded': 3,
        'monthlyRemaining': monthly ? 2 : 500,
        'dailyRemaining': monthly ? 10 : 1,
        'monthlyLimit': 800,
        'dailyLimit': 50,
      };

  var quotaRequests = 0;

  /// 生成撞到伺服器額度 429、關掉自動開的付費牆後，回傳畫面上的額度說明。
  Future<String> generateIntoQuota(WidgetTester t,
      {required String tier,
      required bool monthly,
      Map<String, dynamic>? payload}) async {
    final body = payload ?? quota429(monthly: monthly);
    subTier = tier;
    signals = true;
    quotaRequests = 0;
    NewTopicView.debugServiceFactory = () => NewTopicService(
          accessTokenProvider: () => 'token',
          streamClientFactory: () =>
              MockClient.streaming((request, bodyStream) async {
            await bodyStream.drain<void>();
            quotaRequests++;
            return http.StreamedResponse(
                Stream.value(utf8.encode(jsonEncode(body))), 429,
                headers: {'content-type': 'application/json'});
          }),
        );
    final container = await _pump(t, paywallRoute: true);
    await _tapGenerate(t);
    // 伺服器擋下後會自動開一次付費牆；刷新拿到的用量也不夠這次的 3 則。
    final sub = container.read(subscriptionProvider.notifier) as _Sub;
    monthly ? sub.exhaustMonthly() : sub.exhaustDaily();
    await t.pumpAndSettle();
    expect(paywallOpens, 1);
    // 說明在付費牆滑上來之前就寫好了；付費方案關掉付費牆後這行會收掉（既有行為），
    // 所以趁付費牆還蓋著時讀。
    final message =
        t.widget<Text>(find.textContaining('額度不足，', skipOffstage: false)).data!;
    await t.tap(find.text('關閉付費牆'));
    await t.pumpAndSettle();
    return message;
  }

  String quotaButtonLabel(WidgetTester t) => t
      .widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('new-topic-generate')),
          matching: find.byType(Text)))
      .data!;

  /// 額度不夠時主按鈕再開付費頁。兩次的入口：伺服器擋下那次照它回的剩餘、按鈕那次照
  /// 刷新後的用量（先看本月、再看今天）；本月剩 2 則、或今日剩 1 則，都說「不夠這次用」。
  Future<void> tapQuotaButton(WidgetTester t, {required bool monthly}) async {
    await _tapGenerate(t);
    await t.pumpAndSettle();
    final entry =
        PaywallEntry.forQuota(isMonthly: monthly, remaining: monthly ? 2 : 1);
    expect(paywallExtras, [entry, entry]);
    expect(quotaRequests, 1, reason: '不會再送同一筆去撞額度');
  }

  for (final monthly in [false, true]) {
    final period = monthly ? '本月' : '今日';
    final resetLine = monthly ? kMonthlyQuotaResetLine : kDailyQuotaResetLine;
    final otherResetLine =
        monthly ? kDailyQuotaResetLine : kMonthlyQuotaResetLine;
    testWidgets('$period額度不足：Essential 不叫他升級，只說什麼時候恢復，主按鈕寫「查看方案」', (t) async {
      final message = await generateIntoQuota(t,
          tier: SubscriptionTierHelper.essential, monthly: monthly);
      expect(message, isNot(contains('升級')));
      expect(message, contains(resetLine));
      expect(message, isNot(contains(otherResetLine)));
      expect(quotaButtonLabel(t), '查看方案');
      await tapQuotaButton(t, monthly: monthly);
    });

    for (final tier in [
      SubscriptionTierHelper.free,
      SubscriptionTierHelper.starter,
    ]) {
      testWidgets('$period額度不足：$tier 照舊說升級能多用，不點名升級到 Starter', (t) async {
        final message =
            await generateIntoQuota(t, tier: tier, monthly: monthly);
        expect(
            message,
            monthly
                ? '本月額度不足，升級方案可取得更多新話題與分析額度。'
                : '今日額度不足，$kDailyQuotaResetLine；也可以升級取得更多額度。');
        expect(message, isNot(contains('Starter')));
        expect(quotaButtonLabel(t), NewTopicView.upgradeButtonLabel);
        await tapQuotaButton(t, monthly: monthly);
      });
    }
  }

  // 結算競態（主審第 1 輪 P2-1）：剩餘數是預查時的舊值（本月剩 3、這次要 3，看起來還夠），
  // 只有伺服器的 quotaScope 說是本月擋下。Essential 要看到每月恢復、付費頁開本月入口。
  testWidgets('結算競態：quotaScope 說本月、剩餘數是舊值，Essential 看到每月恢復、付費頁開本月入口',
      (t) async {
    final message = await generateIntoQuota(t,
        tier: SubscriptionTierHelper.essential,
        monthly: true,
        payload: {
          'error': '額度不足',
          'message': '本月額度不足，升級方案可取得更多新話題與分析額度。',
          'quotaScope': 'monthly',
          'quotaNeeded': 3,
          'monthlyRemaining': 3,
          'dailyRemaining': 10,
          'monthlyLimit': 800,
          'dailyLimit': 50,
        });
    expect(message, contains(kMonthlyQuotaResetLine));
    expect(message, isNot(contains(kDailyQuotaResetLine)));
    expect(message, isNot(contains('升級')));
    expect(paywallExtras.first,
        PaywallEntry.forQuota(isMonthly: true, remaining: 3));
  });

  // 升級後重試（主審第 1 輪 P2-2）：上一筆以 Starter 送出、連線中斷沒拿到結果（自動接回
  // 一次也斷），留著待重試；用戶之後升級成 Essential，回來重試同一筆（請求照舊帶原本的
  // expectedTier），伺服器回額度 429。說明照目前的訂閱方案（Essential）說，不照那筆請求
  // 帶的方案。
  testWidgets('升級後重試：待重試那筆是 Starter 送的，現在是 Essential，429 只說什麼時候恢復', (t) async {
    subTier = SubscriptionTierHelper.starter;
    signals = true;
    final sentTiers = <Object?>[];
    NewTopicView.debugServiceFactory = () => NewTopicService(
          accessTokenProvider: () => 'token',
          streamClientFactory: () =>
              MockClient.streaming((request, bodyStream) async {
            final sent = jsonDecode(await utf8.decodeStream(bodyStream))
                as Map<String, dynamic>;
            sentTiers.add(sent['expectedTier']);
            if (sentTiers.length <= 2) {
              throw http.ClientException('connection closed');
            }
            return http.StreamedResponse(
                Stream.value(utf8.encode(jsonEncode(quota429(monthly: false)))),
                429,
                headers: {'content-type': 'application/json'});
          }),
        );
    final container = await _pump(t, paywallRoute: true);
    await _tapGenerate(t);
    await t.pumpAndSettle();
    expect(find.text('重試'), findsOneWidget, reason: '連線中斷：那筆留著待重試');
    final sub = container.read(subscriptionProvider.notifier) as _Sub;
    sub.setTier(SubscriptionTierHelper.essential);
    await t.pump();
    await _tapGenerate(t);
    // 伺服器擋下後會自動開一次付費牆；刷新拿到的用量也不夠這次的 3 則。
    sub.exhaustDaily();
    await t.pumpAndSettle();
    expect(sentTiers, List.filled(3, SubscriptionTierHelper.starter),
        reason: '重試照舊送原本那筆的請求資料');
    expect(paywallOpens, 1);
    expect(
        paywallExtras, [PaywallEntry.forQuota(isMonthly: false, remaining: 1)]);
    final message =
        t.widget<Text>(find.textContaining('額度不足，', skipOffstage: false)).data!;
    expect(message, contains(kDailyQuotaResetLine));
    expect(message, isNot(contains('升級')));
    await t.tap(find.text('關閉付費牆'));
    await t.pumpAndSettle();
    expect(quotaButtonLabel(t), NewTopicView.viewPlansButtonLabel);
  });

  testWidgets('請求編號已用於不同內容（409）：顯示訊息、不留重試，再按生成換新編號', (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    final first = _service.calls.single['id'];
    _service.replies.single.completeError(const NewTopicReplayMismatchException(
        '這筆請求編號已用於不同內容，請重新生成一次。本次不會扣額度。'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('這筆請求編號已用於不同內容，請重新生成一次。本次不會扣額度。'), findsOneWidget);
    expect(find.text('重試'), findsNothing);
    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls.last['id'], isNot(first));
  });

  testWidgets('複製開場句送出去識別化事件：只記是不是推薦那題，不含句子', (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 600));
    await t.ensureVisible(find.text('複製').first);
    await t.tap(find.text('複製').first);
    await t.pump(const Duration(milliseconds: 300));
    final copied = funnelBodies
        .map((b) => b['event'] as Map<String, dynamic>)
        .where((e) => e['event'] == 'new_topic_copied')
        .toList();
    expect(copied, hasLength(1));
    expect(copied.single['properties'], {'is_recommended': true});
    expect(jsonEncode(funnelBodies).contains('最近有找到喜歡的散步路線嗎'), isFalse);
  });

  testWidgets('串流第一個事件與結果緊接著到：兩段「捲到進度」動畫重疊，結果照樣定格', (t) async {
    await _pump(t);
    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '路過一家甜點店');
    await _tapGenerate(t);
    // 第一段動畫還在跑時串流事件到：第二段動畫取消第一段。
    _service.progress?.call('開始寫五個新話題', 'topics');
    await t.pump();
    // 第二段還在跑時結果到。
    final id = _service.calls.single['id']!;
    _service.replies.single.complete(NewTopicResult(
        topics: [
          for (var n = 1; n <= 5; n++)
            NewTopicIdea(
                id: 'nt_$n',
                direction: '第 $n 個方向',
                openingLine: '第 $n 句可以直接傳的開場，長一點才會把結果區撐得比畫面高',
                whyItWorks: '為什麼現在有效的說明，寫兩行左右的長度，讓卡片有正常的高度。',
                nextMove: '她回了之後怎麼接的說明，也寫兩行左右的長度，讓卡片有正常的高度。')
        ],
        recommendation: const NewTopicRecommendation(topicId: 'nt_1'),
        access: const NewTopicAccess(
            servedTier: 'starter',
            limited: false,
            totalCount: 5,
            unlockedCount: 5,
            lockedCount: 0),
        costUsed: 3,
        requestId: id));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final viewport = t.getRect(find.byType(SingleChildScrollView).first);
    final adjust = t.getRect(_key('new-topic-adjust'));
    expect(adjust.top, greaterThanOrEqualTo(viewport.top), reason: '$adjust / $viewport');
    expect(adjust.top, lessThan(viewport.top + 80), reason: '定格在結果區頂端，不是停在原地');
  });

  testWidgets('生成中：按下後捲到看得到進度，串流狀態列出現時也看得到', (t) async {
    await _pump(t);
    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '路過一家甜點店');
    await _tapGenerate(t);
    await t.pump(const Duration(milliseconds: 400));
    final viewport = t.getRect(find.byType(SingleChildScrollView).first);
    // 生成鈕固定在底部，捲動區的下緣就在它上面；進度那一行要整行在捲動區裡。
    final local = t.getRect(find.text(NewTopicView.progressPhrases.first));
    expect(local.bottom, lessThanOrEqualTo(viewport.bottom), reason: '$local / $viewport');
    _service.progress?.call('開始寫五個新話題', 'topics');
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final ticker = t.getRect(find.byKey(const ValueKey('stream-progress-ticker')));
    expect(ticker.bottom, lessThanOrEqualTo(viewport.bottom), reason: '$ticker / $viewport');
    expect(ticker.top, greaterThanOrEqualTo(viewport.top));
  });

  testWidgets('完成後定格在結果區頂端：五張題卡比畫面高也不會把「這組根據／調整狀況」捲過頭', (t) async {
    await _pump(t);
    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '路過一家甜點店');
    await _tapGenerate(t);
    // 結果在「捲到看得到進度」的動畫還沒跑完就回來（例如重播）：那不是用戶在捲，照樣定格。
    final id = _service.calls.single['id']!;
    _service.replies.single.complete(NewTopicResult(
        topics: [
          for (var n = 1; n <= 5; n++)
            NewTopicIdea(
                id: 'nt_$n',
                direction: '第 $n 個方向',
                openingLine: '第 $n 句可以直接傳的開場，長一點才會把結果區撐得比畫面高',
                whyItWorks: '為什麼現在有效的說明，寫兩行左右的長度，讓卡片有正常的高度。',
                nextMove: '她回了之後怎麼接的說明，也寫兩行左右的長度，讓卡片有正常的高度。')
        ],
        recommendation: const NewTopicRecommendation(topicId: 'nt_1'),
        access: const NewTopicAccess(
            servedTier: 'starter',
            limited: false,
            totalCount: 5,
            unlockedCount: 5,
            lockedCount: 0),
        costUsed: 3,
        requestId: id));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final viewport = t.getRect(find.byType(SingleChildScrollView).first);
    final adjust = t.getRect(_key('new-topic-adjust'));
    expect(adjust.top, greaterThanOrEqualTo(viewport.top), reason: '$adjust / $viewport');
    expect(adjust.top, lessThan(viewport.top + 80), reason: '定格在結果區頂端，不是停在原地');
  });

  testWidgets('生成中離開並重建畫面，同答案送出相同 requestId', (t) async {
    signals = true;
    await _pump(t);
    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '路過一家甜點店');
    await _tapGenerate(t);
    final first = _service.calls.single;
    _visible.value = false;
    await t.pump();
    expect(find.byType(NewTopicView), findsNothing);
    // 舊畫面已銷毀，即使請求完成也不能清掉尚未交付的 pending。
    _service.replies.first.complete(_result(first['id']!));
    await t.pump();
    _visible.value = true;
    await t.pump();
    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '路過一家甜點店');
    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls.last, first);
    _service.replies.last.complete(_result(first['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);
  });

  testWidgets('成功交付後離開再生成，送出新的 requestId', (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    final firstId = _service.calls.single['id']!;
    _service.replies.first.complete(_result(firstId));
    await t.pump(const Duration(milliseconds: 300));
    _visible.value = false;
    await t.pump();
    _visible.value = true;
    await t.pump();
    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls.last['id'], isNot(firstId));
    _service.replies.last.complete(_result(_service.calls.last['id']!));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('正式結果立即結束生成，不等待額度刷新', (t) async {
    signals = true;
    refreshGate = Completer<void>();
    await _pump(t);
    await _tapGenerate(t);
    _service.progress?.call('新話題 1/5', 'topic_1');
    await t.pump();
    expect(
        find.byKey(const ValueKey('stream-progress-ticker')), findsOneWidget);
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);
    expect(find.byKey(const ValueKey('stream-progress-ticker')), findsNothing);
    expect(find.text('新話題 1'), findsNothing);
    expect(_service.calls, hasLength(1));
    await _capture(t, 'topic-result-quota-pending');
    refreshGate!.completeError(StateError('refresh offline'));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);
    expect(_service.calls, hasLength(1));
  });

  testWidgets('階段開始沒有完成勾勾，最後確認收起骨架但不提早交付', (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    for (var n = 1; n <= 5; n++) {
      _service.progress?.call('新話題 $n/5', 'topic_$n');
    }
    await t.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('新話題 1'), findsOneWidget);
    _service.progress?.call('正在確認最後結果', 'finalizing');
    await t.pump();
    expect(find.text('新話題 1'), findsNothing);
    expect(
        find.byKey(const ValueKey('stream-progress-ticker')), findsOneWidget);
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsNothing);
    expect(_button(t).onPressed, isNull);
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('stream-progress-ticker')), findsNothing);
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);
  });

  testWidgets('已選對象的深色選取列保有文字對比，不出現亮白底', (t) async {
    partners = [_partner('p'), _partner('q')];
    await _pump(t);
    await t.tap(find.bySemanticsLabel('目前對象 合成對象 p，更換對象'));
    await t.pumpAndSettle();
    const proofLabel =
        String.fromEnvironment('PICKER_PROOF_LABEL', defaultValue: 'after');
    await _capture(t, 'topic-selected-picker-$proofLabel');

    final selected = find.byWidgetPredicate((w) => w is ListTile && w.selected);
    expect(selected, findsOneWidget);
    final tile = t.widget<ListTile>(selected);
    final material = t.widget<Material>(
        find.ancestor(of: selected, matching: find.byType(Material)).first);
    final label = tile.title! as Text;
    final background = material.color!;
    final foreground = label.style!.color!;
    final contrast = (foreground.computeLuminance() + 0.05) /
        (background.computeLuminance() + 0.05);
    expect(background.computeLuminance(), lessThan(0.1),
        reason: '深色底的選取列不能整條變成高亮度底色');
    expect(contrast, greaterThanOrEqualTo(4.5), reason: '白字與選取背景必須仍可清楚閱讀');
    expect(tile.trailing, isA<Icon>());
    await t.tap(find.text('合成對象 q'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('目前對象 合成對象 q，更換對象'), findsOneWidget);
  });

  testWidgets('NT-01/02/04/06 select, search empty and invalid ID are distinct',
      (t) async {
    await _pump(t, selected: 'foreign-id');
    expect(_button(t).onPressed, isNull);
    expect(find.text('合成對象 p'), findsNothing);
    await _capture(t, 'topic-no-selection');
    await t.tap(find.bySemanticsLabel('重新選擇聊天對象'));
    await t.pumpAndSettle();
    await _capture(t, 'topic-picker');
    await t.enterText(find.byType(TextField), 'missing');
    await t.pump();
    expect(find.text('找不到符合的對象，試試其他名字'), findsOneWidget);
    expect(find.textContaining('尚無其他對象'), findsNothing);
    await t.enterText(find.byType(TextField), '合成');
    await t.pump();
    await t.tap(find.text('合成對象 p'));
    await t.pumpAndSettle();
    expect(find.text('更換'), findsOneWidget);
    expect(_button(t).onPressed, isNull);
  });

  testWidgets(
      'NT-05/07/08/09/10/11 readiness reacts without treating name or avatar as material',
      (t) async {
    partners = [_partner('p', avatar: '/nonexistent/test.png')];
    final container = await _pump(t);
    expect(_button(t).onPressed, isNull);
    await _capture(t, 'topic-material-insufficient');
    await t.tap(find.text('冷掉了，想重新聊'));
    await t.pump();
    expect(_button(t).onPressed, isNotNull);
    await _capture(t, 'topic-selected-situation');
    await t.tap(find.text('冷掉了，想重新聊'));
    await t.pump();
    expect(_button(t).onPressed, isNull);
    style = '喜歡自然直白的語氣';
    container.invalidate(newTopicStyleContextProvider('p'));
    await t.pump();
    await t.pump();
    expect(_button(t).onPressed, isNull,
        reason: '「關於我」只給 Coach 1:1，不算新話題素材');
    signals = true;
    container.invalidate(newTopicReadinessProvider('p'));
    await t.pump();
    expect(_button(t).onPressed, isNotNull);
    blocked = true;
    container.invalidate(newTopicReadinessProvider('p'));
    await t.pump();
    await t.tap(find.text('聊得不錯，想更靠近'));
    await t.pump();
    expect(_button(t).onPressed, isNull);
    expect(_service.calls, isEmpty);
  });

  testWidgets(
      'NT-12 style loading stays loading then a failure permits actual situation material',
      (t) async {
    final wait = Completer<String?>();
    styleLoader = () => wait.future;
    await _pump(t);
    await t.tap(find.text('剛約完會'));
    await t.pump();
    expect(_button(t).onPressed, isNull);
    expect(find.text('正在整理可用素材…'), findsOneWidget);
    wait.completeError(StateError('offline'));
    await t.pump();
    expect(_button(t).onPressed, isNotNull);
    expect(find.text('重新載入個人風格'), findsOneWidget);
  });

  testWidgets(
      'NT-13 double tap consent has one preparation; cancellation releases lock',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    signals = true;
    await _pump(t);
    // Two real pointer taps before the disabled rebuild must still share one
    // preparation and one consent dialog.
    final generate = find.byKey(const ValueKey('new-topic-generate'));
    await t.ensureVisible(generate);
    await t.tap(generate);
    await t.tap(generate);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('資料使用說明'), findsOneWidget);
    expect(_service.calls, isEmpty);
    expect(_button(t).onPressed, isNull);
    await t.tap(find.text('暫不同意'));
    await t.pumpAndSettle();
    expect(_button(t).onPressed, isNotNull);
    expect(_service.calls, isEmpty);
  });

  testWidgets(
      'NT-16/17/21 retry freezes all fields despite provider updates and usage refresh failure',
      (t) async {
    signals = true;
    partnerContext = _contextWith('[對象作戰板：合成對象 p]\n- 興趣：散步（v1）');
    final container = await _pump(t);
    await _tapGenerate(t);
    expect(_service.calls, hasLength(1));
    expect(_service.calls[0]['summary'], contains('散步（v1）'));
    _service.replies[0].completeError(
        const NewTopicRequestInProgressException(message: '正在確認本次結果，請勿重複送出。'));
    await t.pump();
    expect(find.text('確認本次結果'), findsOneWidget);
    await _capture(t, 'topic-pending-retry');
    // 待確認期間作戰板改成 v2、訊號也沒了：重試仍送凍結的 v1 與原編號。
    partnerContext = _contextWith('[對象作戰板：合成對象 p]\n- 興趣：爬山（v2）');
    signals = false;
    container.invalidate(newTopicPartnerContextProvider('p'));
    container.invalidate(newTopicReadinessProvider('p'));
    await t.pump();
    await t.pump();
    expect(_button(t).onPressed, isNotNull,
        reason: 'pending envelope remains resolvable without current material');
    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls[1], _service.calls[0]);
    expect(_service.calls[1]['summary'], contains('散步（v1）'));
    refreshFails = true;
    _service.replies[1].complete(_result(_service.calls[1]['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);
    expect(_service.calls, hasLength(2));
    await _capture(t, 'topic-result');
  });

  testWidgets(
      'NT-18 actual HTTP model 429 stays on page and retries without opening paywall',
      (t) async {
    signals = true;
    final requests = <Map<String, dynamic>>[];
    NewTopicView.debugServiceFactory = () => NewTopicService(
          accessTokenProvider: () => 'synthetic-token',
          streamClientFactory: () => MockClient((request) async {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
                jsonEncode({
                  'code': 'MODEL_RATE_LIMITED',
                  'message': '請求太頻繁，請稍後再試。',
                }),
                429,
                headers: {'content-type': 'application/json'});
          }),
        );
    await _pump(t);
    await _tapGenerate(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('請求太頻繁，請稍後再試。'), findsOneWidget);
    expect(find.byType(NewTopicView), findsOneWidget);
    expect(find.textContaining('升級'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull,
        reason:
            'paywall navigation would require a GoRouter absent from this harness');
    expect(_button(t).onPressed, isNotNull);
    expect(requests, hasLength(1));
    await _tapGenerate(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(requests, hasLength(2));
    expect(requests[1], requests[0],
        reason: 'retry retains operation and frozen fields');
    expect(t.takeException(), isNull);
    await _capture(t, 'topic-model-rate-limit');
  });

  testWidgets(
      'NT-14/15 result change needs confirmation; same partner keeps result',
      (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 300));
    await t.ensureVisible(find.bySemanticsLabel('目前對象 合成對象 p，更換對象'));
    await t.tap(find.bySemanticsLabel('目前對象 合成對象 p，更換對象'));
    await t.pumpAndSettle();
    await t.tap(find.text('合成對象 p').last);
    await t.pumpAndSettle();
    expect(find.text('更換條件會清除目前結果'), findsNothing);
    await t.ensureVisible(find.text('聊得不錯，想更靠近'));
    await t.tap(find.text('聊得不錯，想更靠近'));
    await t.pumpAndSettle();
    expect(find.text('更換條件會清除目前結果'), findsOneWidget);
    await t.tap(find.text('先不要'));
    await t.pumpAndSettle();
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);
    await t.tap(find.text('聊得不錯，想更靠近'));
    await t.pumpAndSettle();
    await t.tap(find.text('清除並更換'));
    await t.pumpAndSettle();
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsNothing);
    expect(_button(t).onPressed, isNotNull);
  });

  testWidgets('NT-22 offstage completion keeps current mode and defers scroll',
      (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    _active.value = false;
    await t.pump();
    final scroll = t
        .widget<OpenerResponsiveBody>(
            find.byType(OpenerResponsiveBody, skipOffstage: false))
        .controller;
    final offset = scroll.offset;
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('另一個模式'), findsOneWidget);
    expect(scroll.offset, offset);
    expect(find.byType(AlertDialog), findsNothing);
    _active.value = true;
    _visible.value = true;
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('新話題建議'), findsOneWidget);
  });

  testWidgets('offstage preparation never opens consent after style resolves',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    signals = true;
    final container = await _pump(t);
    final wait = Completer<String?>();
    styleLoader = () => wait.future;
    container.invalidate(newTopicStyleContextProvider('p'));
    // The old enabled callback can still be delivered before the rebuild.
    await t.tap(find.byKey(const ValueKey('new-topic-generate')));
    _active.value = false;
    await t.pump();
    wait.complete('更新風格');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('另一個模式'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_service.calls, isEmpty);
    _active.value = true;
    _visible.value = true;
    await t.pump();
    expect(_button(t).onPressed, isNotNull);
  });

  testWidgets('changing conditions retires pending confirmation label',
      (t) async {
    signals = true;
    await _pump(t);
    await _tapGenerate(t);
    _service.replies.single.completeError(
        const NewTopicRequestInProgressException(message: '等待確認'));
    await t.pump();
    expect(find.text('確認本次結果'), findsOneWidget);
    await t.tap(find.text('冷掉了，想重新聊'));
    await t.pump();
    expect(find.text('確認本次結果'), findsNothing);
    expect(find.text('生成新話題'), findsOneWidget);
    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls[1]['id'], isNot(_service.calls[0]['id']));
    expect(_service.calls[1]['situation'], 'went_cold');
    expect(_service.calls[1]['topicContext'], isNull,
        reason: '只選第一問不送 topicContext，走 legacy');
    _service.replies[1].complete(_result(_service.calls[1]['id']!));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('兩段式：追問依第一問切換、教練提醒即時更新、換第一問清追問留素材', (t) async {
    signals = true;
    await _pump(t);
    expect(find.text('多久沒聊了？'), findsNothing);
    expect(_key('new-topic-coach-tip'), findsNothing);

    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    expect(find.text('多久沒聊了？'), findsOneWidget);
    expect(find.text('上次是怎麼停的？'), findsOneWidget);
    expect(find.text('這次怎麼開：有內容、低壓力、不追討。'), findsOneWidget);
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    expect(_chipSelected(t, 'new-topic-cold-duration-weeks'), isTrue);
    expect(find.textContaining('這次怎麼開：帶一個新東西出現'), findsOneWidget);
    expect(find.text('先避開：檢討關係'), findsOneWidget);
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    expect(_chipSelected(t, 'new-topic-cold-duration-weeks'), isFalse,
        reason: '再點一次取消');
    expect(find.text('這次怎麼開：有內容、低壓力、不追討。'), findsOneWidget);
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '路過一家甜點店');

    await _tapVisible(t, find.text('剛約完會'));
    expect(find.text('多久沒聊了？'), findsNothing);
    expect(find.text('約完之後她的反應？'), findsOneWidget);
    expect(find.text('主動傳訊息或說開心'), findsOneWidget);
    expect(find.text('這次怎麼開：承接約會的餘溫，不急著約下一次。'), findsOneWidget);
    expect(find.text('約會時聊到的事'), findsOneWidget);
    await _tapVisible(t, find.text('還在聊，但接不下去'));
    expect(find.text('她最近回你的樣子？'), findsOneWidget);
    expect(_chipSelected(t, 'new-topic-engagement-green'), isFalse);
    expect(_chipSelected(t, 'new-topic-material-trigger'), isTrue);
    expect(_materialText(t), '路過一家甜點店');
    await _tapVisible(t, _key('new-topic-engagement-red'));
    expect(find.textContaining('不要用更多問題去救'), findsOneWidget);

    await _tapGenerate(t);
    expect(_service.calls.single['situation'], 'stuck');
    expect(jsonDecode(_service.calls.single['topicContext']!), {
      'engagement': 'red',
      'materialKind': 'trigger',
      'materialText': '路過一家甜點店',
    });
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('素材輸入框：選了才出現，沒寫或超長不能生成，超長不截斷', (t) async {
    signals = true;
    await _pump(t);
    expect(_button(t).onPressed, isNotNull);
    expect(_materialField, findsNothing);

    await _tapVisible(t, _key('new-topic-material-past_topic'));
    expect(find.text('她之前提過什麼？'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('她之前提過什麼')), findsWidgets);
    expect(find.bySemanticsLabel('之前聊過的事'), findsOneWidget);
    expect(find.text(NewTopicTwoStageCopy.materialHelper('past_topic')),
        findsOneWidget);
    expect(find.text('0 / 150'), findsOneWidget);
    expect(_button(t).onPressed, isNull);
    expect(find.text(NewTopicTwoStageCopy.materialMissingHint), findsOneWidget);
    await _typeMaterial(t, '   ');
    expect(_button(t).onPressed, isNull);

    await _typeMaterial(t, '她' * 151);
    expect(_button(t).onPressed, isNull);
    expect(find.text(NewTopicTwoStageCopy.materialTooLongHint), findsOneWidget);
    final counter = t.widget<Text>(_key('new-topic-material-counter'));
    expect(counter.data, '151 / 150，超過 1 字，請縮短後再生成');
    expect(counter.style!.color, AppColors.error);
    expect(_materialText(t), hasLength(151), reason: '超長不偷偷截斷');

    await _typeMaterial(t, '她說在準備潛水證照');
    expect(_button(t).onPressed, isNotNull);
    expect(find.text('9 / 150'), findsOneWidget);

    await _tapVisible(t, _key('new-topic-material-none'));
    expect(_materialField, findsNothing);
    expect(_button(t).onPressed, isNotNull);
    await _tapVisible(t, _key('new-topic-material-none'));
    expect(_chipSelected(t, 'new-topic-material-none'), isFalse);
    await _tapVisible(t, _key('new-topic-material-my_story'));
    expect(find.text('發生什麼事？'), findsOneWidget);
    expect(find.text(NewTopicTwoStageCopy.materialHelper('my_story')),
        findsOneWidget,
        reason: '提示跟著素材類型換');
    expect(_materialText(t), '她說在準備潛水證照', reason: '換素材類型保留文字');
    expect(_service.calls, isEmpty);
  });

  testWidgets('結果顯示這組根據、輸入框唯讀；調整狀況確認後清結果並保留答案', (t) async {
    signals = true;
    await _pump(t);
    await _tapVisible(t, find.text('冷掉了，想重新聊'));
    await _tapVisible(t, _key('new-topic-cold-duration-weeks'));
    await _tapVisible(t, _key('new-topic-cold-stop-i_no_reply'));
    await _tapVisible(t, _key('new-topic-material-trigger'));
    await _typeMaterial(t, '  路過一家很浮誇的甜點店  ');
    await _tapGenerate(t);
    final first = _service.calls.single;
    expect(first['situation'], 'went_cold');
    expect(jsonDecode(first['topicContext']!), {
      'coldDuration': 'weeks',
      'coldStop': 'i_no_reply',
      'materialKind': 'trigger',
      'materialText': '路過一家很浮誇的甜點店',
    });
    _service.replies.single.complete(_result(first['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('這組根據：冷掉了・一到四週・我沒回她｜看到想到她的東西'), findsOneWidget);
    expect(t.widget<TextField>(_materialField).readOnly, isTrue);
    await _capture(t, 'topic-two-stage-result');

    await _tapVisible(t, _key('new-topic-adjust'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('更換條件會清除目前結果'), findsOneWidget);
    await t.tap(find.text('先不要'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsOneWidget);

    await _tapVisible(t, _key('new-topic-adjust'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('清除並更換'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsNothing);
    expect(_key('new-topic-basis'), findsNothing);
    expect(_chipSelected(t, 'new-topic-cold-duration-weeks'), isTrue);
    expect(_chipSelected(t, 'new-topic-cold-stop-i_no_reply'), isTrue);
    expect(_materialText(t), '  路過一家很浮誇的甜點店  ');
    expect(t.widget<TextField>(_materialField).readOnly, isFalse);
    final q1 = t.getRect(find.text(NewTopicTwoStageCopy.situationTitle));
    expect(q1.top, inInclusiveRange(0, 200), reason: '捲回第一問');
    expect(_button(t).onPressed, isNotNull);

    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls[1]['id'], isNot(first['id']), reason: '重新生成照常計費');
    expect(_service.calls[1]['topicContext'], first['topicContext']);
    _service.replies[1].complete(_result(_service.calls[1]['id']!));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('進階不可用：先不要保留錯誤；用基本模式重送不帶 topicContext 且保留答案與文字', (t) async {
    signals = true;
    await _pump(t);
    await _tapVisible(t, find.text('聊得不錯，想更靠近'));
    await _tapVisible(t, _key('new-topic-engagement-green'));
    await _tapVisible(t, _key('new-topic-material-inside_joke'));
    await _typeMaterial(t, '她說我的五分鐘都是半小時');
    const unavailable =
        NewTopicAdvancedUnavailableException('進階模式暫時無法使用，可以改用基本模式生成。本次不會扣額度。');

    await _tapGenerate(t);
    _service.replies[0].completeError(unavailable);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(NewTopicTwoStageCopy.advancedUnavailableTitle),
        findsOneWidget);
    await t.tap(find.text(NewTopicTwoStageCopy.advancedUnavailableCancel));
    await t.pump(const Duration(milliseconds: 300));
    expect(_service.calls, hasLength(1));
    expect(find.text(unavailable.message), findsOneWidget);

    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(
        _service.calls[1]['topicContext'], _service.calls[0]['topicContext']);
    // server 已佔住第一筆編號（保證不落帳），App 清掉 pending：再按換新編號。
    expect(_service.calls[1]['id'], isNot(_service.calls[0]['id']));
    _service.replies[1].completeError(unavailable);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text(NewTopicTwoStageCopy.advancedUnavailableConfirm));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(_service.calls, hasLength(3));
    final basic = _service.calls[2];
    expect(basic['topicContext'], isNull);
    expect(basic['situation'], 'warm_up');
    expect(basic['id'], isNot(_service.calls[1]['id']));
    expect(_chipSelected(t, 'new-topic-engagement-green'), isTrue);
    expect(_chipSelected(t, 'new-topic-material-inside_joke'), isTrue);
    expect(_materialText(t), '她說我的五分鐘都是半小時');

    _service.replies[2].complete(_result(basic['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('這組根據：想更靠近'), findsOneWidget, reason: '基本模式只用到第一問');
    expect(find.text(unavailable.message), findsNothing);
  });

  testWidgets('進階不可用但基本模式生不出來（資料少、沒選第一問）：不開對話框，請先選狀況', (t) async {
    await _pump(t);
    await _tapVisible(t, _key('new-topic-material-my_story'));
    await _typeMaterial(t, '合成測試句');
    await _tapGenerate(t);
    _service.replies.single.completeError(
        const NewTopicAdvancedUnavailableException(
            '進階模式暫時無法使用，可以改用基本模式生成。本次不會扣額度。'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(NewTopicTwoStageCopy.advancedUnavailableNeedsSituation),
        findsOneWidget);
    expect(_service.calls, hasLength(1));
    expect(_materialText(t), '合成測試句');
  });

  testWidgets('伺服器擋下素材用字：顯示 server 訊息、不邀重試，改字後換新請求', (t) async {
    // 沒有作戰板訊號、沒有風格、不選第一問：只靠用戶寫的那句也能生成。
    await _pump(t);
    await _tapVisible(t, _key('new-topic-material-my_story'));
    expect(find.text('請選一個目前情境，或先補充對象資料。'), findsOneWidget,
        reason: '還沒寫的空素材不算素材');
    expect(t.widget<TextField>(_materialField).decoration!.hintMaxLines, 5,
        reason: '大字級提示不被截掉');
    await _typeMaterial(t, '合成測試句');
    expect(find.text('可以不選，直接找新的切入點。'), findsOneWidget);
    expect(_button(t).onPressed, isNotNull);
    await _tapGenerate(t);
    _service.replies[0].completeError(const NewTopicMaterialBlockedException(
        '你寫的那句含有不適合的字眼，請改寫後再生成。本次不會扣額度。'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('你寫的那句含有不適合的字眼，請改寫後再生成。本次不會扣額度。'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('重試'), findsNothing);
    expect(find.text('生成新話題'), findsOneWidget);
    await _typeMaterial(t, '合成測試句改');
    expect(find.text('你寫的那句含有不適合的字眼，請改寫後再生成。本次不會扣額度。'), findsNothing);
    await _tapGenerate(t);
    expect(_service.calls[1]['id'], isNot(_service.calls[0]['id']));
    expect(jsonDecode(_service.calls[1]['topicContext']!)['materialText'],
        '合成測試句改');
  });

  for (final removePartner in [false, true]) {
    testWidgets(
        'preparation invalidated by ${removePartner ? 'partner deletion' : 'owner change'}',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      signals = true;
      final container = await _pump(t);
      final wait = Completer<String?>();
      styleLoader = () => wait.future;
      container.invalidate(newTopicStyleContextProvider('p'));
      await t.tap(find.byKey(const ValueKey('new-topic-generate')));
      await t.pump();
      if (removePartner) {
        partners = [];
        container.invalidate(partnerListProvider);
      } else {
        owner = 'b';
        ownerEvents.add(owner);
      }
      await t.pump();
      wait.complete('舊帳號的風格');
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);
      expect(_service.calls, isEmpty);
      expect(find.text('合成對象 p'), findsNothing);
      expect(_button(t).onPressed, isNull);
    });
  }

  testWidgets('NT-23 account or deleted partner rejects late provider result',
      (t) async {
    signals = true;
    final container = await _pump(t);
    await _tapGenerate(t);
    owner = 'b';
    ownerEvents.add(owner);
    await t.pump();
    partners = [];
    container.invalidate(partnerListProvider);
    await t.pump();
    _service.replies.single.complete(_result(_service.calls.single['id']!));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('最近有找到喜歡的散步路線嗎？'), findsNothing);
    expect(find.text('合成對象 p'), findsNothing);
    expect(_button(t).onPressed, isNull);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
        'topic result remains readable in real 320 viewport scale=$scale',
        (t) async {
      signals = true;
      await _pump(t, scale: scale, size: const Size(320, 568));
      await _tapGenerate(t);
      _service.replies.single.complete(_result(_service.calls.single['id']!));
      await t.pump(const Duration(milliseconds: 500));
      await t.ensureVisible(find.text('新話題建議'));
      await _capture(t, 'topic-result-320-$scale');
      await t.ensureVisible(find.text('複製'));
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('new-topic-generate')), findsNothing);
    });
    testWidgets('NT-24/SH-04 320 width scale=$scale and own quota sheet',
        (t) async {
      signals = true;
      await _pump(t, scale: scale, size: const Size(320, 568));
      await t.ensureVisible(find.text('還在聊，但接不下去'));
      await t.tap(find.text('還在聊，但接不下去'));
      await t.pump();
      await _capture(t, 'topic-320-$scale');
      await t.ensureVisible(find.text('額度說明'));
      await t.tap(find.text('額度說明'));
      await t.pumpAndSettle();
      expect(find.textContaining('回看與複製已取得的話題'), findsOneWidget);
      expect(find.textContaining('可以生成 3 組開場白'), findsNothing);
      // 方案名給用戶看的名字，不顯示 free 這類代碼。
      expect(find.text('目前方案：Free'), findsOneWidget);
      expect(find.text('目前方案：free'), findsNothing);
      await _capture(t, 'topic-quota-$scale');
    });
  }

  // onboarding 轉換第 6 步：告訴使用者「額度不夠」的那一刻記一筆 quota_block_shown，
  // 只是記錄；按鈕、提示與付費牆照舊。
  testWidgets('額度不足事件：伺服器擋下記一筆 new_topic／daily／server；之後按鈕被擋（同一種額度）不重記',
      (t) async {
    signals = true;
    final container = await _pump(t, paywallRoute: true);
    await _tapGenerate(t);
    _service.replies.single.completeError(const NewTopicQuotaExceededException(
        message: '今日額度不足。',
        dailyRemaining: 1,
        quotaNeeded: 3,
        isMonthly: false));
    (container.read(subscriptionProvider.notifier) as _Sub).exhaustDaily();
    await t.pumpAndSettle();
    await t.tap(find.text('關閉付費牆'));
    await t.pumpAndSettle();
    expect(find.text(NewTopicView.upgradeButtonLabel), findsOneWidget);
    await _tapGenerate(t);
    await t.pumpAndSettle();

    expect(paywallOpens, 2);
    expect(_quotaBlocks(), [
      {'feature': 'new_topic', 'scope': 'daily', 'block_source': 'server'},
    ]);
  });

  testWidgets('額度不足事件：額度不夠、按鈕被擋就記一筆 new_topic／monthly／precheck；在另一個模式時不記',
      (t) async {
    signals = true;
    _active.value = false;
    final container = await _pump(t, paywallRoute: true);
    (container.read(subscriptionProvider.notifier) as _Sub).exhaustMonthly();
    await t.pumpAndSettle();
    expect(_quotaBlocks(), isEmpty);

    _active.value = true;
    await t.pumpAndSettle();
    expect(find.text(NewTopicView.upgradeButtonLabel), findsOneWidget);
    expect(_quotaBlocks(), [
      {'feature': 'new_topic', 'scope': 'monthly', 'block_source': 'precheck'},
    ]);

    await _tapGenerate(t);
    await t.pumpAndSettle();
    expect(paywallOpens, 1);
    expect(_quotaBlocks(), hasLength(1));
    expect(_service.calls, isEmpty);
  });

  testWidgets('額度不足事件：按下生成後才知道額度不夠（生成前預檢）：只記一筆 precheck、不送出', (t) async {
    SharedPreferences.setMockInitialValues({});
    signals = true;
    final container = await _pump(t, paywallRoute: true);
    await _tapGenerate(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('資料使用說明'), findsOneWidget);
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    // 同意框開著時刷新拿到今日只剩 1 則，接著同意：生成前的預檢擋下。
    (container.read(subscriptionProvider.notifier) as _Sub).exhaustDaily();
    await t.ensureVisible(find.text('同意並繼續'));
    await t.tap(find.text('同意並繼續'));
    await t.pumpAndSettle();

    expect(paywallOpens, 1);
    expect(_service.calls, isEmpty);
    expect(find.text('本次需要 3 則，目前可用額度不足。', skipOffstage: false), findsWidgets);
    expect(_quotaBlocks(), [
      {'feature': 'new_topic', 'scope': 'daily', 'block_source': 'precheck'},
    ]);
  });
}
