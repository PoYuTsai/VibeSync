// test/unit/features/night_market/data/night_market_watch_store_test.dart
//
// 夜市「看完過一次」的本機紀錄（Eric 2026-10-28：學習頁的「查看復盤」要先看完
// 影片）。重點：綁帳號、沒帳號不寫、重複記不改第一次的時間、讀不到當沒看完、
// 換帳號跟著重算、寫入途中換帳號不把「看完」發布給新帳號。
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/night_market/data/night_market_watch_store.dart';
import 'package:vibesync/features/night_market/presentation/night_market_essential_gate.dart';
import 'package:vibesync/features/night_market/presentation/night_market_watch_gate.dart';

const _testHivePath = './.dart_tool/test_hive_night_market_watch';
const _testBoxName = 'test_night_market_watch_settings';

void main() {
  group('HiveNightMarketWatchStore', () {
    setUpAll(() {
      Hive.init(_testHivePath);
    });

    late Box box;
    late HiveNightMarketWatchStore store;

    setUp(() async {
      box = await Hive.openBox(_testBoxName);
      store = HiveNightMarketWatchStore(
        box,
        now: () => DateTime.utc(2026, 10, 28, 12),
      );
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    tearDownAll(() async {
      await Hive.close();
      final dir = Directory(_testHivePath);
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('看完記在這個帳號底下，別的帳號還是沒看完', () async {
      expect(store.hasWatched('user-a'), isFalse);

      await store.markWatched('user-a');

      expect(store.hasWatched('user-a'), isTrue);
      expect(store.hasWatched('user-b'), isFalse);
      expect(
        box.get('night_market_watched_v1:user-a'),
        '2026-10-28T12:00:00.000Z',
      );
    });

    test('沒有帳號：不寫入、讀到沒看完', () async {
      await store.markWatched('  ');

      expect(box.isEmpty, isTrue);
      expect(store.hasWatched(null), isFalse);
      expect(store.hasWatched(''), isFalse);
    });

    test('重複記不改第一次看完的時間；帳號前後空白算同一個', () async {
      await store.markWatched(' user-a ');
      await HiveNightMarketWatchStore(
        box,
        now: () => DateTime.utc(2026, 11, 1),
      ).markWatched('user-a');

      expect(store.hasWatched('user-a'), isTrue);
      expect(
        box.get('night_market_watched_v1:user-a'),
        '2026-10-28T12:00:00.000Z',
      );
    });

    test('存的不是字串（壞資料）當沒看完', () async {
      await box.put('night_market_watched_v1:user-a', 42);

      expect(store.hasWatched('user-a'), isFalse);
    });
  });

  group('nightMarketWatchedProvider', () {
    ProviderContainer containerFor(
      Stream<String?> Function() accounts,
      NightMarketWatchStore store,
    ) {
      final container = ProviderContainer(overrides: [
        nightMarketAccountIdProvider.overrideWith((ref) => accounts()),
        nightMarketWatchStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(nightMarketWatchedProvider, (_, __) {});
      addTearDown(sub.close);
      return container;
    }

    test('跟著帳號：A 看完過，換成 B 就是沒看完', () async {
      final changes = StreamController<String?>.broadcast();
      addTearDown(changes.close);
      Stream<String?> accounts() async* {
        yield 'user-a';
        yield* changes.stream;
      }

      final container = containerFor(
        accounts,
        InMemoryNightMarketWatchStore(watchedAccounts: ['user-a']),
      );
      expect(await container.read(nightMarketWatchedProvider.future), isTrue);

      changes.add('user-b');
      await pumpEventQueue();

      expect(await container.read(nightMarketWatchedProvider.future), isFalse);
    });

    test('markWatched 記在目前帳號底下，馬上變成看完', () async {
      final store = InMemoryNightMarketWatchStore();
      final container = containerFor(() => Stream.value('user-a'), store);
      expect(await container.read(nightMarketWatchedProvider.future), isFalse);

      await container.read(nightMarketWatchedProvider.notifier).markWatched();

      expect(store.watchedAccounts, {'user-a'});
      expect(container.read(nightMarketWatchedProvider).valueOrNull, isTrue);
    });

    test('沒登入：markWatched 不寫入，維持沒看完', () async {
      final store = InMemoryNightMarketWatchStore();
      final container = containerFor(() => Stream.value(null), store);
      expect(await container.read(nightMarketWatchedProvider.future), isFalse);

      await container.read(nightMarketWatchedProvider.notifier).markWatched();

      expect(store.watchedAccounts, isEmpty);
      expect(container.read(nightMarketWatchedProvider).valueOrNull, isFalse);
    });

    test('讀紀錄失敗當沒看完（fail closed）', () async {
      final container =
          containerFor(() => Stream.value('user-a'), _ThrowingStore());

      expect(await container.read(nightMarketWatchedProvider.future), isFalse);
    });

    test('寫入途中換了帳號：記在原帳號底下，但不把「看完」發布給新帳號', () async {
      final changes = StreamController<String?>.broadcast();
      addTearDown(changes.close);
      Stream<String?> accounts() async* {
        yield 'user-a';
        yield* changes.stream;
      }

      final store = _SwitchDuringWriteStore(() async {
        changes.add('user-b');
        await pumpEventQueue();
      });
      final container = containerFor(accounts, store);
      expect(await container.read(nightMarketWatchedProvider.future), isFalse);

      await container.read(nightMarketWatchedProvider.notifier).markWatched();

      expect(store.inner.watchedAccounts, {'user-a'});
      expect(await container.read(nightMarketWatchedProvider.future), isFalse);
    });
  });
}

class _ThrowingStore implements NightMarketWatchStore {
  @override
  bool hasWatched(String? accountId) => throw StateError('box closed');

  @override
  Future<void> markWatched(String accountId) async =>
      throw StateError('box closed');
}

/// 寫入當下觸發換帳號，模擬「看完那一刻剛好登出換人」。
class _SwitchDuringWriteStore implements NightMarketWatchStore {
  _SwitchDuringWriteStore(this._duringWrite);

  final Future<void> Function() _duringWrite;
  final inner = InMemoryNightMarketWatchStore();

  @override
  bool hasWatched(String? accountId) => inner.hasWatched(accountId);

  @override
  Future<void> markWatched(String accountId) async {
    await inner.markWatched(accountId);
    await _duringWrite();
  }
}
