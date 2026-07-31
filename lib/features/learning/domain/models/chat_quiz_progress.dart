// lib/features/learning/domain/models/chat_quiz_progress.dart
//
// 聊天測驗的本機進度。
//
// **這個檔案存在的唯一理由是：測驗進度絕不能和電子書進度共用一顆
// schemaVersion。** `EbookProgressSnapshot.fromJson` 的語意是「版本號對不上就
// 整包回空」——把測驗進度塞進那份 snapshot 再升版號，等於把所有現有使用者已經
// 讀完的章節、勾選、翻卡狀態一次清光，而且不會有任何錯誤訊息。
//
// 所以：獨立的模型、獨立的 [currentSchemaVersion]、獨立的 Hive key
// （`chat_quiz_progress_v1:<ownerUserId>`）。兩邊唯一的關聯是它們都住在同一個
// 加密 settingsBox 裡，而那只是儲存位置，不是資料結構。
library;

/// 一題的作答紀錄。
///
/// [revision] 存下來，題目改寫（revision +1）後舊答案自動失效需要重答——沿用
/// 電子書 quiz 已有的語意，避免「題目換了但畫面顯示上次答對」。
class ChatQuizAnswer {
  const ChatQuizAnswer({
    required this.choiceId,
    required this.revision,
    required this.answeredAt,
  });

  final String choiceId;
  final int revision;
  final DateTime answeredAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'choiceId': choiceId,
        'revision': revision,
        'answeredAt': answeredAt.toUtc().toIso8601String(),
      };

  /// 缺欄位或型別不符回 `null`，由呼叫端當成沒答過。單筆壞掉不影響其他題。
  static ChatQuizAnswer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final choiceId = raw['choiceId'];
    final revision = raw['revision'];
    if (choiceId is! String || choiceId.trim().isEmpty) return null;
    if (revision is! int || revision < 1) return null;
    final answeredAtRaw = raw['answeredAt'];
    final answeredAt =
        answeredAtRaw is String ? DateTime.tryParse(answeredAtRaw) : null;
    if (answeredAt == null) return null;
    return ChatQuizAnswer(
      choiceId: choiceId,
      revision: revision,
      answeredAt: answeredAt,
    );
  }
}

/// 一關的最佳成績。
///
/// 刻意只留「最好的那一次」：重試無限次且不扣任何東西，所以保留最差或最新的
/// 成績都會讓使用者覺得被懲罰。比較用比例而不是題數，題數之後改了也不會讓
/// 舊成績變成看起來更好。
class ChatQuizLevelResult {
  const ChatQuizLevelResult({
    required this.correctCount,
    required this.questionCount,
    required this.passed,
    required this.achievedAt,
  });

  final int correctCount;
  final int questionCount;
  final bool passed;
  final DateTime achievedAt;

  double get ratio => questionCount == 0 ? 0 : correctCount / questionCount;

  /// [other] 是否比這一筆更好。相同就不算更好——這讓重複送出同一個成績成為
  /// no-op（冪等）。
  bool isBetterThan(ChatQuizLevelResult other) => ratio > other.ratio;

  Map<String, Object?> toJson() => <String, Object?>{
        'correctCount': correctCount,
        'questionCount': questionCount,
        'passed': passed,
        'achievedAt': achievedAt.toUtc().toIso8601String(),
      };

  static ChatQuizLevelResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final correctCount = raw['correctCount'];
    final questionCount = raw['questionCount'];
    final passed = raw['passed'];
    if (correctCount is! int || correctCount < 0) return null;
    if (questionCount is! int || questionCount < 1) return null;
    if (correctCount > questionCount) return null;
    if (passed is! bool) return null;
    final achievedAtRaw = raw['achievedAt'];
    final achievedAt =
        achievedAtRaw is String ? DateTime.tryParse(achievedAtRaw) : null;
    if (achievedAt == null) return null;
    return ChatQuizLevelResult(
      correctCount: correctCount,
      questionCount: questionCount,
      passed: passed,
      achievedAt: achievedAt,
    );
  }
}

/// 一個帳號的完整測驗進度。
class ChatQuizProgress {
  const ChatQuizProgress({
    this.schemaVersion = currentSchemaVersion,
    this.updatedAt,
    this.levels = const <String, ChatQuizLevelResult>{},
    this.answers = const <String, ChatQuizAnswer>{},
  });

  /// **測驗自己的版本號。** 與 `EbookProgressSnapshot.currentSchemaVersion`
  /// 完全無關，升這一顆不會動到任何人的閱讀進度。
  static const int currentSchemaVersion = 1;
  static const empty = ChatQuizProgress();

  final int schemaVersion;
  final DateTime? updatedAt;

  /// levelId → 最佳成績。
  final Map<String, ChatQuizLevelResult> levels;

  /// questionId → 作答紀錄。
  final Map<String, ChatQuizAnswer> answers;

  ChatQuizLevelResult? resultFor(String levelId) => levels[levelId];

  bool isLevelPassed(String levelId) => levels[levelId]?.passed ?? false;

  /// 這一題的有效作答。題目 [revision] 改過就回 `null`（舊答案失效，要重答）。
  ChatQuizAnswer? answerFor(String questionId, {required int revision}) {
    final answer = answers[questionId];
    if (answer == null) return null;
    return answer.revision == revision ? answer : null;
  }

  ChatQuizProgress copyWith({
    DateTime? updatedAt,
    Map<String, ChatQuizLevelResult>? levels,
    Map<String, ChatQuizAnswer>? answers,
  }) {
    return ChatQuizProgress(
      schemaVersion: currentSchemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      levels: levels ?? this.levels,
      answers: answers ?? this.answers,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
        'levels': <String, Object?>{
          for (final entry in levels.entries) entry.key: entry.value.toJson(),
        },
        'answers': <String, Object?>{
          for (final entry in answers.entries) entry.key: entry.value.toJson(),
        },
      };

  /// 未知 schema version 一律回空進度（fail closed），並且不刪除原始資料。
  ///
  /// 這裡的「整包回空」只影響測驗——電子書進度住在另一顆 key，看不到這個決定。
  static ChatQuizProgress fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final schemaVersion = raw['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      return empty;
    }

    final levels = <String, ChatQuizLevelResult>{};
    final levelsRaw = raw['levels'];
    if (levelsRaw is Map) {
      for (final entry in levelsRaw.entries) {
        final key = entry.key;
        if (key is! String || key.trim().isEmpty) continue;
        final result = ChatQuizLevelResult.fromJson(entry.value);
        if (result != null) levels[key] = result;
      }
    }

    final answers = <String, ChatQuizAnswer>{};
    final answersRaw = raw['answers'];
    if (answersRaw is Map) {
      for (final entry in answersRaw.entries) {
        final key = entry.key;
        if (key is! String || key.trim().isEmpty) continue;
        final answer = ChatQuizAnswer.fromJson(entry.value);
        if (answer != null) answers[key] = answer;
      }
    }

    final updatedAtRaw = raw['updatedAt'];
    return ChatQuizProgress(
      schemaVersion: currentSchemaVersion,
      updatedAt: updatedAtRaw is String ? DateTime.tryParse(updatedAtRaw) : null,
      levels: levels,
      answers: answers,
    );
  }
}
