// test/unit/features/onboarding/onboarding_quiz_question_test.dart
//
// onboarding 轉換第 12 步第 2 頁用的那一題（kOnboardingQuizQuestionId）。題庫 #111
// 改寫過，這支釘住：這一題真的在內建題庫裡、是讀燈題、在免費關、恰好一個正解。
// Bruce 要換題只改那個常數；換到付費關或別的題型，這裡會擋下來。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/onboarding/data/onboarding_quiz.dart';

import '../../../helpers/chat_quiz_test_content.dart';

void main() {
  late ChatQuizCatalog catalog;

  setUpAll(() async {
    catalog = await loadProductionChatQuizCatalog();
  });

  test('預設題號是 q-1-1-01', () {
    expect(kOnboardingQuizQuestionId, 'q-1-1-01');
  });

  test('這一題在內建題庫：讀燈題、在免費關、恰好一個正解、每個選項都有解析', () {
    final question = catalog.findQuestion(kOnboardingQuizQuestionId);
    expect(question, isNotNull, reason: '題庫裡要有 $kOnboardingQuizQuestionId');
    expect(question!.type, ChatQuizQuestionType.signalRead);
    expect(question.scenario, isNotNull);
    expect(question.question, isNotEmpty);
    expect(question.takeaway, isNotEmpty);
    expect(question.choices.where((choice) => choice.isCorrect), hasLength(1));
    for (final choice in question.choices) {
      expect(choice.feedback, isNotEmpty, reason: choice.id);
    }

    final level = catalog.allLevels
        .firstWhere((level) => level.findQuestion(question.id) != null);
    expect(level.id, 'quiz-level-1-1');
    expect(level.access, EbookAccess.free, reason: 'onboarding 不能露出付費關的題目');
  });

  test('onboardingQuizItemProvider：找得到這一題並帶關號', () async {
    final container = ProviderContainer(
      overrides: [
        chatQuizCatalogProvider.overrideWith((ref) async => catalog),
      ],
    );
    addTearDown(container.dispose);

    final item = await container.read(onboardingQuizItemProvider.future);
    expect(item, isNotNull);
    expect(item!.question.id, kOnboardingQuizQuestionId);
    expect(item.levelNumber, '1-1');
  });

  test('onboardingQuizItemProvider：題庫裡沒有這一題回 null', () async {
    final container = ProviderContainer(
      overrides: [
        chatQuizCatalogProvider
            .overrideWith((ref) async => buildTestChatQuizCatalog()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(onboardingQuizItemProvider.future), isNull);
  });
}
