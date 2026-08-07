// test/unit/features/learning/chat_quiz_catalog_test.dart
//
// 聊天測驗 JSON parser 與 catalog 的行為測試。重點只有一個：fail closed。
//
// 不認識的題型、缺必填欄位、單選題不是恰好一個正解、id 重複、passRatio 超界
// 都必須拋 [QuizContentException]，而不是靜默跳過造成「玩完了但少幾題」。
// 錯誤訊息一律要帶 JSON 路徑，讓內容作者能直接定位。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';

import '../../../helpers/ebook_test_content.dart';

Map<String, Object?> _choice({
  required String id,
  required bool correct,
  Object? feedback = '回饋。',
  String text = '選項文字',
}) {
  return <String, Object?>{
    'id': id,
    'text': text,
    'correct': correct,
    if (feedback != null) 'feedback': feedback,
  };
}

Map<String, Object?> _question({
  String id = 'q-1-1-01',
  String type = 'signalRead',
  int revision = 1,
  int choiceCount = 3,
  int correctCount = 1,
  Object? feedback = '回饋。',
  Map<String, Object?>? source,
  bool includeSource = true,
}) {
  return <String, Object?>{
    'id': id,
    'type': type,
    'revision': revision,
    'scenario': '她：今天上班快累死',
    'question': '這句是什麼燈？',
    'choices': [
      for (var index = 0; index < choiceCount; index++)
        _choice(
          id: '$id-${String.fromCharCode(97 + index)}',
          correct: index < correctCount,
          feedback: feedback,
        ),
    ],
    'takeaway': '情緒是開口，事實是死路。',
    if (includeSource)
      'source': source ??
          <String, Object?>{
            'bookId': 'ebook-2-conversation',
            'chapterId': 'ebook-2-chapter-1',
          },
  };
}

Map<String, Object?> _level({
  String id = 'quiz-level-1-1',
  String number = '1-1',
  String access = 'free',
  Object passRatio = 0.8,
  List<Map<String, Object?>>? questions,
}) {
  return <String, Object?>{
    'id': id,
    'number': number,
    'title': '她現在是哪一種',
    'goal': '把「我該說什麼」換成「她現在是哪一種狀態」。',
    'access': access,
    'passRatio': passRatio,
    'questions': questions ?? [_question()],
  };
}

Map<String, Object?> _group({
  String id = 'quiz-group-1',
  int number = 1,
  String key = 'signal',
  int schemaVersion = kChatQuizSchemaVersion,
  List<Map<String, Object?>>? levels,
}) {
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'number': number,
    'key': key,
    'title': '讀燈',
    'subtitle': '她現在是什麼狀態',
    'stageLabel': '破冰',
    'levels': levels ?? [_level()],
  };
}

ChatQuizGroup _parse(Map<String, Object?> json) =>
    parseQuizGroup(jsonEncode(json), assetPath: 'test_quiz.json');

ChatQuizCatalog _catalog(List<Map<String, Object?>> groups) =>
    buildChatQuizCatalog([for (final group in groups) _parse(group)]);

void main() {
  group('題型', () {
    test('兩種合法題型都解析成對應的 sealed 子型別', () {
      final signal = _parse(
        _group(levels: [
          _level(questions: [_question(type: 'signalRead')]),
        ]),
      );
      expect(
        signal.levels.single.questions.single,
        isA<ChatQuizSignalReadQuestion>(),
      );
      expect(
        signal.levels.single.questions.single.type,
        ChatQuizQuestionType.signalRead,
      );

      final reply = _parse(
        _group(levels: [
          _level(questions: [_question(type: 'pickReply')]),
        ]),
      );
      expect(
        reply.levels.single.questions.single,
        isA<ChatQuizPickReplyQuestion>(),
      );
    });

    test('不認識的題型直接報錯，不靜默跳過', () {
      expect(
        () => _parse(
          _group(levels: [
            _level(questions: [_question(type: 'dragOrder')]),
          ]),
        ),
        throwsA(
          isA<QuizContentException>().having(
            (error) => error.message,
            'message',
            allOf(contains('dragOrder'), contains('questions[0]')),
          ),
        ),
      );
    });

    test('題型是封閉清單，型別層擋掉自由輸入答案', () {
      // 這條守鐵律 7：正解永遠是一個選擇，不會是某個特定字串。
      // findDeathPoint 於擴充批 A 引入、doseCheck 於批 C 引入；gearShift
      // 屬批 D，落地時在這裡補。
      expect(ChatQuizQuestionType.values, <ChatQuizQuestionType>[
        ChatQuizQuestionType.signalRead,
        ChatQuizQuestionType.pickReply,
        ChatQuizQuestionType.findDeathPoint,
        ChatQuizQuestionType.doseCheck,
      ]);
    });
  });

  group('選項', () {
    test('單選題沒有恰好一個正解就報錯', () {
      expect(
        () => _parse(
          _group(levels: [
            _level(questions: [_question(correctCount: 2)]),
          ]),
        ),
        throwsA(isA<QuizContentException>()),
      );
      expect(
        () => _parse(
          _group(levels: [
            _level(questions: [_question(correctCount: 0)]),
          ]),
        ),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('每個選項都必須有 feedback', () {
      expect(
        () => _parse(
          _group(levels: [
            _level(questions: [_question(feedback: null)]),
          ]),
        ),
        throwsA(
          isA<QuizContentException>().having(
            (error) => error.message,
            'message',
            contains('feedback'),
          ),
        ),
      );
      expect(
        () => _parse(
          _group(levels: [
            _level(questions: [_question(feedback: '   ')]),
          ]),
        ),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('選項少於兩個報錯', () {
      expect(
        () => _parse(
          _group(levels: [
            _level(questions: [_question(choiceCount: 1)]),
          ]),
        ),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('同一題選項 id 重複報錯', () {
      final question = _question();
      (question['choices']! as List)[1] =
          _choice(id: 'q-1-1-01-a', correct: false);
      expect(
        () => _parse(_group(levels: [_level(questions: [question])])),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('正解可以由 correctChoice 取得，其餘選項為錯', () {
      final parsed = _parse(_group());
      final question = parsed.levels.single.questions.single;
      expect(question.correctChoice.id, 'q-1-1-01-a');
      expect(question.isCorrectChoice('q-1-1-01-a'), isTrue);
      expect(question.isCorrectChoice('q-1-1-01-b'), isFalse);
    });
  });

  group('必填欄位', () {
    test('缺 takeaway 報錯，訊息帶 JSON 路徑', () {
      final question = _question()..remove('takeaway');
      expect(
        () => _parse(_group(levels: [_level(questions: [question])])),
        throwsA(
          isA<QuizContentException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('test_quiz.json'),
              contains('levels[0].questions[0].takeaway'),
            ),
          ),
        ),
      );
    });

    test('scenario 可省略', () {
      final question = _question()..remove('scenario');
      final parsed = _parse(_group(levels: [_level(questions: [question])]));
      expect(parsed.levels.single.questions.single.scenario, isNull);
    });

    test('schemaVersion 不符直接報錯', () {
      expect(
        () => _parse(_group(schemaVersion: 2)),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('關卡不得沒有題目', () {
      expect(
        () => _parse(_group(levels: [_level(questions: const [])])),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('passRatio 必須落在 0 與 1 之間', () {
      expect(
        () => _parse(_group(levels: [_level(passRatio: 0)])),
        throwsA(isA<QuizContentException>()),
      );
      expect(
        () => _parse(_group(levels: [_level(passRatio: 1.2)])),
        throwsA(isA<QuizContentException>()),
      );
      expect(_parse(_group(levels: [_level(passRatio: 1)])).levels.single.passRatio, 1.0);
    });

    test('關卡編號必須以群編號開頭', () {
      expect(
        () => _parse(_group(number: 1, levels: [_level(number: '2-1')])),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('access 解析成 EbookAccess，未知值報錯', () {
      expect(
        _parse(_group(levels: [_level(access: 'essential')])).levels.single.access,
        EbookAccess.essential,
      );
      expect(
        () => _parse(_group(levels: [_level(access: 'starter')])),
        throwsA(isA<QuizContentException>()),
      );
    });
  });

  group('深連 source', () {
    test('沒有 source 是合法的', () {
      final parsed = _parse(
        _group(levels: [
          _level(questions: [_question(includeSource: false)]),
        ]),
      );
      expect(parsed.levels.single.questions.single.source, isNull);
    });

    test('有 source 就必須同時有 bookId 與 chapterId', () {
      expect(
        () => _parse(
          _group(levels: [
            _level(
              questions: [
                _question(source: const {'bookId': 'ebook-2-conversation'}),
              ],
            ),
          ]),
        ),
        throwsA(
          isA<QuizContentException>().having(
            (error) => error.message,
            'message',
            contains('chapterId'),
          ),
        ),
      );
    });
  });

  group('catalog 不變量', () {
    test('題目 id 在整份 catalog 全域唯一', () {
      expect(
        () => _catalog([
          _group(
            levels: [
              _level(questions: [_question(id: 'q-dup')]),
            ],
          ),
          _group(
            id: 'quiz-group-2',
            number: 2,
            key: 'lifeline',
            levels: [
              _level(
                id: 'quiz-level-2-1',
                number: '2-1',
                questions: [_question(id: 'q-dup')],
              ),
            ],
          ),
        ]),
        throwsA(
          isA<QuizContentException>().having(
            (error) => error.message,
            'message',
            contains('q-dup'),
          ),
        ),
      );
    });

    test('關卡 id 全域唯一', () {
      expect(
        () => _catalog([
          _group(),
          _group(
            id: 'quiz-group-2',
            number: 2,
            key: 'lifeline',
            levels: [
              _level(number: '2-1', questions: [_question(id: 'q-2-1-01')]),
            ],
          ),
        ]),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('群編號必須從 1 連號', () {
      expect(
        () => _catalog([_group(number: 2)]),
        throwsA(isA<QuizContentException>()),
      );
    });

    test('catalog 不得為空', () {
      expect(() => buildChatQuizCatalog(const []),
          throwsA(isA<QuizContentException>()));
    });

    test('合法 catalog 可依 id 查群、查關、查前一關', () {
      final catalog = _catalog([
        _group(
          levels: [
            _level(questions: [_question()]),
            _level(
              id: 'quiz-level-1-2',
              number: '1-2',
              access: 'premium',
              questions: [_question(id: 'q-1-2-01')],
            ),
          ],
        ),
      ]);

      expect(catalog.groups, hasLength(1));
      expect(catalog.findLevel('quiz-level-1-2')?.number, '1-2');
      expect(catalog.groupOfLevel('quiz-level-1-2')?.key, 'signal');
      expect(catalog.levelBefore('quiz-level-1-2')?.id, 'quiz-level-1-1');
      expect(catalog.levelBefore('quiz-level-1-1'), isNull);
      expect(catalog.findQuestion('q-1-2-01')?.id, 'q-1-2-01');
      expect(catalog.allQuestions, hasLength(2));
    });
  });

  group('repository', () {
    test('從 bundle 依序載入多個群', () async {
      final repository = ChatQuizCatalogRepository(
        bundle: MapAssetBundle({
          'a.json': jsonEncode(_group()),
          'b.json': jsonEncode(
            _group(
              id: 'quiz-group-2',
              number: 2,
              key: 'lifeline',
              levels: [
                _level(
                  id: 'quiz-level-2-1',
                  number: '2-1',
                  access: 'premium',
                  questions: [_question(id: 'q-2-1-01')],
                ),
              ],
            ),
          ),
        }),
        assetPaths: const ['a.json', 'b.json'],
      );

      final catalog = await repository.load();
      expect(catalog.groups.map((group) => group.key), ['signal', 'lifeline']);
    });

    test('讀不到資產時拋 QuizContentException 而不是原始錯誤', () {
      final repository = ChatQuizCatalogRepository(
        bundle: MapAssetBundle(const {}),
        assetPaths: const ['missing.json'],
      );
      expect(repository.load(), throwsA(isA<QuizContentException>()));
    });
  });
}
