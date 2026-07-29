// test/helpers/ebook_test_content.dart
//
// 互動電子書測試共用素材：
//   - [MapAssetBundle]：把 in-memory JSON 當成 asset，讓 catalog repository 在
//     unit / widget test 裡完全不依賴 rootBundle。
//   - [productionEbookAssets]：從磁碟讀真實的四份內容資產，用來驗真內容不變量。
//   - [buildTestEbook] 等 builder：widget test 用的最小 typed fixture。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';

/// 以 Map 為後端的 [AssetBundle]，key 是 asset path。
class MapAssetBundle extends CachingAssetBundle {
  MapAssetBundle(this.entries);

  final Map<String, String> entries;

  @override
  Future<ByteData> load(String key) async {
    final value = entries[key];
    if (value == null) {
      throw FlutterError('MapAssetBundle 沒有這個 asset：$key');
    }
    final bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.view(bytes.buffer);
  }
}

/// 讀取 repo 內真實的四份電子書 JSON（不經 rootBundle，直接讀檔）。
Map<String, String> productionEbookAssets() {
  final entries = <String, String>{};
  for (final path in EbookCatalogRepository.productionAssetPaths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('缺少電子書內容資產：$path');
    }
    entries[path] = file.readAsStringSync();
  }
  return entries;
}

/// 用真實內容資產建立 catalog repository。
EbookCatalogRepository productionCatalogRepository() =>
    EbookCatalogRepository(bundle: MapAssetBundle(productionEbookAssets()));

/// 載入真實內容 catalog。
Future<EbookCatalog> loadProductionCatalog() =>
    productionCatalogRepository().load();

// ---------------------------------------------------------------------------
// Typed fixtures（widget test 用，避免每個測試都要準備完整 JSON）
// ---------------------------------------------------------------------------

EbookQuizBlock buildTestQuiz({
  String id = 'quiz-1',
  EbookQuizMode mode = EbookQuizMode.single,
  EbookQuizRetryPolicy retryPolicy = EbookQuizRetryPolicy.untilCorrect,
  int revision = 1,
}) {
  return EbookQuizBlock(
    id: id,
    question: '哪一句先回應了情緒？',
    scenario: '她說今天上班快累死。',
    mode: mode,
    retryPolicy: retryPolicy,
    revision: revision,
    choices: [
      EbookQuizChoice(
        id: '$id-a',
        text: '辛苦了',
        isCorrect: false,
        feedback: '這是終結句，對話無處可去。',
      ),
      EbookQuizChoice(
        id: '$id-b',
        text: '發生什麼事，是人的問題還是事的問題',
        isCorrect: true,
        feedback: '往情緒走，而且給了超好答的框架。',
      ),
      EbookQuizChoice(
        id: '$id-c',
        text: '那你早點休息',
        isCorrect: mode == EbookQuizMode.multiple,
        feedback: '這是關心，但它把對話收掉了。',
      ),
    ],
    takeaway: '情緒是開口，事實是死路。',
  );
}

EbookFlipCardBlock buildTestFlipCard({String id = 'flip-1'}) {
  return EbookFlipCardBlock(
    id: id,
    frontTitle: '表面問題',
    frontText: '我聊天不夠有趣。',
    backTitle: '真正的瓶頸',
    backText: '對話撐得住，掉的是他從來沒開口。',
    backPoints: const ['先修最前面的瓶頸。'],
  );
}

EbookChecklistBlock buildTestChecklist({String id = 'check-1'}) {
  return EbookChecklistBlock(
    id: id,
    title: '本週自評',
    items: [
      EbookChecklistItem(id: '$id-i1', text: '我引用了對方檔案裡的具體東西'),
      EbookChecklistItem(id: '$id-i2', text: '我露出了關於自己的一點東西'),
    ],
  );
}

EbookDialogueBlock buildTestDialogue({String id = 'dlg-1'}) {
  return EbookDialogueBlock(
    id: id,
    title: '逐句標記示範',
    lines: [
      EbookDialogueLine(
        id: '$id-l1',
        speaker: EbookSpeaker.you,
        text: '剛練完腿，現在下樓梯像八十歲',
        annotation: 'V↑ E↑',
      ),
      EbookDialogueLine(
        id: '$id-l2',
        speaker: EbookSpeaker.other,
        text: '哈哈哈我上次練完隔天完全站不起來',
        signal: EbookSignal.green,
      ),
      EbookDialogueLine(
        id: '$id-l3',
        speaker: EbookSpeaker.you,
        text: '喔喔',
        isDeathPoint: true,
        signal: EbookSignal.red,
      ),
    ],
  );
}

/// 漏斗 fixture。目標刻意可覆寫，方便驗「跳到另一本書」與「跳到同一本書」。
EbookStageFunnelBlock buildTestStageFunnel({
  String id = 'funnel-1',
  String targetBookId = 'book-1',
  String targetChapterId = 'book-1-chapter-2',
  int stageCount = 3,
}) {
  return EbookStageFunnelBlock(
    id: id,
    title: '你在漏斗的哪一層掉出去？',
    intro: '不用算數字，點最像你現況的那一層。',
    stages: [
      for (var index = 0; index < stageCount; index++)
        EbookFunnelStage(
          id: '$id-s$index',
          number: '$index',
          stageName: '階段 · 測試 $index',
          symptom: '症狀 $index',
          verdictTitle: '你卡在階段 $index',
          verdictText: '判斷內容 $index。',
          targetBookId: targetBookId,
          targetChapterId: targetChapterId,
          targetLabel: '前往目標 $index',
        ),
    ],
  );
}

EbookChapter buildTestChapter({
  required String id,
  String number = '1.1',
  String title = '測試章節',
  List<EbookBlock>? blocks,
}) {
  return EbookChapter(
    id: id,
    number: number,
    title: title,
    learningGoal: '這一章只回答一個問題。',
    estimatedMinutes: 5,
    sourceRefs: const [
      EbookSourceRef(document: 'five-stage-course', sections: ['第一節']),
    ],
    blocks: blocks ??
        [
          EbookParagraphBlock(id: '$id-p1', text: '段落內容。'),
          buildTestDialogue(id: '$id-dlg'),
          buildTestFlipCard(id: '$id-flip'),
          buildTestQuiz(id: '$id-quiz'),
        ],
  );
}

Ebook buildTestEbook({
  required String id,
  int number = 1,
  EbookUnit unit = EbookUnit.ultimateGuide,
  String title = '測試書',
  EbookAccess access = EbookAccess.free,
  EbookTheme theme = EbookTheme.compass,
  int chapterCount = 2,
  List<EbookChapter>? chapters,
}) {
  return Ebook(
    schemaVersion: kEbookSchemaVersion,
    id: id,
    contentVersion: 1,
    number: number,
    unit: unit,
    title: title,
    subtitle: '測試副標',
    goal: '測試目標。',
    access: access,
    theme: theme,
    estimatedMinutes: 30,
    sourceRefs: const [
      EbookSourceRef(document: 'five-stage-course', sections: ['第一節']),
    ],
    chapters: chapters ??
        List.generate(
          chapterCount,
          (index) => buildTestChapter(
            id: '$id-chapter-${index + 1}',
            number: '$number.${index + 1}',
            title: '第 ${index + 1} 章',
          ),
        ),
  );
}

/// 兩本書的 catalog：第一本免費、第二本訂閱，剛好夠測付費閘門。
EbookCatalog buildTestCatalog({
  int freeChapterCount = 2,
  int premiumChapterCount = 2,
}) {
  return EbookCatalog(
    books: [
      buildTestEbook(
        id: 'test-book-free',
        number: 1,
        title: '免費測試書',
        access: EbookAccess.free,
        chapterCount: freeChapterCount,
      ),
      buildTestEbook(
        id: 'test-book-premium',
        number: 2,
        title: '訂閱測試書',
        access: EbookAccess.premium,
        theme: EbookTheme.lens,
        chapterCount: premiumChapterCount,
      ),
    ],
  );
}
