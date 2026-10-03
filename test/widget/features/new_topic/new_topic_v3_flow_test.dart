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
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import '../../../visual_proof/proof_support.dart';

class _Sub extends SubscriptionNotifier {
  _Sub() {
    state =
        const SubscriptionState(tier: 'free', monthlyLimit: 30, dailyLimit: 15);
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
bool blocked = false;
bool refreshFails = false;
Completer<void>? refreshGate;
Future<String?> Function()? styleLoader;

Future<ProviderContainer> _pump(WidgetTester t,
    {String? selected = 'p',
    double scale = 1,
    Size size = const Size(390, 844)}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
      overrides: [
        authConversationScopeProvider.overrideWith((_) => ownerEvents.stream),
        partnerListProvider.overrideWith((_) => partners),
        partnerByIdProvider.overrideWith(
            (_, id) => partners.where((p) => p.id == id).firstOrNull),
        conversationsByPartnerProvider.overrideWith((_, id) => []),
        newTopicPartnerContextProvider
            .overrideWith((_, id) => NewTopicPartnerContext.empty),
        newTopicReadinessProvider.overrideWith((_, id) => blocked
            ? NewTopicReadiness.dataQualityBlocked
            : NewTopicReadiness.readyWithoutPartnerSignals),
        newTopicStyleContextProvider.overrideWith(
            (_, id) => styleLoader?.call() ?? Future.value(style)),
        subscriptionProvider.overrideWith((_) => _Sub()),
        subscriptionScreenRefreshProvider.overrideWith((_) => () async {
              if (refreshFails) throw StateError('offline');
              await refreshGate?.future;
            }),
      ],
      child: RepaintBoundary(
          key: _root,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'AppTC'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
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
    owner = 'a';
    partners = [_partner('p')];
    style = null;
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

  testWidgets('生成中離開並重建畫面，同答案送出相同 requestId', (t) async {
    style = '有效風格';
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
    style = '有效風格';
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
    style = '有效風格';
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
    style = '有效風格';
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
    style = '有效風格';
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
    style = '原始風格';
    final container = await _pump(t);
    await _tapGenerate(t);
    expect(_service.calls, hasLength(1));
    _service.replies[0].completeError(
        const NewTopicRequestInProgressException(message: '正在確認本次結果，請勿重複送出。'));
    await t.pump();
    expect(find.text('確認本次結果'), findsOneWidget);
    await _capture(t, 'topic-pending-retry');
    style = null;
    container.invalidate(newTopicStyleContextProvider('p'));
    await t.pump();
    await t.pump();
    expect(_button(t).onPressed, isNotNull,
        reason: 'pending envelope remains resolvable without current material');
    await _tapGenerate(t);
    expect(_service.calls, hasLength(2));
    expect(_service.calls[1], _service.calls[0]);
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
    style = '有效風格';
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
    style = '有效風格';
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
    style = '有效風格';
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
    style = '原本已載入的風格';
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
    style = '有效風格';
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
    style = '有效風格';
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
    style = '有效風格';
    await _pump(t);
    expect(_button(t).onPressed, isNotNull);
    expect(_materialField, findsNothing);

    await _tapVisible(t, _key('new-topic-material-past_topic'));
    expect(find.text('她之前提過什麼？'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('她之前提過什麼')), findsWidgets);
    expect(find.bySemanticsLabel('之前聊過的事'), findsOneWidget);
    expect(find.text(NewTopicTwoStageCopy.materialHelper), findsOneWidget);
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
    expect(_materialText(t), '她說在準備潛水證照', reason: '換素材類型保留文字');
    expect(_service.calls, isEmpty);
  });

  testWidgets('結果顯示這組根據、輸入框唯讀；調整狀況確認後清結果並保留答案', (t) async {
    style = '有效風格';
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
    style = '有效風格';
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
      style = '有效風格';
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
    style = '有效風格';
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
      style = '有效風格';
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
      style = '有效風格';
      await _pump(t, scale: scale, size: const Size(320, 568));
      await t.ensureVisible(find.text('還在聊，但接不下去'));
      await t.tap(find.text('還在聊，但接不下去'));
      await t.pump();
      await _capture(t, 'topic-320-$scale');
      await t.ensureVisible(find.text('額度說明'));
      await t.tap(find.text('額度說明'));
      await t.pumpAndSettle();
      expect(find.textContaining('回看與複製已取得的話題'), findsOneWidget);
      expect(find.textContaining('包含 3 組'), findsNothing);
      await _capture(t, 'topic-quota-$scale');
    });
  }
}
