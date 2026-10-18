// test/widget/features/analysis/guide_v3_locked_funnel_test.dart
//
// 鎖卡區塊「看方案」的漏斗事件（Eric 2026-10-18，audit P1-4）：
// - locked_cards_upgrade_tap 只帶 locked_count，等於區塊自己寫的「還有 N 張」。
// - 結果頁和分析紀錄共用同一塊，兩邊都記。
// - 埋點掛住、出錯、甚至沒有 ProviderScope，都照樣開付費頁。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_record_detail_screen.dart';
import 'package:vibesync/features/analysis/presentation/sections/guide_v3_result_section.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';

const _upgrade = ValueKey('guide-v3-locked-upgrade');

/// 免費方案 5 張排卡、送到 2 張（後面 3 張鎖住）。
const _plannedFiveSentTwo = [
  {'slot': 1, 'task': 'accept', 'locked': false},
  {'slot': 2, 'task': 'tension', 'locked': false},
  {'slot': 3, 'task': 'tension', 'locked': true},
  {'slot': 4, 'task': 'push', 'locked': true},
  {'slot': 5, 'task': 'push', 'locked': true},
];

Map<String, dynamic> _readJson(List<Map<String, Object>> planned) => {
      'guideVersion': 'v3.4',
      'decision': 'send',
      'light': 'green',
      'judgment': '她有在接你的話，可以往前一步。',
      'plannedCards': planned,
    };

Map<String, dynamic> _cardJson(int slot, String task, String message) => {
      'slot': slot,
      'task': task,
      'method': 'reaction',
      'voice': 'default',
      'messages': [message],
      'hasInventedDetail': false,
      'hasBlank': false,
    };

final _sentCards = [
  _cardJson(1, 'accept', '那家我也想吃吃看'),
  _cardJson(2, 'tension', '妳這樣說我會當真喔'),
];

/// 送出去的事件（照順序）。
class _Sent {
  final events = <Map<String, dynamic>>[];

  List<String> get names => [for (final e in events) e['event'] as String];

  List<Object?> propsOf(String name) => [
        for (final e in events)
          if (e['event'] == name) e['properties'],
      ];
}

FunnelTracker _recordingTracker(_Sent sent) => FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.events.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
    );

Widget _section({
  required GuideV3Read read,
  required VoidCallback onUpgrade,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GuideV3ResultSection(
            read: read,
            cards: [for (final c in _sentCards) GuideV3Card.fromJson(c)!],
            isStreaming: false,
            isFinal: true,
            editedMessagesFor: (_) => null,
            onCopy: (_, __, ___) {},
            onEdit: (_) async => null,
            onUpgrade: onUpgrade,
          ),
        ),
      ),
    );

Future<void> _setSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

AnalysisRecord _record() {
  final at = DateTime(2026, 10, 18, 21);
  return AnalysisRecord(
    id: 'v3-locked',
    ownerUserId: 'user-1',
    conversationId: 'conversation-v3-locked',
    partnerId: 'partner-1',
    subjectName: '小雲',
    segmentStart: 0,
    segmentEnd: 1,
    createdAt: at,
    messages: [
      AnalysisRecordMessage(
        id: 'm-1',
        content: '妳週末去哪裡玩？',
        isFromMe: true,
        timestamp: at,
      ),
      AnalysisRecordMessage(
        id: 'm-2',
        content: '去吃了一家新開的拉麵',
        isFromMe: false,
        timestamp: at.add(const Duration(minutes: 1)),
      ),
    ],
    analysisSnapshotJson: jsonEncode({
      'guideVersion': 'v3.4',
      'read': _readJson(_plannedFiveSentTwo),
      'cards': _sentCards,
      'partial': false,
    }),
    analyzedContentRevision: 'revision-v3-locked',
    completionKey: 'completion-v3-locked',
    sourcePlatform: null,
    enthusiasmScore: null,
    gameStageLabel: '',
    guideVersion: 'v3.4',
    guideV3Light: 'green',
  );
}

void main() {
  group('結果頁的鎖卡區塊', () {
    testWidgets('點「看方案」：記一筆，locked_count 等於區塊寫的張數，照樣開付費頁', (tester) async {
      await _setSurface(tester);
      final read = GuideV3Read.fromJson(_readJson(_plannedFiveSentTwo))!;
      final sent = _Sent();
      var upgrades = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          funnelTrackerProvider.overrideWithValue(_recordingTracker(sent)),
        ],
        child: _section(read: read, onUpgrade: () => upgrades++),
      ));
      expect(
        find.text('這輪付費方案還有 ${read.lockedCards.length} 張：帶張力、推進 ×2'),
        findsOneWidget,
      );
      expect(sent.names, isEmpty, reason: '區塊出現不記，點了才記');

      await tester.tap(find.byKey(_upgrade));
      await tester.pump();

      expect(upgrades, 1);
      expect(sent.names, ['locked_cards_upgrade_tap']);
      expect(sent.propsOf('locked_cards_upgrade_tap'), [
        {'locked_count': read.lockedCards.length},
      ]);
    });

    testWidgets('只鎖 1 張：locked_count 是 1', (tester) async {
      await _setSurface(tester);
      final read = GuideV3Read.fromJson(_readJson([
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'tension', 'locked': false},
        {'slot': 3, 'task': 'push', 'locked': true},
      ]))!;
      final sent = _Sent();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          funnelTrackerProvider.overrideWithValue(_recordingTracker(sent)),
        ],
        child: _section(read: read, onUpgrade: () {}),
      ));

      await tester.tap(find.byKey(_upgrade));
      await tester.pump();

      expect(sent.propsOf('locked_cards_upgrade_tap'), [
        {'locked_count': 1},
      ]);
    });

    testWidgets('埋點掛住或出錯：照樣開付費頁', (tester) async {
      await _setSurface(tester);
      final read = GuideV3Read.fromJson(_readJson(_plannedFiveSentTwo))!;
      for (final tracker in [
        FunnelTracker(
          invoker: (fn, {required body}) => Completer<int>().future,
        ),
        FunnelTracker(
          invoker: (fn, {required body}) async => throw StateError('boom'),
        ),
      ]) {
        var upgrades = 0;
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [funnelTrackerProvider.overrideWithValue(tracker)],
          child: _section(read: read, onUpgrade: () => upgrades++),
        ));

        await tester.tap(find.byKey(_upgrade));
        await tester.pump();

        expect(upgrades, 1);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('沒有 ProviderScope（只拿區塊來畫）：照樣開付費頁、不丟錯', (tester) async {
      await _setSurface(tester);
      final read = GuideV3Read.fromJson(_readJson(_plannedFiveSentTwo))!;
      var upgrades = 0;
      await tester.pumpWidget(
        _section(read: read, onUpgrade: () => upgrades++),
      );

      await tester.tap(find.byKey(_upgrade));
      await tester.pump();

      expect(upgrades, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('分析紀錄的鎖卡區塊：點「看方案」一樣記，付費頁用鎖卡入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sent = _Sent();
    final paywallExtras = <Object?>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => AnalysisRecordDetailScreen(record: _record()),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, state) {
            paywallExtras.add(state.extra);
            return const Scaffold(body: Text('paywall-stub'));
          },
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        funnelTrackerProvider.overrideWithValue(_recordingTracker(sent)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final upgrade = find.byKey(_upgrade);
    expect(upgrade, findsOneWidget);
    await tester.ensureVisible(upgrade);
    await tester.pump();
    await tester.tap(upgrade);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('paywall-stub'), findsOneWidget);
    expect(paywallExtras.last, PaywallEntry.lockedCards);
    expect(sent.names, ['locked_cards_upgrade_tap']);
    expect(sent.propsOf('locked_cards_upgrade_tap'), [
      {'locked_count': 3},
    ]);
  });
}
