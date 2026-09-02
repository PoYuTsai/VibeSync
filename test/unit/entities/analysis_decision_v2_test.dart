// Phase 1c：Analyze V2 一級決策的解析與「後端決策是唯一真相」規則。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';

void main() {
  const noSend = {
    'schemaVersion': 2,
    'messageDecision': 'do_not_send',
    'replyMode': 'none',
    'action': 'pause',
    'reason': '她只回哈哈，沒有新內容',
    'stopCondition': '等她主動給新話題',
  };

  group('AnalysisDecisionV2.fromJson', () {
    test('合法 no-send 決策全欄位解析', () {
      final decision = AnalysisDecisionV2.fromJson(noSend)!;
      expect(decision.messageDecision, 'do_not_send');
      expect(decision.replyMode, 'none');
      expect(decision.action, 'pause');
      expect(decision.reason, '她只回哈哈，沒有新內容');
      expect(decision.stopCondition, '等她主動給新話題');
      expect(decision.closingMessage, isNull);
      expect(decision.isSend, isFalse);
      expect(decision.hidesReplyZone, isTrue);
    });

    test('acknowledge_and_stop 帶 closingMessage，replyMode 缺席時推導 single', () {
      final decision = AnalysisDecisionV2.fromJson({
        ...noSend,
        'messageDecision': 'acknowledge_and_stop',
        'replyMode': null,
        'closingMessage': ' 好，那先這樣。 ',
      })!;
      expect(decision.replyMode, 'single');
      expect(decision.closingMessage, '好，那先這樣。');
      expect(decision.hidesReplyZone, isTrue);
    });

    test('send 決策不藏回覆區', () {
      final decision = AnalysisDecisionV2.fromJson({
        'schemaVersion': 2,
        'messageDecision': 'send',
      })!;
      expect(decision.isSend, isTrue);
      expect(decision.replyMode, 'variants');
      expect(decision.hidesReplyZone, isFalse);
    });

    test('矛盾的 replyMode 以 messageDecision 為準，非 send 永遠藏回覆區', () {
      final contradictory = AnalysisDecisionV2.fromJson({
        ...noSend,
        'replyMode': 'variants',
      })!;
      expect(contradictory.replyMode, 'none');
      expect(contradictory.hidesReplyZone, isTrue);

      final ackVariants = AnalysisDecisionV2.fromJson({
        ...noSend,
        'messageDecision': 'acknowledge_and_stop',
        'replyMode': 'variants',
        'closingMessage': '先這樣。',
      })!;
      expect(ackVariants.replyMode, 'single');
      expect(ackVariants.hidesReplyZone, isTrue);

      // send 帶 none 也不會把回覆區藏起來（send 才有卡可顯示）。
      final sendNone = AnalysisDecisionV2.fromJson({
        'schemaVersion': 2,
        'messageDecision': 'send',
        'replyMode': 'none',
      })!;
      expect(sendNone.replyMode, 'none');
      expect(sendNone.hidesReplyZone, isFalse);
    });

    test('closingMessage 只屬於 acknowledge_and_stop，其他決策一律丟棄', () {
      final held = AnalysisDecisionV2.fromJson({
        ...noSend,
        'closingMessage': '不該出現的句子',
      })!;
      expect(held.closingMessage, isNull);
      expect(held.sendableClosingMessage, isNull);
      final needContext = AnalysisDecisionV2.fromJson({
        ...noSend,
        'messageDecision': 'need_context',
        'closingMessage': '不該出現的句子',
      })!;
      expect(needContext.closingMessage, isNull);
      // 即使直接建構帶了句子，也只有 acknowledge_and_stop 可傳。
      const constructed = AnalysisDecisionV2(
        messageDecision: 'do_not_send',
        replyMode: 'none',
        closingMessage: '不該出現的句子',
      );
      expect(constructed.sendableClosingMessage, isNull);
    });

    test('缺 schemaVersion 2、未知決策、非物件一律 null（退回 v1）', () {
      expect(AnalysisDecisionV2.fromJson(null), isNull);
      expect(AnalysisDecisionV2.fromJson('do_not_send'), isNull);
      expect(
        AnalysisDecisionV2.fromJson({...noSend, 'schemaVersion': 1}),
        isNull,
      );
      expect(
        AnalysisDecisionV2.fromJson({...noSend, 'messageDecision': 'hold'}),
        isNull,
      );
      expect(
        AnalysisDecisionV2.fromJson({...noSend, 'messageDecision': null}),
        isNull,
      );
    });
  });

  group('AnalysisResult.fromJson 與 V2 決策', () {
    test('決策存在時 shouldGiveUp 由後端決定，不看本地 cold＋警語', () {
      final coldWarned = {
        'enthusiasm': {'score': 12, 'level': 'cold'},
        'warnings': ['對方已讀不回，建議放棄'],
        'replies': {'extend': '延展句'},
      };
      // v1：本地 heuristic 仍然成立。
      expect(AnalysisResult.fromJson(coldWarned).shouldGiveUp, isTrue);
      expect(AnalysisResult.fromJson(coldWarned).decision, isNull);

      // v2 send：後端說可以回，本地警語不得再開放棄橫幅。
      final sent = AnalysisResult.fromJson({
        ...coldWarned,
        'analysisDecisionV2': {'schemaVersion': 2, 'messageDecision': 'send'},
      });
      expect(sent.shouldGiveUp, isFalse);
      expect(sent.decision!.isSend, isTrue);

      // v2 do_not_send：不管本地訊號怎麼說。
      final held = AnalysisResult.fromJson({
        'enthusiasm': {'score': 80, 'level': 'hot'},
        'replies': <String, dynamic>{},
        'analysisDecisionV2': noSend,
      });
      expect(held.shouldGiveUp, isTrue);
      expect(held.decision!.messageDecision, 'do_not_send');
      expect(held.replies, isEmpty);

      // need_context 不是放棄，但一樣藏回覆區。
      final needContext = AnalysisResult.fromJson({
        'replies': <String, dynamic>{},
        'analysisDecisionV2': {...noSend, 'messageDecision': 'need_context'},
      });
      expect(needContext.shouldGiveUp, isFalse);
      expect(needContext.decision!.hidesReplyZone, isTrue);
    });

    test('決策隨 rawResponse 回存，重新解析後仍在（歷史快照 round-trip）', () {
      final result = AnalysisResult.fromJson({
        'replies': <String, dynamic>{},
        'analysisDecisionV2': noSend,
      });
      final restored = AnalysisResult.fromJson(result.rawResponse!);
      expect(restored.decision!.messageDecision, 'do_not_send');
      expect(restored.decision!.stopCondition, '等她主動給新話題');
    });
  });
}
