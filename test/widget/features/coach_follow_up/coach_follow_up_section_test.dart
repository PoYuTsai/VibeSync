// Phase E Task 6 — CoachFollowUpSection 薄 wrapper widget TDD spec.
//
// 對象頁教練區改掛 CoachSurface（partner scope）：section 只剩
// 標題＋三情境 chip＋caption＋openCoach entry＋CoachSurface。chip 點擊
// 只「種入」lifecyclePhase＋prefill＋focus token（絕無 auto-send）；
// 舊罐頭卡 engine（input sheet / controller.generate / result card）
// 全數凍結退場，不再被本 widget 引用。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
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

/// 三情境 chip 的規格三元組（Task 6 拍板；與實作常數字面對齊）。
const _chipSpecs = [
  (phase: 'chatStalled', label: '聊天卡住了', prefill: '我們聊天卡住了，接下來該怎麼辦？'),
  (phase: 'prepareInvite', label: '想約她出來', prefill: '我想約她出來，該怎麼開口比較自然？'),
  (phase: 'postDate', label: '約完會之後', prefill: '剛約完會，接下來要怎麼經營比較好？'),
];

Partner _partner() => Partner(
      id: _partnerId,
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
    })> _pump(
  WidgetTester tester, {
  Future<void> Function()? onQuotaExceeded,
  Key? openCoachEntryAnchorKey,
  bool openCoachInputOnFirstBuild = false,
  bool compactPracticePresentation = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final repo = MemoryCoachChatRepository();
  final apiCalls = <Map<String, dynamic>>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachChatRepositoryProvider.overrideWithValue(repo),
        coachChatApiServiceProvider.overrideWithValue(
          CoachChatApiService(invoker: _recordingInvoker(apiCalls)),
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
              onQuotaExceeded: onQuotaExceeded,
              openCoachEntryAnchorKey: openCoachEntryAnchorKey,
              openCoachInputOnFirstBuild: openCoachInputOnFirstBuild,
              compactPracticePresentation: compactPracticePresentation,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repo: repo, apiCalls: apiCalls);
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
    testWidgets('渲染三情境 chip＋openCoach entry＋partner-scope CoachSurface',
        (t) async {
      await _pump(t);

      for (final chip in _chipSpecs) {
        expect(find.text(chip.label), findsOneWidget);
      }
      expect(find.text('或直接問教練一個問題…'), findsOneWidget);

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

    testWidgets('openCoach entry 支援 anchor key（deep-link 捲動錨點不變）', (t) async {
      final anchorKey = GlobalKey();
      await _pump(t, openCoachEntryAnchorKey: anchorKey);

      expect(
        find.descendant(
          of: find.byKey(anchorKey),
          matching: find.text('或直接問教練一個問題…'),
        ),
        findsOneWidget,
      );
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

    testWidgets('點 openCoach entry → token 遞增、lifecyclePhase null、prefill null',
        (t) async {
      final pumped = await _pump(t);
      final baseToken = _surface(t).focusRequestToken;

      // 先種一個 chip，確認 openCoach 會清掉 phase/prefill。
      await t.tap(find.text('聊天卡住了'));
      await t.pumpAndSettle();
      await t.tap(find.text('或直接問教練一個問題…'));
      await t.pumpAndSettle();

      final surface = _surface(t);
      expect(surface.focusRequestToken, baseToken + 2);
      expect(surface.lifecyclePhase, isNull);
      expect(surface.prefillText, isNull);
      expect(pumped.apiCalls, isEmpty);
    });

    testWidgets('openCoachInputOnFirstBuild → 首幀後自動 bump focus token（無 phase）',
        (t) async {
      await _pump(t, openCoachInputOnFirstBuild: true);

      final surface = _surface(t);
      expect(surface.focusRequestToken, greaterThan(0));
      expect(surface.lifecyclePhase, isNull);
      expect(surface.prefillText, isNull);
    });
  });

  group('CoachFollowUpSection — 舊 engine 退場', () {
    testWidgets('點 chip 不再開舊 input sheet／不呼叫舊 generate 流程', (t) async {
      await _pump(t);

      await t.tap(find.text('想約她出來'));
      await t.pumpAndSettle();

      expect(find.byType(CoachFollowUpInputSheet), findsNothing);
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
}
