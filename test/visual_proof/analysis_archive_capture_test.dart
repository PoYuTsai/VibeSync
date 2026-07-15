import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_record_detail_screen.dart';
import 'package:vibesync/features/analysis/presentation/screens/partner_analysis_records_screen.dart';

import 'proof_support.dart';

String _snapshot() => jsonEncode({
      'enthusiasm': {'score': 72, 'level': 'warm'},
      'strategy': '先接住她分享的內容，再補一個輕鬆的小問題。',
      'gameStage': {
        'current': 'iceBreaking',
        'status': 'normal',
        'nextStep': '延伸她主動提到的旅行話題',
      },
      'psychology': {'subtext': '她有接球，也願意補充細節，可以自然往下聊。'},
      'topicDepth': {'current': 'personal', 'suggestion': ''},
      'replies': {'extend': '沖繩我也一直想去，妳那次最喜歡哪個地方？'},
      'finalRecommendation': {
        'pick': 'extend',
        'content': '沖繩我也一直想去，妳那次最喜歡哪個地方？',
        'reason': '順著她主動分享的內容延伸，回覆壓力比較低。',
        'psychology': '讓她感覺你真的有在聽，而不是急著換話題。',
      },
    });

AnalysisRecord _record({
  required String id,
  required DateTime createdAt,
  required String reply,
  required int score,
  required String stage,
  String? platform,
}) {
  return AnalysisRecord(
    id: id,
    ownerUserId: 'visual-proof-user',
    conversationId: 'conversation-$id',
    partnerId: 'partner-test',
    subjectName: 'Test',
    segmentStart: 0,
    segmentEnd: 2,
    createdAt: createdAt,
    messages: [
      AnalysisRecordMessage(
        id: '$id-mine',
        content: '妳之前說想去旅行，最近有想去哪裡嗎？',
        isFromMe: true,
        timestamp: createdAt,
      ),
      AnalysisRecordMessage(
        id: '$id-hers',
        content: reply,
        isFromMe: false,
        timestamp: createdAt.add(const Duration(minutes: 2)),
        quotedReplyPreview: '妳之前說想去旅行，最近有想去哪裡嗎？',
        quotedReplyPreviewIsFromMe: true,
      ),
    ],
    analysisSnapshotJson: _snapshot(),
    analyzedContentRevision: 'revision-$id',
    completionKey: 'completion-$id',
    sourcePlatform: platform,
    enthusiasmScore: score,
    gameStageLabel: stage,
  );
}

void main() {
  setUpAll(loadProofFonts);

  final records = [
    _record(
      id: 'omi',
      createdAt: DateTime(2026, 7, 16, 2, 26),
      reply: '我上次去沖繩很喜歡，海邊超漂亮。',
      score: 72,
      stage: '破冰階段',
      platform: 'Omi',
    ),
    _record(
      id: 'line',
      createdAt: DateTime(2026, 7, 15, 22, 10),
      reply: '最近比較忙，不過週末應該可以。',
      score: 58,
      stage: '建立連結',
      platform: 'LINE',
    ),
    _record(
      id: 'unknown',
      createdAt: DateTime(2026, 7, 14, 20, 8),
      reply: '哈哈可以啊，那你呢？',
      score: 45,
      stage: '破冰階段',
    ),
  ];

  testWidgets('capture analysis archive sheet', (tester) async {
    await pumpAndCapture(
      tester,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF110B20)),
          ColoredBox(color: Colors.black.withValues(alpha: 0.58)),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.74,
              child: PartnerAnalysisRecordsScreen(
                subjectName: 'Test',
                metVia: 'IG',
                records: records,
                platformForRecord: (record) => record.sourcePlatform,
                archivedConversationCount: 2,
                onSetMetVia: (_) {},
                onOpenArchivedConversations: () {},
              ),
            ),
          ),
        ],
      ),
      outPath: outPath('analysis_archive_sheet.png'),
    );
  });

  testWidgets('capture analysis record detail', (tester) async {
    await pumpAndCapture(
      tester,
      child: AnalysisRecordDetailScreen(
        record: records.first,
        platform: records.first.sourcePlatform,
        onDelete: () async {},
      ),
      outPath: outPath('analysis_record_detail.png'),
    );
  });
}
