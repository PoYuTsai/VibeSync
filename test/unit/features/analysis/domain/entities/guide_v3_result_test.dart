import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
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

    test('邀約進度：伺服器七個代碼都認得；不認得、沒帶（舊快照）是 null；care 一律沒有', () {
      GuideV3Read read(Object? code, {String decision = 'send'}) =>
          GuideV3Read.fromJson({
            ..._read(decision: decision),
            if (code != null) 'inviteReadiness': code,
          })!;
      // 伺服器 wire.ts 的 INVITE_READINESS_CODE（flow_parts_test.ts 釘住同一張表）。
      const labels = {
        'none': '沒機會',
        'declined': '婉拒過',
        'vague_yes': '含糊答應',
        'clear_yes': '明確答應',
        'she_proposed': '她自己提見面',
        'she_cancelled': '她取消了',
        'hesitant': '猶豫',
      };
      expect(GuideV3InviteReadiness.values.map((r) => r.wire).toSet(),
          labels.keys.toSet());
      for (final entry in labels.entries) {
        final parsed = read(entry.key).inviteReadiness;
        expect(parsed?.wire, entry.key);
        expect(parsed?.label, entry.value);
        expect(read(entry.key, decision: 'hold').inviteReadiness, parsed);
      }
      expect(read('maybe_later').inviteReadiness, isNull);
      expect(read(3).inviteReadiness, isNull);
      expect(read(null).inviteReadiness, isNull);
      expect(read('clear_yes', decision: 'care').inviteReadiness, isNull);
    });

    test('冷訊號：c1＋她連續敷衍幾輪；缺欄、型別不對、負數整個不收；舊快照與 care 沒有', () {
      GuideV3Read read(Object? cold, {String decision = 'hold'}) =>
          GuideV3Read.fromJson({
            ..._read(decision: decision, plannedCards: const []),
            if (cold != null) 'cold': cold,
          })!;
      final fired = read({'c1': true, 'herPerfunctoryStreak': 2}).cold!;
      expect(fired.c1, isTrue);
      expect(fired.herPerfunctoryStreak, 2);
      final quiet =
          read({'c1': false, 'herPerfunctoryStreak': 0}, decision: 'send')
              .cold!;
      expect(quiet.c1, isFalse);
      expect(quiet.herPerfunctoryStreak, 0);
      expect(read({'c1': true}).cold, isNull);
      expect(read({'c1': 'yes', 'herPerfunctoryStreak': 1}).cold, isNull);
      expect(read({'c1': false, 'herPerfunctoryStreak': -1}).cold, isNull);
      expect(read({'c1': false, 'herPerfunctoryStreak': 1.5}).cold, isNull);
      expect(read('cold').cold, isNull);
      expect(read(null).cold, isNull);
      expect(
        read({'c1': true, 'herPerfunctoryStreak': 2}, decision: 'care').cold,
        isNull,
      );
    });

    test('新欄位不影響其他欄位：舊快照照舊解析、最終結果帶得到', () {
      final legacy = GuideV3Result.fromJson(_final())!;
      expect(legacy.read.inviteReadiness, isNull);
      expect(legacy.read.cold, isNull);
      expect(legacy.read.light, GuideV3Light.green);
      final withSignals = GuideV3Result.fromJson(_final(read: {
        ..._read(),
        'inviteReadiness': 'she_proposed',
        'cold': {'c1': false, 'herPerfunctoryStreak': 1},
      }))!;
      expect(
          withSignals.read.inviteReadiness, GuideV3InviteReadiness.sheProposed);
      expect(withSignals.read.cold?.herPerfunctoryStreak, 1);
      expect(withSignals.cards, hasLength(2));
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

  group('GuideV3Relation（關係狀態，Bruce 2026-10-19 路線二）', () {
    Map<String, dynamic> relation({
      Object? stage = 'premise',
      Object? heat = 72,
      Object? dimensions = const {
        'heat': 72,
        'engagement': 70,
        'topicDepth': 45,
        'replyWillingness': 78,
        'emotionalConnection': 60,
      },
      Object? herMove = 'high',
      Object? willingness = 'high',
    }) =>
        {
          'stage': stage,
          'heat': heat,
          'dimensions': dimensions,
          'herMove': herMove,
          'willingness': willingness,
        };

    GuideV3Read? read(Map<String, dynamic>? rel, {String decision = 'send'}) =>
        GuideV3Read.fromJson({
          ..._read(decision: decision),
          if (rel != null) 'relation': rel,
        });

    test('判讀帶得到階段、熱度、五維雷達、她在做什麼、回覆意願', () {
      final rel = read(relation())!.relation!;
      expect(rel.stage, GameStage.premise);
      expect(rel.heat, 72);
      expect(rel.dimensions, {
        'heat': 72,
        'engagement': 70,
        'topicDepth': 45,
        'replyWillingness': 78,
        'emotionalConnection': 60,
      });
      expect(rel.herMove, GuideV3HerMove.high);
      expect(rel.willingness, GuideV3Willingness.high);
    });

    test('顯示與存檔的熱度跟 v2 一樣換成 0–90：ceil(原始 × 0.9)', () {
      int? visible(int raw) => read(relation(heat: raw))!.relation!.visibleHeat;
      expect(visible(72), 65);
      expect(visible(100), 90);
      expect(visible(0), 0);
      expect(visible(1), 1);
    });

    test('伺服器的英文代碼都認得', () {
      for (final move in GuideV3HerMove.values) {
        expect(
          read(relation(herMove: move.wire))!.relation!.herMove,
          move,
        );
      }
      for (final level in GuideV3Willingness.values) {
        expect(
          read(relation(willingness: level.wire))!.relation!.willingness,
          level,
        );
      }
      for (final stage in GameStage.values) {
        expect(read(relation(stage: stage.name))!.relation!.stage, stage);
      }
    });

    test('壞掉的欄位各自不收，其他照收；判讀不受影響', () {
      final rel = read(relation(
        stage: '破冰',
        heat: 101,
        herMove: '高點',
        willingness: 'very_high',
      ))!
          .relation!;
      expect(rel.stage, isNull);
      expect(rel.heat, isNull);
      expect(rel.visibleHeat, isNull);
      expect(rel.herMove, isNull);
      expect(rel.willingness, isNull);
      expect(rel.dimensions, isNotNull);

      for (final bad in <Object?>[-1, 50.5, '50', null]) {
        expect(read(relation(heat: bad))!.relation!.heat, isNull);
      }
      // 五維雷達要五個都在、都是 0–100 的整數，缺一個或壞一個整組不收。
      for (final bad in <Object?>[
        const {
          'heat': 72,
          'engagement': 70,
          'topicDepth': 45,
          'replyWillingness': 78,
        },
        const {
          'heat': 72,
          'engagement': 170,
          'topicDepth': 45,
          'replyWillingness': 78,
          'emotionalConnection': 60,
        },
        const [72, 70, 45, 78, 60],
        null,
      ]) {
        expect(read(relation(dimensions: bad))!.relation!.dimensions, isNull);
      }
      expect(read(relation(heat: 101))!.decision, GuideV3Decision.send);
    });

    test('沒送（開關沒開、改版前的快照）或每一欄都讀不懂：沒有關係狀態', () {
      expect(read(null)!.relation, isNull);
      expect(
        read(relation(
          stage: null,
          heat: null,
          dimensions: null,
          herMove: null,
          willingness: null,
        ))!
            .relation,
        isNull,
      );
      expect(
        GuideV3Read.fromJson({..._read(), 'relation': 'premise'})!.relation,
        isNull,
      );
    });

    test('關心一律不收：固定訊息那次不拿來算階段、熱度與雷達', () {
      final care = read(
        relation(),
        decision: 'care',
      )!;
      expect(care.relation, isNull);
      // 先別回、停照收（伺服器照樣送）。
      expect(read(relation(), decision: 'hold')!.relation, isNotNull);
      expect(read(relation(), decision: 'stop')!.relation, isNotNull);
    });

    test('最終結果的判讀帶得到（重開畫面從快照還原也一樣）', () {
      final result = GuideV3Result.fromJson(_final(
        read: {..._read(), 'relation': relation()},
      ))!;
      expect(result.read.relation!.stage, GameStage.premise);
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

    test('再調結果要照則留住空格：原稿有空格才查，則數與每一則的段數都要一樣', () {
      expect(guideV3BlankRuns('我做＿＿，住＿和＿＿'), 3);
      expect(guideV3BlankRuns('沒有空格'), 0);
      // 原稿沒有空格：不查（多出空格的話，卡片的複製規則會要他先填）。
      expect(guideV3RefineKeepsBlanks(['好啊'], ['好啊，週末去＿＿']), isTrue);
      expect(
        guideV3RefineKeepsBlanks(['我做＿＿', '住＿＿'], ['我做＿＿啦', '住＿＿附近']),
        isTrue,
      );
      // 空格被填成編的。
      expect(
        guideV3RefineKeepsBlanks(['我是＿＿', '週末常去＿＿'], ['我是工程師', '週末常爬山']),
        isFalse,
      );
      // 總數一樣、但挪了則（主審第 1 輪 P2-5 的例子）。
      expect(
        guideV3RefineKeepsBlanks(['我做＿＿', '住＿＿'], ['我做設計', '住＿＿，週末去＿＿']),
        isFalse,
      );
      // 兩則被併成一則。
      expect(
        guideV3RefineKeepsBlanks(['我做＿＿', '住＿＿'], ['我做＿＿，住＿＿']),
        isFalse,
      );
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
    test('比預定的少：partial、recovered、送到的比這個方案預定的少都算；免費鎖住的不算', () {
      // _read 預設排 3 張、第 3 張鎖住（免費方案只送前 2 張）。
      final complete = GuideV3Result.fromJson(_final())!;
      expect(complete.read.deliverableCount, 2);
      expect(complete.deliveredFewer, isFalse);
      expect(GuideV3Result.fromJson(_final(partial: true))!.deliveredFewer,
          isTrue);
      expect(GuideV3Result.fromJson(_final(recovered: true))!.deliveredFewer,
          isTrue);
      expect(GuideV3Result.fromJson(_final(cards: [_card(1)]))!.deliveredFewer,
          isTrue);
      // 先別回沒有卡也沒有預定的卡。
      final hold = GuideV3Result.fromJson(_final(
        read: _read(decision: 'hold', plannedCards: const []),
        cards: const [],
      ))!;
      expect(hold.deliveredFewer, isFalse);
      expect(
        guideV3DeliveredFewer(
          partial: false,
          recovered: false,
          deliveredCards: 2,
          deliverableCards: 2,
        ),
        isFalse,
      );
    });

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

    test('跟進提醒（P1 安全修正）：關心與停不催他回去找她；先別回、出卡、收尾照舊', () {
      bool silences(String decision) => GuideV3Result.fromJson({
            'guideVersion': 'v3.6',
            'read': _read(decision: decision, plannedCards: const []),
            'cards': const [],
          })!
              .decision
              .silencesFollowUp;
      expect(silences('care'), isTrue);
      expect(silences('stop'), isTrue);
      expect(silences('hold'), isFalse);
      expect(silences('send'), isFalse);
      expect(silences('close'), isFalse);
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
