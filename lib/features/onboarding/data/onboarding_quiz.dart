// lib/features/onboarding/data/onboarding_quiz.dart
//
// onboarding 轉換第 12 步：第 2 頁「先考你一題」用的那一題，從內建聊天測驗題庫
// 拿（chatQuizCatalogProvider 讀 bundled JSON，不連網、零 AI 費用）。
// 不記作答進度：還沒登入，測驗進度本來就只存在登入帳號底下。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../learning/data/providers/chat_quiz_providers.dart';
import '../../learning/domain/models/chat_quiz.dart';

/// 第 2 頁的題號。Bruce 要換題只改這一處；換的題要在免費關，而且是讀燈題
/// （`onboarding_quiz_question_test.dart` 會擋）。
const kOnboardingQuizQuestionId = 'q-1-1-01';

/// 第 2 頁要顯示的一題，連同它所在的關號（畫面上寫「取自聊天測驗 1-1」）。
class OnboardingQuizItem {
  const OnboardingQuizItem({
    required this.question,
    required this.levelNumber,
  });

  final ChatQuizQuestion question;
  final String levelNumber;
}

/// 從內建題庫找 [kOnboardingQuizQuestionId]；題庫裡沒有這一題回 null，題庫讀
/// 不到是 AsyncError。兩種情況第 2 頁都改顯示一句說明，「下一步」照樣能按。
final onboardingQuizItemProvider =
    FutureProvider<OnboardingQuizItem?>((ref) async {
  final catalog = await ref.watch(chatQuizCatalogProvider.future);
  for (final level in catalog.allLevels) {
    final question = level.findQuestion(kOnboardingQuizQuestionId);
    if (question != null) {
      return OnboardingQuizItem(question: question, levelNumber: level.number);
    }
  }
  return null;
});
