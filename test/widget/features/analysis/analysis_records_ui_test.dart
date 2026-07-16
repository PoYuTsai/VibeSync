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
      'psychology': {
        'subtext': '她願意多分享，是可以繼續接球的訊號。',
        'shitTest': {
          'detected': true,
          'suggestion': '她在確認你是不是只會嘴上說說。',
        },
        'qualificationSignal': true,
      },
      'topicDepth': {
        'current': 'personal',
        'suggestion': '從旅行經驗聊到她在意的生活感受。',
      },
      'healthCheck': {
        'issues': ['連續問句偏多'],
        'suggestions': ['先分享再提一個問題'],
      },
      'dimensions': {
        'heat': 72,
        'engagement': 68,
        'topicDepth': 64,
        'replyWillingness': 75,
        'emotionalConnection': 61,
      },
      'replies': {
        'extend': '聽起來超有趣，哪一段最讓妳印象深刻？',
        'resonate': '我也很喜歡那種意外找到小店的驚喜感。',
        'tease': '妳這樣講，我要先懷疑妳是不是台南美食臥底。',
        'humor': '收到，下次行程直接交給妳這位民間米其林。',
        'coldRead': '感覺妳旅行時比起踩景點，更在意遇到的小驚喜。',
      },
      'finalRecommendation': {
        'pick': 'extend',
        'content': '聽起來超有趣，哪一段最讓妳印象深刻？',
        'reason': '順著她主動分享的內容延伸，回覆壓力比較低。',
        'psychology': '讓她感覺你真的有在聽，而不是急著換話題。',
      },
      'reminder': '別急著證明自己，先觀察她是否也願意投入。',
    });

AnalysisRecord _record({
  required String id,
  required DateTime createdAt,
  required String preview,
  String? sourcePlatform,
  String? analysisSnapshotJson,
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
    analysisSnapshotJson: analysisSnapshotJson ?? _snapshot(),
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
    expect(find.text('聽起來超有趣，哪一段最讓妳印象深刻？'), findsWidgets);
    expect(find.text('為什麼這樣回'), findsOneWidget);
    expect(find.text('順著她主動分享的內容延伸，回覆壓力比較低。'), findsOneWidget);
    expect(find.text('五維度剖析', skipOffstage: false), findsOneWidget);
    expect(find.text('對話進度', skipOffstage: false), findsOneWidget);
    expect(find.text('她在確認你是不是只會嘴上說說。', skipOffstage: false), findsOneWidget);
    expect(find.text('從旅行經驗聊到她在意的生活感受。', skipOffstage: false), findsOneWidget);
    expect(find.text('連續問句偏多', skipOffstage: false), findsOneWidget);
    expect(find.text('先分享再提一個問題', skipOffstage: false), findsOneWidget);
    expect(find.text('接法建議・5 種風格', skipOffstage: false), findsOneWidget);
    expect(
      find.text('別急著證明自己，先觀察她是否也願意投入。', skipOffstage: false),
      findsOneWidget,
    );
    final detailList = find.byKey(const ValueKey('analysis-record-detail'));
    await tester.drag(detailList, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.drag(detailList, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('🔄 延展'), findsOneWidget);
    final replyCarousel =
        find.byKey(const ValueKey('analysis-record-reply-styles'));
    await tester.drag(replyCarousel, const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('💬 共鳴'), findsOneWidget);
    await tester.drag(replyCarousel, const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('😏 調情'), findsOneWidget);
    await tester.drag(replyCarousel, const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('🎭 幽默'), findsOneWidget);
    await tester.drag(replyCarousel, const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('🔮 冷讀'), findsOneWidget);
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
    expect(find.textContaining('重新分析'), findsNothing);
    expect(find.textContaining('繼續這一段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('冰點分析紀錄會保留當時的停損警示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final record = _record(
      id: 'cold-detail',
      createdAt: DateTime(2026, 7, 13, 22),
      preview: '她只回了一個貼圖。',
      analysisSnapshotJson: jsonEncode({
        'enthusiasm': {'score': 18, 'level': 'cold'},
        'warnings': ['建議放棄：目前投入明顯不對等'],
        'strategy': '先停止追問，觀察對方是否會主動。',
        'reminder': '你不需要靠更多訊息換取回覆。',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: AnalysisRecordDetailScreen(record: record)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('analysis-record-give-up-warning')),
      findsOneWidget,
    );
    expect(
      find.text('這段互動目前不建議再投入，先保護自己的時間與情緒成本。'),
      findsOneWidget,
    );
    expect(
      find.text('你不需要靠更多訊息換取回覆。', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('重新分析'), findsNothing);
    expect(find.textContaining('繼續這一段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('舊版缺欄位快照仍能唯讀顯示已有分析', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final record = _record(
      id: 'legacy-detail',
      createdAt: DateTime(2026, 6, 1, 18),
      preview: '這是舊版保存的聊天。',
      analysisSnapshotJson: jsonEncode({
        'enthusiasm': {'score': 58, 'level': 'warm'},
        'strategy': '舊版仍有的互動策略。',
        'finalRecommendation': {
          'content': '先接住她的情緒，再問一個小問題。',
          'reason': '讓對話保持輕鬆。',
          'psychology': '',
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: AnalysisRecordDetailScreen(record: record)),
    );
    await tester.pumpAndSettle();

    expect(find.text('這是舊版保存的聊天。'), findsOneWidget);
    expect(find.text('舊版仍有的互動策略。', skipOffstage: false), findsOneWidget);
    expect(
      find.text('先接住她的情緒，再問一個小問題。', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('五維度剖析', skipOffstage: false), findsNothing);
    expect(find.textContaining('種風格', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('損壞分析快照仍保留當時聊天且不提供重跑入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final record = _record(
      id: 'corrupt-detail',
      createdAt: DateTime(2026, 6, 2, 19),
      preview: '即使分析壞掉，這段聊天也不能消失。',
      analysisSnapshotJson: '{not-json',
    );

    await tester.pumpWidget(
      MaterialApp(home: AnalysisRecordDetailScreen(record: record)),
    );
    await tester.pumpAndSettle();

    expect(find.text('即使分析壞掉，這段聊天也不能消失。'), findsOneWidget);
    expect(
      find.text('這筆分析內容暫時無法顯示，但上方聊天片段仍完整保留。'),
      findsOneWidget,
    );
    expect(find.textContaining('重新分析'), findsNothing);
    expect(find.textContaining('繼續這一段'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
