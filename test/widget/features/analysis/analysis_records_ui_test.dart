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
        quotedReplyPreview: '妳週末去哪裡玩？',
        quotedReplyPreviewIsFromMe: true,
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
  testWidgets('平台 picker 提供常用平台、暫不設定與自訂值', (tester) async {
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
    expect(find.text('暫不設定'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-platform-unset')),
      findsOneWidget,
    );
    expect(find.text('未分類'), findsNothing);

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

  testWidgets('紀錄抽屜最新優先、只篩選已知平台，並從詳情刪除', (tester) async {
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
    final unknownSource = _record(
      id: 'unknown-source',
      createdAt: DateTime(2026, 7, 11, 21),
      preview: '還沒標記平台的片段',
    );
    AnalysisRecord? deleted;

    await tester.pumpWidget(
      MaterialApp(
        home: PartnerAnalysisRecordsScreen(
          subjectName: '名字非常長但仍然不能讓窄螢幕爆版的小雲',
          metVia: 'Omi',
          records: [older, newer, unknownSource],
          platformForRecord: (record) => record.sourcePlatform,
          onSetMetVia: (_) {},
          onDelete: (record) => deleted = record,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每次分析獨立保存，不會串成逐字稿'), findsOneWidget);
    expect(find.text('認識於 Omi'), findsOneWidget);
    expect(find.text('全部 3'), findsOneWidget);
    expect(find.text('Omi 1'), findsOneWidget);
    expect(find.text('LINE 1'), findsOneWidget);
    expect(find.text('未分類'), findsNothing);
    expect(find.textContaining('本次投入 72'), findsNWidgets(3));
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(
      tester.getTopLeft(find.text('她說：「Omi 上的新片段」')).dy,
      lessThan(
        tester.getTopLeft(find.text('她說：「LINE 上的舊片段」')).dy,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('analysis-record-filter-LINE')),
    );
    await tester.pumpAndSettle();
    expect(find.text('她說：「LINE 上的舊片段」'), findsOneWidget);
    expect(find.text('她說：「Omi 上的新片段」'), findsNothing);
    expect(find.text('她說：「還沒標記平台的片段」'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('analysis-record-older')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('analysis-record-detail-menu')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('analysis-record-detail-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('analysis-record-delete-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('刪除這筆分析？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('analysis-record-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(deleted?.id, 'older');
    expect(find.text('她說：「LINE 上的舊片段」'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未設來源紀錄留在全部，不從認識平台推測或顯示未分類', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final unknownSource = _record(
      id: 'unknown-source',
      createdAt: DateTime(2026, 7, 11, 21),
      preview: '從這一句開始繼續聊',
    );
    final oneKnownSource = _record(
      id: 'one-known-source',
      createdAt: DateTime(2026, 7, 10, 21),
      preview: 'Omi 上的另一段對話',
      sourcePlatform: 'Omi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PartnerAnalysisRecordsScreen(
          subjectName: '小雲',
          metVia: 'IG',
          records: [unknownSource, oneKnownSource],
          platformForRecord: (record) => record.sourcePlatform,
          onSetMetVia: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('認識於 IG'), findsOneWidget);
    expect(find.text('她說：「從這一句開始繼續聊」'), findsOneWidget);
    expect(find.text('她說：「Omi 上的另一段對話」'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-record-platform-filters')),
      findsNothing,
    );
    expect(find.text('IG'), findsNothing);
    expect(find.text('未分類'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多筆紀錄時仍可捲到已收起對話次入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final records = List.generate(
      4,
      (index) => _record(
        id: 'scroll-$index',
        createdAt: DateTime(2026, 7, 16).subtract(Duration(days: index)),
        preview: '第 ${index + 1} 筆獨立分析',
        sourcePlatform: index.isEven ? 'Omi' : 'LINE',
      ),
    );
    PartnerAnalysisRecordsSheetAction? action;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                action = await showPartnerAnalysisRecordsSheet(
                  context,
                  subjectName: '小雲',
                  records: records,
                  platformForRecord: (record) => record.sourcePlatform,
                  archivedConversationCount: 2,
                );
              },
              child: const Text('開啟分析紀錄'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟分析紀錄'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('partner-analysis-records-list')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    final secondaryEntry = find.byKey(
      const ValueKey('archived-conversations-secondary-entry'),
    );

    expect(secondaryEntry.hitTestable(), findsOneWidget);
    await tester.tap(secondaryEntry);
    await tester.pumpAndSettle();
    expect(
      action,
      PartnerAnalysisRecordsSheetAction.openArchivedConversations,
    );
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
          onDelete: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7 月 12 日的分析'), findsOneWidget);
    expect(find.text('小雲'), findsOneWidget);
    expect(find.text('7 月 12 日 · 21:00 · 2 則訊息'), findsOneWidget);
    expect(find.text('獨立分析'), findsOneWidget);
    expect(find.text('Threads'), findsOneWidget);
    expect(find.text('本次投入 · 投入明顯'), findsOneWidget);
    expect(find.text('只反映這次互動中的文字訊號'), findsOneWidget);
    expect(find.text('妳週末去哪裡玩？'), findsOneWidget);
    expect(find.text('我去了台南，吃到一家很好吃的小店。'), findsOneWidget);
    expect(find.text('引用我說的：妳週末去哪裡玩？'), findsOneWidget);
    expect(find.text('先接住她提到的旅行，再分享一個短故事。'), findsOneWidget);
    expect(find.text('聽起來超有趣，哪一段最讓妳印象深刻？'), findsOneWidget);
    expect(find.text('為什麼這樣回'), findsOneWidget);
    expect(find.text('順著她主動分享的內容延伸，回覆壓力比較低。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-record-copy-recommendation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('analysis-record-detail-menu')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.text('未分類'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
