import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/data/services/new_topic_request_session.dart';

void main() {
  group('NewTopicRequestSession', () {
    test('同 Partner＋同 situation 的 failure retry 沿用同一 frozen envelope', () {
      final session = NewTopicRequestSession();
      final first = session.beginAttempt(
        partnerId: 'p-1',
        partnerSummary: '摘要 v1',
        effectiveStyleContext: '風格 v1',
        situation: 'went_cold',
      );
      // 背景 provider 更新（summary/style 變新版）不得偷換 payload。
      final retry = session.beginAttempt(
        partnerId: 'p-1',
        partnerSummary: '摘要 v2',
        effectiveStyleContext: '風格 v2',
        situation: 'went_cold',
      );

      expect(retry.requestId, first.requestId);
      expect(retry.partnerSummary, '摘要 v1');
      expect(retry.effectiveStyleContext, '風格 v1');
    });

    test('Partner 或 situation 改變 rotate（即使 summary 相同）', () {
      final session = NewTopicRequestSession();
      final first = session.beginAttempt(
        partnerId: 'p-1',
        partnerSummary: '同一份摘要',
        effectiveStyleContext: null,
        situation: 'stuck',
      );

      final partnerChanged = session.beginAttempt(
        partnerId: 'p-2',
        partnerSummary: '同一份摘要',
        effectiveStyleContext: null,
        situation: 'stuck',
      );
      expect(partnerChanged.requestId, isNot(first.requestId));

      final situationChanged = session.beginAttempt(
        partnerId: 'p-2',
        partnerSummary: '同一份摘要',
        effectiveStyleContext: null,
        situation: 'warm_up',
      );
      expect(situationChanged.requestId, isNot(partnerChanged.requestId));
    });

    test('markSuccess 後同輸入鑄新 id（下一次是新計費）', () {
      final session = NewTopicRequestSession();
      final first = session.beginAttempt(
        partnerId: 'p-1',
        partnerSummary: null,
        effectiveStyleContext: '風格',
        situation: null,
      );
      session.markSuccess();
      final second = session.beginAttempt(
        partnerId: 'p-1',
        partnerSummary: null,
        effectiveStyleContext: '風格',
        situation: null,
      );
      expect(second.requestId, isNot(first.requestId));
    });

    test('visible fingerprint 保欄位邊界', () {
      expect(
        NewTopicRequestSession.visibleFingerprintFor(
          partnerId: 'p-1',
          situation: 'stuck',
        ),
        isNot(
          NewTopicRequestSession.visibleFingerprintFor(
            partnerId: 'p-1s',
            situation: 'tuck',
          ),
        ),
      );
    });

    test('topicContext 改變（含素材文字）rotate；鍵序不同但內容相同沿用', () {
      final session = NewTopicRequestSession();
      NewTopicAttempt begin(Map<String, dynamic>? topicContext) =>
          session.beginAttempt(
            partnerId: 'p-1',
            partnerSummary: null,
            effectiveStyleContext: '風格',
            situation: 'went_cold',
            topicContext: topicContext,
          );
      final legacy = begin(null);
      final advanced = begin({'coldStop': 'she_cold'});
      expect(advanced.requestId, isNot(legacy.requestId));
      expect(advanced.topicContext, {'coldStop': 'she_cold'});

      final withText =
          begin({'materialKind': 'trigger', 'materialText': '甜點店'});
      expect(withText.requestId, isNot(advanced.requestId));
      final reordered =
          begin({'materialText': '甜點店', 'materialKind': 'trigger'});
      expect(reordered.requestId, withText.requestId);
      expect(
        session.pendingFor(
          partnerId: 'p-1',
          situation: 'went_cold',
          topicContext: {'materialKind': 'trigger', 'materialText': '甜點店'},
        ),
        same(withText),
      );
      expect(
        session.pendingFor(
          partnerId: 'p-1',
          situation: 'went_cold',
          topicContext: {'materialKind': 'trigger', 'materialText': '甜點店！'},
        ),
        isNull,
      );
      final edited = begin({'materialKind': 'trigger', 'materialText': '甜點店！'});
      expect(edited.requestId, isNot(withText.requestId));
    });

    test('凍結的 topicContext 不受呼叫端之後改 Map 影響', () {
      final session = NewTopicRequestSession();
      final source = <String, dynamic>{'engagement': 'red'};
      final attempt = session.beginAttempt(
        partnerId: 'p-1',
        partnerSummary: null,
        effectiveStyleContext: null,
        situation: 'stuck',
        topicContext: source,
      );
      source['engagement'] = 'green';
      expect(attempt.topicContext, {'engagement': 'red'});
      expect(() => attempt.topicContext!['engagement'] = 'green',
          throwsUnsupportedError);
    });
  });
}
