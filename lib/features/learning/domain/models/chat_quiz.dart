// lib/features/learning/domain/models/chat_quiz.dart
//
// 聊天測驗（判讀訓練場）的內容模型。
//
// 產品不變量（CC 不自行改動）：
//   - 題型目前有三種：讀燈（signalRead）、選回覆（pickReply）、找死亡點
//     （findDeathPoint，2026-08-07 擴充批 A 引入）。擴充批 C／D 才會加
//     doseCheck 與 gearShift。
//   - **正解永遠是一個選擇，不會是使用者輸入的字串。** 這條由型別層守住：
//     [ChatQuizQuestion] 只有 choices，沒有任何自由輸入欄位。「自己改一句」
//     那種題型延到第 3 期，且需要另外授權（會動到 Edge Function 與計費）。
//   - 一關的權限＝這一關所有題目來源書當中最高的那一層（free < premium <
//     essential）。JSON 裡的 [ChatQuizLevel.access] 是宣告值，由
//     `chat_quiz_content_invariants_test.dart` 驗證它與來源推導的結果一致——
//     runtime 不推導，否則內容一改權限就會悄悄跟著飄。
//   - 測驗進度用自己的 Hive key，絕不併進電子書的 `learning_progress_v1:`。
//     見 `chat_quiz_progress.dart`。
//
// 權限型別刻意重用電子書的 [EbookAccess]：測驗題目取材自電子書，兩邊若各有
// 一套權限階梯，遲早會出現「書鎖著但題目開著」的破洞。
library;

import 'ebook.dart';

/// 題型。新增一種就會讓所有 exhaustive switch 編譯失敗，逼著補 UI 與內容守門。
enum ChatQuizQuestionType { signalRead, pickReply, findDeathPoint }

/// 深連目標：這一題背後的原理寫在哪本書的哪一章。
///
/// 查不到對應章節時，內容端整個省略這個欄位（而不是填空字串），UI 就不顯示
/// 「讀原理」按鈕。目標存在與否由內容不變式測試對照 `ebookCatalog` 驗。
class ChatQuizSource {
  const ChatQuizSource({required this.bookId, required this.chapterId});

  final String bookId;
  final String chapterId;
}

/// 一個選項。每個選項都必須有自己的 [feedback]——答錯的人需要知道為什麼錯，
/// 只給「正確答案是 B」等於沒教。
class ChatQuizChoice {
  const ChatQuizChoice({
    required this.id,
    required this.text,
    required this.isCorrect,
    required this.feedback,
  });

  final String id;
  final String text;
  final bool isCorrect;
  final String feedback;
}

/// 一題。
///
/// sealed：之後加題型時，答題器與結果頁的 switch 會編譯失敗，不會有「新題型
/// 靜默走預設分支」的情況。第 1 期兩個子型別欄位相同，差別在 UI 呈現與內容
/// 守門規則，不在資料形狀。
sealed class ChatQuizQuestion {
  const ChatQuizQuestion({
    required this.id,
    required this.revision,
    required this.scenario,
    required this.question,
    required this.choices,
    required this.takeaway,
    required this.source,
  });

  /// 全域唯一（catalog 驗證保證）。它是本機作答紀錄的鍵。
  final String id;

  /// 語意版本。題目改寫要 +1，舊答案自動失效需要重答，沿用電子書 quiz 的語意。
  final int revision;

  /// 情境（對話片段）。可省略——有些題目本身就是完整的問句。
  final String? scenario;
  final String question;
  final List<ChatQuizChoice> choices;

  /// 送出後顯示的一句總結。每題都要有。
  final String takeaway;

  final ChatQuizSource? source;

  ChatQuizQuestionType get type;

  /// 單選題保證恰好一個正解（parser 驗證）。
  ChatQuizChoice get correctChoice =>
      choices.firstWhere((choice) => choice.isCorrect);

  bool isCorrectChoice(String choiceId) =>
      choices.any((choice) => choice.id == choiceId && choice.isCorrect);

  ChatQuizChoice? findChoice(String choiceId) {
    for (final choice in choices) {
      if (choice.id == choiceId) return choice;
    }
    return null;
  }
}

/// 讀燈：判斷對方這一句是什麼狀態（綠／黃／紅）。
final class ChatQuizSignalReadQuestion extends ChatQuizQuestion {
  const ChatQuizSignalReadQuestion({
    required super.id,
    required super.revision,
    required super.scenario,
    required super.question,
    required super.choices,
    required super.takeaway,
    required super.source,
  });

  @override
  ChatQuizQuestionType get type => ChatQuizQuestionType.signalRead;
}

/// 選回覆：同一個局面，挑出該送出的那一句。
final class ChatQuizPickReplyQuestion extends ChatQuizQuestion {
  const ChatQuizPickReplyQuestion({
    required super.id,
    required super.revision,
    required super.scenario,
    required super.question,
    required super.choices,
    required super.takeaway,
    required super.source,
  });

  @override
  ChatQuizQuestionType get type => ChatQuizQuestionType.pickReply;
}

/// 找死亡點：一組候選項裡，選出「哪一個在扣分」。
///
/// 載體刻意通用——可以是多回合對話的某一句，也可以是照片清單、自介段落、
/// 一週行程裡的某一項。同一個認知動作（找出扣分點），不綁死在對話框裡，
/// 群 3「場外」的題目全靠它。
final class ChatQuizFindDeathPointQuestion extends ChatQuizQuestion {
  const ChatQuizFindDeathPointQuestion({
    required super.id,
    required super.revision,
    required super.scenario,
    required super.question,
    required super.choices,
    required super.takeaway,
    required super.source,
  });

  @override
  ChatQuizQuestionType get type => ChatQuizQuestionType.findDeathPoint;
}

/// 一關。
class ChatQuizLevel {
  const ChatQuizLevel({
    required this.id,
    required this.number,
    required this.title,
    required this.goal,
    required this.access,
    required this.passRatio,
    required this.questions,
  });

  final String id;

  /// 顯示用關號，例如 `1-1`。必須以所屬群的編號開頭（catalog 驗證）。
  final String number;
  final String title;

  /// 這一關只練一件事，關卡地圖用它當一行說明。
  final String goal;

  /// 內容宣告的權限。真相由不變式測試對照題目來源驗證。
  final EbookAccess access;

  /// 過關門檻（答對比例）。第 1 期全部是 0.8。
  final double passRatio;

  final List<ChatQuizQuestion> questions;

  int get questionCount => questions.length;

  /// 沒過不是失敗，只是「再跑一次」——文案在結果頁，這裡只回布林。
  bool isPassing(int correctCount) =>
      questions.isNotEmpty && correctCount / questions.length >= passRatio;

  /// 過關所需的最少答對題數。結果頁用它顯示「再對幾題就過」。
  int get requiredCorrectCount {
    for (var count = 0; count <= questions.length; count++) {
      if (isPassing(count)) return count;
    }
    return questions.length;
  }

  ChatQuizQuestion? findQuestion(String questionId) {
    for (final question in questions) {
      if (question.id == questionId) return question;
    }
    return null;
  }
}

/// 一個關卡群（報告頁的短標籤層級）。
class ChatQuizGroup {
  const ChatQuizGroup({
    required this.schemaVersion,
    required this.id,
    required this.number,
    required this.key,
    required this.title,
    required this.subtitle,
    required this.stageLabel,
    required this.levels,
  });

  final int schemaVersion;
  final String id;

  /// 群號，從 1 連號（catalog 驗證）。
  final int number;

  /// 對映報告頁短標籤的語意 key，例如 `signal`、`lifeline`。
  final String key;
  final String title;
  final String subtitle;

  /// 跟隨報告頁的階段短標籤（§11 決定 6）。
  final String stageLabel;

  final List<ChatQuizLevel> levels;

  ChatQuizLevel? findLevel(String levelId) {
    for (final level in levels) {
      if (level.id == levelId) return level;
    }
    return null;
  }
}

/// 所有關卡群。由 [ChatQuizCatalogRepository] 建立並驗證。
class ChatQuizCatalog {
  const ChatQuizCatalog({required this.groups});

  final List<ChatQuizGroup> groups;

  Iterable<ChatQuizLevel> get allLevels =>
      groups.expand((group) => group.levels);

  Iterable<ChatQuizQuestion> get allQuestions =>
      allLevels.expand((level) => level.questions);

  ChatQuizGroup? findGroup(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  ChatQuizLevel? findLevel(String levelId) {
    for (final group in groups) {
      final level = group.findLevel(levelId);
      if (level != null) return level;
    }
    return null;
  }

  ChatQuizGroup? groupOfLevel(String levelId) {
    for (final group in groups) {
      if (group.findLevel(levelId) != null) return group;
    }
    return null;
  }

  /// 群內線性解鎖用：同一群裡的前一關。第一關回 `null`。
  ///
  /// 刻意只看群內：群跟群之間全開，跨群串成一條線會讓第 2 群永遠鎖著。
  ChatQuizLevel? levelBefore(String levelId) {
    for (final group in groups) {
      final index = group.levels.indexWhere((level) => level.id == levelId);
      if (index > 0) return group.levels[index - 1];
      if (index == 0) return null;
    }
    return null;
  }

  ChatQuizQuestion? findQuestion(String questionId) {
    for (final question in allQuestions) {
      if (question.id == questionId) return question;
    }
    return null;
  }
}
