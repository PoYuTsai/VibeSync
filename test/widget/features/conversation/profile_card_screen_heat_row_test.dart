import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/screens/profile_card_screen.dart';

Conversation _conversation({
  int? score,
  String? snapshotJson,
  String? stage,
}) =>
    Conversation(
      id: 'c-1',
      name: '小雨',
      messages: const [],
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 18),
      lastEnthusiasmScore: score,
      lastAnalysisSnapshotJson: snapshotJson,
      currentGameStage: stage,
    );

Future<void> _pump(WidgetTester tester, Conversation conversation) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationProvider('c-1').overrideWithValue(conversation),
      ],
      child: const MaterialApp(
        home: ProfileCardScreen(conversationId: 'c-1'),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('v3 分析過的對話不放「本次投入 --」', (tester) async {
    await _pump(
      tester,
      _conversation(
        snapshotJson: jsonEncode({
          'guideVersion': 'v3.5',
          'read': {'light': 'yellow', 'decision': 'hold'},
          'cards': const [],
        }),
      ),
    );

    expect(find.text('本次投入'), findsNothing);
    expect(find.text('目前階段'), findsOneWidget);
  });

  testWidgets('v3 帶了關係狀態（Bruce 2026-10-19 路線二）：存檔寫進對話的階段與熱度照 v2 顯示',
      (tester) async {
    await _pump(
      tester,
      _conversation(
        score: 65,
        stage: 'premise',
        snapshotJson: jsonEncode({
          'guideVersion': 'v3.6',
          'read': {
            'light': 'green',
            'decision': 'send',
            'relation': {'stage': 'premise', 'heat': 72},
          },
          'cards': const [],
        }),
      ),
    );

    expect(find.text('目前階段'), findsOneWidget);
    expect(find.text('升溫'), findsOneWidget);
    expect(find.text('本次投入'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('還沒分析的對話照舊顯示「本次投入 --」', (tester) async {
    await _pump(tester, _conversation());

    expect(find.text('本次投入'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('舊流程有分數的對話照舊顯示投入度', (tester) async {
    await _pump(tester, _conversation(score: 72));

    expect(find.text('本次投入'), findsOneWidget);
  });
}
