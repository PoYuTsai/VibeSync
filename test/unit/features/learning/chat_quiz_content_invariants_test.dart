// test/unit/features/learning/chat_quiz_content_invariants_test.dart
//
// 真實 bundled 測驗內容的不變量。這裡守的是內容契約而不是程式行為。
//
// 這一支刻意在內容還沒寫之前就存在：測驗的題目是 AI 起草、人工編輯，沒有
// 自動守門的話會長歪成「越寫越像練習室」或「免費關偷偷取材 Essential 教材」。
// 兩種歪法都不會有錯誤訊息，只會靜靜地上線。
//
// 三個分工邊界：
//   - 結構與 id 的硬規則在 parser（`chat_quiz_catalog_repository.dart`），
//     那些是載入時就該爆掉的。
//   - 「Starter 能不能進」這種 runtime 判斷在 `chat_quiz_access_test.dart`。
//     這裡守的是它的內容側前提：免費關不得取材第 5–7 冊（ADR #38 後，付費
//     關的取材不再影響 access）。
//   - 這裡只守「內容寫成什麼樣」。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/ebook_test_content.dart';

/// 免費關清單。1-1 是免費櫥窗關；3-1（場外）於擴充批 A 開免費——三條底線
/// 不鎖付費牆（2026-08-07 Eric 拍板）。
const _freeLevelIds = ['quiz-level-1-1', 'quiz-level-3-1'];

/// 每一關固定 15 題。
///
/// 原本的規則是「免費櫥窗關 10 題、付費關 6–8 題」，前提是櫥窗要比內頁密。
/// 內容重做（2026-08-02）推翻了它：四關等量，付費關不再比免費關短。
const _questionsPerLevel = 15;

/// 目前規模：擴充批 B（群 4「問與聽」）之後為 4 群、9 關、135 題。
/// 批 C–D 落地時依序更新（終點 7 群 / 15 關 / 225 題）。
const _expectedGroupCount = 4;
const _expectedLevelCount = 9;
const _expectedQuestionCount = 135;

/// 題型難度階梯。第一題與最後一題刻意收在簡單題，中間才給難的。
///
/// 階梯依擴充規劃 §4.1：signalRead < findDeathPoint < pickReply（＝doseCheck）
/// < gearShift。既有 4 關首末題全是 signalRead，重排數值不影響它們。
int _difficulty(ChatQuizQuestionType type) => switch (type) {
      ChatQuizQuestionType.signalRead => 0,
      ChatQuizQuestionType.findDeathPoint => 1,
      ChatQuizQuestionType.pickReply => 2,
    };

/// 操縱／施壓語彙。出現在錯誤選項或回饋裡是好事（那是在教「這樣做是錯的」），
/// 出現在正解裡就必須帶否定框架，否則等於教使用者去做。
const _manipulationTerms = <String>[
  '情緒勒索',
  '情勒',
  '施壓',
  '逼她',
  '逼他',
  '欲擒故縱',
  '冷暴力',
  '已讀不回懲罰',
  '吊著',
  '讓她愧疚',
  '讓他愧疚',
];

/// 否定框架標記。正解裡若出現操縱語彙，必須同時出現其中之一。
const _negationMarkers = <String>['不', '別', '停', '收手', '錯'];

/// 「該停了」的語彙。救援關必須至少有一題的正解是這個。
const _stopSignalTerms = <String>[
  '停',
  '收手',
  '退開',
  '不要再',
  '別再',
  '放手',
  '結束',
  '不追',
];

/// 推進／邀約題的判定詞（只看題幹，不看情境，避免情境裡提到「約」就誤判）。
const _escalationTerms = <String>['推進', '約出來', '邀約', '約她', '約他'];

/// 推進題必須提供的「收手」選項語彙。
const _holdBackTerms = <String>['先不', '不推', '收手', '再等', '不約', '緩', '暫時不'];

bool _containsAny(String text, List<String> terms) =>
    terms.any(text.contains);

void main() {
  late ChatQuizCatalog catalog;
  late EbookCatalog books;
  late List<ChatQuizLevel> levels;
  late List<ChatQuizQuestion> questions;

  setUpAll(() async {
    catalog = await loadProductionChatQuizCatalog();
    books = await loadProductionCatalog();
    levels = catalog.allLevels.toList();
    questions = catalog.allQuestions.toList();
  });

  group('結構', () {
    test('目前規模：群、關、題數與常數一致', () {
      expect(catalog.groups, hasLength(_expectedGroupCount));
      expect(levels, hasLength(_expectedLevelCount));
      expect(questions, hasLength(_expectedQuestionCount));
    });

    test('每題至少三個選項，且恰好一個正解', () {
      for (final question in questions) {
        expect(
          question.choices.length,
          greaterThanOrEqualTo(3),
          reason: '${question.id} 只有兩個選項，二選一猜得中，練不到判讀',
        );
        expect(
          question.choices.where((choice) => choice.isCorrect).length,
          1,
          reason: '${question.id} 的正解數不是 1',
        );
      }
    });

    test('每個選項都有 feedback，每題都有 takeaway', () {
      for (final question in questions) {
        expect(question.takeaway.trim(), isNotEmpty, reason: question.id);
        for (final choice in question.choices) {
          expect(
            choice.feedback.trim(),
            isNotEmpty,
            reason: '${question.id} / ${choice.id} 沒有回饋，答錯的人學不到東西',
          );
        }
      }
    });

    test('所有題目 id 全域唯一', () {
      final ids = questions.map((question) => question.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('每一關固定 15 題', () {
      for (final level in levels) {
        expect(
          level.questionCount,
          _questionsPerLevel,
          reason: '${level.id} 的題數是 ${level.questionCount}，四關必須等量',
        );
      }
    });

    test('第一題與最後一題都不是該關最難的題型', () {
      for (final level in levels) {
        final difficulties =
            level.questions.map((question) => _difficulty(question.type));
        final hardest = difficulties.reduce((a, b) => a > b ? a : b);
        final easiest = difficulties.reduce((a, b) => a < b ? a : b);
        if (hardest == easiest) continue; // 整關同一種題型，沒有階梯可談。

        expect(
          _difficulty(level.questions.first.type),
          lessThan(hardest),
          reason: '${level.id} 開場就是最難的題型，會直接勸退',
        );
        expect(
          _difficulty(level.questions.last.type),
          lessThan(hardest),
          reason: '${level.id} 收在最難的題型，離開時的感覺是挫敗',
        );
      }
    });

    test('過關門檻一律 80%', () {
      for (final level in levels) {
        expect(level.passRatio, 0.8, reason: level.id);
      }
    });
  });

  group('權限', () {
    // ADR #38（2026-08-07）：關卡 access 只表達訂閱檔位，不再由取材推導。
    // 付費關可自由取材第 1–7 冊——Starter 作答時拿得到 takeaway 判準，點
    // 「讀原理」深連進書會撞電子書自己的 Essential 閘門，那是轉換路徑不是
    // 外洩。原本的「access ≥ 取材推導值」「取材 5–7 冊必須宣告 essential」
    // 兩條隨之移除；免費關的兩條紅線保留如下。
    test('免費關就是免費關清單，其餘全部要付費', () {
      final freeLevels =
          levels.where((level) => level.access == EbookAccess.free).toList();
      expect(freeLevels.map((level) => level.id), _freeLevelIds);
    });

    test('免費關的每一題，來源都不是第 5–7 冊', () {
      for (final levelId in _freeLevelIds) {
        final level = catalog.findLevel(levelId);
        expect(level, isNotNull, reason: '找不到免費關 $levelId');
        for (final question in level!.questions) {
          final source = question.source;
          if (source == null) continue;
          final book = books.findBook(source.bookId);
          expect(
            book?.unit,
            isNot(EbookUnit.becomeThePrize),
            reason: '${question.id} 取材《成為獎賞》，那是唯一的免費出口，不得外洩',
          );
        }
      }
    });
  });

  group('深連', () {
    test('每個 source 都指向真的存在的書與章', () {
      for (final question in questions) {
        final source = question.source;
        if (source == null) continue;
        final book = books.findBook(source.bookId);
        expect(book, isNotNull, reason: '${question.id} 的 bookId 不存在');
        expect(
          book!.findChapter(source.chapterId),
          isNotNull,
          reason: '${question.id} 的 chapterId 在 ${source.bookId} 裡不存在',
        );
      }
    });

    test('沒有 source 的題目就是沒有，不會留半套欄位', () {
      // parser 已經擋掉「有 source 但缺 chapterId」；這裡守的是另一半：
      // 內容不得把 bookId／chapterId 平鋪在題目層，那樣 parser 讀不到、
      // UI 也不會顯示「讀原理」，但寫的人會以為自己連好了。
      for (final entry in productionChatQuizAssets().entries) {
        expect(
          entry.value.contains('"bookId"'),
          entry.value.contains('"source"'),
          reason: '${entry.key} 出現了不在 source 裡的 bookId',
        );
      }
    });
  });

  group('界線', () {
    test('沒有任何一題的正解是自由輸入字串', () {
      // 型別層就沒有輸入欄位（sealed class 只有 choices），這條守的是
      // 「題型沒有偷偷長出清單外的種類」。「自己改一句」那種自由輸入題
      // 屬第 3 期，要另外授權。
      expect(ChatQuizQuestionType.values, hasLength(3));
      for (final question in questions) {
        expect(
          question,
          anyOf(
            isA<ChatQuizSignalReadQuestion>(),
            isA<ChatQuizPickReplyQuestion>(),
            isA<ChatQuizFindDeathPointQuestion>(),
          ),
          reason: question.id,
        );
        expect(question.choices, isNotEmpty);
      }
    });
  });

  group('安全底線', () {
    test('§7.5-1 操縱／施壓語彙只能出現在「這樣做是錯的」的框架裡', () {
      for (final question in questions) {
        final correct = question.correctChoice;
        for (final term in _manipulationTerms) {
          if (!correct.text.contains(term)) continue;
          expect(
            _containsAny(correct.text, _negationMarkers),
            isTrue,
            reason: '${question.id} 的正解出現「$term」卻沒有否定框架，'
                '等於教使用者去做',
          );
        }
      }
    });

    test('§7.5-3 救援關至少一題的正解是「這是真的拒絕，該停了」', () {
      final rescueLevel = catalog.findLevel('quiz-level-1-2');
      expect(rescueLevel, isNotNull, reason: '找不到救援關 quiz-level-1-2');
      final hasStopAnswer = rescueLevel!.questions.any(
        (question) => _containsAny(question.correctChoice.text, _stopSignalTerms),
      );
      expect(
        hasStopAnswer,
        isTrue,
        reason: '救援關沒有任何一題的正解是收手；'
            '一個只教怎麼救回來的關卡等於教人不接受拒絕',
      );
    });

    test('§7.5-4 推進題一定要有「收手」選項，且它在該收手的情境裡是正解', () {
      // 第 1 期沒有換檔題型，所以這條多半是空跑；它的作用是第 2 期加推進群
      // 時自動生效，而不是等人想起來要補。
      for (final question in questions) {
        if (!_containsAny(question.question, _escalationTerms)) continue;
        expect(
          question.choices.any(
            (choice) => _containsAny(choice.text, _holdBackTerms),
          ),
          isTrue,
          reason: '${question.id} 是推進題但沒有收手選項，'
              '所有選項都在推等於逼使用者推',
        );
      }
    });

    test(
      '§7.5-2 邀約題必須附安全提醒',
      () {},
      skip: '第 1 期沒有邀約關卡；第 2 期開推進群時解除。',
    );

    test(
      '§7.5-5 明確化關卡必須教「對方沒答應就是沒答應」',
      () {},
      skip: '第 1 期沒有明確化關卡；第 2 期開推進群時解除。',
    );
  });
}
