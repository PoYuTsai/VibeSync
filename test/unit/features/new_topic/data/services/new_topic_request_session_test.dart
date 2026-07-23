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

    test('visible fingerprint 只含 partnerId＋situation 且保欄位邊界', () {
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
  });
}
