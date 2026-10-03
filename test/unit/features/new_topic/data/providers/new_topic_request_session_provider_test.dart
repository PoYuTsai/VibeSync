import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/data/providers/new_topic_providers.dart';
import 'package:vibesync/features/new_topic/data/services/new_topic_request_session.dart';

void main() {
  late ProviderContainer container;
  const key = (ownerId: 'user-a', partnerId: 'partner-1');

  NewTopicAttempt begin({
    NewTopicRequestSessionKey scope = key,
    String answer = '甜點店',
  }) =>
      container.read(newTopicRequestSessionProvider(scope)).beginAttempt(
        partnerId: scope.partnerId,
        partnerSummary: '摘要',
        effectiveStyleContext: '風格',
        situation: 'stuck',
        topicContext: {'materialKind': 'trigger', 'materialText': answer},
      );

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('最後一個 listener dispose 後重訂閱，同答案保留 requestId 與 envelope', () async {
    final provider = newTopicRequestSessionProvider(key);
    final listener = container.listen(provider, (_, __) {});
    final first = begin();
    listener.close();
    await container.pump();
    final returned = container.listen(provider, (_, __) {});
    expect(begin(), same(first));
    returned.close();
  });

  test('答案改變產生新的 requestId', () {
    final first = begin();
    expect(begin(answer: '咖啡店').requestId, isNot(first.requestId));
  });

  test('成功後同答案產生新的 requestId', () {
    final first = begin();
    container.read(newTopicRequestSessionProvider(key)).markSuccess();
    expect(begin().requestId, isNot(first.requestId));
  });

  test('不同使用者與不同對象不共用 requestId', () {
    final first = begin();
    final otherUser = begin(scope: (ownerId: 'user-b', partnerId: 'partner-1'));
    final otherPartner =
        begin(scope: (ownerId: 'user-a', partnerId: 'partner-2'));
    expect({first.requestId, otherUser.requestId, otherPartner.requestId},
        hasLength(3));
    expect(begin(), same(first));
  });

  test('登出卸載 listener 後換帳號不會取得前一帳號 pending', () async {
    final listener =
        container.listen(newTopicRequestSessionProvider(key), (_, __) {});
    final first = begin();
    listener.close();
    await container.pump();
    const otherKey = (ownerId: 'user-b', partnerId: 'partner-1');
    final otherSession =
        container.read(newTopicRequestSessionProvider(otherKey));
    expect(
        otherSession.pendingFor(
            partnerId: otherKey.partnerId,
            situation: 'stuck',
            topicContext: first.topicContext),
        isNull);
    expect(begin(scope: otherKey).requestId, isNot(first.requestId));
  });
}
