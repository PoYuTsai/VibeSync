// 跟進提醒／作戰板的問教練導向 spec（2026-08-15 拍板：獨立聊天視窗）。
//
// 兩條路徑：
// • 跟進提醒通知 deep-link（focus=coachFollowUp）→ 對象詳情頁背景捲到
//   問教練 CTA 區（lazy ListView 深處，靠 _CoachFocusOrchestrator 收斂）。
//   focusAction=openCoachInput 已退場：對象頁不再內嵌輸入框。
// • 作戰板「下一步」節點 → 直達問教練 Sydney 視窗（鎖定本對象），開場
//   泡泡吃最近分析的下一步（記憶素材優先序 P2）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/presentation/screens/global_coach_screen.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
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
import '../../../helpers/memory_coaching_outcome_repository.dart';

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
        'provenanceVersion': 1,
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
      coachChatRepositoryProvider
          .overrideWithValue(MemoryCoachChatRepository()),
      coachingOutcomeRepositoryProvider
          .overrideWithValue(MemoryCoachingOutcomeRepository()),
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
      'focus=coachFollowUp（跟進提醒通知）：tall device + many records 背景捲到 '
      '問教練 CTA 區', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: _overrides(List.generate(8, (i) => _conv(i))),
      child: const MaterialApp(
        home: PartnerDetailScreen(
          partnerId: 'p1',
          focusCoachFollowUp: true,
        ),
      ),
    ));
    await t.pumpAndSettle();

    // Background positioned away from the top hero/heat cards.
    final offset = _listScrollable(t).position.pixels;
    expect(offset, greaterThan(100),
        reason: 'background must leave the top hero/heat cards');

    // CTA 卡已被 lazy ListView 建出、落在視窗內。
    final anchor = find.byKey(const Key('coach_follow_up_cta'));
    expect(anchor, findsOneWidget);
    final anchorDy = t.getTopLeft(anchor).dy;
    expect(anchorDy, greaterThan(0));
    expect(anchorDy, lessThan(844),
        reason: 'coach CTA must be on-screen, not below the fold');
  });

  testWidgets(
      'via real router: mind-map 下一步 → 問教練 Sydney 視窗（鎖定對象）＋'
      '分析下一步當開場素材', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

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
          path: '/coach',
          builder: (_, s) => GlobalCoachScreen(
            lockedPartnerId: s.uri.queryParameters['partnerId'],
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
    await t.tap(find.descendant(
      of: find.byType(PartnerMindMapView),
      matching: find.text('本輪更新｜約她週末喝咖啡'),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();

    // 落在鎖定模式的聊天視窗：標題帶對象名、不渲染「問誰」。
    expect(find.text('問教練 Sydney・Alice'), findsOneWidget);
    expect(find.text('問誰'), findsNothing);
    // 開場泡泡吃最近分析的下一步（記憶素材 P2；教練串為空所以輪到它）。
    expect(find.textContaining('約她週末喝咖啡'), findsOneWidget);
  });
}
