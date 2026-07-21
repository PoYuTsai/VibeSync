// Regression: the mind-map「下一步」node must land the partner-detail
// background ON the coach follow-up section (not the top hero/heat cards)
// before the coach input takes focus.
//
// These tests encode the real device condition the previous tests missed:
//   • a tall surface (the old focus tests used 520px, which kept the section
//     inside the lazy ListView's viewport+cacheExtent so it "worked"); and
//   • a dogfood partner WITH several conversation records, pushing the coach
//     section far below the built range — exactly when ensureVisible-on-an-
//     unbuilt-GlobalKey silently no-ops.
//
// Phase E Task 7: the orchestrator no longer opens the legacy input sheet
// (which charged via the legacy controller while the new UI renders no legacy
// result card — the user paid and saw nothing). deep-link focusAction=
// openCoachInput now focuses the CoachSurface input instead, and consent is
// NOT pre-prompted by the orchestrator (CoachSurface gates it at ask time).
//
// The router test drives the REAL router (mind map → tap → detail) instead of
// building PartnerDetailScreen directly, so the route/scroll/focus timing is
// faithful rather than short-circuited.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coach_follow_up/data/providers/coach_follow_up_providers.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_mind_map_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_view.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

import '../../../helpers/memory_coach_chat_repository.dart';

class _FakeCoachFollowUpRepo implements CoachFollowUpRepository {
  final Map<String, CoachFollowUpResult> _store = {};
  @override
  CoachFollowUpResult? get(String id) => _store[id];
  @override
  Future<void> put(CoachFollowUpResult r) async => _store[r.partnerId] = r;
  @override
  Future<void> delete(String id) async => _store.remove(id);
  @override
  Future<void> clearAll() async => _store.clear();
}

class _FakeStyleRepo implements PartnerStyleRepository {
  final Map<String, PartnerStyleOverride> byPartner = {};
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async =>
      byPartner[partnerId];
  @override
  Future<void> save(PartnerStyleOverride o) async {}
  @override
  Future<void> delete(String partnerId) async => byPartner.remove(partnerId);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      ownerUserId: 'u1',
    );

String _snapshot() => jsonEncode({
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '約她週末喝咖啡',
      },
      'topicDepth': {'current': 'personal', 'suggestion': ''},
      'strategy': '維持神祕感',
      'targetProfile': {
        'interests': ['爬山'],
        'traits': ['幽默'],
        'notes': <String>[],
      },
    });

Conversation _conv(int i, {String? snapshot}) => Conversation(
      id: 'c$i',
      name: '第 $i 段',
      messages: [
        Message(
          id: 'm$i',
          content: '訊息 $i',
          isFromMe: i.isEven,
          timestamp: DateTime(2026, 6, 1, 12, i),
        ),
      ],
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1, 12, i),
      partnerId: 'p1',
      lastAnalysisSnapshotJson: snapshot,
    );

List<Override> _overrides(List<Conversation> conversations) => [
      partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
      coachFollowUpRepositoryProvider
          .overrideWithValue(_FakeCoachFollowUpRepo()),
      // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
      coachChatRepositoryProvider
          .overrideWithValue(MemoryCoachChatRepository()),
      partnerByIdProvider('p1').overrideWith((_) => _p()),
      partnerAggregateProvider('p1')
          .overrideWith((_) => PartnerAggregateView.empty()),
      dataQualityFlagProvider('p1')
          .overrideWith((_) => const DataQualityFlag.unflagged()),
      conversationsByPartnerProvider('p1').overrideWith((_) => conversations),
      partnerListProvider.overrideWith((_) => [_p()]),
    ];

ScrollableState _listScrollable(WidgetTester t) {
  // The body ListView is the first/primary scrollable on the screen.
  return t.state<ScrollableState>(find.byType(Scrollable).first);
}

CoachSurface _surface(WidgetTester t) =>
    t.widget<CoachSurface>(find.byType(CoachSurface));

TextField _surfaceInput(WidgetTester t) => t.widget<TextField>(
      find.descendant(
        of: find.byType(CoachSurface),
        matching: find.byType(TextField),
      ),
    );

/// Task 7 sealed contract: the legacy input sheet must NOT open, and the
/// orchestrator must NOT pre-prompt the AI data-sharing consent dialog
/// (consent is gated inside CoachSurface at ask time only).
void _expectNoLegacySheetNoConsent(WidgetTester t) {
  expect(find.text('讓教練看一下'), findsNothing,
      reason: 'legacy input sheet must not open (charged w/o visible result)');
  expect(find.text('第三方 AI 資料使用同意'), findsNothing,
      reason: 'orchestrator must not pre-prompt consent');
}

void main() {
  testWidgets(
      'tall device + many records: background scrolls to coach section, then '
      'CoachSurface input takes focus (no legacy sheet, no consent)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: _overrides(List.generate(8, (i) => _conv(i))),
      child: const MaterialApp(
        home: PartnerDetailScreen(
          partnerId: 'p1',
          focusCoachFollowUp: true,
          openCoachInputOnFocus: true,
        ),
      ),
    ));
    await t.pumpAndSettle();

    // Background positioned away from the top hero/heat cards.
    final offset = _listScrollable(t).position.pixels;
    expect(offset, greaterThan(100),
        reason: 'background must leave the top hero/heat cards');

    // The coach entry is laid out and visible inside the viewport.
    final anchor = find.text('或直接問教練一個問題…');
    expect(anchor, findsOneWidget);
    final anchorDy = t.getTopLeft(anchor).dy;
    expect(anchorDy, greaterThan(0));
    expect(anchorDy, lessThan(844),
        reason: 'coach entry must be on-screen, not below the fold');

    // Phase E Task 7: the open-input intent flows through the section's
    // focus-token mechanism into CoachSurface (invariant: AFTER positioning).
    expect(_surface(t).focusRequestToken, greaterThan(0),
        reason: 'openCoachInput intent must bump the section focus token');
    expect(_surfaceInput(t).focusNode?.hasFocus, isTrue,
        reason: 'CoachSurface input must hold focus after the deep-link');
    _expectNoLegacySheetNoConsent(t);
  });

  testWidgets(
      'focus=coachFollowUp WITHOUT focusAction: positions on coach section '
      'but does not focus the input', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: _overrides(List.generate(8, (i) => _conv(i))),
      child: const MaterialApp(
        home: PartnerDetailScreen(
          partnerId: 'p1',
          focusCoachFollowUp: true,
          // openCoachInputOnFocus defaults to false — scroll-only semantics.
        ),
      ),
    ));
    await t.pumpAndSettle();

    final offset = _listScrollable(t).position.pixels;
    expect(offset, greaterThan(100),
        reason: 'background must still land on the coach section');
    expect(find.text('或直接問教練一個問題…'), findsOneWidget);

    // Scroll-only deep-link keeps the existing semantics: no focus request.
    expect(_surface(t).focusRequestToken, 0,
        reason: 'no focusAction → focus token must stay untouched');
    expect(_surfaceInput(t).focusNode?.hasFocus, isNot(isTrue),
        reason: 'no focusAction → the input must not steal focus');
    _expectNoLegacySheetNoConsent(t);
  });

  testWidgets(
      'via real router: mind-map 下一步 lands on coach section + focuses '
      'CoachSurface input', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // First record carries the analysis snapshot so the mind map renders the
    // nextStep node; the rest pad the detail page so the coach section is deep.
    final conversations = [
      _conv(0, snapshot: _snapshot()),
      ...List.generate(7, (i) => _conv(i + 1)),
    ];

    final router = GoRouter(
      initialLocation: '/partner/p1/mindmap',
      routes: [
        GoRoute(
          path: '/partner/:partnerId/mindmap',
          builder: (_, s) =>
              PartnerMindMapScreen(partnerId: s.pathParameters['partnerId']!),
        ),
        GoRoute(
          path: '/partner/:partnerId',
          builder: (_, s) => PartnerDetailScreen(
            partnerId: s.pathParameters['partnerId']!,
            focusCoachFollowUp: s.uri.queryParameters[
                    PartnerDetailScreen.focusQueryParam] ==
                PartnerDetailScreen.coachFollowUpFocusValue,
            openCoachInputOnFocus: s.uri.queryParameters[
                    PartnerDetailScreen.focusActionQueryParam] ==
                PartnerDetailScreen.openCoachInputFocusActionValue,
          ),
        ),
      ],
    );

    await t.pumpWidget(ProviderScope(
      overrides: _overrides(conversations),
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();

    // Tap the nextStep leaf node (single tap settles via the gesture arena).
    // 圖節點短標籤現在是「下一步行動」，全文「約她週末喝咖啡」改在底部 panel，
    // 所以 tap 要鎖定圖內節點。
    await t.tap(find.descendant(
      of: find.byType(PartnerMindMapView),
      matching: find.text('下一步行動'),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();

    // Landed on the detail screen, positioned on the coach section.
    final offset = _listScrollable(t).position.pixels;
    expect(offset, greaterThan(100),
        reason: 'detail must land on the coach section, not the hero cards');

    final anchor = find.text('或直接問教練一個問題…');
    expect(anchor, findsOneWidget);
    expect(t.getTopLeft(anchor).dy, lessThan(844));

    // Phase E Task 7：deep-link 改 focus CoachSurface 輸入框，絕不開舊 sheet。
    expect(_surface(t).focusRequestToken, greaterThan(0),
        reason: 'mind-map deep-link must bump the section focus token');
    expect(_surfaceInput(t).focusNode?.hasFocus, isTrue,
        reason: 'CoachSurface input must hold focus after positioning');
    _expectNoLegacySheetNoConsent(t);
  });
}
