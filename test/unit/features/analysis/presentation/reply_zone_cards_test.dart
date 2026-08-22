// Work C C2：canonical 回覆卡集合的精確張數／順序／對映測試。
//
// 顯示卡組、張數（橫滑提示門檻）與 outcome bar 對映都由同一份
// ReplyZoneCards 推導；這裡鎖住推導規則本身。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/sections/reply_zone_section.dart';

const _fullReplies = {
  'extend': '延展',
  'resonate': '共鳴',
  'tease': '調情',
  'humor': '幽默',
  'coldRead': '冷讀',
};

FinalRecommendation _recommendation({
  String pick = 'tease',
  String content = '調情',
}) {
  return FinalRecommendation(
    pick: pick,
    content: content,
    reason: '理由',
    psychology: '心理',
  );
}

void main() {
  test('付費完整結果：推薦卡＋4 張風格卡（pick 型別去重），順序固定', () {
    final cards = ReplyZoneCards(
      recommendation: _recommendation(),
      replies: _fullReplies,
      replyOptions: const {},
    );

    expect(cards.showRecommended, isTrue);
    expect(cards.cardCount, 5);
    expect(
      cards.styleCards.map((c) => c.type).toList(),
      ['extend', 'resonate', 'humor', 'coldRead'],
    );
    expect(cards.styleCards.every((c) => !c.isRecommended), isTrue);
    // outcome bar 對映不去重：五種型別全在、照固定順序。
    expect(
      cards.presentStyleTypes,
      ['extend', 'resonate', 'tease', 'humor', 'coldRead'],
    );
    expect(cards.hasContent, isTrue);
  });

  test('免費結果（extend+tease，pick=extend）：推薦卡＋1 張風格卡', () {
    final cards = ReplyZoneCards(
      recommendation: _recommendation(pick: 'extend', content: '延展'),
      replies: const {'extend': '延展', 'tease': '調情'},
      replyOptions: const {},
    );

    expect(cards.cardCount, 2);
    expect(cards.styleCards.map((c) => c.type).toList(), ['tease']);
    expect(cards.presentStyleTypes, ['extend', 'tease']);
  });

  test('pick 不在回覆鍵內：不去重，推薦卡＋5 張', () {
    final cards = ReplyZoneCards(
      recommendation: _recommendation(pick: 'unknownStyle', content: '內容'),
      replies: _fullReplies,
      replyOptions: const {},
    );

    expect(cards.cardCount, 6);
    expect(
      cards.styleCards.map((c) => c.type).toList(),
      ['extend', 'resonate', 'tease', 'humor', 'coldRead'],
    );
  });

  test('推薦內容空白：無推薦卡，pick 型別風格卡標記推薦', () {
    final cards = ReplyZoneCards(
      recommendation: _recommendation(content: '   '),
      replies: _fullReplies,
      replyOptions: const {},
    );

    expect(cards.showRecommended, isFalse);
    expect(cards.cardCount, 5);
    final tease = cards.styleCards.firstWhere((c) => c.type == 'tease');
    expect(tease.isRecommended, isTrue);
    expect(
      cards.styleCards.where((c) => c.isRecommended).map((c) => c.type),
      ['tease'],
    );
  });

  test('pick 型別的回覆為空白字串：不去重（推薦卡外仍渲染該風格卡）', () {
    final replies = Map<String, String>.from(_fullReplies)..['tease'] = '  ';
    final cards = ReplyZoneCards(
      recommendation: _recommendation(),
      replies: replies,
      replyOptions: const {},
    );

    expect(cards.cardCount, 6);
    expect(
      cards.styleCards.map((c) => c.type).toList(),
      ['extend', 'resonate', 'tease', 'humor', 'coldRead'],
    );
    expect(cards.styleCards.every((c) => !c.isRecommended), isTrue);
  });

  test('回覆只含未知鍵且無推薦：canonical 空態（不因原始 map 非空撐開回覆區）', () {
    final cards = ReplyZoneCards(
      recommendation: null,
      replies: const {'unknownStyle': '未知風格回覆', 'another': '另一個'},
      replyOptions: const {},
    );

    expect(cards.hasContent, isFalse, reason: 'hasContent 必須由 canonical 卡組推導');
    expect(cards.cardCount, 0);
    expect(cards.styleCards, isEmpty);
    expect(cards.presentStyleTypes, isEmpty);
  });

  test('回覆只含未知鍵但推薦卡存在：只有推薦卡', () {
    final cards = ReplyZoneCards(
      recommendation: _recommendation(pick: 'unknownStyle', content: '推薦內容'),
      replies: const {'unknownStyle': '未知風格回覆'},
      replyOptions: const {},
    );

    expect(cards.hasContent, isTrue);
    expect(cards.cardCount, 1);
    expect(cards.styleCards, isEmpty);
  });

  test('無推薦亦無回覆：無內容', () {
    final cards = ReplyZoneCards(
      recommendation: null,
      replies: null,
      replyOptions: null,
    );

    expect(cards.hasContent, isFalse);
    expect(cards.cardCount, 0);
    expect(cards.styleCards, isEmpty);
    expect(cards.presentStyleTypes, isEmpty);
  });

  test('replyOptions 依型別對映到對應風格卡', () {
    const option = ReplyOption(approach: '先延展她的話題');
    final cards = ReplyZoneCards(
      recommendation: null,
      replies: const {'extend': '延展'},
      replyOptions: const {'extend': option},
    );

    expect(cards.styleCards.single.option, same(option));
  });
}
