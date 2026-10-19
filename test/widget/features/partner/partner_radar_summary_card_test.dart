// test/widget/features/partner/partner_radar_summary_card_test.dart
//
// Tests the snapshot → 5-dim parser path inside PartnerRadarSummaryCard.
// Confirms reuse of `AnalysisResult.fromJson` (not duplicate parsing).
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_radar_summary_card.dart';

Conversation _conv({String? snapshot}) => Conversation(
      id: 'c1',
      partnerId: 'p1',
      name: '測試',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      lastAnalysisSnapshotJson: snapshot,
    );

void main() {
  testWidgets('null conversation → fallback text', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: PartnerRadarSummaryCard(conversations: [])),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });

  testWidgets('snapshot with dimensions renders RadarChart', (t) async {
    final snapshot = jsonEncode({
      'enthusiasm': {'score': 70, 'level': 'warm'},
      'dimensions': {
        'heat': 70,
        'engagement': 65,
        'topicDepth': 55,
        'replyWillingness': 80,
        'emotionalConnection': 60,
      },
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body:
            PartnerRadarSummaryCard(conversations: [_conv(snapshot: snapshot)]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('最新對話尚未分析'), findsNothing);
    final chart = t.widget<RadarChart>(find.byType(RadarChart));
    expect(chart.data.getTitle!(0, 0).text, '整體投入');
    expect(chart.data.getTitle!(1, 0).text, '回覆投入');
  });

  testWidgets(
      'snapshot without dimensions key → factory returns null map → fallback',
      (t) async {
    final snapshot = jsonEncode({
      'enthusiasm': {'score': 50, 'level': 'cool'},
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body:
            PartnerRadarSummaryCard(conversations: [_conv(snapshot: snapshot)]),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });

  testWidgets('v3 任務卡結果沒有雷達：整張不顯示，也不說尚未分析', (t) async {
    final snapshot = jsonEncode({
      'guideVersion': 'v3.4',
      'read': {'decision': 'send', 'light': 'green', 'judgment': '她有在接'},
      'cards': [],
      'partial': false,
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body:
            PartnerRadarSummaryCard(conversations: [_conv(snapshot: snapshot)]),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsNothing);
    expect(find.byType(RadarChart), findsNothing);
  });

  testWidgets('v3 帶了關係狀態的雷達（Bruce 2026-10-19 路線二）：跟 v2 一樣畫，數值照伺服器', (t) async {
    final snapshot = jsonEncode({
      'guideVersion': 'v3.6',
      'read': {
        'decision': 'send',
        'light': 'green',
        'judgment': '她有在接',
        'relation': {
          'stage': 'premise',
          'heat': 72,
          'dimensions': {
            'heat': 72,
            'engagement': 70,
            'topicDepth': 45,
            'replyWillingness': 78,
            'emotionalConnection': 60,
          },
        },
      },
      'cards': [],
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body:
            PartnerRadarSummaryCard(conversations: [_conv(snapshot: snapshot)]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('最新對話尚未分析'), findsNothing);
    final chart = t.widget<RadarChart>(find.byType(RadarChart));
    expect(
      chart.data.dataSets.single.dataEntries.map((e) => e.value),
      [72, 70, 45, 78, 60],
    );
  });

  testWidgets('最新那段還沒分析、最近分析過的是 v3：照對象頁同一條規則整張不顯示', (t) async {
    final v3 = jsonEncode({
      'guideVersion': 'v3.6',
      'read': {'decision': 'hold', 'light': 'yellow', 'judgment': '先等她'},
      'cards': [],
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(
          conversations: [
            Conversation(
              id: 'blank',
              partnerId: 'p1',
              name: '測試',
              messages: const [],
              createdAt: DateTime(2026, 10, 19),
              updatedAt: DateTime(2026, 10, 19),
            ),
            _conv(snapshot: v3),
          ],
        ),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsNothing);
    expect(find.byType(RadarChart), findsNothing);
  });

  testWidgets('最新那段還沒分析、最近分析過的是 v2：照舊說最新對話尚未分析', (t) async {
    final v2 = jsonEncode({
      'enthusiasm': {'score': 70, 'level': 'warm'},
      'dimensions': {
        'heat': 70,
        'engagement': 65,
        'topicDepth': 55,
        'replyWillingness': 80,
        'emotionalConnection': 60,
      },
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(
          conversations: [
            _conv(snapshot: v2),
            Conversation(
              id: 'blank',
              partnerId: 'p1',
              name: '測試',
              messages: const [],
              createdAt: DateTime(2026, 10, 19),
              updatedAt: DateTime(2026, 10, 19),
            ),
          ],
        ),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });

  testWidgets('malformed snapshot → fallback (no throw)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(
          conversations: [_conv(snapshot: 'not-json{{{')],
        ),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });
}
