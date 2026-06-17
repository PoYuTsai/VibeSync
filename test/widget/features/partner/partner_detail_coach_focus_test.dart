// Regression: the mind-map「下一步」node must land the partner-detail
// background ON the coach follow-up section (not the top hero/heat cards)
// before the input sheet opens.
//
// These tests encode the real device condition the previous tests missed:
//   • a tall surface (the old focus tests used 520px, which kept the section
//     inside the lazy ListView's viewport+cacheExtent so it "worked"); and
//   • a dogfood partner WITH several conversation records, pushing the coach
//     section far below the built range — exactly when ensureVisible-on-an-
//     unbuilt-GlobalKey silently no-ops.
//
// The second test drives the REAL router (mind map → tap → detail) instead of
// building PartnerDetailScreen directly, so the route/scroll/sheet timing is
// faithful rather than short-circuited.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

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

void main() {
  testWidgets(
      'tall device + many records: background scrolls to coach section, then '
      'sheet opens', (t) async {
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
    final anchor = find.text('或直接問教練一個問題...');
    expect(anchor, findsOneWidget);
    final anchorDy = t.getTopLeft(anchor).dy;
    expect(anchorDy, greaterThan(0));
    expect(anchorDy, lessThan(844),
        reason: 'coach entry must be on-screen, not below the fold');

    // And the input sheet opened (invariant: AFTER positioning).
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
      'via real router: mind-map 下一步 lands on coach section + opens sheet',
      (t) async {
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
    await t.tap(find.text('約她週末喝咖啡'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();

    // Landed on the detail screen, positioned on the coach section.
    final offset = _listScrollable(t).position.pixels;
    expect(offset, greaterThan(100),
        reason: 'detail must land on the coach section, not the hero cards');

    final anchor = find.text('或直接問教練一個問題...');
    expect(anchor, findsOneWidget);
    expect(t.getTopLeft(anchor).dy, lessThan(844));

    expect(find.byType(TextField), findsOneWidget,
        reason: 'sheet opens after positioning');
  });
}
