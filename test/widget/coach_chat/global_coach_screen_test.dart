// 問教練 Sydney 聊天視窗 spec（2026-08-15 拍板：三入口共用同一視窗）。
//
// GlobalCoachScreen＝AppBar「問教練 Sydney」＋開場泡泡＋引導問句＋CoachSurface。
// 引導問句跟著 scope 走：一般＝三句「怎麼做」問句；對象＝三句情境 chips
// （種入 lifecyclePhase＋prefill）。點擊只「預填」進輸入框（prefill＋focus
// token），絕不自動送出（quota 安全）。
//
// 「問誰」chips（首頁進場）：選對象＝CoachSurface 切到該對象的 partner
// scope（跟對象頁跟進共用同一條串）；「一般」＝global 串；無對象卡整排
// 不渲染；切換保留輸入框草稿。`?partnerId=` 進場＝鎖定模式：不渲染 chips、
// 標題帶對象名。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/presentation/screens/global_coach_screen.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/learning/domain/dating_knowledge_links.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

import '../../helpers/memory_coach_chat_repository.dart';
import '../../helpers/memory_coaching_outcome_repository.dart';

/// 引導問句直接引實作常數（review Grok Minor-3：防測試與文案漂移）。
const _guideQuestions = GlobalCoachScreen.guideQuestions;
const _scenarioChips = GlobalCoachScreen.scenarioChips;

class _FakeStyleRepo implements PartnerStyleRepository {
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async => null;
  @override
  Future<void> save(PartnerStyleOverride o) async {}
  @override
  Future<void> delete(String partnerId) async {}
  @override
  Future<void> clearAll() async {}
}

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      ownerUserId: 'owner-a',
    );

CoachChatInvoker _recordingInvoker(
  List<Map<String, dynamic>> calls, {
  int status = 429,
}) {
  return (String _, {required Map<String, dynamic> body}) async {
    calls.add(body);
    return CoachChatInvokeResponse(
      status: status,
      data: const <String, dynamic>{'error': 'Daily limit exceeded'},
    );
  };
}

/// 對象相關 provider 全 override 成記憶體空資料：視窗在 partner scope 會
/// 讀 aggregate／conversations（開場泡泡素材），測試不落 Hive。
List<Override> _partnerOverrides(
  List<Partner> partners,
  Map<String, List<Conversation>> partnerConversations,
) =>
    [
      partnerListProvider.overrideWithValue(partners),
      for (final partner in partners) ...[
        dataQualityFlagProvider(partner.id)
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        partnerByIdProvider(partner.id).overrideWithValue(partner),
        partnerAggregateProvider(partner.id)
            .overrideWithValue(PartnerAggregateView.empty()),
        conversationsByPartnerProvider(partner.id)
            .overrideWithValue(partnerConversations[partner.id] ?? const []),
      ],
    ];

Future<List<Map<String, dynamic>>> _pump(
  WidgetTester tester, {
  List<Partner> partners = const [],
  String? lockedPartnerId,
  int invokerStatus = 429,
  Map<String, List<Conversation>> partnerConversations = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final apiCalls = <Map<String, dynamic>>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        coachChatApiServiceProvider.overrideWithValue(
          CoachChatApiService(
            invoker: _recordingInvoker(apiCalls, status: invokerStatus),
          ),
        ),
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        ..._partnerOverrides(partners, partnerConversations),
        // 鎖定的 id 不在對象清單（已刪除）→ 顯式回 null，不落 Hive。
        if (lockedPartnerId != null &&
            partners.every((partner) => partner.id != lockedPartnerId))
          partnerByIdProvider(lockedPartnerId).overrideWithValue(null),
      ],
      child: MaterialApp(
        home: GlobalCoachScreen(lockedPartnerId: lockedPartnerId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return apiCalls;
}

CoachSurface _surface(WidgetTester tester) =>
    tester.widget<CoachSurface>(find.byType(CoachSurface));

TextField _inputField(WidgetTester tester) => tester.widget<TextField>(
      find.descendant(
        of: find.byType(CoachSurface),
        matching: find.byType(TextField),
      ),
    );

void main() {
  testWidgets('AppBar 標題「問教練 Sydney」＋CoachSurface 掛 global scope',
      (tester) async {
    await _pump(tester);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('問教練 Sydney'),
      ),
      findsOneWidget,
    );
    expect(_surface(tester).scope, const CoachScope.global());
    // 視窗開場泡泡已含標題與額度說明，CoachSurface 的舊 header 整段退場。
    expect(find.text('問教練一句'), findsNothing);
  });

  testWidgets('一般 scope：開場泡泡固定句＋三句引導問句', (tester) async {
    await _pump(tester);

    expect(find.text('隨時問我，聊天卡住我來接。'), findsOneWidget);
    for (final question in _guideQuestions) {
      expect(find.text(question), findsOneWidget);
    }
  });

  testWidgets('點引導問句只預填輸入框，絕不自動送出', (tester) async {
    final apiCalls = await _pump(tester);

    await tester.tap(find.text(_guideQuestions[0]));
    await tester.pumpAndSettle();

    expect(_inputField(tester).controller?.text, _guideQuestions[0]);
    expect(apiCalls, isEmpty);
  });

  testWidgets('無對象卡：「問誰」chips 整排不渲染', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('coach_scope_general')), findsNothing);
    expect(find.text('問誰'), findsNothing);
  });

  testWidgets('有對象卡：chips 出現、預設「一般」＝global scope', (tester) async {
    await _pump(tester, partners: [_partner('p1', 'Alice')]);

    final generalChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('coach_scope_general')),
    );
    expect(generalChip.selected, isTrue);
    expect(find.byKey(const Key('coach_scope_partner_p1')), findsOneWidget);
    expect(_surface(tester).scope, const CoachScope.global());
  });

  testWidgets('點對象 chip → partner scope＋情境問句＋開場泡泡換對象版',
      (tester) async {
    await _pump(tester, partners: [_partner('p1', 'Alice')]);

    await tester.tap(find.byKey(const Key('coach_scope_partner_p1')));
    await tester.pumpAndSettle();

    expect(_surface(tester).scope, const CoachScope.partner('p1'));
    // 引導問句跟著 scope 走：一般三句退場、情境三句上場。
    for (final question in _guideQuestions) {
      expect(find.text(question), findsNothing);
    }
    for (final chip in _scenarioChips) {
      expect(find.text(chip.label), findsOneWidget);
    }
    // 無任何記憶素材 → 開場 fallback 帶對象名。
    expect(find.text('想聊Alice的什麼？卡住的地方直接丟給我。'), findsOneWidget);
  });

  testWidgets('partner scope 顯示「教練會參考」；無有效對話不渲染（Batch B1）',
      (tester) async {
    await _pump(
      tester,
      partners: [_partner('p1', 'Alice')],
      partnerConversations: {
        'p1': [
          Conversation(
            id: 'c-1',
            name: 'Alice',
            messages: [
              Message(
                id: 'm-1',
                content: '週末要去爬山',
                isFromMe: false,
                timestamp: DateTime(2026, 8, 30, 21),
              ),
            ],
            createdAt: DateTime(2026, 8, 1),
            updatedAt: DateTime(2026, 8, 30),
            partnerId: 'p1',
          ),
        ],
      },
    );

    // global scope 不渲染。
    expect(
      find.byKey(const Key('coach_partner_context_reference')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('coach_scope_partner_p1')));
    await tester.pumpAndSettle();

    expect(find.text('教練會參考：你們 8/30 的對話紀錄'), findsOneWidget);
  });

  testWidgets('點情境 chip → 預填情境問句＋種入 lifecyclePhase，不自動送出',
      (tester) async {
    final apiCalls = await _pump(tester, partners: [_partner('p1', 'Alice')]);

    await tester.tap(find.byKey(const Key('coach_scope_partner_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_scenarioChips[1].label));
    await tester.pumpAndSettle();

    expect(_inputField(tester).controller?.text, _scenarioChips[1].prefill);
    expect(_surface(tester).lifecyclePhase, _scenarioChips[1].phase);
    expect(apiCalls, isEmpty);
  });

  testWidgets('切回「一般」→ 回到 global scope 且清掉 lifecyclePhase',
      (tester) async {
    await _pump(tester, partners: [_partner('p1', 'Alice')]);

    await tester.tap(find.byKey(const Key('coach_scope_partner_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_scenarioChips[0].label));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coach_scope_general')));
    await tester.pumpAndSettle();

    expect(_surface(tester).scope, const CoachScope.global());
    expect(_surface(tester).lifecyclePhase, isNull,
        reason: '情境是跟著對象串的，回一般不得殘留 phase');
  });

  testWidgets('鎖定模式（?partnerId=）：不渲染問誰、標題帶對象名、直接情境問句',
      (tester) async {
    await _pump(
      tester,
      partners: [_partner('p1', 'Alice')],
      lockedPartnerId: 'p1',
    );

    expect(find.text('問誰'), findsNothing);
    expect(find.byKey(const Key('coach_scope_general')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('問教練 Sydney・Alice'),
      ),
      findsOneWidget,
    );
    expect(_surface(tester).scope, const CoachScope.partner('p1'));
    for (final chip in _scenarioChips) {
      expect(find.text(chip.label), findsOneWidget);
    }
  });

  testWidgets('情境選中才出現知識庫入口，且每個情境都有對應章節', (tester) async {
    await _pump(
      tester,
      partners: [_partner('p1', 'Alice')],
      lockedPartnerId: 'p1',
    );
    const linkKey = Key('coach_window_knowledge_link');
    expect(find.byKey(linkKey), findsNothing,
        reason: '沒選情境就無從得知該連哪一章，寧可不給入口');

    for (final chip in _scenarioChips) {
      await tester.tap(find.text(chip.label));
      await tester.pumpAndSettle();
      expect(find.byKey(linkKey), findsOneWidget,
          reason: '點了「${chip.label}」之後應該出現知識庫入口');
      expect(DatingKnowledgeLinks.forFollowUpPhase(chip.phase), isNotNull,
          reason: 'phase ${chip.phase} 沒有對應章節，入口會連不到東西');
    }
  });

  testWidgets('鎖定的對象已刪除 → 安靜退回一般模式', (tester) async {
    await _pump(
      tester,
      partners: const [],
      lockedPartnerId: 'ghost',
    );

    expect(_surface(tester).scope, const CoachScope.global());
    expect(find.text('隨時問我，聊天卡住我來接。'), findsOneWidget);
  });

  testWidgets('鎖定的對象開著視窗時被刪 → 退回一般模式（ref.listen 路徑）',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final alice = _partner('p1', 'Alice');
    // 可翻轉的刪除開關：不能用 overrideWithValue，值要能中途變 null。
    final deleted = StateProvider((_) => false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coachChatRepositoryProvider
              .overrideWithValue(MemoryCoachChatRepository()),
          coachChatApiServiceProvider.overrideWithValue(
            CoachChatApiService(invoker: _recordingInvoker([])),
          ),
          coachingOutcomeRepositoryProvider
              .overrideWithValue(MemoryCoachingOutcomeRepository()),
          partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
          partnerListProvider.overrideWithValue(const []),
          partnerByIdProvider('p1')
              .overrideWith((ref) => ref.watch(deleted) ? null : alice),
          dataQualityFlagProvider('p1')
              .overrideWith((_) => const DataQualityFlag.unflagged()),
          partnerAggregateProvider('p1')
              .overrideWithValue(PartnerAggregateView.empty()),
          conversationsByPartnerProvider('p1').overrideWithValue(const []),
        ],
        child: const MaterialApp(
          home: GlobalCoachScreen(lockedPartnerId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_surface(tester).scope, const CoachScope.partner('p1'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GlobalCoachScreen)),
    );
    container.read(deleted.notifier).state = true;
    await tester.pumpAndSettle();

    expect(_surface(tester).scope, const CoachScope.global());
    expect(find.text('隨時問我，聊天卡住我來接。'), findsOneWidget);
  });

  testWidgets('切換對象不清輸入框草稿（CoachSurface State 不重建）', (tester) async {
    await _pump(tester, partners: [_partner('p1', 'Alice')]);

    final field = find.descendant(
      of: find.byType(CoachSurface),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '她已讀我兩天，我該追問嗎？');
    await tester.tap(find.byKey(const Key('coach_scope_partner_p1')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(field).controller?.text,
      '她已讀我兩天，我該追問嗎？',
    );
  });

  testWidgets('熱切換 scope 清問句記憶：A 串 loading 不得顯示 B 串問句', (tester) async {
    // Grok review 必修：_lastAskedQuestion 是跟著串的記憶。A 串 in-flight
    // （keepAlive 撐著）→ 切 B 送出 → 切回仍在 loading 的 A，若不清記憶，
    // A 的 progress 卡會顯示 B 的問句。
    SharedPreferences.setMockInitialValues(
      {AiDataSharingConsent.acceptedKeyForTesting: true},
    );
    final pending = <Completer<CoachChatInvokeResponse>>[];
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coachChatRepositoryProvider
              .overrideWithValue(MemoryCoachChatRepository()),
          coachChatApiServiceProvider.overrideWithValue(
            CoachChatApiService(
              invoker: (String _, {required Map<String, dynamic> body}) {
                final completer = Completer<CoachChatInvokeResponse>();
                pending.add(completer);
                return completer.future;
              },
            ),
          ),
          coachingOutcomeRepositoryProvider
              .overrideWithValue(MemoryCoachingOutcomeRepository()),
          partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
          ..._partnerOverrides([_partner('p1', 'Alice')], const {}),
        ],
        child: const MaterialApp(home: GlobalCoachScreen()),
      ),
    );
    await tester.pump();

    const questionA = '她已讀我兩天了怎麼辦？';
    const questionB = '約 Alice 週五會太急嗎？';
    final field = find.descendant(
      of: find.byType(CoachSurface),
      matching: find.byType(TextField),
    );

    // A（general）送出，卡在 loading。
    await tester.enterText(field, questionA);
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining(questionA), findsOneWidget,
        reason: 'general 串 loading 中，progress 卡應帶 A 問句');

    // 切到 Alice 串，送出 B 問句，也卡在 loading。
    await tester.tap(find.byKey(const Key('coach_scope_partner_p1')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, questionB);
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining(questionB), findsOneWidget);

    // 切回仍在 loading 的 A 串：不得顯示 B 的問句。
    await tester.tap(find.byKey(const Key('coach_scope_general')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining(questionB), findsNothing,
        reason: 'A 串的 progress 卡不得顯示 B 串的問句（scope 記憶要清）');

    // 收尾：把掛著的請求收掉，避免 keepAlive 拖到測試結束。
    // 用 500 而非 429——429 會觸發 onQuotaExceeded 的 context.push，
    // 這棵測試樹沒有 GoRouter。
    for (final completer in pending) {
      completer.complete(const CoachChatInvokeResponse(
        status: 500,
        data: <String, dynamic>{'error': 'server error'},
      ));
    }
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('快速切 scope 不得閃「正在送出問題」（controller build 必須同步）',
      (tester) async {
    // 2026-08-11 Eric 真機回報：快速連點問誰 chips，下方閃出「正在送出
    // 問題」。真因＝autoDispose controller 的 async build 每次熱切換都留
    // 一幀 AsyncLoading，UI 誤當成問題送出中。此測試逐幀斷言堵回歸。
    await _pump(
      tester,
      partners: [_partner('p1', 'Alice'), _partner('p2', 'Bella')],
    );

    const chipKeys = [
      Key('coach_scope_partner_p1'),
      Key('coach_scope_general'),
      Key('coach_scope_partner_p2'),
      Key('coach_scope_partner_p1'),
    ];
    for (final key in chipKeys) {
      await tester.tap(find.byKey(key));
      // 只 pump 單幀：假 loading 就是只活一兩幀，settle 後看不到。
      await tester.pump();
      expect(find.text('正在送出問題'), findsNothing,
          reason: '沒有問題在送，切 scope 不得出現送出中通知');
      expect(
        find.descendant(
          of: find.byType(CoachSurface),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: '送出鈕不得因 scope 初始化閃成轉圈',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('正在送出問題'), findsNothing);
    }
  });
}
