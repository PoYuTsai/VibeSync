// 稽核 #7 前半（2026-08-07）：刪帳號本機清理的重放標記。
// 遠端刪除成功→落 marker→清理完成→收 marker；清理中被強殺→下次啟動
// replayIfNeeded 補完。任一步驟失敗必須保留 marker 讓下次啟動再試。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/account_deletion_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('markPending 存 owner、clearMarker 收走', () async {
    await AccountDeletionCleanup.markPending(ownerUserId: 'user-1');
    expect(
      (await prefs()).getString(AccountDeletionCleanup.markerKey),
      'user-1',
    );

    await AccountDeletionCleanup.clearMarker();
    expect(
      (await prefs()).getString(AccountDeletionCleanup.markerKey),
      isNull,
    );
  });

  test('無 marker → 不執行任何清理步驟', () async {
    var steps = 0;
    await AccountDeletionCleanup.replayIfNeeded(
      purgeKeyboardContext: (_) async => steps++,
      clearLocalStorage: () async => steps++,
      purgeKeyboardCredentials: () async => steps++,
      clearSession: () async => steps++,
      prefsProvider: prefs,
    );
    expect(steps, 0);
  });

  test('有 marker → 依序清理並收 marker，owner 正確帶入', () async {
    await AccountDeletionCleanup.markPending(ownerUserId: 'user-1');

    final order = <String>[];
    String? seenOwner;
    await AccountDeletionCleanup.replayIfNeeded(
      purgeKeyboardContext: (owner) async {
        seenOwner = owner;
        order.add('keyboard');
      },
      clearLocalStorage: () async => order.add('storage'),
      purgeKeyboardCredentials: () async => order.add('credentials'),
      clearSession: () async => order.add('session'),
      prefsProvider: prefs,
    );

    expect(seenOwner, 'user-1');
    expect(order, ['keyboard', 'storage', 'credentials', 'session']);
    expect(
      (await prefs()).getString(AccountDeletionCleanup.markerKey),
      isNull,
    );
  });

  test('無 owner 的 marker 重放時帶 null owner', () async {
    await AccountDeletionCleanup.markPending();

    String? seenOwner = 'sentinel';
    await AccountDeletionCleanup.replayIfNeeded(
      purgeKeyboardContext: (owner) async => seenOwner = owner,
      clearLocalStorage: () async {},
      purgeKeyboardCredentials: () async {},
      clearSession: () async {},
      prefsProvider: prefs,
    );
    expect(seenOwner, isNull);
  });

  test('清理步驟失敗 → marker 保留給下次啟動', () async {
    await AccountDeletionCleanup.markPending(ownerUserId: 'user-1');

    await expectLater(
      AccountDeletionCleanup.replayIfNeeded(
        purgeKeyboardContext: (_) async {},
        clearLocalStorage: () async => throw Exception('disk error'),
        purgeKeyboardCredentials: () async {},
        clearSession: () async {},
        prefsProvider: prefs,
      ),
      throwsException,
    );
    expect(
      (await prefs()).getString(AccountDeletionCleanup.markerKey),
      'user-1',
    );
  });
}
