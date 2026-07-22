// test/widget/features/partner/partner_detail_expandable_recycle_test.dart
//
// 回歸鎖：「詳細特質與趨勢」摺疊面板的展開狀態必須在捲動回收後存活。
// 詳情頁 body 是 lazy ListView；面板位於清單底部，展開後往上捲會滑出
// cacheExtent 被回收。若展開狀態存在面板自己的 State 裡，回收即歸零：
// 高度暴縮觸發捲動 offset 反覆修正（畫面橫跳）、收起鍵永遠點不到。
// 本檔用貼近真機的小 viewport（400x800）逼出回收路徑——既有測試都用
// 2400 高的 surface 把整頁塞進單一 viewport，永遠測不到這條路。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

import '../../../helpers/memory_coach_chat_repository.dart';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Conversation _conv(String id) => Conversation(
      id: id,
      name: '第 $id 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 21),
      partnerId: 'p1',
    );

PartnerAggregateView _aggregate() => PartnerAggregateView(
      unionInterests: const ['爬山', '咖啡'],
      unionTraits: const ['幽默'],
      unionNotes: null,
      latestHeat: 70,
      totalRounds: 1,
      totalMessages: 0,
      lastInteraction: DateTime(2026, 4, 21),
    );

class _FakeStyleRepo implements PartnerStyleRepository {
  final Map<String, PartnerStyleOverride> byPartner = {};
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async =>
      byPartner[partnerId];
  @override
  Future<void> save(PartnerStyleOverride o) async {
    if (o.isEmpty) {
      byPartner.remove(o.partnerId);
    } else {
      byPartner[o.partnerId] = o;
    }
  }

  @override
  Future<void> delete(String partnerId) async => byPartner.remove(partnerId);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

Future<void> _pumpScreen(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));

  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
      coachChatRepositoryProvider.overrideWithValue(
        MemoryCoachChatRepository(),
      ),
      partnerByIdProvider('p1').overrideWith((_) => _p()),
      partnerAggregateProvider('p1').overrideWith((_) => _aggregate()),
      dataQualityFlagProvider('p1')
          .overrideWith((_) => const DataQualityFlag.unflagged()),
      conversationsByPartnerProvider('p1')
          .overrideWith((_) => [_conv('c1')]),
      partnerListProvider.overrideWith((_) => [_p()]),
    ],
    child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
  ));
  await t.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    450,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('詳細特質與趨勢展開狀態在捲離回收後仍保留（不歸零、可收起）',
      (t) async {
    await _pumpScreen(t);

    // 展開面板。
    await _scrollUntilVisible(t, find.text('詳細特質與趨勢'));
    await t.tap(find.text('展開'));
    await t.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);

    // 往上捲回頁首，讓面板滑出 viewport + cacheExtent 被回收。
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 6; i++) {
      await t.drag(scrollable, const Offset(0, 600));
      await t.pumpAndSettle();
    }
    expect(find.text('詳細特質與趨勢'), findsNothing,
        reason: '前置條件：面板必須真的滑出視窗（含 cache），本斷言失敗代表測試沒逼出回收路徑');

    // 捲回面板：展開狀態必須還在（顯示「收起」而非重置成「展開」）。
    await _scrollUntilVisible(t, find.text('詳細特質與趨勢'));
    expect(find.text('收起'), findsOneWidget,
        reason: '展開狀態存在會被回收的本地 State 會歸零，'
            '導致高度暴縮、捲動反覆修正與收不起來');

    // 且收起鍵要真的可用。
    await t.tap(find.text('收起'));
    await t.pumpAndSettle();
    expect(find.text('展開'), findsOneWidget);
  });
}
