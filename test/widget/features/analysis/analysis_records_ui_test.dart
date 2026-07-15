import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_record_detail_screen.dart';
import 'package:vibesync/features/analysis/presentation/screens/partner_analysis_records_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_platform_picker.dart';

String _snapshot() => jsonEncode({
      'enthusiasm': {'score': 72, 'level': 'warm'},
      'strategy': '先接住她提到的旅行，再分享一個短故事。',
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '延伸共同話題',
      },
      'psychology': {'subtext': '她願意多分享，是可以繼續接球的訊號。'},
      'topicDepth': {'current': 'personal', 'suggestion': ''},
      'replies': {'extend': '聽起來超有趣，哪一段最讓妳印象深刻？'},
      'finalRecommendation': {
        'pick': 'extend',
        'content': '聽起來超有趣，哪一段最讓妳印象深刻？',
        'reason': '順著她主動分享的內容延伸，回覆壓力比較低。',
        'psychology': '讓她感覺你真的有在聽，而不是急著換話題。',
      },
    });

AnalysisRecord _record({
  required String id,
  required DateTime createdAt,
  required String preview,
  String? sourcePlatform,
}) {
  return AnalysisRecord(
    id: id,
    ownerUserId: 'user-1',
    conversationId: 'conversation-$id',
    partnerId: 'partner-1',
    subjectName: '小雲',
    segmentStart: 0,
    segmentEnd: 2,
    createdAt: createdAt,
    messages: [
      AnalysisRecordMessage(
        id: '$id-1',
        content: '妳週末去哪裡玩？',
        isFromMe: true,
        timestamp: createdAt,
      ),
      AnalysisRecordMessage(
        id: '$id-2',
        content: preview,
        isFromMe: false,
        timestamp: createdAt.add(const Duration(minutes: 1)),
      ),
    ],
    analysisSnapshotJson: _snapshot(),
    analyzedContentRevision: 'revision-$id',
    completionKey: 'completion-$id',
    sourcePlatform: sourcePlatform,
    enthusiasmScore: 72,
    gameStageLabel: '建立男女感',
  );
}

void main() {
  testWidgets('平台 picker 提供常用平台、未分類與自訂值', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AnalysisPlatformPickerResult? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selection = await showAnalysisPlatformPicker(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final platform in commonAnalysisPlatforms) {
      expect(find.text(platform), findsOneWidget);
    }
    expect(find.text('未分類'), findsWidgets);

    await tester.tap(find.text('其他平台'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('analysis-platform-custom-input')),
      'Discord',
    );
    await tester.tap(
      find.byKey(const ValueKey('analysis-platform-custom-confirm')),
    );
    await tester.pumpAndSettle();

    expect(selection?.platform, 'Discord');
    expect(tester.takeException(), isNull);
  });

  testWidgets('紀錄頁最新優先、動態篩選，並可手動刪除', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final older = _record(
      id: 'older',
      createdAt: DateTime(2026, 7, 10, 21),
      preview: 'LINE 上的舊片段',
      sourcePlatform: 'LINE',
    );
    final newer = _record(
      id: 'newer',
      createdAt: DateTime(2026, 7, 12, 21),
      preview: 'Omi 上的新片段',
      sourcePlatform: 'Omi',
    );
    final unclassified = _record(
      id: 'unclassified',
      createdAt: DateTime(2026, 7, 11, 21),
      preview: '還沒標記平台的片段',
    );
    AnalysisRecord? deleted;

    await tester.pumpWidget(
      MaterialApp(
        home: PartnerAnalysisRecordsScreen(
          subjectName: '名字非常長但仍然不能讓窄螢幕爆版的小雲',
          metVia: 'Omi',
          records: [older, newer, unclassified],
          platformForRecord: (record) => record.sourcePlatform,
          onSetMetVia: (_) {},
          onDelete: (record) => deleted = record,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每次分析獨立保存，不會串成逐字稿'), findsOneWidget);
    expect(find.text('認識於 Omi'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('Omi'), findsWidgets);
    expect(find.text('LINE'), findsWidgets);
    expect(find.text('未分類'), findsWidgets);
    expect(
      tester.getTopLeft(find.text('Omi 上的新片段')).dy,
      lessThan(tester.getTopLeft(find.text('LINE 上的舊片段')).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey('analysis-record-filter-LINE')),
    );
    await tester.pumpAndSettle();
    expect(find.text('LINE 上的舊片段'), findsOneWidget);
    expect(find.text('Omi 上的新片段'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('analysis-record-delete-older')),
    );
    await tester.pumpAndSettle();
    expect(find.text('刪除這筆分析？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('analysis-record-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(deleted?.id, 'older');
    expect(find.text('LINE 上的舊片段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紀錄詳情只讀顯示當時聊天與建議', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final record = _record(
      id: 'detail',
      createdAt: DateTime(2026, 7, 12, 21),
      preview: '我去了台南，吃到一家很好吃的小店。',
      sourcePlatform: 'Threads',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AnalysisRecordDetailScreen(
          record: record,
          platform: record.sourcePlatform,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小雲・Threads'), findsOneWidget);
    expect(find.text('妳週末去哪裡玩？'), findsOneWidget);
    expect(find.text('我去了台南，吃到一家很好吃的小店。'), findsOneWidget);
    expect(find.text('先接住她提到的旅行，再分享一個短故事。'), findsOneWidget);
    expect(find.text('聽起來超有趣，哪一段最讓妳印象深刻？'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
