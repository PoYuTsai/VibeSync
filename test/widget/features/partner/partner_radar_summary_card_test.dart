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
      home: Scaffold(body: PartnerRadarSummaryCard(latestConversation: null)),
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
        body: PartnerRadarSummaryCard(
            latestConversation: _conv(snapshot: snapshot)),
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
        body: PartnerRadarSummaryCard(
            latestConversation: _conv(snapshot: snapshot)),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });

  testWidgets('malformed snapshot → fallback (no throw)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(
          latestConversation: _conv(snapshot: 'not-json{{{'),
        ),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });
}
