// test/widget/features/partner/getting_started_checklist_test.dart
//
// 起步清單卡（訊號驅動，全完成即消失）。2026-08-01 起三項（iOS）／兩項（Android）：
// - 關於我／第一次分析或第一局練習（二擇一）／設定鍵盤（僅 iOS）。
// - 非 iOS 隱藏鍵盤項；全完成整卡 SizedBox.shrink()。
// - 未完成項點擊導航正確；打勾項發 checklist_item_done once 埋點。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/partner/presentation/widgets/getting_started_checklist.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class _SeededProfileController extends UserProfileController {
  _SeededProfileController(this._profile);
  final UserProfile? _profile;

  @override
  Future<UserProfile?> build() async => _profile;
}

AnalysisHistoryEvent _analyzeEvent() => AnalysisHistoryEvent.analyze(
      id: 'e1',
      createdAt: DateTime(2026, 7, 1),
      conversationId: 'c1',
      subjectName: 'Vivi',
      enthusiasmScore: 66,
      gameStageLabel: 'premise',
    );

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: GettingStartedChecklist()),
        ),
        GoRoute(
          path: '/profile/about-me',
          builder: (_, __) => const Scaffold(body: Text('about-me-screen')),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, __) => const Scaffold(body: Text('partner-new-screen')),
        ),
        GoRoute(
          path: '/settings/keyboard',
          builder: (_, __) => const Scaffold(body: Text('keyboard-screen')),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  UserProfile? profile,
  List<AnalysisHistoryEvent> historyEvents = const [],
  List<Partner> partners = const [],
  FunnelTracker? tracker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileControllerProvider.overrideWith(
          () => _SeededProfileController(profile),
        ),
        analysisHistoryEventsProvider.overrideWithValue(historyEvents),
        partnerListProvider.overrideWithValue(partners),
        if (tracker != null) funnelTrackerProvider.overrideWithValue(tracker),
      ],
      child: MaterialApp.router(routerConfig: _stubRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 靜態 ValueNotifier 會跨測試殘留，逐測歸零。
    OnboardingService.keyboardCompletedListenable.value = false;
  });

  final iosVariant = TargetPlatformVariant.only(TargetPlatform.iOS);
  final androidVariant = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets('全未完成（iOS）→ 卡片與三項全部渲染，無跟進提醒項', (tester) async {
    await _pump(tester);

    expect(find.byKey(GettingStartedChecklist.cardKey), findsOneWidget);
    expect(find.text('填 30 秒關於我'), findsOneWidget);
    expect(find.text('完成第一次分析或練習'), findsOneWidget);
    expect(find.text('設定 AI 鍵盤'), findsOneWidget);
    expect(find.text('開啟跟進提醒'), findsNothing);
  }, variant: iosVariant);

  testWidgets('部分完成 → 完成項打勾、未完成項不打勾', (tester) async {
    await _pump(
      tester,
      profile: UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime(2026, 7, 1),
      ),
      historyEvents: [_analyzeEvent()],
    );

    expect(
      find.byKey(const Key('checklist_done_profile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('checklist_done_first_action')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('checklist_done_keyboard')), findsNothing);
  }, variant: iosVariant);

  testWidgets('Android → 鍵盤項整個不顯示（僅兩項）', (tester) async {
    await _pump(tester);

    expect(find.text('設定 AI 鍵盤'), findsNothing);
    expect(find.text('填 30 秒關於我'), findsOneWidget);
    expect(find.text('完成第一次分析或練習'), findsOneWidget);
  }, variant: androidVariant);

  testWidgets('非 iOS 且兩項完成 → 整卡消失', (tester) async {
    await _pump(
      tester,
      profile: UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime(2026, 7, 1),
      ),
      historyEvents: [_analyzeEvent()],
    );

    expect(find.byKey(GettingStartedChecklist.cardKey), findsNothing);
  }, variant: androidVariant);

  testWidgets('未完成項點擊導航：關於我 → /profile/about-me', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('填 30 秒關於我'));
    await tester.pumpAndSettle();

    expect(find.text('about-me-screen'), findsOneWidget);
  }, variant: iosVariant);

  testWidgets('未完成項點擊導航：鍵盤 → /settings/keyboard', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('設定 AI 鍵盤'));
    await tester.pumpAndSettle();
    expect(find.text('keyboard-screen'), findsOneWidget);
  }, variant: iosVariant);

  testWidgets('第一步未完成＋沒對象 → 點擊導 /partner/new', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('完成第一次分析或練習'));
    await tester.pumpAndSettle();

    expect(find.text('partner-new-screen'), findsOneWidget);
  }, variant: iosVariant);

  testWidgets('全完成＋贈抽未消耗 → 變身領獎卡（不再直接消失）', (tester) async {
    OnboardingService.keyboardCompletedListenable.value = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileControllerProvider.overrideWith(
            () => _SeededProfileController(UserProfile.create(
              interactionStyle: InteractionStyle.humorous,
              updatedAt: DateTime(2026, 7, 1),
            )),
          ),
          analysisHistoryEventsProvider.overrideWithValue([_analyzeEvent()]),
          partnerListProvider.overrideWithValue(const []),
          onboardingDrawBonusConsumedProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp.router(routerConfig: _stubRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GettingStartedChecklist.cardKey), findsNothing);
    expect(find.byKey(OnboardingDrawRewardCard.cardKey), findsOneWidget);
    expect(find.text('去抽卡'), findsOneWidget);
  }, variant: iosVariant);

  testWidgets('全完成＋贈抽已消耗 → 整卡消失', (tester) async {
    OnboardingService.keyboardCompletedListenable.value = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileControllerProvider.overrideWith(
            () => _SeededProfileController(UserProfile.create(
              interactionStyle: InteractionStyle.humorous,
              updatedAt: DateTime(2026, 7, 1),
            )),
          ),
          analysisHistoryEventsProvider.overrideWithValue([_analyzeEvent()]),
          partnerListProvider.overrideWithValue(const []),
          onboardingDrawBonusConsumedProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp.router(routerConfig: _stubRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GettingStartedChecklist.cardKey), findsNothing);
    expect(find.byKey(OnboardingDrawRewardCard.cardKey), findsNothing);
  }, variant: iosVariant);

  testWidgets('鍵盤引導走完寫旗標後：清單鍵盤項即時打勾（stale bug 回歸鎖）', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('checklist_done_keyboard')), findsNothing);

    // 模擬設定流程走完寫旗標（本 widget 不重掛）——必須即時反映。
    await OnboardingService.markKeyboardCompleted();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checklist_done_keyboard')), findsOneWidget);
  }, variant: iosVariant);
}
