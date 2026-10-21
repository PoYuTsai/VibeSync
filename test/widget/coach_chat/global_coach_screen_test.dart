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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
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
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/quota_copy.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

import '../../helpers/memory_coach_chat_repository.dart';
import '../../helpers/memory_coaching_outcome_repository.dart';
import '../../helpers/fake_sydney_video_platform.dart';
import '../features/user_profile/_harness.dart';

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

/// 第一次讀「關於我」成功、之後打開 [failLoads] 就讀取失敗（換帳號重新讀取時）。
class _FlakyProfileRepo implements UserProfileRepository {
  _FlakyProfileRepo(this.profile);

  final UserProfile profile;
  bool failLoads = false;

  @override
  Future<UserProfile?> load(String uid) async {
    if (failLoads) throw Exception('profile load boom');
    return profile;
  }

  @override
  Future<void> save(UserProfile profile, String uid) async {}

  @override
  Future<void> clear(String uid) async {}
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
  List<Override> extraOverrides = const [],
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
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: GlobalCoachScreen(lockedPartnerId: lockedPartnerId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return apiCalls;
}

/// 開場是 chips；開始输入後從標題列選單選 scope，兩者都是使用者可操作路徑。
Future<void> _selectScope(WidgetTester tester, Key scopeKey) async {
  if (find.byKey(scopeKey).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('coach_scope_menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(find.byKey(scopeKey).hitTestable(), findsOneWidget);
  await tester.tap(find.byKey(scopeKey));
  // A/B 串可各自仍在等待，因此不能對持續進度動畫 pumpAndSettle。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// 有 /paywall 路由時依序記每次帶的入口（開了幾次＝長度）。
final _paywallExtras = <Object?>[];

/// 額度 429 走真的 CoachChatApiService，伺服器回 [quotaBody]；方案是 [tier]。
Future<void> _pumpQuota(
  WidgetTester tester, {
  required String tier,
  required Map<String, dynamic> quotaBody,
}) async {
  SharedPreferences.setMockInitialValues(
    {AiDataSharingConsent.acceptedKeyForTesting: true},
  );
  _paywallExtras.clear();
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        coachChatApiServiceProvider.overrideWithValue(
          CoachChatApiService(
            invoker: (String _, {required Map<String, dynamic> body}) async =>
                CoachChatInvokeResponse(status: 429, data: quotaBody),
          ),
        ),
        // 風格設定預設讀 Hive（測試裡等不到），這裡直接回沒有風格。
        coachChatStyleContextResolverProvider
            .overrideWithValue(() async => null),
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        ..._partnerOverrides(const [], const {}),
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(
            SubscriptionState(tier: tier, monthlyLimit: 800, dailyLimit: 30),
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const GlobalCoachScreen()),
          GoRoute(
            path: '/paywall',
            builder: (context, state) {
              _paywallExtras.add(state.extra);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('關閉付費牆'),
                  ),
                ),
              );
            },
          ),
        ]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 教練的釐清問題（免費）。
Map<String, dynamic> _clarificationBody(int request) => {
      'card': {
        'responseType': 'clarifyingQuestion',
        'mode': 'clarifyIntent',
        'headline': '先問清楚你的想法',
        'answer': '先補一個線索，我才不會亂猜。',
        'userState': '想推進又怕太快',
        'frictionType': 'unclearIntent',
        'nextStep': '說說你原本想怎麼回。',
        'suggestedLine': null,
        'boundaryReminder': '補充釐清不扣額度；正式建議才扣 1 則。',
        'needsReflection': true,
        'reflectionQuestion': '你原本想怎麼回她？',
        'costDeducted': 0,
      },
      'provider': 'test',
      'model': 'test-coach',
      'generatedAt': DateTime.now()
          .toUtc()
          .add(Duration(seconds: request))
          .toIso8601String(),
      'sessionId': 'about-me-toggle-session',
    };

/// 教練的正式建議（不是釐清），扣 1 則。
Map<String, dynamic> _formalAnswerBody(int request) => {
      'card': {
        'responseType': 'coachAnswer',
        'mode': 'replyCraft',
        'headline': '先接住她的話題',
        'answer': '她回得快是好訊號，先順著她的話題聊，再看她有沒有延伸。',
        'userState': '想推進又怕太快',
        'frictionType': 'unclearIntent',
        'nextStep': '先回她的話題，再看她有沒有反問。',
        'suggestedLine': '這個我也有興趣，妳都怎麼找到的？',
        'boundaryReminder': '別為了確認而連續追問。',
        'needsReflection': false,
        'reflectionQuestion': null,
        'costDeducted': 1,
      },
      'provider': 'test',
      'model': 'test-coach',
      'generatedAt': DateTime.now()
          .toUtc()
          .add(Duration(seconds: request))
          .toIso8601String(),
      'sessionId': 'about-me-toggle-session',
    };

CoachSurface _surface(WidgetTester tester) =>
    tester.widget<CoachSurface>(find.byType(CoachSurface));

TextField _inputField(WidgetTester tester) => tester.widget<TextField>(
      find.descendant(
        of: find.byType(CoachSurface),
        matching: find.byType(TextField),
      ),
    );

void main() {
  testWidgets('進場影片播放後，點引導輸入會釋放播放器且不送出問題', (tester) async {
    final previous = VideoPlayerPlatform.instance;
    final platform = FakeSydneyVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() {
      platform.close();
      VideoPlayerPlatform.instance = previous;
    });

    final calls = await _pump(tester);
    expect(platform.playing[0], isTrue);
    await tester.tap(find.text(_guideQuestions.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(_inputField(tester).controller!.text, _guideQuestions.first);
    expect(find.byKey(const Key('coach-welcome')), findsNothing);
    expect(find.byKey(const Key('coach-compact-avatar')), findsOneWidget);
    expect(platform.disposed, [0]);
    expect(platform.playing[0], isFalse);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('點對象 chip → partner scope＋情境問句＋開場泡泡換對象版', (tester) async {
    await _pump(tester, partners: [_partner('p1', 'Alice')]);

    await _selectScope(tester, const Key('coach_scope_partner_p1'));
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

  testWidgets('partner scope 顯示「教練會參考」；無有效對話不渲染（Batch B1）', (tester) async {
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

    await _selectScope(tester, const Key('coach_scope_partner_p1'));
    await tester.pumpAndSettle();

    expect(find.text('教練會參考：你們 8/30 的對話紀錄'), findsOneWidget);
  });

  testWidgets('點情境 chip → 預填情境問句＋種入 lifecyclePhase，不自動送出', (tester) async {
    final apiCalls = await _pump(tester, partners: [_partner('p1', 'Alice')]);

    await _selectScope(tester, const Key('coach_scope_partner_p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_scenarioChips[1].label));
    await tester.pumpAndSettle();

    expect(_inputField(tester).controller?.text, _scenarioChips[1].prefill);
    expect(_surface(tester).lifecyclePhase, _scenarioChips[1].phase);
    expect(apiCalls, isEmpty);
  });

  testWidgets('切回「一般」→ 回到 global scope 且清掉 lifecyclePhase', (tester) async {
    await _pump(tester, partners: [_partner('p1', 'Alice')]);

    await _selectScope(tester, const Key('coach_scope_partner_p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_scenarioChips[0].label));
    await tester.pumpAndSettle();
    await _selectScope(tester, const Key('coach_scope_general'));
    await tester.pumpAndSettle();

    expect(_surface(tester).scope, const CoachScope.global());
    expect(_surface(tester).lifecyclePhase, isNull,
        reason: '情境是跟著對象串的，回一般不得殘留 phase');
  });

  group('對象 scope 的開場：作戰板同一套快照（Bruce 2026-10-19 路線二）', () {
    Conversation analyzed(String id, DateTime at, Map<String, dynamic> json) =>
        Conversation(
          id: id,
          name: '第 $id 段',
          messages: const [],
          createdAt: at,
          updatedAt: at,
          partnerId: 'p1',
          lastAnalysisSnapshotJson: jsonEncode(json),
        );

    Map<String, dynamic> v3(
      String decision, {
      String? waitFor,
      Map<String, dynamic>? relation,
    }) =>
        {
          'guideVersion': 'v3.6',
          'read': {
            'guideVersion': 'v3.6',
            'decision': decision,
            'light': decision == 'care' ? null : 'yellow',
            'judgment': decision == 'care' ? '' : '球在她那邊。',
            if (waitFor != null) 'waitFor': waitFor,
            if (decision == 'care') 'careMessage': '先把安全放在第一位。',
            if (relation != null) 'relation': relation,
            'plannedCards': const [],
          },
          'cards': const [],
          'partial': false,
        };

    final v2 = {
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '約她週末喝咖啡',
      },
      'strategy': '維持神祕感',
    };

    Future<void> pumpWith(WidgetTester tester, List<Conversation> convs) =>
        _pump(
          tester,
          partners: [_partner('p1', 'Alice')],
          lockedPartnerId: 'p1',
          partnerConversations: {'p1': convs},
        );

    testWidgets('最近一次是 v3 先別回：下一步是要等她做什麼', (tester) async {
      await pumpWith(tester, [
        analyzed('c1', DateTime(2026, 10, 1), v2),
        analyzed(
            'c2', DateTime(2026, 10, 18), v3('hold', waitFor: '等她回你，再看她怎麼接')),
      ]);
      expect(find.text('上次分析完的下一步是「等她回你，再看她怎麼接」，試了嗎？'), findsOneWidget);
    });

    testWidgets('v3 帶了階段、沒有下一步：照階段說目前的狀態（不是舊流程的階段）', (tester) async {
      await pumpWith(tester, [
        analyzed('c1', DateTime(2026, 10, 1), {
          ...v2,
          'gameStage': {
            'current': 'opening',
            'status': 'normal',
            'nextStep': ''
          },
          'strategy': '',
        }),
        analyzed('c2', DateTime(2026, 10, 20),
            v3('send', relation: const {'stage': 'premise'})),
      ]);
      expect(find.text('你們目前的狀態：開始有男女氛圍，可以加點張力。想從哪裡推進？'), findsOneWidget);
    });

    testWidgets('最近一次是 v3 的關心：不拿舊的階段或下一步開場，照一般的說法', (tester) async {
      await pumpWith(tester, [
        analyzed('c1', DateTime(2026, 10, 1), v2),
        analyzed('c2', DateTime(2026, 10, 18), v3('care')),
      ]);
      expect(find.text('想聊Alice的什麼？卡住的地方直接丟給我。'), findsOneWidget);
    });

    testWidgets('v2 照舊：下一步照分析的 nextStep', (tester) async {
      await pumpWith(tester, [analyzed('c1', DateTime(2026, 10, 1), v2)]);
      expect(find.text('上次分析完的下一步是「約她週末喝咖啡」，試了嗎？'), findsOneWidget);
    });

    // A、B 依序分析，再重跑 A（主審第 1 輪 finding 2）：A 的紀錄沿用第一次的建立時間；開場要
    // 看最後完成分析的 A，不是照紀錄時間排到最前面的 B。
    Future<void> pumpRerunOlder(
      WidgetTester tester,
      Map<String, dynamic> rerunA,
    ) {
      final t1 = DateTime(2026, 10, 18, 9);
      final t2 = DateTime(2026, 10, 18, 12);
      final t3 = DateTime(2026, 10, 18, 15);
      final b = v3('hold', waitFor: '等她回你，再看她怎麼接');
      Map<String, dynamic> withMeta(
        Map<String, dynamic> json,
        DateTime analyzedAt,
      ) =>
          {
            ...json,
            '__vibesync_snapshot_meta_v1': {
              'contentRevision': 'rev',
              'messageCount': 1,
              'analyzedAt': analyzedAt.toUtc().toIso8601String(),
            },
          };
      AnalysisRecord record(
              String id, DateTime at, Map<String, dynamic> json) =>
          AnalysisRecord(
            id: 'rec-$id',
            ownerUserId: 'owner-a',
            conversationId: id,
            partnerId: 'p1',
            subjectName: 'Alice',
            segmentStart: 0,
            segmentEnd: 1,
            createdAt: at,
            messages: const [],
            analysisSnapshotJson: jsonEncode(json),
            analyzedContentRevision: 'revision-$id',
            completionKey: 'completion-$id',
            sourcePlatform: null,
            enthusiasmScore: null,
            gameStageLabel: '',
          );
      return _pump(
        tester,
        partners: [_partner('p1', 'Alice')],
        lockedPartnerId: 'p1',
        partnerConversations: {
          'p1': [
            analyzed('a', t3, withMeta(rerunA, t3)),
            analyzed('b', t2, withMeta(b, t2)),
          ],
        },
        extraOverrides: [
          partnerAnalysisRecordsProvider('p1').overrideWith(
            (_) => [record('a', t1, rerunA), record('b', t2, b)],
          ),
        ],
      );
    }

    testWidgets('重跑較舊的 A 判成停：開場講停止條件，不是 B 的先別回', (tester) async {
      await pumpRerunOlder(tester, v3('stop'));
      expect(
        find.text('上次分析完的下一步是「先停在這裡，不再主動傳訊息」，試了嗎？'),
        findsOneWidget,
      );
    });

    testWidgets('重跑較舊的 A 判成關心：照一般的說法開場', (tester) async {
      await pumpRerunOlder(tester, v3('care'));
      expect(find.text('想聊Alice的什麼？卡住的地方直接丟給我。'), findsOneWidget);
    });
  });

  testWidgets('鎖定模式（?partnerId=）：不渲染問誰、標題帶對象名、直接情境問句', (tester) async {
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

  for (final chip in _scenarioChips) {
    testWidgets('情境「${chip.label}」選中後才出現對應知識庫入口', (tester) async {
      // 每個情境從新畫面進場；首次預填後引導已完成任務，會收起。
      final apiCalls = await _pump(
        tester,
        partners: [_partner('p1', 'Alice')],
        lockedPartnerId: 'p1',
      );
      const linkKey = Key('coach_window_knowledge_link');
      expect(find.byKey(linkKey), findsNothing,
          reason: '沒選情境就無從得知該連哪一章，寧可不給入口');

      await tester.tap(find.text(chip.label));
      await tester.pumpAndSettle();
      expect(find.byKey(linkKey), findsOneWidget,
          reason: '點了「${chip.label}」之後應該出現知識庫入口');
      expect(DatingKnowledgeLinks.forFollowUpPhase(chip.phase), isNotNull,
          reason: 'phase ${chip.phase} 沒有對應章節，入口會連不到東西');
      expect(_inputField(tester).controller?.text, chip.prefill);
      expect(_surface(tester).lifecyclePhase, chip.phase);
      expect(apiCalls, isEmpty);
    });
  }

  testWidgets('鎖定的對象已刪除 → 安靜退回一般模式', (tester) async {
    await _pump(
      tester,
      partners: const [],
      lockedPartnerId: 'ghost',
    );

    expect(_surface(tester).scope, const CoachScope.global());
    expect(find.text('隨時問我，聊天卡住我來接。'), findsOneWidget);
  });

  testWidgets('鎖定的對象開著視窗時被刪 → 退回一般模式（ref.listen 路徑）', (tester) async {
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
    await _selectScope(tester, const Key('coach_scope_partner_p1'));
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
    await _selectScope(tester, const Key('coach_scope_partner_p1'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, questionB);
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining(questionB), findsOneWidget);

    // 切回仍在 loading 的 A 串：不得顯示 B 的問句。
    await _selectScope(tester, const Key('coach_scope_general'));
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

  testWidgets('快速切 scope 不得閃「正在送出問題」（controller build 必須同步）', (tester) async {
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

  // 額度說法照方案（Eric 2026-10-18）：Essential 已經是最高方案，不叫他升級，只說
  // 什麼時候恢復；Starter 照舊說升級（只會升到 Essential），每日那句不再說「明天」
  // （台灣早上 8 點才恢復）。走真的 API 服務與畫面，伺服器回額度 429。
  Map<String, dynamic> coachQuota429({required bool monthly}) => {
        'error': monthly ? 'Monthly limit exceeded' : 'Daily limit exceeded',
        'message': monthly
            ? '本月額度已用完，升級方案可取得更多分析與教練額度。'
            : '今日額度已用完，每天早上 8 點恢復；也可以升級取得更多額度。',
        'quotaNeeded': 1,
        'used': monthly ? 800 : 30,
        'limit': monthly ? 800 : 30,
        'monthlyLimit': 800,
        'dailyLimit': 30,
      };

  String textOf(WidgetTester tester, String fragment) =>
      tester.widget<Text>(find.textContaining(fragment)).data!;

  /// 問一題撞到額度：自動開一次付費牆，關掉後看額度卡。
  Future<void> askIntoQuota(WidgetTester tester) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(CoachSurface),
        matching: find.byType(TextField),
      ),
      '她已讀我兩天，我該追問嗎？',
    );
    // 送出鈕要等下一幀才會因為有字而亮起來。
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(_paywallExtras, hasLength(1));
    await tester.tap(find.text('關閉付費牆'));
    await tester.pumpAndSettle();
  }

  for (final monthly in [false, true]) {
    final period = monthly ? '本月' : '今日';
    final resetLine = monthly ? kMonthlyQuotaResetLine : kDailyQuotaResetLine;
    final usage = monthly ? '（800/800）' : '（30/30）';
    // 這題要 1 則、剩 0 則：付費頁照每月或每日、說「用完了」。
    final entry = PaywallEntry.forQuota(isMonthly: monthly, remaining: 0);

    testWidgets('$period額度用完：Essential 只看到什麼時候恢復，鈕寫「查看方案」', (tester) async {
      await _pumpQuota(
        tester,
        tier: SubscriptionTierHelper.essential,
        quotaBody: coachQuota429(monthly: monthly),
      );
      expect(
        textOf(tester, '幫教練釐清最多 3 次'),
        '幫教練釐清最多 3 次；正式建議扣 1 則，用完會說何時恢復。',
      );

      await askIntoQuota(tester);
      final message = textOf(tester, '額度已用完（');
      expect(message, contains(usage));
      expect(message, contains(resetLine));
      expect(message, isNot(contains('升級')));
      expect(message, isNot(contains('明天')));
      expect(textOf(tester, '這是額度限制'), isNot(contains('升級')));
      expect(find.text('查看方案'), findsOneWidget);
      expect(find.textContaining('升級'), findsNothing);
      await tester.tap(find.text('查看方案'));
      await tester.pumpAndSettle();
      expect(_paywallExtras, [entry, entry]);
    });

    testWidgets('$period額度用完：Starter 照舊說升級，不點名升級到 Starter', (tester) async {
      await _pumpQuota(
        tester,
        tier: SubscriptionTierHelper.starter,
        quotaBody: coachQuota429(monthly: monthly),
      );
      expect(
        textOf(tester, '幫教練釐清最多 3 次'),
        '幫教練釐清最多 3 次；正式建議扣 1 則，額度用完會提醒升級。',
      );

      await askIntoQuota(tester);
      final message = textOf(tester, '額度已用完（');
      expect(
        message,
        monthly
            ? '本月額度已用完$usage，升級後可以繼續問教練。'
            : '今日額度已用完$usage，$kDailyQuotaResetLine，也可以升級解鎖更多教練建議。',
      );
      expect(message, isNot(contains('Starter')));
      expect(
        textOf(tester, '這是額度限制'),
        '這是額度限制，不是教練失敗。升級或等額度重置後再試。',
      );
      expect(find.text('查看升級'), findsOneWidget);
      await tester.tap(find.text('查看升級'));
      await tester.pumpAndSettle();
      expect(_paywallExtras, [entry, entry]);
    });
  }

  // 規格 PR-5：「教練參考」的「關於我」不分範圍，送出的內容不是空的就標；
  // 讀取參數跟 controller 送出時同一組，標籤和實際送出的
  // effectiveStyleContext 要一致。
  group('教練參考：關於我', () {
    final withNotes = UserProfile.create(
      notes: '不要太快邀約',
      updatedAt: DateTime(2026, 10, 21),
    );

    List<Override> aboutMe(UserProfile? profile) => [
          userProfileRepositoryProvider
              .overrideWithValue(FakeUserProfileRepo(initial: profile)),
          authUserProfileScopeProvider.overrideWith(
            (ref) => Stream.value(FakeUserProfileRepo.testUid),
          ),
        ];

    Finder sourceChip(String label) => find.descendant(
          of: find.ancestor(
            of: find.text('教練參考'),
            matching: find.byType(Wrap),
          ),
          matching: find.text(label),
        );

    /// 問一題（伺服器回 500，不開付費頁），回傳送出去的請求內容。
    Future<Map<String, dynamic>> ask(
      WidgetTester tester,
      List<Map<String, dynamic>> calls,
    ) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(CoachSurface),
          matching: find.byType(TextField),
        ),
        '她回很快，要不要今晚直接約？',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      return calls.single;
    }

    setUp(() {
      SharedPreferences.setMockInitialValues(
        {AiDataSharingConsent.acceptedKeyForTesting: true},
      );
    });

    testWidgets('一般：填了關於我就標「關於我」，送出的也帶著', (tester) async {
      final calls = await _pump(
        tester,
        invokerStatus: 500,
        extraOverrides: aboutMe(withNotes),
      );
      expect(sourceChip('關於我'), findsOneWidget);
      expect(find.text('你的風格'), findsNothing);

      final body = await ask(tester, calls);
      expect(body['effectiveStyleContext'], contains('不要太快邀約'));
    });

    // PR-5 主審 1 P2：valueOrNull 在重新讀取失敗時會回上一次的值；controller
    // 送出時讀到的是這次的錯誤、退回不送，標籤不能還掛著「關於我」。
    testWidgets('讀過一次之後重新讀取失敗：不再標「關於我」，送出的也不帶', (tester) async {
      final repo = _FlakyProfileRepo(withNotes);
      final uid = StreamController<String?>();
      addTearDown(uid.close);
      final calls = await _pump(
        tester,
        invokerStatus: 500,
        extraOverrides: [
          userProfileRepositoryProvider.overrideWithValue(repo),
          authUserProfileScopeProvider.overrideWith((ref) => uid.stream),
        ],
      );
      uid.add('user-a');
      await tester.pumpAndSettle();
      expect(sourceChip('關於我'), findsOneWidget);

      repo.failLoads = true;
      uid.add('user-b');
      await tester.pumpAndSettle();
      // 確認真的走到「讀取失敗、但還留著上一次的值」，不是別的路徑讓這條通過
      // （PR-5 主審 2 建議）。
      final style = ProviderScope.containerOf(
        tester.element(find.byType(CoachSurface)),
      ).read(userProfileControllerProvider);
      expect(style.hasError, isTrue);
      expect(style.hasValue, isTrue);
      expect(sourceChip('關於我'), findsNothing);

      final body = await ask(tester, calls);
      expect(body.containsKey('effectiveStyleContext'), isFalse);
    });

    // 規格 PR-10：「這次不參考關於我」只管這一題：失敗重試也照它，拿到正式
    // 建議才回到預設。
    testWidgets('這次不參考關於我：這題不標不送、重試照它；拿到正式建議回到預設', (tester) async {
      final calls = <Map<String, dynamic>>[];
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachChatRepositoryProvider
                .overrideWithValue(MemoryCoachChatRepository()),
            coachChatApiServiceProvider.overrideWithValue(
              CoachChatApiService(
                invoker: (String _,
                    {required Map<String, dynamic> body}) async {
                  calls.add(body);
                  return calls.length == 1
                      ? const CoachChatInvokeResponse(
                          status: 500,
                          data: {'error': 'transient'},
                        )
                      : CoachChatInvokeResponse(
                          status: 200,
                          data: _formalAnswerBody(calls.length),
                        );
                },
              ),
            ),
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
            ..._partnerOverrides(const [], const {}),
            ...aboutMe(withNotes),
          ],
          child: const MaterialApp(home: GlobalCoachScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(CoachSurface),
        matching: find.byType(TextField),
      );

      expect(sourceChip('關於我'), findsOneWidget);
      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      expect(sourceChip('關於我'), findsNothing);

      await tester.enterText(field, '她回很快，要不要今晚直接約？');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls[0].containsKey('effectiveStyleContext'), isFalse);

      // 失敗：這一題還沒問完，開關照舊勾著，重試也不帶。
      expect(sourceChip('關於我'), findsNothing);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls[1].containsKey('effectiveStyleContext'), isFalse);

      // 拿到正式建議：回到預設，又標「關於我」，下一題照送。
      expect(sourceChip('關於我'), findsOneWidget);
      // 等失敗提示（SnackBar）收掉，它會蓋住送出鈕。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.enterText(field, '那明天約呢？');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      expect(calls, hasLength(3));
      expect(calls[2]['effectiveStyleContext'], contains('不要太快邀約'));
    });

    /// 照順序回應的教練（每次呼叫從 [responses] 取一個；Completer 可以延遲）。
    Future<void> pumpScripted(
      WidgetTester tester, {
      required List<Map<String, dynamic>> calls,
      required List<Future<CoachChatInvokeResponse> Function()> responses,
      List<Partner> partners = const [],
      MemoryCoachChatRepository? repo,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachChatRepositoryProvider
                .overrideWithValue(repo ?? MemoryCoachChatRepository()),
            coachChatApiServiceProvider.overrideWithValue(
              CoachChatApiService(
                invoker: (String _, {required Map<String, dynamic> body}) {
                  calls.add(body);
                  return responses[calls.length - 1]();
                },
              ),
            ),
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
            ..._partnerOverrides(partners, const {}),
            ...aboutMe(withNotes),
          ],
          child: const MaterialApp(home: GlobalCoachScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<CoachChatInvokeResponse> Function() ok(
      Map<String, dynamic> Function(int) body,
      int request,
    ) =>
        () async => CoachChatInvokeResponse(status: 200, data: body(request));

    Future<void> send(WidgetTester tester, String text) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(CoachSurface),
          matching: find.byType(TextField),
        ),
        text,
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
    }

    /// 切範圍：chip 在畫面上就先捲進來再點，不然走選單（同 [_selectScope]）。
    Future<void> switchScope(WidgetTester tester, Key key) async {
      if (find.byKey(key).evaluate().isNotEmpty) {
        await tester.ensureVisible(find.byKey(key));
        await tester.pumpAndSettle();
      }
      await _selectScope(tester, key);
      await tester.pumpAndSettle();
    }

    // PR-10 主審 1 P2：送出中改開關不算數，標籤要跟這次送出的一致。
    testWidgets('送出中開關鎖住：點了不變，標籤照這次送出的', (tester) async {
      final calls = <Map<String, dynamic>>[];
      final pending = Completer<CoachChatInvokeResponse>();
      await pumpScripted(
        tester,
        calls: calls,
        responses: [() => pending.future],
      );
      await send(tester, '她回很快，要不要今晚直接約？');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.single['effectiveStyleContext'], contains('不要太快邀約'));

      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      expect(sourceChip('關於我'), findsOneWidget, reason: '這次送出有帶關於我');

      pending.complete(
        CoachChatInvokeResponse(status: 200, data: _formalAnswerBody(1)),
      );
      await tester.pumpAndSettle();
      expect(sourceChip('關於我'), findsOneWidget);
    });

    // 同一題的釐清還沒答完：切走再切回來，選擇照留，回答釐清也不帶。
    testWidgets('釐清未完切換對象再回來：選擇照留，回答釐清不帶關於我', (tester) async {
      final calls = <Map<String, dynamic>>[];
      await pumpScripted(
        tester,
        calls: calls,
        partners: [_partner('p1', 'Alice')],
        responses: [
          ok(_clarificationBody, 1),
          ok(_formalAnswerBody, 2),
        ],
      );
      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      await send(tester, '她回很快，要不要今晚直接約？');
      await tester.pumpAndSettle();
      expect(calls[0].containsKey('effectiveStyleContext'), isFalse);
      expect(find.text('你原本想怎麼回她？'), findsOneWidget);

      await switchScope(tester, const Key('coach_scope_partner_p1'));
      await switchScope(tester, const Key('coach_scope_general'));
      expect(find.text('你原本想怎麼回她？'), findsOneWidget);
      expect(sourceChip('關於我'), findsNothing, reason: '這題還沒問完，選擇照留');

      await send(tester, '我原本想回好啊');
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls[1].containsKey('effectiveStyleContext'), isFalse);
      // 拿到正式建議：這題問完，回到預設。
      expect(sourceChip('關於我'), findsOneWidget);
    });

    // PR-10 主審 2：切走再切回時畫面問句記憶會被清掉，但正式建議回來照樣算
    // 這題問完，開關要回到預設。
    testWidgets('送出中切走再切回、正式建議才回來：開關回到預設，下一題照送', (tester) async {
      final calls = <Map<String, dynamic>>[];
      final pending = Completer<CoachChatInvokeResponse>();
      await pumpScripted(
        tester,
        calls: calls,
        partners: [_partner('p1', 'Alice')],
        responses: [() => pending.future, ok(_formalAnswerBody, 2)],
      );
      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      await send(tester, '她回很快，要不要今晚直接約？');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.single.containsKey('effectiveStyleContext'), isFalse);

      // 送出中有進度動畫，不能 pumpAndSettle；兩次切換之間等選單收起。
      await _selectScope(tester, const Key('coach_scope_partner_p1'));
      await tester.pump(const Duration(seconds: 1));
      await _selectScope(tester, const Key('coach_scope_general'));
      await tester.pump(const Duration(seconds: 1));
      expect(sourceChip('關於我'), findsNothing, reason: '還在送出，選擇照留');

      pending.complete(
        CoachChatInvokeResponse(status: 200, data: _formalAnswerBody(1)),
      );
      await tester.pumpAndSettle();
      expect(sourceChip('關於我'), findsOneWidget);

      await send(tester, '那明天約呢？');
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls[1]['effectiveStyleContext'], contains('不要太快邀約'));
    });

    testWidgets('釐清未完切走再切回、直接看建議：照選擇不帶，正式建議後回到預設', (tester) async {
      final calls = <Map<String, dynamic>>[];
      await pumpScripted(
        tester,
        calls: calls,
        partners: [_partner('p1', 'Alice')],
        responses: [ok(_clarificationBody, 1), ok(_formalAnswerBody, 2)],
      );
      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      await send(tester, '她回很快，要不要今晚直接約？');
      await tester.pumpAndSettle();
      await switchScope(tester, const Key('coach_scope_partner_p1'));
      await switchScope(tester, const Key('coach_scope_general'));

      final forceAnswer = find.text('直接看建議（扣 1 則）');
      await tester.ensureVisible(forceAnswer);
      await tester.pumpAndSettle();
      await tester.tap(forceAnswer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('扣 1 則並生成'));
      await tester.pumpAndSettle();

      expect(calls, hasLength(2));
      expect(calls[1]['forceAnswer'], isTrue);
      expect(calls[1].containsKey('effectiveStyleContext'), isFalse);
      expect(sourceChip('關於我'), findsOneWidget, reason: '正式建議回來，這題問完');
    });

    testWidgets('還沒送就切走再回來：選擇不留，回到預設', (tester) async {
      await pumpScripted(
        tester,
        calls: <Map<String, dynamic>>[],
        partners: [_partner('p1', 'Alice')],
        responses: const [],
      );
      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      expect(sourceChip('關於我'), findsNothing);

      await switchScope(tester, const Key('coach_scope_partner_p1'));
      await switchScope(tester, const Key('coach_scope_general'));
      expect(sourceChip('關於我'), findsOneWidget);
    });

    // 重開畫面：只顯示這次進來後問的問答，舊的釐清不會出現，下一句在畫面上
    // 就是新問題；開關回到預設，標籤也照實標「關於我」。
    testWidgets('重開畫面：舊釐清不顯示、開關回到預設、標籤照實標關於我', (tester) async {
      final repo = MemoryCoachChatRepository();
      final calls = <Map<String, dynamic>>[];
      await pumpScripted(
        tester,
        calls: calls,
        repo: repo,
        responses: [ok(_clarificationBody, 1)],
      );
      await tester.tap(find.byKey(const Key('coach-skip-about-me')));
      await tester.pump();
      await send(tester, '她回很快，要不要今晚直接約？');
      await tester.pumpAndSettle();
      expect(find.text('你原本想怎麼回她？'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScripted(
        tester,
        calls: calls,
        repo: repo,
        responses: [ok(_clarificationBody, 1)],
      );
      expect(find.text('你原本想怎麼回她？'), findsNothing);
      expect(sourceChip('關於我'), findsOneWidget);
      final toggle = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const Key('coach-skip-about-me')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(toggle.properties.toggled, isFalse);
    });

    testWidgets('沒填關於我：不出現「這次不參考關於我」', (tester) async {
      await _pump(tester, invokerStatus: 500, extraOverrides: aboutMe(null));
      expect(find.byKey(const Key('coach-skip-about-me')), findsNothing);
    });

    testWidgets('一般：沒填關於我就不標，也不送', (tester) async {
      final calls = await _pump(
        tester,
        invokerStatus: 500,
        extraOverrides: aboutMe(null),
      );
      expect(sourceChip('關於我'), findsNothing);

      final body = await ask(tester, calls);
      expect(body.containsKey('effectiveStyleContext'), isFalse);
    });

    testWidgets('對象資料被標記有問題：照樣標「只看本段」，關於我也照實標', (tester) async {
      final partner = _partner('p1', 'Alice');
      final calls = <Map<String, dynamic>>[];
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachChatRepositoryProvider
                .overrideWithValue(MemoryCoachChatRepository()),
            coachChatApiServiceProvider.overrideWithValue(
              CoachChatApiService(
                invoker: _recordingInvoker(calls, status: 500),
              ),
            ),
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
            partnerListProvider.overrideWithValue([partner]),
            dataQualityFlagProvider(partner.id).overrideWith(
              (_) => DataQualityFlag.flagged(
                NamePair.canonical('Alice', 'Anna'),
              ),
            ),
            partnerByIdProvider(partner.id).overrideWithValue(partner),
            partnerAggregateProvider(partner.id)
                .overrideWithValue(PartnerAggregateView.empty()),
            conversationsByPartnerProvider(partner.id)
                .overrideWithValue(const []),
            ...aboutMe(withNotes),
          ],
          child: MaterialApp(
            home: GlobalCoachScreen(lockedPartnerId: partner.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceChip('只看本段'), findsOneWidget);
      expect(sourceChip('對象資料'), findsNothing);
      expect(sourceChip('關於我'), findsOneWidget);

      final body = await ask(tester, calls);
      expect(body['effectiveStyleContext'], contains('不要太快邀約'));
    });
  });
}
