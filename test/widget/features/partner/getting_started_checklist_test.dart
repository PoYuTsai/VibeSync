// test/widget/features/partner/getting_started_checklist_test.dart
//
// Tier 2 批 2：首頁起步清單卡（四項訊號驅動，全完成即消失）。
// - 關於我／第一次分析或第一局練習（二擇一）／開跟進提醒／設定鍵盤（僅 iOS）。
// - 非 iOS 隱藏鍵盤項；全完成整卡 SizedBox.shrink()。
// - 未完成項點擊導航正確；打勾項發 checklist_item_done once 埋點。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
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

class _FakeOptInStore extends FollowUpOptInStore {
  _FakeOptInStore(this.state);
  FollowUpOptIn state;
  final _changes = StreamController<FollowUpOptIn>.broadcast();

  @override
  FollowUpOptIn read() => state;

  @override
  Future<void> write(FollowUpOptIn value) async {
    state = value;
    _changes.add(value);
  }

  @override
  Stream<FollowUpOptIn> changes() => _changes.stream;
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
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('settings-screen')),
        ),
        GoRoute(
          path: '/settings/keyboard',
          builder: (_, __) => const Scaffold(body: Text('keyboard-screen')),
        ),
      ],
    );

Future<_FakeOptInStore> _pump(
  WidgetTester tester, {
  UserProfile? profile,
  List<AnalysisHistoryEvent> historyEvents = const [],
  FollowUpOptIn optIn = FollowUpOptIn.unknown,
  List<Partner> partners = const [],
  FunnelTracker? tracker,
}) async {
  final optInStore = _FakeOptInStore(optIn);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileControllerProvider.overrideWith(
          () => _SeededProfileController(profile),
        ),
        analysisHistoryEventsProvider.overrideWithValue(historyEvents),
        followUpOptInStoreProvider.overrideWithValue(optInStore),
        partnerListProvider.overrideWithValue(partners),
        if (tracker != null) funnelTrackerProvider.overrideWithValue(tracker),
      ],
      child: MaterialApp.router(routerConfig: _stubRouter()),
    ),
  );
  await tester.pumpAndSettle();
  return optInStore;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final iosVariant = TargetPlatformVariant.only(TargetPlatform.iOS);
  final androidVariant = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets('全未完成（iOS）→ 卡片與四項全部渲染', (tester) async {
    await _pump(tester);

    expect(find.byKey(GettingStartedChecklist.cardKey), findsOneWidget);
    expect(find.text('填 30 秒關於我'), findsOneWidget);
    expect(find.text('完成第一次分析或練習'), findsOneWidget);
    expect(find.text('開啟跟進提醒'), findsOneWidget);
    expect(find.text('設定 AI 鍵盤'), findsOneWidget);
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
    expect(find.byKey(const Key('checklist_done_follow_up')), findsNothing);
    expect(find.byKey(const Key('checklist_done_keyboard')), findsNothing);
  }, variant: iosVariant);

  testWidgets('Android → 鍵盤項整個不顯示', (tester) async {
    await _pump(tester);

    expect(find.text('設定 AI 鍵盤'), findsNothing);
    expect(find.text('填 30 秒關於我'), findsOneWidget);
  }, variant: androidVariant);

  testWidgets('非 iOS 且前三項完成 → 整卡消失', (tester) async {
    await _pump(
      tester,
      profile: UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime(2026, 7, 1),
      ),
      historyEvents: [_analyzeEvent()],
      optIn: FollowUpOptIn.granted,
    );

    expect(find.byKey(GettingStartedChecklist.cardKey), findsNothing);
  }, variant: androidVariant);

  testWidgets('未完成項點擊導航：關於我 → /profile/about-me', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('填 30 秒關於我'));
    await tester.pumpAndSettle();

    expect(find.text('about-me-screen'), findsOneWidget);
  }, variant: iosVariant);

  testWidgets('未完成項點擊導航：跟進提醒 → /settings、鍵盤 → /settings/keyboard',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('開啟跟進提醒'));
    await tester.pumpAndSettle();
    expect(find.text('settings-screen'), findsOneWidget);

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

  testWidgets('設定頁開啟提醒後回首頁：清單即時打勾、全完成整卡即時消失（stale bug 回歸鎖）',
      (tester) async {
    final store = await _pump(
      tester,
      profile: UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime(2026, 7, 1),
      ),
      historyEvents: [_analyzeEvent()],
    );
    expect(find.byKey(const Key('checklist_done_follow_up')), findsNothing);

    // 模擬設定頁 toggle 寫入（本 widget 不重掛）——必須即時反映。
    await store.write(FollowUpOptIn.granted);
    await tester.pumpAndSettle();

    // Android variant：無鍵盤項，三項全完成 → 整卡消失。
    expect(find.byKey(GettingStartedChecklist.cardKey), findsNothing);
  }, variant: androidVariant);
}
