// test/unit/features/learning/chat_quiz_copy_lint_test.dart
//
// 真實 bundled 測驗內容的文案檢查。這裡守的是「第一次讀的人看得懂」，
// 規則出自 `docs/plans/2026-10-01-chat-quiz-copy-readability-spec.md`
// §3、§4.5。內容契約（題數、正解、安全底線）仍然歸
// `chat_quiz_content_invariants_test.dart` 管，這支只看字面。
//
// 規則分兩種開法：
//   - L1 英文白名單、L2 禁用字串：第 1 批起全庫生效。
//   - L3 符號、L4 字數：地圖的副標和目標第 1 批已全部重寫，所以全部生效；
//     題目要等第 2、3 批逐關重寫完，再加進來。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';

import '../../../helpers/chat_quiz_test_content.dart';

/// L1：允許出現的英文單字（規格 §3 第 10 條）。
///
/// Hey、all、pass 只出現在 q-7-2-05-b 的對話原句裡，那是她傳的字，照原樣保留。
/// Bio 刻意不在清單裡：一律寫「自介」。
const _allowedEnglishWords = <String>{
  'Tinder',
  'IG',
  'LINE',
  'Google',
  'Excel',
  'app',
  'XD',
  'NG',
  'tone',
  'Hey',
  'all',
  'pass',
};

/// L2：禁用字串。key 是禁用的字，value 是為什麼。
const _bannedPhrases = <String, String>{
  '第九部': '外部講義的章節編號，玩家看不到那份講義',
  '死因四': '教材只有三個死因',
  '自我復格': '錯字，教材寫「自我覆格」',
  '停損': '「結束這段」寫「收手」，「她冷時少說一點」寫「止損」（規格 §2.4）',
};

/// L3：地圖文字不用的符號（規格 §3 第 6 條）。
const _bannedSymbols = <String>['——', '＝', '→', '×'];

/// L4：關卡目標的字數上限（不算換行）。
const _maxGoalLength = 70;

final _englishWord = RegExp('[A-Za-z]{2,}');

/// 一段使用者看得到的文字，以及它在題庫裡的位置。
typedef _Segment = ({String where, String text});

Iterable<_Segment> _mapSegments(ChatQuizCatalog catalog) sync* {
  for (final group in catalog.groups) {
    yield (where: '${group.id}.title', text: group.title);
    yield (where: '${group.id}.subtitle', text: group.subtitle);
    yield (where: '${group.id}.stageLabel', text: group.stageLabel);
    for (final level in group.levels) {
      yield (where: '${level.id}.title', text: level.title);
      yield (where: '${level.id}.goal', text: level.goal);
    }
  }
}

Iterable<_Segment> _questionSegments(ChatQuizCatalog catalog) sync* {
  for (final question in catalog.allQuestions) {
    final scenario = question.scenario;
    if (scenario != null) {
      yield (where: '${question.id}.scenario', text: scenario);
    }
    yield (where: '${question.id}.question', text: question.question);
    for (final choice in question.choices) {
      yield (where: '${choice.id}.text', text: choice.text);
      yield (where: '${choice.id}.feedback', text: choice.feedback);
    }
    yield (where: '${question.id}.takeaway', text: question.takeaway);
  }
}

void main() {
  late ChatQuizCatalog catalog;
  late List<_Segment> allSegments;

  setUpAll(() async {
    catalog = await loadProductionChatQuizCatalog();
    allSegments = [..._mapSegments(catalog), ..._questionSegments(catalog)];
  });

  test('L1 英文單字只能是白名單裡的字', () {
    final offenders = <String>[];
    for (final segment in allSegments) {
      for (final match in _englishWord.allMatches(segment.text)) {
        final word = match.group(0)!;
        if (!_allowedEnglishWords.contains(word)) {
          offenders.add('${segment.where}：$word');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '英文要改成中文（例如 Bio 寫「自介」）；'
          '真的要保留的，先加進白名單並寫明理由',
    );
  });

  test('L2 沒有禁用字串', () {
    final offenders = <String>[];
    for (final segment in allSegments) {
      for (final entry in _bannedPhrases.entries) {
        if (segment.text.contains(entry.key)) {
          offenders.add('${segment.where}：「${entry.key}」${entry.value}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('L3 地圖的副標和關卡目標不用破折號、等號、箭頭、乘號', () {
    final offenders = <String>[];
    for (final group in catalog.groups) {
      final targets = <_Segment>[
        (where: '${group.id}.subtitle', text: group.subtitle),
        for (final level in group.levels)
          (where: '${level.id}.goal', text: level.goal),
      ];
      for (final segment in targets) {
        for (final symbol in _bannedSymbols) {
          if (segment.text.contains(symbol)) {
            offenders.add('${segment.where}：$symbol');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '符號要讀者自己補意思，改成完整的句子',
    );
  });

  test('L4 關卡目標不超過 $_maxGoalLength 字', () {
    for (final level in catalog.allLevels) {
      final length = level.goal.replaceAll('\n', '').runes.length;
      expect(
        length,
        lessThanOrEqualTo(_maxGoalLength),
        reason: '${level.id} 的目標有 $length 字，地圖上會太長',
      );
    }
  });
}
