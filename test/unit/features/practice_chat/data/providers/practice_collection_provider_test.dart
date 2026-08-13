// 角色圖鑑集合的真相源守門：server 的翻牌事件，不是裝置本機。
//
// 這組測試釘死 2026-08-13 收掉的那個病：本機那份集合跨帳號、刪帳號清得掉磁碟
// 卻清不掉常駐快取，帳號與圖鑑必然對不上。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';

class _CollectionApi extends PracticeChatApiService {
  _CollectionApi(this.responses);

  /// 每次呼叫依序取一筆；丟 Exception 的項目代表該次失敗。
  final List<Object> responses;
  int calls = 0;

  @override
  Future<Set<String>> fetchPracticeCollection() async {
    final next = responses[calls.clamp(0, responses.length - 1)];
    calls++;
    if (next is Exception) throw next;
    return (next as Set).cast<String>();
  }
}

void main() {
  ProviderContainer makeContainer({
    required _CollectionApi api,
    required Stream<String?> owners,
  }) {
    final container = ProviderContainer(
      overrides: [
        practiceChatApiServiceProvider.overrideWithValue(api),
        practiceCollectionOwnerProvider.overrideWith((ref) => owners),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('登入中 → 圖鑑就是 server 說的那份', () async {
    final api = _CollectionApi([
      {'practice_girl_004'}
    ]);
    final container = makeContainer(
      api: api,
      owners: Stream<String?>.value('user-a'),
    );

    final unlocked = await container.read(practiceCollectionProvider.future);

    expect(unlocked, {'practice_girl_004'});
    expect(api.calls, 1);
  });

  test('未登入 → 空集合，且絕不打 server', () async {
    final api = _CollectionApi([
      {'practice_girl_004'}
    ]);
    final container = makeContainer(
      api: api,
      owners: Stream<String?>.value(null),
    );

    expect(await container.read(practiceCollectionProvider.future), isEmpty);
    expect(api.calls, 0);
  });

  test('換帳號 → 整份重抓，絕不沿用上一個帳號的圖鑑', () async {
    final api = _CollectionApi([
      {'practice_girl_004', 'practice_girl_009'},
      {'practice_girl_030'},
    ]);
    final owners = StreamController<String?>();
    addTearDown(owners.close);
    final container = makeContainer(api: api, owners: owners.stream);

    final sub = container.listen(practiceCollectionProvider, (_, __) {});
    addTearDown(sub.close);

    owners.add('user-a');
    expect(
      await container.read(practiceCollectionProvider.future),
      {'practice_girl_004', 'practice_girl_009'},
    );

    owners.add('user-b');
    await pumpEventQueue();
    expect(
      await container.read(practiceCollectionProvider.future),
      {'practice_girl_030'},
    );
    expect(api.calls, 2);
  });

  test('翻牌樂觀 +1；集合還沒載到時不硬造一份只有一張卡的圖鑑', () async {
    final api = _CollectionApi([
      {'practice_girl_004'}
    ]);
    final container = makeContainer(
      api: api,
      owners: Stream<String?>.value('user-a'),
    );
    final notifier = container.read(practiceCollectionProvider.notifier);

    // build 還沒完成（AsyncLoading）→ add 不得偽造集合。
    notifier.add('practice_girl_010');
    expect(container.read(practiceUnlockedProfileIdsProvider), isEmpty);

    await container.read(practiceCollectionProvider.future);
    notifier.add('practice_girl_010');

    expect(container.read(practiceUnlockedProfileIdsProvider),
        {'practice_girl_004', 'practice_girl_010'});
  });

  test('讀取失敗 → error 狀態，絕不謊報空圖鑑；重試成功即補回', () async {
    final api = _CollectionApi([
      Exception('boom'),
      {'practice_girl_004'},
    ]);
    final container = makeContainer(
      api: api,
      owners: Stream<String?>.value('user-a'),
    );
    final sub = container.listen(practiceCollectionProvider, (_, __) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(practiceCollectionProvider.future),
      throwsA(isA<Exception>()),
    );
    // 空集合只是「畫不出格子」的呈現值，狀態本身必須是 error（畫面才會出重試）。
    expect(container.read(practiceCollectionProvider).hasError, true);
    expect(container.read(practiceUnlockedProfileIdsProvider), isEmpty);

    await container.read(practiceCollectionProvider.notifier).refresh();

    expect(container.read(practiceUnlockedProfileIdsProvider),
        {'practice_girl_004'});
  });
}
