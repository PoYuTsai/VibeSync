// Phase E Task 6 — CoachFollowUpSection 薄 wrapper widget TDD spec.
//
// 對象頁教練區改掛 CoachSurface（partner scope）：section 只剩
// 標題＋三情境 chip＋caption＋openCoach entry＋CoachSurface。chip 點擊
// 只「種入」lifecyclePhase＋prefill＋focus token（絕無 auto-send）；
// 舊罐頭卡 engine（input sheet / controller.generate / result card）
// Phase F 已整包刪除，不再被本 widget 引用。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/learning/domain/dating_knowledge_links.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

import '../../../helpers/memory_coach_chat_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────

const _partnerId = 'p1';
const _altPartnerId = 'p2';

/// 三情境 chip 的規格三元組（Task 6 拍板；與實作常數字面對齊）。
const _chipSpecs = [
  (phase: 'chatStalled', label: '聊天卡住了', prefill: '我們聊天卡住了，接下來該怎麼辦？'),
  (phase: 'prepareInvite', label: '想約她出來', prefill: '我想約她出來，該怎麼開口比較自然？'),
  (phase: 'postDate', label: '約完會之後', prefill: '剛約完會，接下來要怎麼經營比較好？'),
];

Partner _partner([String id = _partnerId]) => Partner(
      id: id,
      name: 'Mia',
      ownerUserId: 'u1',
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

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

/// 記錄每次真正打到 API 的呼叫（auto-send 佐證：必須為 0）。
CoachChatInvoker _recordingInvoker(
  List<Map<String, dynamic>> calls, {
  int status = 429,
  Map<String, dynamic>? data,
}) {
  return (String _, {required Map<String, dynamic> body}) async {
    calls.add(body);
    return CoachChatInvokeResponse(
      status: status,
      data: data ??
          <String, dynamic>{
            'error': 'Daily limit exceeded',
            'used': 15,
            'limit': 15,
          },
    );
  };
}

// ── Pump helper ───────────────────────────────────────────────────────────

Future<
    ({
      MemoryCoachChatRepository repo,
      List<Map<String, dynamic>> apiCalls,
      Future<void> Function({
        required String partnerId,
        required bool openCoachInputRequested,
      }) rebuild,
    })> _pump(
  WidgetTester tester, {
  Future<void> Function()? onQuotaExceeded,
  bool openCoachInputRequested = false,
  bool compactPracticePresentation = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final repo = MemoryCoachChatRepository();
  final apiCalls = <Map<String, dynamic>>[];
  // 同一組 overrides 物件重複餵給 ProviderScope（rebuild 不換 container）；
  // 兩個 partnerId 都預先掛好 family overrides，供原地切換情境用。
  final overrides = [
    coachChatRepositoryProvider.overrideWithValue(repo),
    coachChatApiServiceProvider.overrideWithValue(
      CoachChatApiService(invoker: _recordingInvoker(apiCalls)),
    ),
    coachingOutcomeRepositoryProvider
        .overrideWithValue(MemoryCoachingOutcomeRepository()),
    partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
    for (final id in const [_partnerId, _altPartnerId]) ...[
      partnerByIdProvider(id).overrideWith((_) => _partner(id)),
      partnerAggregateProvider(id)
          .overrideWith((_) => PartnerAggregateView.empty()),
      dataQualityFlagProvider(id)
          .overrideWith((_) => const DataQualityFlag.unflagged()),
    ],
  ];

  Future<void> pumpTree({
    required String partnerId,
    required bool openCoachInputRequested,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachFollowUpSection(
                partnerId: partnerId,
                onQuotaExceeded: onQuotaExceeded,
                openCoachInputRequested: openCoachInputRequested,
                compactPracticePresentation: compactPracticePresentation,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await pumpTree(
    partnerId: _partnerId,
    openCoachInputRequested: openCoachInputRequested,
  );
  return (
    repo: repo,
    apiCalls: apiCalls,
    rebuild: ({
      required String partnerId,
      required bool openCoachInputRequested,
    }) =>
        pumpTree(
          partnerId: partnerId,
          openCoachInputRequested: openCoachInputRequested,
        ),
  );
}

CoachSurface _surface(WidgetTester tester) =>
    tester.widget<CoachSurface>(find.byType(CoachSurface));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(
      {AiDataSharingConsent.acceptedKeyForTesting: true},
    );
  });

  group('CoachFollowUpSection — 薄 wrapper 渲染', () {
    testWidgets('渲染三情境 chip＋partner-scope CoachSurface', (t) async {
      await _pump(t);

      for (final chip in _chipSpecs) {
        expect(find.text(chip.label), findsOneWidget);
      }

      final surface = _surface(t);
      expect(surface.scope.isConversation, isFalse);
      expect(surface.scope.id, _partnerId);
      // 初始：無 phase、無 prefill、token 起點。
      expect(surface.lifecyclePhase, isNull);
      expect(surface.prefillText, isNull);
    });

    testWidgets('caption＝「釐清免費，正式建議才扣 1 則」；舊扣費文案全滅', (t) async {
      await _pump(t);

      expect(find.text('釐清免費，正式建議才扣 1 則'), findsOneWidget);
      expect(find.textContaining('生成會扣 1 則'), findsNothing);
      expect(find.textContaining('重新生成會再扣 1 則額度'), findsNothing);
    });

    testWidgets('compact 練習版仍渲染三 chip＋CoachSurface', (t) async {
      await _pump(t, compactPracticePresentation: true);

      for (final chip in _chipSpecs) {
        expect(find.text(chip.label), findsOneWidget);
      }
      expect(find.byType(CoachSurface), findsOneWidget);
    });
  });

  group('CoachFollowUpSection — chip 種入 CoachSurface', () {
    testWidgets('點 chip → lifecyclePhase＋prefill＋focus token 遞增，絕無 auto-send',
        (t) async {
      final pumped = await _pump(t);
      final baseToken = _surface(t).focusRequestToken;

      var taps = 0;
      for (final chip in _chipSpecs) {
        await t.tap(find.text(chip.label));
        await t.pumpAndSettle();
        taps += 1;

        final surface = _surface(t);
        expect(surface.lifecyclePhase, chip.phase);
        expect(surface.prefillText, chip.prefill);
        expect(surface.focusRequestToken, baseToken + taps);
        // prefill 落在輸入框、等待用戶自行送出。
        expect(find.widgetWithText(TextField, chip.prefill), findsOneWidget);
      }

      // 絕無 auto-send：零 API 呼叫、零落卡。
      expect(pumped.apiCalls, isEmpty);
      expect(pumped.repo.putUnifiedCalls, 0);
      expect(find.textContaining('你剛剛問'), findsNothing);
    });

    testWidgets('openCoachInputRequested → 首幀後自動 bump focus token（無 phase）',
        (t) async {
      await _pump(t, openCoachInputRequested: true);

      final surface = _surface(t);
      expect(surface.focusRequestToken, greaterThan(0));
      expect(surface.lifecyclePhase, isNull);
      expect(surface.prefillText, isNull);
    });

    testWidgets('partnerId 原地切換重置閂鎖 → 新對象 false→true 再次 bump token', (t) async {
      final pumped = await _pump(t, openCoachInputRequested: true);

      // 首幀 auto-focus 已發、閂鎖鎖上。
      expect(_surface(t).focusRequestToken, 1);

      // 原地切換對象（flag 收回）→ 同對象 false→true transition。
      await pumped.rebuild(
        partnerId: _altPartnerId,
        openCoachInputRequested: false,
      );
      await pumped.rebuild(
        partnerId: _altPartnerId,
        openCoachInputRequested: true,
      );

      // partnerId 切換必須重置閂鎖：新對象的請求要再 bump 一次。
      expect(_surface(t).focusRequestToken, 2);
    });
  });

  group('CoachFollowUpSection — 舊 engine 退場', () {
    testWidgets('點 chip 不再開舊 input sheet／不呼叫舊 generate 流程', (t) async {
      await _pump(t);

      await t.tap(find.text('想約她出來'));
      await t.pumpAndSettle();

      // 舊 input sheet widget 型別已於 Phase F 刪除（無從 findsByType）；
      // 以其專屬文案佐證 sheet 表面不存在。
      expect(find.text('產生跟進建議'), findsNothing);
      // 舊 with-result 表面（重新生成／換情境）也不復存在。
      expect(find.text('重新生成'), findsNothing);
      expect(find.text('換情境'), findsNothing);
    });
  });

  group('CoachFollowUpSection — quota → paywall wiring', () {
    testWidgets('CoachSurface ask 撞 quota → onQuotaExceeded 恰好一次', (t) async {
      var paywallOpenCount = 0;
      final pumped = await _pump(
        t,
        onQuotaExceeded: () async => paywallOpenCount += 1,
      );

      await t.tap(find.text('想約她出來'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.arrow_upward_rounded));
      await t.pumpAndSettle();

      expect(pumped.apiCalls, hasLength(1));
      expect(paywallOpenCount, 1);
    });
  });

  group('CoachFollowUpSection — Dating Knowledge Library 入口', () {
    const linkKey = Key('coach_follow_up_knowledge_link');

    testWidgets('沒選情境時不出現——沒有情境就無從得知該連哪一章', (t) async {
      await _pump(t);
      expect(find.byKey(linkKey), findsNothing);
    });

    testWidgets('每個情境 chip 都能叫出入口，且都有對應章節', (t) async {
      await _pump(t);

      for (final chip in _chipSpecs) {
        await t.tap(find.text(chip.label));
        await t.pumpAndSettle();

        expect(
          find.byKey(linkKey),
          findsOneWidget,
          reason: '點了「${chip.label}」之後應該出現知識庫入口',
        );
        expect(
          DatingKnowledgeLinks.forFollowUpPhase(chip.phase),
          isNotNull,
          reason: 'phase ${chip.phase} 沒有對應章節，入口會連不到東西',
        );
      }
    });

    testWidgets('入口不搶 chip 的工作：點了之後仍然沒有 auto-send', (t) async {
      final pumped = await _pump(t);

      await t.tap(find.text('聊天卡住了'));
      await t.pumpAndSettle();
      expect(find.byKey(linkKey), findsOneWidget);

      // chip 原本的職責（種入 phase／prefill）沒有被入口列改掉。
      expect(_surface(t).lifecyclePhase, 'chatStalled');
      expect(pumped.apiCalls, isEmpty);
    });
  });

  // CoachSurface 在這棵樹裡被渲染，composer 的版面／焦點行為一併在這裡驗。
  group('CoachSurface — composer 版面與焦點', () {
    testWidgets('五個灰色快捷問句 chip 已整組移除，連同知識庫入口', (t) async {
      await _pump(t);

      for (final question in const [
        '她是什麼意思？',
        '我該怎麼回？',
        '我是不是太急？',
        '這局值不值得？',
        '我該推進嗎？',
      ]) {
        expect(find.text(question), findsNothing);
      }
      // chip 是知識庫入口唯一的觸發來源，chip 沒了入口也不該再出現。
      expect(
        find.byKey(const Key('coach_surface_knowledge_link')),
        findsNothing,
      );
    });

    testWidgets('未聚焦：suffix 只有送出鈕、沒有收起鍵盤', (t) async {
      await _pump(t);

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byTooltip('收起鍵盤'), findsNothing);
      expect(find.byIcon(Icons.keyboard_hide_outlined), findsNothing);
    });

    testWidgets('聚焦：收起鍵盤出現在 header（不在輸入框 suffix），點了即失焦', (t) async {
      await _pump(t);

      await t.showKeyboard(find.byType(TextField));
      await t.pumpAndSettle();

      final hideButton = find.byTooltip('收起鍵盤');
      expect(hideButton, findsOneWidget);
      // 收起鍵盤已移出輸入框：suffix 只剩送出鈕。
      expect(
        find.ancestor(of: hideButton, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byIcon(Icons.arrow_upward_rounded),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );

      await t.tap(hideButton);
      await t.pumpAndSettle();

      final input = t.widget<TextField>(find.byType(TextField));
      expect(input.focusNode?.hasFocus, isNot(isTrue));
      expect(find.byTooltip('收起鍵盤'), findsNothing);
    });

    testWidgets('onCoachInputFocusChanged 隨聚焦/失焦上拋 true/false', (t) async {
      final events = <bool>[];
      await _pumpWithFocusListener(t, events.add);

      await t.showKeyboard(find.byType(TextField));
      await t.pumpAndSettle();
      expect(events, [true]);

      t.widget<TextField>(find.byType(TextField)).focusNode?.unfocus();
      await t.pumpAndSettle();
      expect(events, [true, false]);
    });
  });
}

/// 帶焦點監聽的精簡 pump（其餘 overrides 與 [_pump] 對齊）。
Future<void> _pumpWithFocusListener(
  WidgetTester tester,
  ValueChanged<bool> onCoachInputFocusChanged,
) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
        partnerByIdProvider(_partnerId).overrideWith((_) => _partner()),
        partnerAggregateProvider(_partnerId)
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider(_partnerId)
            .overrideWith((_) => const DataQualityFlag.unflagged()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CoachFollowUpSection(
              partnerId: _partnerId,
              onCoachInputFocusChanged: onCoachInputFocusChanged,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
