import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';

/// 形狀照伺服器 `guide_v3/wire.ts`（readView／cardView／finalResult）。
Map<String, dynamic> _read({
  String decision = 'send',
  String light = 'green',
  String judgment = '她有在接你的話，可以往前一步。',
  List<Object?>? plannedCards,
  String? waitFor,
  String? careMessage,
  String? careKind,
}) {
  return {
    'guideVersion': 'v3.4',
    'decision': decision,
    'light': light,
    'judgment': judgment,
    if (waitFor != null) 'waitFor': waitFor,
    if (careMessage != null) 'careMessage': careMessage,
    if (careKind != null) 'careKind': careKind,
    'plannedCards': plannedCards ??
        [
          {'slot': 1, 'task': 'accept', 'locked': false},
          {'slot': 2, 'task': 'tension', 'locked': false},
          {'slot': 3, 'task': 'push', 'locked': true},
        ],
  };
}

Map<String, dynamic> _card(
  int slot, {
  String task = 'accept',
  List<Object?> messages = const ['那家我也想吃吃看'],
  bool hasInventedDetail = false,
  bool hasBlank = false,
}) {
  return {
    'slot': slot,
    'task': task,
    'method': 'reaction',
    'voice': 'default',
    'messages': messages,
    'hasInventedDetail': hasInventedDetail,
    'hasBlank': hasBlank,
  };
}

Map<String, dynamic> _final({
  Map<String, dynamic>? read,
  List<Object?>? cards,
  bool partial = false,
  bool recovered = false,
}) {
  return {
    'guideVersion': 'v3.4',
    'read': read ?? _read(),
    'cards': cards ?? [_card(1), _card(2, task: 'tension')],
    'partial': partial,
    if (recovered) 'recovered': true,
    'usage': {'messagesUsed': 1, 'shouldChargeQuota': true},
  };
}

void main() {
  group('GuideV3Read.fromJson', () {
    test('排好的卡照 slot 排序、locked 照伺服器標', () {
      final read = GuideV3Read.fromJson(_read(plannedCards: [
        {'slot': 3, 'task': 'push', 'locked': true},
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'close', 'locked': false},
      ]))!;
      expect(read.decision, GuideV3Decision.send);
      expect(read.light, GuideV3Light.green);
      expect(read.plannedCards.map((c) => c.slot), [1, 2, 3]);
      expect(read.plannedCards.map((c) => c.task),
          [GuideV3Task.accept, GuideV3Task.close, GuideV3Task.push]);
      expect(read.hasLockedCards, isTrue);
      expect(read.lockedCards.single.slot, 3);
      expect(read.deliverableCount, 2);
    });

    test('waitFor 只給先別回、careMessage 只給關心', () {
      final hold = GuideV3Read.fromJson(_read(
        decision: 'hold',
        waitFor: '等她回你，再看她怎麼接',
        careMessage: '不該出現',
        plannedCards: const [],
      ))!;
      expect(hold.waitFor, '等她回你，再看她怎麼接');
      expect(hold.careMessage, isNull);

      final care = GuideV3Read.fromJson(_read(
        decision: 'care',
        waitFor: '不該出現',
        careMessage: '先把安全放在第一位',
        plannedCards: const [],
      ))!;
      expect(care.careMessage, '先把安全放在第一位');
      expect(care.waitFor, isNull);
      expect(care.decision.hasCards, isFalse);
    });

    test('固定訊息的種類：未成年另外認；沒帶（舊快照）或認不得都當自傷關心；不是 care 就沒有', () {
      GuideV3Read care(String? kind) => GuideV3Read.fromJson(_read(
            decision: 'care',
            plannedCards: const [],
            careMessage: '固定文案',
            careKind: kind,
          ))!;
      expect(care('minor').careKind, GuideV3CareKind.minor);
      expect(care('self_harm').careKind, GuideV3CareKind.selfHarm);
      expect(care(null).careKind, GuideV3CareKind.selfHarm);
      expect(care('other').careKind, GuideV3CareKind.selfHarm);
      final send = GuideV3Read.fromJson(_read(careKind: 'minor'))!;
      expect(send.careKind, isNull);
    });

    test('讀不懂的決定整個不收；讀不懂的燈號只是不顯示', () {
      expect(GuideV3Read.fromJson(_read(decision: 'maybe')), isNull);
      expect(GuideV3Read.fromJson('not a map'), isNull);
      final read = GuideV3Read.fromJson(_read(light: 'purple'))!;
      expect(read.light, isNull);
    });

    test('判讀被伺服器拿掉時是空字串', () {
      final read = GuideV3Read.fromJson(_read(judgment: '  '))!;
      expect(read.judgment, '');
    });

    test('壞掉的排卡項目跳過，不讓整個判讀失敗', () {
      final read = GuideV3Read.fromJson(_read(plannedCards: [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 0, 'task': 'accept'},
        {'slot': 2, 'task': 'unknown'},
        'junk',
      ]))!;
      expect(read.plannedCards.map((c) => c.slot), [1]);
    });
  });

  group('GuideV3Card.fromJson', () {
    test('任務標籤是給用戶看的中文', () {
      expect(GuideV3Task.values.map((t) => t.label),
          ['接住', '共鳴', '帶張力', '推進', '收']);
    });

    test('空格以內容為準：伺服器旗標沒標也要擋複製', () {
      final card = GuideV3Card.fromJson(
          _card(1, messages: const ['我是做＿＿的', '妳呢'], hasBlank: false))!;
      expect(card.hasBlank, isTrue);
      final noBlank = GuideV3Card.fromJson(
          _card(2, messages: const ['好啊'], hasBlank: true))!;
      expect(noBlank.hasBlank, isFalse);
    });

    test('整張複製用換行接起來；空白訊息拿掉、原樣保留', () {
      final card = GuideV3Card.fromJson(_card(1,
          messages: const [' 先這句 ', '', '再這句'], hasInventedDetail: true))!;
      expect(card.messages, ['先這句', '再這句']);
      expect(card.copyText, '先這句\n再這句');
      expect(card.hasInventedDetail, isTrue);
      expect(card.raw['method'], 'reaction');
    });

    test('再調用的卡片規格：任務、口吻、做法都是伺服器的代碼；舊快照缺欄位就不給', () {
      final card = GuideV3Card.fromJson(_card(1, task: 'push'))!;
      expect(
        card.refineSpec,
        const GuideV3RefineSpec(
          task: 'push',
          voice: 'default',
          method: 'reaction',
        ),
      );
      expect(card.refineSpec!.toJson(), {
        'task': 'push',
        'voice': 'default',
        'method': 'reaction',
      });
      final his = GuideV3Card.fromJson({
        ..._card(2, task: 'tension'),
        'voice': 'his',
        'method': 'blank',
      })!;
      expect(his.refineSpec!.voice, 'his');
      expect(his.refineSpec!.method, 'blank');
      for (final broken in [
        {'voice': null},
        {'method': null},
        {'voice': '照他'},
        {'method': '留空格'},
        {'method': 3},
      ]) {
        final raw = {..._card(3), ...broken}
          ..removeWhere((_, value) => value == null);
        expect(GuideV3Card.fromJson(raw)!.refineSpec, isNull,
            reason: '$broken');
      }
    });

    test('形狀不對就不收', () {
      expect(GuideV3Card.fromJson(_card(0)), isNull);
      expect(GuideV3Card.fromJson(_card(1, task: 'coldRead')), isNull);
      expect(GuideV3Card.fromJson(_card(1, messages: const [])), isNull);
      expect(GuideV3Card.fromJson(_card(1, messages: const ['  '])), isNull);
      expect(GuideV3Card.fromJson(_card(1, messages: const [1])), isNull);
      expect(GuideV3Card.fromJson({'slot': 1, 'task': 'accept'}), isNull);
    });
  });

  group('GuideV3Result', () {
    test('認形狀照伺服器 isGuideV3FinalResult', () {
      expect(isGuideV3Payload(_final()), isTrue);
      expect(isGuideV3Payload({'guideVersion': 3, 'cards': []}), isFalse);
      expect(isGuideV3Payload({'guideVersion': 'v3.4'}), isFalse);
      expect(
        isGuideV3Payload({
          'enthusiasm': {'score': 70},
          'replies': {'extend': 'a'},
        }),
        isFalse,
      );
    });

    test('解析最終結果：卡照 slot 排、同 slot 只留第一張、壞卡跳過', () {
      final result = GuideV3Result.fromJson(_final(cards: [
        _card(2, task: 'tension', messages: const ['第二張']),
        _card(1, messages: const ['第一張']),
        _card(2, messages: const ['重複的第二張']),
        {'slot': 3},
      ]))!;
      expect(result.cards.map((c) => c.slot), [1, 2]);
      expect(result.cards[1].messages, ['第二張']);
      expect(result.partial, isFalse);
      expect(result.recovered, isFalse);
      expect(result.usage?['messagesUsed'], 1);
      expect(result.isCare, isFalse);
    });

    test('判讀壞掉整個結果不收', () {
      expect(GuideV3Result.fromJson(_final(read: {'decision': 'x'})), isNull);
    });

    test('潤飾入口只在出卡與收尾給：先別回、停、固定訊息都不給', () {
      bool offers(String decision) => GuideV3Result.fromJson({
            'guideVersion': 'v3.5',
            'read': _read(decision: decision, plannedCards: const []),
            'cards': const [],
          })!
              .offersDraftPolish;
      expect(offers('send'), isTrue);
      expect(offers('close'), isTrue);
      expect(offers('hold'), isFalse);
      expect(offers('stop'), isFalse);
      expect(offers('care'), isFalse);
    });

    test('關心沒有卡、不扣費', () {
      final result = GuideV3Result.fromJson(_final(
        read: _read(
          decision: 'care',
          careMessage: '先把安全放在第一位',
          plannedCards: const [],
        ),
        cards: const [],
      ))!;
      expect(result.isCare, isTrue);
      expect(result.cards, isEmpty);
    });

    test('續看重組只有第一張：把畫面上已經送到的卡照 slot 補回來，存檔原樣一起改', () {
      final recovered = GuideV3Result.fromJson(_final(
        cards: [
          _card(1, messages: const ['第一張'])
        ],
        partial: true,
        recovered: true,
      ))!;
      final shown = [
        GuideV3Card.fromJson(_card(1, messages: const ['第一張']))!,
        GuideV3Card.fromJson(
            _card(2, task: 'tension', messages: const ['第二張']))!,
        GuideV3Card.fromJson(_card(3, task: 'push', messages: const ['第三張']))!,
      ];
      final merged = recovered.withShownCards(shown);
      expect(merged.cards.map((c) => c.slot), [1, 2, 3]);
      expect(merged.recovered, isTrue);
      expect(merged.partial, isTrue);
      final rawCards = merged.rawResponse['cards'] as List;
      expect(rawCards.map((c) => (c as Map)['slot']), [1, 2, 3]);
      // 存檔後再讀回來還是三張。
      expect(GuideV3Result.fromJson(merged.rawResponse)!.cards.length, 3);
      // 沒有要補的就是原本那份。
      expect(identical(merged.withShownCards(shown), merged), isTrue);
    });
  });
}
