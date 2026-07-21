// test/widget/features/partner/partner_detail_screen_test.dart
//
// Hermetic widget tests for PartnerDetailScreen.
// Overrides the three narrow providers; no Hive required.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/widgets/new_conversation_sheet.dart';
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_data_quality_banner.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_heat_hero_card.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

import '_fakes/recording_conversation_write_controller.dart';
import '_fakes/recording_partner_write_controller.dart';
import '../../../helpers/memory_coach_chat_repository.dart';

Partner _p({String? customNote}) => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
      customNote: customNote,
    );

Partner _other(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Conversation _conv(String id) => Conversation(
      id: id,
      name: '第 $id 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
    );

/// 最近一段已分析互動：帶可解析快照（gameStage.nextStep + 互動摘錄 +
/// 興趣/特質），用於 IA 去重鎖測試。
String _analysisSnapshot({
  required String nextStep,
  String? sourceMessage,
  String? recommendedReply,
}) =>
    jsonEncode({
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': nextStep,
      },
      'topicDepth': {'current': 'personal', 'suggestion': ''},
      'strategy': '維持神祕感',
      'psychology': {
        'subtext': sourceMessage == null ? '' : '她在丟「$sourceMessage」這顆球',
      },
      'finalRecommendation': {
        'pick': 'extend',
        'content': recommendedReply ?? '',
        'reason': '先接互動紀錄裡最有畫面的球',
        'psychology': '她願意把生活片段丟出來，適合先延伸那段故事',
        'replySegments': [
          if (sourceMessage != null && recommendedReply != null)
            {
              'label': '接她的生活故事',
              'sourceMessage': sourceMessage,
              'reply': recommendedReply,
              'reason': '直接承接最近互動紀錄',
            },
        ],
      },
      'targetProfile': {
        'interests': ['爬山', '咖啡'],
        'traits': ['幽默'],
        'notes': <String>[],
      },
    });

Conversation _analyzedConv({
  required String nextStep,
  String? sourceMessage,
  String? recommendedReply,
}) =>
    Conversation(
      id: 'c-analyzed',
      name: '第一段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 21),
      partnerId: 'p1',
      lastAnalysisSnapshotJson: _analysisSnapshot(
        nextStep: nextStep,
        sourceMessage: sourceMessage,
        recommendedReply: recommendedReply,
      ),
    );

PartnerAggregateView _aggregateWithTags() => PartnerAggregateView(
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

/// Records markSamePerson calls for hermetic widget assertions. Overrides
/// only the methods exercised by the action handler — load/save/etc. would
/// hit `_box` (i.e. StorageService) and are intentionally left as `super`'s
/// implementation so any accidental reach-through fails loudly.
class _RecordingDataQualityRepo extends PartnerDataQualityRepository {
  _RecordingDataQualityRepo() : super();

  final List<({String partnerId, NamePair pair})> markSamePersonCalls = [];

  @override
  Future<void> markSamePerson(String partnerId, NamePair pair) async {
    markSamePersonCalls.add((partnerId: partnerId, pair: pair));
  }
}

Future<void> _scrollUntilVisible(
  WidgetTester t,
  Finder finder, {
  double delta = 450,
}) async {
  await t.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

Future<void> _expandDetailedTraits(WidgetTester t) async {
  await _scrollUntilVisible(t, find.text('詳細特質與趨勢'));
  await t.tap(find.text('展開'));
  await t.pumpAndSettle();
}

void main() {
  // IA 去重鎖：詳情頁第一頁的下一步卡改吃互動摘錄，不再重貼作戰板完整
  // nextStep；作戰板內頁仍保留完整 nextStep。
  testWidgets('下一步行動使用互動摘錄，不重貼作戰板 nextStep', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    const fullNextStep = '約她這週末一起去看她提過的那個攝影展，順勢帶到展後找間咖啡店坐坐';
    const sourceMessage = '台南車被拖的故事';
    const recommendedReply = '台南那段太有畫面了，後來怎麼收場？';

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => _aggregateWithTags()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1').overrideWith(
          (_) => [
            _analyzedConv(
              nextStep: fullNextStep,
              sourceMessage: sourceMessage,
              recommendedReply: recommendedReply,
            ),
          ],
        ),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.textContaining(sourceMessage), findsWidgets);
    expect(find.textContaining(recommendedReply), findsWidgets);
    expect(find.textContaining(fullNextStep), findsNothing,
        reason: '詳情頁主卡應改用互動摘錄；作戰板 nextStep 留在作戰板內頁');
  });

  testWidgets('tile delete confirm calls ConversationWriteController.delete',
      (t) async {
    // Tile lives below the new PartnerStyleEntryCard — give the surface
    // enough height so ListView's cache extent reaches the tile (matches
    // the reassign-tile tests' convention below).
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();
    final attachedConv = Conversation(
      id: 'c1',
      name: 'Alice',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      partnerId: 'p1',
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    final tileMenu = find.descendant(
      of: find.byType(PartnerConversationTile),
      matching: find.byIcon(Icons.more_vert),
    );
    await t.tap(tileMenu);
    await t.pumpAndSettle();
    await t.tap(find.text('刪除對話'));
    await t.pumpAndSettle();
    await t.tap(find.text('確認刪除'));
    await t.pumpAndSettle();

    expect(fake.deleteCalled, isTrue);
    expect(fake.deletedConversation?.id, 'c1');
    expect(find.text('已刪除這段互動紀錄'), findsOneWidget);
  });

  testWidgets('右上有分析紀錄與 settings gear，⋮ 只放合併', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('Alice'), findsWidgets);
    expect(find.byTooltip('分析紀錄'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('partner-analysis-records-entry')),
      findsOneWidget,
    );
    expect(find.byTooltip('對象設定'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('合併重複對象'), findsOneWidget);
    expect(find.text('編輯對象'), findsNothing);
    expect(find.text('編輯對象（即將推出）'), findsNothing);
    expect(find.text('刪除對象（即將推出）'), findsNothing);
  });

  testWidgets('settings gear → 儲存 calls updateName + success snackbar',
      (t) async {
    final fake = RecordingPartnerWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('對象設定'));
    await t.pumpAndSettle();

    // Phase E Task 6：頁面本體多了 CoachSurface 輸入框，改鎖定 dialog 內欄位。
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogFields, findsNWidgets(2));
    await t.enterText(dialogFields.at(0), '  Alicia  ');
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isTrue);
    expect(fake.updateCustomNoteCalled, isFalse);
    expect(fake.updatedPartner?.id, 'p1');
    expect(fake.updatedName, 'Alicia',
        reason: 'dialog must trim before handing off to controller');
    expect(find.text('已更新對象設定'), findsOneWidget);
  });

  testWidgets('settings gear → 取消 does not call updateName or update note',
      (t) async {
    final fake = RecordingPartnerWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('對象設定'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isFalse);
    expect(fake.updateCustomNoteCalled, isFalse);
    expect(find.text('已更新對象設定'), findsNothing);
  });

  testWidgets('settings gear → controller throw shows error snackbar',
      (t) async {
    final fake = RecordingPartnerWriteController()
      ..throwOnUpdateName = StateError('boom');

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('對象設定'));
    await t.pumpAndSettle();
    // Phase E Task 6：改鎖定 dialog 內欄位（頁面本體有 CoachSurface 輸入框）。
    await t.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .at(0),
      'Alicia',
    );
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isTrue);
    expect(find.textContaining('更新失敗'), findsOneWidget);
  });

  testWidgets('settings gear edits partner-level custom note', (t) async {
    final fake = RecordingPartnerWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('對象設定'));
    await t.pumpAndSettle();
    // Phase E Task 6：改鎖定 dialog 內欄位（頁面本體有 CoachSurface 輸入框）。
    await t.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .at(1),
      '  慢熱，喜歡戶外活動  ',
    );
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isFalse);
    expect(fake.updateCustomNoteCalled, isTrue);
    expect(fake.notePartner?.id, 'p1');
    expect(fake.updatedCustomNote, '慢熱，喜歡戶外活動');
    expect(find.text('已更新對象設定'), findsOneWidget);
  });

  testWidgets('traits card renders existing partner-level custom note',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1')
            .overrideWith((_) => _p(customNote: '慢熱，喜歡戶外活動')),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_conv('existing')]),
        partnerListProvider.overrideWith(
          (_) => [_p(customNote: '慢熱，喜歡戶外活動')],
        ),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await _expandDetailedTraits(t);
    await _scrollUntilVisible(t, find.text('你的設定'));
    expect(find.text('你的設定'), findsOneWidget);
    expect(find.text('慢熱，喜歡戶外活動'), findsOneWidget);
  });

  testWidgets('⋮ menu: merge DISABLED when only one partner exists', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('合併重複對象（需至少 2 個對象）'), findsOneWidget);
    expect(find.text('合併重複對象'), findsNothing);
  });

  testWidgets('⋮ merge tap navigates to /partner/p1/merge', (t) async {
    final router = GoRouter(
      initialLocation: '/partner/p1',
      routes: [
        GoRoute(
          path: '/partner/:partnerId',
          builder: (_, state) => PartnerDetailScreen(
            partnerId: state.pathParameters['partnerId']!,
          ),
        ),
        GoRoute(
          path: '/partner/:partnerId/merge',
          builder: (_, state) => Scaffold(
            body: Text('merge-stub-${state.pathParameters['partnerId']}'),
          ),
        ),
      ],
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('合併重複對象'));
    await t.pumpAndSettle();

    expect(find.text('merge-stub-p1'), findsOneWidget);
  });

  testWidgets('renders simplified first-conversation empty state', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('還沒有分析片段'), findsOneWidget);
    expect(find.textContaining('開始你們的第一次分析'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('partner-analysis-records-entry')),
      findsOneWidget,
    );
    expect(find.text('+ 分析新片段'), findsOneWidget);
    expect(find.byKey(const Key('partner-empty-add-conversation')),
        findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(PartnerHeatHeroCard), findsNothing);
    expect(find.byType(PartnerTraitsCard), findsNothing);
    expect(find.text('還沒有素材？先練習一下'), findsOneWidget);
    // Phase E Task 6：三情境 chip 改為 chatStalled/prepareInvite/postDate。
    expect(find.text('聊天卡住了'), findsOneWidget);
    expect(find.text('想約她出來'), findsOneWidget);
    expect(find.text('約完會之後'), findsOneWidget);

    await _scrollUntilVisible(t, find.text('關係下一步'));
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('關係下一步'), findsOneWidget);
    expect(find.text('完成第一次分析後解鎖'), findsNWidgets(2));
  });

  testWidgets('new-conversation sheet receives current partnerId', (t) async {
    // Default flutter_test surface is 800x600 → modal sheet height 289.5px,
    // sheet content needs ~291px → 1.5px RenderFlex overflow fails the test.
    // Use a phone-realistic size so the sheet has room to render.
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('partner-empty-add-conversation')));
    await t.pumpAndSettle();

    final sheet =
        t.widget<NewConversationSheet>(find.byType(NewConversationSheet));
    expect(sheet.partnerId, 'p1');
  });

  testWidgets('focusCoachFollowUp scrolls to the open coach input entry',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 520));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(
        home: PartnerDetailScreen(
          partnerId: 'p1',
          focusCoachFollowUp: true,
        ),
      ),
    ));
    await t.pumpAndSettle();

    final inputEntry = find.text('或直接問教練一個問題…');
    expect(inputEntry, findsOneWidget);
    expect(
      t.getTopLeft(inputEntry).dy,
      lessThan(140),
      reason: 'Mind map focus should land on the input affordance, not the '
          'top of the whole CoachFollowUp card.',
    );
  });

  testWidgets(
      'openCoachInputOnFocus focuses the CoachSurface input (no legacy sheet)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 520));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(
        home: PartnerDetailScreen(
          partnerId: 'p1',
          focusCoachFollowUp: true,
          openCoachInputOnFocus: true,
        ),
      ),
    ));
    await t.pumpAndSettle();

    // Phase E Task 7：orchestrator 不再開舊 input sheet（sheet 專屬欄位
    // maxLength 120 / maxLines 4 必須缺席），改為 CoachSurface 輸入框取得
    // focus。
    final sheetFields = t
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.maxLength == 120 && f.maxLines == 4);
    expect(sheetFields, isEmpty,
        reason: 'legacy input sheet must not open on deep-link');
    final focusedFields = t
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.focusNode?.hasFocus ?? false);
    expect(focusedFields, hasLength(1),
        reason: 'the CoachSurface input must take focus instead');

    final inputEntry = find.text('或直接問教練一個問題…');
    expect(inputEntry, findsOneWidget);
    expect(
      t.getTopLeft(inputEntry).dy,
      lessThan(260),
      reason: 'Mind map open action should leave the underlying page at the '
          'coach input area, not at the top hero cards.',
    );
  });

  testWidgets('empty conversation list shows hint text', (t) async {
    // The CoachFollowUpSection (Spec 5 C24) lands above this hint inside
    // the same ListView; default surface keeps the hint outside the lazy
    // build cache. Match the tall-surface convention used by tile tests.
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('還沒有分析片段'), findsOneWidget);
  });

  testWidgets('renders one tile per conversation when list non-empty',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_conv('a'), _conv('b')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.byType(PartnerConversationTile), findsNWidgets(2),
        reason: 'Tile titles no longer carry conversation.name (per "人 vs 互動" '
            'mental-model fix); verify by widget count instead.');
    expect(
      find.byKey(const ValueKey('partner-analysis-records-entry')),
      findsOneWidget,
    );
  });

  testWidgets('conversation records sit between heat score and next step',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1').overrideWith((_) => [_conv('a')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    final heatTop = t.getTopLeft(find.byType(PartnerHeatHeroCard)).dy;
    final recordTop = t.getTopLeft(find.byType(PartnerConversationTile)).dy;
    final nextStepTop = t.getTopLeft(find.text('下一步行動')).dy;

    expect(recordTop, greaterThan(heatTop));
    expect(recordTop, lessThan(nextStepTop));
  });

  testWidgets('tile ⋮ → 改派 opens reassign picker excluding current partner',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final attachedConv = Conversation(
      id: 'c1',
      name: '第 a 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      partnerId: 'p1',
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    // Header ⋮ is also Icons.more_vert — scope to the tile.
    final tileMenu = find.descendant(
      of: find.byType(PartnerConversationTile),
      matching: find.byIcon(Icons.more_vert),
    );
    expect(tileMenu, findsOneWidget);
    await t.tap(tileMenu);
    await t.pumpAndSettle();

    await t.tap(find.text('改派到其他對象'));
    await t.pumpAndSettle();

    // Reassign sheet rendered: Bob visible (Alice = p1 excluded from picker;
    // header still shows "Alice", so we scope to the picker subtree).
    expect(find.text('Bob'), findsOneWidget);
    final pickerSubtree = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Alice'),
    );
    expect(pickerSubtree, findsNothing);
  });

  testWidgets('reassign picker confirms single-record move before save',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();
    final attachedConv = Conversation(
      id: 'c1',
      name: '第 a 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      partnerId: 'p1',
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    final tileMenu = find.descendant(
      of: find.byType(PartnerConversationTile),
      matching: find.byIcon(Icons.more_vert),
    );
    await t.tap(tileMenu);
    await t.pumpAndSettle();
    await t.tap(find.text('改派到其他對象'));
    await t.pumpAndSettle();

    await t.tap(find.text('Bob'));
    await t.pumpAndSettle();

    expect(find.text('把這段移到「Bob」？'), findsOneWidget);
    expect(find.textContaining('請確認這段聊天真的屬於「Bob」'), findsOneWidget);
    expect(find.textContaining('只會移動目前這一段互動紀錄'), findsOneWidget);
    expect(find.textContaining('不會合併兩張對象卡'), findsOneWidget);
    expect(fake.saveCalled, isFalse);

    await t.tap(find.text('移過去'));
    await t.pumpAndSettle();

    expect(fake.saveCalled, isTrue);
    expect(fake.savedPartnerIdAtCallTime, 'q1');
    expect(fake.savedPreviousPartnerId, 'p1');
    expect(fake.savedIntent, ConversationSaveIntent.metadataOnly);
  });

  testWidgets('partner missing (deleted/merged) shows fallback', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('ghost').overrideWith((_) => null),
        partnerAggregateProvider('ghost')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('ghost')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'ghost')),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('找不到對象'), findsOneWidget);
  });

  // Spec 3 Task 19 — PartnerDataQualityBanner integration on PartnerDetailScreen.
  // Spec 6D moves the banner below detailed traits/trends so it no longer
  // interrupts the command-center flow.
  // only renders when the dataQualityFlagProvider returns a flagged result
  // with a non-null conflictingPair. Action handlers are STUBS in this task
  // (Tasks 20/21 fill them in); these tests verify rendering only.
  testWidgets(
      'PartnerDataQualityBanner appears when dataQualityFlagProvider is flagged',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final pair = NamePair.canonical('May', 'Anna');

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => DataQualityFlag.flagged(pair)),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerDataQualityBanner), findsOneWidget);
    // Display names are title-cased for UX; canonical lower-case names stay
    // inside NamePair for matching/storage only.
    expect(find.textContaining('Anna'), findsOneWidget);
    expect(find.textContaining('May'), findsOneWidget);
  });

  testWidgets('PartnerDataQualityBanner is NOT rendered when flag is unflagged',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerDataQualityBanner), findsNothing);
  });

  // Spec 3 Task 20 — 「這是同一人」action handler.
  //
  // Hermetic widget test: override `partnerDataQualityRepoProvider` with a
  // fake that records markSamePerson calls, and override
  // `dataQualityFlagProvider` directly to flagged so the banner renders
  // (matching the working banner-render test above).
  //
  // We do NOT use a real Hive-backed repo here because widget tests run
  // under FakeAsync, where real file I/O (Hive.openBox) never resolves and
  // pumpAndSettle hangs to the 10-minute timeout. The reactive
  // "banner disappears after the comparator re-runs" leg is already
  // covered hermetically by data_quality_flag_provider_test
  // (`returns unflagged when the two candidates are in confirmed pairs`),
  // so the widget test only needs to prove the tap reaches the repo with
  // the canonical pair.
  testWidgets('tapping 這是同一人 calls markSamePerson with the canonical NamePair',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final pair = NamePair.canonical('Anna', 'May');
    final repo = _RecordingDataQualityRepo();

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Phase E Task 6：section 掛 CoachSurface 後會經 coach chat repo。
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => DataQualityFlag.flagged(pair)),
        partnerDataQualityRepoProvider.overrideWithValue(repo),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    // Banner renders (override forces flagged state).
    expect(find.byType(PartnerDataQualityBanner), findsOneWidget);

    await _scrollUntilVisible(t, find.text('這是同一人'));
    await t.tap(find.text('這是同一人'));
    await t.pumpAndSettle();

    expect(repo.markSamePersonCalls, hasLength(1));
    expect(repo.markSamePersonCalls.single.partnerId, 'p1');
    expect(repo.markSamePersonCalls.single.pair, pair);
  });

  // Spec 3 Task 21 — 「拆成新對象」action handler.
  //
  // Flow: tap banner button → confirm dialog → on confirm filter conversations
  // by candidate name (== pair.second) → PartnerWriteController.split.
  // Defensive guard: empty match list → no split call.
  group('拆成新對象 action', () {
    Conversation convNamed(String id, String name) => Conversation(
          id: id,
          name: name,
          messages: const [],
          createdAt: DateTime(2026, 4, 20),
          updatedAt: DateTime(2026, 4, 20),
          partnerId: 'p1',
        );

    ProviderScope scope({
      required RecordingPartnerWriteController fakeController,
      required List<Conversation> conversations,
      required Widget child,
      Partner? partner,
    }) {
      final pair = NamePair.canonical('Anna', 'May');
      return ProviderScope(
        overrides: [
          partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
          coachChatRepositoryProvider
              .overrideWithValue(MemoryCoachChatRepository()),
          partnerByIdProvider('p1').overrideWith((_) => partner ?? _p()),
          partnerAggregateProvider('p1')
              .overrideWith((_) => PartnerAggregateView.empty()),
          dataQualityFlagProvider('p1')
              .overrideWith((_) => DataQualityFlag.flagged(pair)),
          partnerDataQualityRepoProvider
              .overrideWithValue(_RecordingDataQualityRepo()),
          conversationsByPartnerProvider('p1')
              .overrideWith((_) => conversations),
          partnerListProvider.overrideWith((_) => [_p()]),
          partnerWriteControllerProvider.overrideWith(() => fakeController),
        ],
        child: child,
      );
    }

    testWidgets('tapping 拆成新對象 shows confirm dialog with both names',
        (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final fake = RecordingPartnerWriteController();
      await t.pumpWidget(scope(
        fakeController: fake,
        conversations: [convNamed('c1', 'May')],
        child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
      ));
      await t.pumpAndSettle();

      await _scrollUntilVisible(t, find.text('拆成新對象'));
      await t.tap(find.text('拆成新對象'));
      await t.pumpAndSettle();

      expect(find.text('拆成新對象？'), findsOneWidget);
      expect(find.textContaining('Anna'), findsWidgets);
      expect(find.textContaining('May'), findsWidgets);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('確認拆卡'), findsOneWidget);
      expect(fake.splitCalled, isFalse,
          reason: 'showing the dialog must not call split');
    });

    testWidgets('dialog 取消 dismisses and does not call split', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final fake = RecordingPartnerWriteController();
      await t.pumpWidget(scope(
        fakeController: fake,
        conversations: [convNamed('c1', 'May')],
        child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
      ));
      await t.pumpAndSettle();

      await _scrollUntilVisible(t, find.text('拆成新對象'));
      await t.tap(find.text('拆成新對象'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();

      expect(find.text('拆成新對象？'), findsNothing);
      expect(fake.splitCalled, isFalse);
    });

    testWidgets(
        'dialog 確認拆卡 calls split with matched conv ids and shows snackbar',
        (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final fake = RecordingPartnerWriteController();
      // Three convs: two extract to 'May' (the moving side), one to 'Anna'
      // (stays). Only 'May' ids should be in matchedConversationIds.
      await t.pumpWidget(scope(
        fakeController: fake,
        conversations: [
          convNamed('c1', 'May'),
          convNamed('c2', 'Anna'),
          convNamed('c3', 'May'),
        ],
        child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
      ));
      await t.pumpAndSettle();

      await _scrollUntilVisible(t, find.text('拆成新對象'));
      await t.tap(find.text('拆成新對象'));
      await t.pumpAndSettle();
      await t.tap(find.text('確認拆卡'));
      await t.pumpAndSettle();

      expect(fake.splitCalled, isTrue);
      expect(fake.splitSourceId, 'p1');
      expect(fake.splitNewName, 'May');
      expect(fake.splitMatchedIds, equals(['c1', 'c3']));
      expect(find.textContaining('已把'), findsOneWidget);
    });

    testWidgets(
        'dialog 確認拆卡 keeps conversations matching current partner name on source',
        (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final fake = RecordingPartnerWriteController();
      await t.pumpWidget(scope(
        fakeController: fake,
        partner: _other('p1', 'May'),
        conversations: [
          convNamed('c1', 'May'),
          convNamed('c2', 'Anna'),
          convNamed('c3', 'Anna'),
        ],
        child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
      ));
      await t.pumpAndSettle();

      await _scrollUntilVisible(t, find.text('拆成新對象'));
      await t.tap(find.text('拆成新對象'));
      await t.pumpAndSettle();

      expect(find.textContaining('「May」會留在這張卡'), findsOneWidget);
      expect(find.textContaining('含「Anna」的對話'), findsOneWidget);

      await t.tap(find.text('確認拆卡'));
      await t.pumpAndSettle();

      expect(fake.splitCalled, isTrue);
      expect(fake.splitSourceId, 'p1');
      expect(fake.splitNewName, 'Anna');
      expect(fake.splitMatchedIds, equals(['c2', 'c3']));
    });

    testWidgets(
        'dialog 確認拆卡 with no matching conversations is a no-op (defensive guard)',
        (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final fake = RecordingPartnerWriteController();
      // No conv extracts to "May" — guard short-circuits before split.
      await t.pumpWidget(scope(
        fakeController: fake,
        conversations: [convNamed('c1', 'Anna')],
        child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
      ));
      await t.pumpAndSettle();

      await _scrollUntilVisible(t, find.text('拆成新對象'));
      await t.tap(find.text('拆成新對象'));
      await t.pumpAndSettle();
      await t.tap(find.text('確認拆卡'));
      await t.pumpAndSettle();

      expect(fake.splitCalled, isFalse);
    });
  });
}
