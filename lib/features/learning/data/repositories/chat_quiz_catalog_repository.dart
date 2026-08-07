// lib/features/learning/data/repositories/chat_quiz_catalog_repository.dart
//
// 從 bundled JSON 載入聊天測驗的關卡群。形狀刻意與
// `ebook_catalog_repository.dart` 一致：JSON 內容 + typed parser + fail closed。
//
// Parser 一律 fail closed：未知題型、缺必填欄位、單選題不是恰好一個正解、
// id 重複、passRatio 超界都直接拋 [QuizContentException]，而不是靜默跳過造成
// 「這一關玩完了但少了三題」。錯誤訊息帶 JSON 路徑，內容作者能直接定位。
//
// 這裡不判斷「使用者能不能玩這一關」。權限判斷在 `chat_quiz_access.dart`，
// 資料來源是訂閱狀態，不是內容檔。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../domain/models/chat_quiz.dart';
import '../../domain/models/ebook.dart';

/// 測驗內容資產無法安全解析時拋出。訊息是給開發者與測試看的可讀定位資訊，
/// 不含使用者資料。
class QuizContentException implements Exception {
  const QuizContentException(this.message);

  final String message;

  @override
  String toString() => 'QuizContentException: $message';
}

/// 目前支援的測驗群 JSON schema 版本。未知版本 fail closed。
const int kChatQuizSchemaVersion = 1;

class ChatQuizCatalogRepository {
  ChatQuizCatalogRepository({
    AssetBundle? bundle,
    List<String>? assetPaths,
  })  : _bundle = bundle,
        assetPaths = assetPaths ?? productionAssetPaths;

  /// production 內容資產。順序即關卡地圖的顯示順序。
  ///
  /// 不畫「即將推出」的佔位群（§11 決定 7）。擴充批 B–D 落地時依序在
  /// 這裡加 group_4～group_7。
  static const List<String> productionAssetPaths = <String>[
    'assets/learning/quizzes/group_1_signal.json',
    'assets/learning/quizzes/group_2_lifeline.json',
    'assets/learning/quizzes/group_3_offstage.json',
    'assets/learning/quizzes/group_4_ask_listen.json',
  ];

  final AssetBundle? _bundle;
  final List<String> assetPaths;

  AssetBundle get _resolvedBundle => _bundle ?? rootBundle;

  Future<ChatQuizCatalog> load() async {
    final groups = <ChatQuizGroup>[];
    for (final path in assetPaths) {
      final String raw;
      try {
        raw = await _resolvedBundle.loadString(path);
      } catch (error) {
        throw QuizContentException('無法讀取測驗資產 $path：$error');
      }
      groups.add(parseQuizGroup(raw, assetPath: path));
    }
    return buildChatQuizCatalog(groups);
  }
}

/// Catalog 層級不變量。
///
/// 只守跨檔案才看得到的結構性規則（id 全域唯一、群號連號）。「題數 6–8 題」、
/// 「1-1 不得取材第 5–7 冊」那類內容審稿不變量留給
/// `chat_quiz_content_invariants_test.dart`——寫進 runtime 的話，未來合法地
/// 多加一題就會讓整個學習頁掛掉，代價遠大於效益。
ChatQuizCatalog buildChatQuizCatalog(List<ChatQuizGroup> groups) {
  if (groups.isEmpty) {
    throw const QuizContentException('聊天測驗 catalog 不得為空');
  }

  final groupIds = <String>{};
  final groupKeys = <String>{};
  final levelIds = <String, String>{};
  final questionIds = <String, String>{};

  for (var index = 0; index < groups.length; index++) {
    final group = groups[index];
    if (!groupIds.add(group.id)) {
      throw QuizContentException('測驗群 id 重複：${group.id}');
    }
    if (!groupKeys.add(group.key)) {
      throw QuizContentException('測驗群 key 重複：${group.key}');
    }
    if (group.number != index + 1) {
      throw QuizContentException(
        '測驗群 ${group.id} 的 number=${group.number} 與它的順序 ${index + 1} '
        '不一致（群號必須從 1 連號）',
      );
    }

    for (final level in group.levels) {
      final levelOwner = levelIds[level.id];
      if (levelOwner != null) {
        throw QuizContentException(
          '關卡 id 全域重複：${level.id}（已出現於 $levelOwner）',
        );
      }
      levelIds[level.id] = group.id;

      for (final question in level.questions) {
        final questionOwner = questionIds[question.id];
        if (questionOwner != null) {
          throw QuizContentException(
            '題目 id 全域重複：${question.id}（已出現於 $questionOwner）',
          );
        }
        questionIds[question.id] = '${group.id}/${level.id}';
      }
    }
  }

  return ChatQuizCatalog(groups: List<ChatQuizGroup>.unmodifiable(groups));
}

ChatQuizGroup parseQuizGroup(String raw, {String assetPath = 'quiz.json'}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (error) {
    throw QuizContentException('$assetPath 不是合法 JSON：$error');
  }
  if (decoded is! Map<String, Object?>) {
    throw QuizContentException('$assetPath 最外層必須是 JSON object');
  }

  final path = assetPath;
  final schemaVersion = _requireInt(decoded, 'schemaVersion', path);
  if (schemaVersion != kChatQuizSchemaVersion) {
    throw QuizContentException(
      '$path 的 schemaVersion=$schemaVersion 不受支援'
      '（目前支援 $kChatQuizSchemaVersion）',
    );
  }

  final levelsRaw = _requireList(decoded, 'levels', path);
  if (levelsRaw.isEmpty) {
    throw QuizContentException('$path.levels 不得為空');
  }

  final number = _requireInt(decoded, 'number', path, min: 1);

  final levels = <ChatQuizLevel>[];
  final seenLevelIds = <String>{};
  for (var index = 0; index < levelsRaw.length; index++) {
    final levelPath = '$path.levels[$index]';
    final level = _parseLevel(
      _requireObjectAt(levelsRaw, index, '$path.levels'),
      levelPath,
    );
    if (!seenLevelIds.add(level.id)) {
      throw QuizContentException('$path.levels 內關卡 id 重複：${level.id}');
    }
    // 關號要能自我解釋：`1-2` 一定屬於第 1 群。錯位的話關卡地圖會顯示成
    // 別群的關，而使用者看到的順序就跟編號對不上。
    if (!level.number.startsWith('$number-')) {
      throw QuizContentException(
        '$levelPath.number=${level.number} 不屬於群 $number',
      );
    }
    levels.add(level);
  }

  return ChatQuizGroup(
    schemaVersion: schemaVersion,
    id: _requireString(decoded, 'id', path),
    number: number,
    key: _requireString(decoded, 'key', path),
    title: _requireString(decoded, 'title', path),
    subtitle: _requireString(decoded, 'subtitle', path),
    stageLabel: _requireString(decoded, 'stageLabel', path),
    levels: List<ChatQuizLevel>.unmodifiable(levels),
  );
}

ChatQuizLevel _parseLevel(Map<String, Object?> json, String path) {
  final questionsRaw = _requireList(json, 'questions', path);
  if (questionsRaw.isEmpty) {
    throw QuizContentException('$path.questions 不得為空');
  }

  final questions = <ChatQuizQuestion>[];
  final seenQuestionIds = <String>{};
  for (var index = 0; index < questionsRaw.length; index++) {
    final question = _parseQuestion(
      _requireObjectAt(questionsRaw, index, '$path.questions'),
      '$path.questions[$index]',
    );
    if (!seenQuestionIds.add(question.id)) {
      throw QuizContentException('$path.questions 內題目 id 重複：${question.id}');
    }
    questions.add(question);
  }

  final passRatio = _requireRatio(json, 'passRatio', path);

  return ChatQuizLevel(
    id: _requireString(json, 'id', path),
    number: _requireString(json, 'number', path),
    title: _requireString(json, 'title', path),
    goal: _requireString(json, 'goal', path),
    access: _requireEnum(json, 'access', path, _accessByName),
    passRatio: passRatio,
    questions: List<ChatQuizQuestion>.unmodifiable(questions),
  );
}

ChatQuizQuestion _parseQuestion(Map<String, Object?> json, String path) {
  final type = _requireEnum(json, 'type', path, _questionTypeByName);
  final id = _requireString(json, 'id', path);
  final revision = _requireInt(json, 'revision', path, min: 1);
  final scenario = _optionalString(json, 'scenario', path);
  final question = _requireString(json, 'question', path);
  final takeaway = _requireString(json, 'takeaway', path);
  final source = _parseSource(json, path);
  final choices = _parseChoices(json, path);

  return switch (type) {
    ChatQuizQuestionType.signalRead => ChatQuizSignalReadQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: question,
        choices: choices,
        takeaway: takeaway,
        source: source,
      ),
    ChatQuizQuestionType.pickReply => ChatQuizPickReplyQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: question,
        choices: choices,
        takeaway: takeaway,
        source: source,
      ),
    ChatQuizQuestionType.findDeathPoint => ChatQuizFindDeathPointQuestion(
        id: id,
        revision: revision,
        scenario: scenario,
        question: question,
        choices: choices,
        takeaway: takeaway,
        source: source,
      ),
  };
}

/// 選項。第 1 期兩種題型都是單選，所以正解必須恰好一個。
List<ChatQuizChoice> _parseChoices(Map<String, Object?> json, String path) {
  final choicesRaw = _requireList(json, 'choices', path);
  if (choicesRaw.length < 2) {
    throw QuizContentException('$path.choices 至少要兩個選項');
  }

  final choices = <ChatQuizChoice>[];
  final seen = <String>{};
  for (var index = 0; index < choicesRaw.length; index++) {
    final choicePath = '$path.choices[$index]';
    final choice = _requireObjectAt(choicesRaw, index, '$path.choices');
    final choiceId = _requireString(choice, 'id', choicePath);
    if (!seen.add(choiceId)) {
      throw QuizContentException('$path.choices 內 id 重複：$choiceId');
    }
    choices.add(
      ChatQuizChoice(
        id: choiceId,
        text: _requireString(choice, 'text', choicePath),
        isCorrect: _requireBool(choice, 'correct', choicePath),
        feedback: _requireString(choice, 'feedback', choicePath),
      ),
    );
  }

  final correctCount = choices.where((choice) => choice.isCorrect).length;
  if (correctCount != 1) {
    throw QuizContentException(
      '$path 是單選題但有 $correctCount 個正解（必須恰好一個）',
    );
  }

  return List<ChatQuizChoice>.unmodifiable(choices);
}

/// 深連目標。整個欄位省略是合法的（那一題就不顯示「讀原理」按鈕）；
/// 但只要出現，兩個欄位都必須齊全——半套的深連會在 UI 上變成點了沒反應的按鈕。
ChatQuizSource? _parseSource(Map<String, Object?> json, String path) {
  final value = json['source'];
  if (value == null) return null;
  if (value is! Map<String, Object?>) {
    throw QuizContentException('$path.source 必須是 JSON object');
  }
  final sourcePath = '$path.source';
  return ChatQuizSource(
    bookId: _requireString(value, 'bookId', sourcePath),
    chapterId: _requireString(value, 'chapterId', sourcePath),
  );
}

// ---------------------------------------------------------------------------
// JSON 讀取小工具。全部帶 path，讓錯誤訊息能直接定位到出錯的欄位。
// ---------------------------------------------------------------------------

const Map<String, ChatQuizQuestionType> _questionTypeByName =
    <String, ChatQuizQuestionType>{
  'signalRead': ChatQuizQuestionType.signalRead,
  'pickReply': ChatQuizQuestionType.pickReply,
  'findDeathPoint': ChatQuizQuestionType.findDeathPoint,
};

const Map<String, EbookAccess> _accessByName = <String, EbookAccess>{
  'free': EbookAccess.free,
  'premium': EbookAccess.premium,
  'essential': EbookAccess.essential,
};

Map<String, Object?> _requireObjectAt(
  List<Object?> list,
  int index,
  String path,
) {
  final value = list[index];
  if (value is! Map<String, Object?>) {
    throw QuizContentException('$path[$index] 必須是 JSON object');
  }
  return value;
}

String _requireString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw QuizContentException('$path.$key 必須是非空字串');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw QuizContentException('$path.$key 必須是字串');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : value;
}

int _requireInt(
  Map<String, Object?> json,
  String key,
  String path, {
  int? min,
}) {
  final value = json[key];
  if (value is! int) {
    throw QuizContentException('$path.$key 必須是整數');
  }
  if (min != null && value < min) {
    throw QuizContentException('$path.$key 必須 >= $min（實際 $value）');
  }
  return value;
}

/// 比例欄位。JSON 寫 `1` 會被 jsonDecode 解成 int，所以兩種都收。
double _requireRatio(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num) {
    throw QuizContentException('$path.$key 必須是數字');
  }
  final ratio = value.toDouble();
  if (ratio <= 0 || ratio > 1) {
    throw QuizContentException(
      '$path.$key 必須大於 0 且不超過 1（實際 $ratio）',
    );
  }
  return ratio;
}

bool _requireBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) {
    throw QuizContentException('$path.$key 必須是布林值');
  }
  return value;
}

List<Object?> _requireList(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List) {
    throw QuizContentException('$path.$key 必須是陣列');
  }
  return value;
}

T _requireEnum<T>(
  Map<String, Object?> json,
  String key,
  String path,
  Map<String, T> byName,
) {
  final raw = _requireString(json, key, path);
  final value = byName[raw];
  if (value == null) {
    throw QuizContentException(
      '$path.$key 的值「$raw」不受支援（可用：${byName.keys.join(' / ')}）',
    );
  }
  return value;
}
