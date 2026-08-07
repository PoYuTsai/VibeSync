// test/helpers/chat_quiz_test_content.dart
//
// 聊天測驗測試共用素材：
//   - [productionChatQuizAssets]：從磁碟讀真實的測驗內容資產，用來驗真內容
//     不變量（不經 rootBundle）。
//   - [buildTestChatQuizLevel] 等 builder：unit / widget test 用的最小 fixture。
import 'dart:io';

import 'package:vibesync/features/learning/data/repositories/chat_quiz_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';

import 'ebook_test_content.dart';

/// 讀取 repo 內真實的測驗 JSON（不經 rootBundle，直接讀檔）。
Map<String, String> productionChatQuizAssets() {
  final entries = <String, String>{};
  for (final path in ChatQuizCatalogRepository.productionAssetPaths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('缺少聊天測驗內容資產：$path');
    }
    entries[path] = file.readAsStringSync();
  }
  return entries;
}

/// 用真實內容資產建立測驗 catalog repository。
ChatQuizCatalogRepository productionChatQuizRepository() =>
    ChatQuizCatalogRepository(bundle: MapAssetBundle(productionChatQuizAssets()));

/// 載入真實測驗 catalog。
Future<ChatQuizCatalog> loadProductionChatQuizCatalog() =>
    productionChatQuizRepository().load();

// ---------------------------------------------------------------------------
// Typed fixtures
// ---------------------------------------------------------------------------

ChatQuizQuestion buildTestChatQuizQuestion({
  String id = 'q-test-1',
  ChatQuizQuestionType type = ChatQuizQuestionType.signalRead,
  int revision = 1,
  String? scenario = '她：今天上班快累死',
  ChatQuizSource? source,
  int choiceCount = 3,
  int correctIndex = 0,
}) {
  final choices = [
    for (var index = 0; index < choiceCount; index++)
      ChatQuizChoice(
        id: '$id-${String.fromCharCode(97 + index)}',
        text: '選項 ${index + 1}',
        isCorrect: index == correctIndex,
        feedback: index == correctIndex ? '對，往情緒走。' : '這句把對話收掉了。',
      ),
  ];

  return switch (type) {
    ChatQuizQuestionType.signalRead => ChatQuizSignalReadQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: '這句是什麼燈？',
        choices: choices,
        takeaway: '情緒是開口，事實是死路。',
        source: source,
      ),
    ChatQuizQuestionType.pickReply => ChatQuizPickReplyQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: '這一句你會怎麼回？',
        choices: choices,
        takeaway: '往情緒走，而且給她好答的框架。',
        source: source,
      ),
    ChatQuizQuestionType.findDeathPoint => ChatQuizFindDeathPointQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: '哪一個在扣分？',
        choices: choices,
        takeaway: '先找出在扣分的那一個，再談怎麼加分。',
        source: source,
      ),
    ChatQuizQuestionType.doseCheck => ChatQuizDoseCheckQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: '這份草稿多給了什麼？',
        choices: choices,
        takeaway: '她給多少，你就給差不多多少。',
        source: source,
      ),
  };
}

ChatQuizLevel buildTestChatQuizLevel({
  String id = 'quiz-level-1-1',
  String number = '1-1',
  String title = '她現在是哪一種',
  EbookAccess access = EbookAccess.free,
  double passRatio = 0.8,
  int questionCount = 5,
  List<ChatQuizQuestion>? questions,
}) {
  return ChatQuizLevel(
    id: id,
    number: number,
    title: title,
    goal: '把「我該說什麼」換成「她現在是哪一種狀態」。',
    access: access,
    passRatio: passRatio,
    questions: questions ??
        List.generate(
          questionCount,
          (index) => buildTestChatQuizQuestion(
            id: '$id-q${index + 1}',
            type: index.isEven
                ? ChatQuizQuestionType.signalRead
                : ChatQuizQuestionType.pickReply,
          ),
        ),
  );
}

ChatQuizGroup buildTestChatQuizGroup({
  String id = 'quiz-group-1',
  int number = 1,
  String key = 'signal',
  String title = '讀燈',
  List<ChatQuizLevel>? levels,
}) {
  return ChatQuizGroup(
    schemaVersion: kChatQuizSchemaVersion,
    id: id,
    number: number,
    key: key,
    title: title,
    subtitle: '她現在是什麼狀態',
    stageLabel: '破冰',
    levels: levels ?? [buildTestChatQuizLevel()],
  );
}

/// 一群兩關：第一關免費、第二關訂閱，剛好夠測付費閘門與群內線性解鎖。
ChatQuizCatalog buildTestChatQuizCatalog() {
  return ChatQuizCatalog(
    groups: [
      buildTestChatQuizGroup(
        levels: [
          buildTestChatQuizLevel(),
          buildTestChatQuizLevel(
            id: 'quiz-level-1-2',
            number: '1-2',
            title: '消極期先止損',
            access: EbookAccess.premium,
          ),
        ],
      ),
    ],
  );
}
