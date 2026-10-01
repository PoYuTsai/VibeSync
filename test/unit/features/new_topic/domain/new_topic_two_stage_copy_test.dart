import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/domain/new_topic_two_stage_copy.dart';

typedef _A = NewTopicTwoStageAnswers;

NewTopicCoachTip? _tip(String situation,
        {String? duration, String? stop, String? engagement}) =>
    NewTopicTwoStageCopy.coachTip(_A(
        situation: situation,
        coldDuration: duration,
        coldStop: stop,
        engagement: engagement));

void main() {
  group('選項', () {
    test('第一問順序與 value 照規格', () {
      expect(NewTopicTwoStageCopy.situationOptions.map((o) => o.value),
          ['went_cold', 'stuck', 'after_date', 'warm_up']);
    });

    test('素材順序固定、剛約完會改舊話題標籤與輸入框標題', () {
      expect(NewTopicTwoStageCopy.materialOptions(null).map((o) => o.value),
          ['past_topic', 'trigger', 'my_story', 'inside_joke', 'none']);
      expect(
          NewTopicTwoStageCopy.materialOptions('stuck').first.label, '之前聊過的事');
      expect(NewTopicTwoStageCopy.materialOptions('after_date').first.label,
          '約會時聊到的事');
      expect(NewTopicTwoStageCopy.materialInputTitle('past_topic', 'stuck'),
          '她之前提過什麼？');
      expect(
          NewTopicTwoStageCopy.materialInputTitle('past_topic', 'after_date'),
          '約會時聊到什麼？');
      expect(NewTopicTwoStageCopy.materialInputTitle('none', null), isNull);
      expect(NewTopicTwoStageCopy.materialInputTitle(null, null), isNull);
    });

    test('投入程度追問：剛約完會用約會版標題與選項', () {
      expect(NewTopicTwoStageCopy.engagementTitle('after_date'), '約完之後她的反應？');
      expect(NewTopicTwoStageCopy.engagementTitle('warm_up'), '她最近回你的樣子？');
      expect(NewTopicTwoStageCopy.engagementOptions('after_date').first.label,
          '主動傳訊息或說開心');
      expect(NewTopicTwoStageCopy.engagementOptions('stuck').last.label,
          '常只回哈哈、嗯');
    });
  });

  group('教練提醒', () {
    test('沒選第一問不出現', () {
      expect(NewTopicTwoStageCopy.coachTip(const _A()), isNull);
      expect(NewTopicTwoStageCopy.coachTip(const _A(materialKind: 'none')),
          isNull);
    });

    test('冷掉了沒選追問、或只選聊著聊著就停了 → 沒選多久那行', () {
      for (final stop in [null, 'faded']) {
        expect(_tip('went_cold', stop: stop),
            (open: '這次怎麼開：有內容、低壓力、不追討。', avoid: '先避開：「在嗎」式空敲門'));
      }
    });

    test('多久＋怎麼停兩行都顯示，先避開依序合併', () {
      expect(_tip('went_cold', duration: 'days', stop: 'she_no_reply'), (
        open: '這次怎麼開：話題還熱，直接把上次那條線接回來。不追上一則；有新的東西，再傳一則全新的內容。',
        avoid: '先避開：正式說「好久沒聊」、「在嗎」「妳怎麼沒回」',
      ));
      expect(_tip('went_cold', duration: 'weeks', stop: 'she_cold')!.avoid,
          '先避開：檢討關係、連續補話題、硬約');
    });

    test('只選怎麼停（非 faded）就只有那一行', () {
      expect(_tip('went_cold', stop: 'i_no_reply'),
          (open: '這次怎麼開：一句帶過就好，接著直接進內容。', avoid: '先避開：長篇解釋、過度道歉'));
    });

    test('一個月以上：自然停了或沒選 → 可以輕鬆說一句', () {
      for (final stop in [null, 'faded']) {
        expect(_tip('went_cold', duration: 'month_plus', stop: stop),
            (open: '這次怎麼開：可以輕鬆說一句有陣子沒聊，接著直接帶內容。', avoid: '先避開：一上來就曖昧'));
      }
    });

    test('一個月以上＋她沒回我／她最近都回很冷 → 隔很久了那行＋怎麼停那行', () {
      expect(
          _tip('went_cold', duration: 'month_plus', stop: 'she_no_reply')!.open,
          '這次怎麼開：隔很久了，這次帶著一個具體的新東西出現。不追上一則；有新的東西，再傳一則全新的內容。');
      expect(_tip('went_cold', duration: 'month_plus', stop: 'she_cold'), (
        open: '這次怎麼開：隔很久了，這次帶著一個具體的新東西出現。先降低頻率和強度：一則就好，看她會不會主動多聊。',
        avoid: '先避開：一上來就曖昧、連續補話題、硬約',
      ));
    });

    test('例外：一個月以上＋我沒回她只顯示一句帶過那行', () {
      expect(_tip('went_cold', duration: 'month_plus', stop: 'i_no_reply'),
          (open: '這次怎麼開：一句帶過就好，接著直接進內容。', avoid: '先避開：長篇解釋、過度道歉'));
    });

    test('其他三種：3×4 表含沒選欄', () {
      expect(_tip('stuck', engagement: 'red'), (
        open: '這次怎麼開：不要用更多問題去救：接住一句、自然收尾，留個下次的點。',
        avoid: '先避開：追問「怎麼了」、加碼曖昧',
      ));
      expect(_tip('after_date'),
          (open: '這次怎麼開：承接約會的餘溫，不急著約下一次。', avoid: '先避開：索取評價'));
      expect(_tip('warm_up', engagement: 'green'),
          (open: '這次怎麼開：可以加一點個人感：具體稱讚、共同想像。', avoid: '先避開：突然告白、越界'));
      expect(_tip('after_date', engagement: 'yellow')!.avoid, '先避開：索取評價、急約下次');
    });
  });

  group('這組根據', () {
    test('全沒選回 null；沒選的段落省略', () {
      expect(NewTopicTwoStageCopy.basisLine(const _A()), isNull);
      expect(NewTopicTwoStageCopy.basisLine(const _A(situation: 'went_cold')),
          '這組根據：冷掉了');
      expect(NewTopicTwoStageCopy.basisLine(const _A(materialKind: 'none')),
          '這組根據：沒有，幫我想');
    });

    test('提案例子：冷掉了・一到四週・我沒回她｜看到想到她的東西', () {
      expect(
          NewTopicTwoStageCopy.basisLine(const _A(
              situation: 'went_cold',
              coldDuration: 'weeks',
              coldStop: 'i_no_reply',
              materialKind: 'trigger',
              materialText: '路過甜點店')),
          '這組根據：冷掉了・一到四週・我沒回她｜看到想到她的東西');
    });

    test('投入程度用追問選項原文；剛約完會用約會版素材標籤', () {
      expect(
          NewTopicTwoStageCopy.basisLine(const _A(
              situation: 'after_date',
              engagement: 'green',
              materialKind: 'past_topic')),
          '這組根據：剛約完會・主動傳訊息或說開心｜約會時聊到的事');
      expect(
          NewTopicTwoStageCopy.basisLine(
              const _A(situation: 'stuck', engagement: 'red')),
          '這組根據：還在聊但接不下去・常只回哈哈、嗯');
    });
  });

  group('toTopicContextJson', () {
    test('全沒選或只選第一問 → null（走 legacy）', () {
      expect(const _A().toTopicContextJson(), isNull);
      expect(const _A(situation: 'warm_up').toTopicContextJson(), isNull);
    });

    test('追問與素材照固定鍵帶；素材送 trim 後的文字', () {
      expect(
          const _A(
                  situation: 'went_cold',
                  coldDuration: 'weeks',
                  coldStop: 'i_no_reply',
                  materialKind: 'trigger',
                  materialText: '  路過一家甜點店 \n')
              .toTopicContextJson(),
          {
            'coldDuration': 'weeks',
            'coldStop': 'i_no_reply',
            'materialKind': 'trigger',
            'materialText': '路過一家甜點店',
          });
      expect(
          const _A(situation: 'stuck', engagement: 'yellow')
              .toTopicContextJson(),
          {'engagement': 'yellow'});
    });

    test('「沒有，幫我想」可以單獨送，不帶殘留文字', () {
      expect(
          const _A(materialKind: 'none', materialText: '之前打的字')
              .toTopicContextJson(),
          {'materialKind': 'none'});
    });

    test('搭不上第一問的追問不送（避免 server 400）', () {
      expect(
          const _A(situation: 'stuck', coldDuration: 'days')
              .toTopicContextJson(),
          isNull);
      expect(
          const _A(situation: 'went_cold', engagement: 'green')
              .toTopicContextJson(),
          isNull);
      expect(const _A(engagement: 'green').toTopicContextJson(), isNull);
    });
  });

  group('素材檢查', () {
    test('選了要寫的素材卻沒寫 → missing；none 不需要寫', () {
      expect(
          const _A(materialKind: 'my_story', materialText: '  ')
              .materialMissing,
          isTrue);
      expect(const _A(materialKind: 'none').materialMissing, isFalse);
      expect(const _A().materialMissing, isFalse);
    });

    test('150 個 grapheme（含組合 emoji）可以，151 超長且不截斷', () {
      final ok = '👍🏽' * 150;
      final over = '${'👍🏽' * 150}a';
      expect(_A(materialKind: 'trigger', materialText: ok).materialTooLong,
          isFalse);
      final tooLong = _A(materialKind: 'trigger', materialText: over);
      expect(tooLong.materialTooLong, isTrue);
      expect(tooLong.materialLength, 151);
      expect(tooLong.toTopicContextJson()!['materialText'], over);
    });

    test('計數文案：n / 150，超過時說明超過幾字', () {
      expect(NewTopicTwoStageCopy.materialCounter(12), '12 / 150');
      expect(NewTopicTwoStageCopy.materialCounter(153),
          '153 / 150，超過 3 字，請縮短後再生成');
    });
  });
}
