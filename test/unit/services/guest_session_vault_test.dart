import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/core/services/guest_session_vault.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

class _MockVault extends Mock implements GuestSessionVault {}

User _user({required bool isAnonymous}) => User(
      id: 'uid-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-08-01T00:00:00Z',
      isAnonymous: isAnonymous,
    );

AuthResponse _response({required bool isAnonymous}) {
  final user = _user(isAnonymous: isAnonymous);
  return AuthResponse(
    session: Session(
      accessToken: 'at',
      tokenType: 'bearer',
      refreshToken: 'rt-new',
      user: user,
    ),
  );
}

void main() {
  late _MockStorage storage;
  late GuestSessionVault vault;

  setUp(() {
    storage = _MockStorage();
    vault = GuestSessionVault(storage: storage);
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'tok-1');
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  });

  group('GuestSessionVault（訪客額度綁裝置）', () {
    test('save 寫入 Keychain；同 token 重複 save 只寫一次（記憶體去重）', () async {
      await vault.save('tok-1');
      await vault.save('tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(1);

      await vault.save('tok-2');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-2'))
          .called(1);
    });

    test('save 空字串直接略過', () async {
      await vault.save('');
      verifyNever(
          () => storage.write(key: any(named: 'key'), value: any(named: 'value')));
    });

    test('clear 之後同 token 可再次 save（去重快取歸零）', () async {
      await vault.save('tok-1');
      await vault.clear();
      await vault.save('tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(2);
    });

    test('read 回傳儲存值', () async {
      expect(await vault.read(), 'tok-1');
    });

    test('storage 全炸時 save/read/clear 都吞例外不外拋（best-effort）', () async {
      when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'))).thenThrow(Exception('keychain down'));
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('keychain down'));
      when(() => storage.delete(key: any(named: 'key')))
          .thenThrow(Exception('keychain down'));

      await vault.save('tok-1');
      expect(await vault.read(), isNull);
      await vault.clear();
    });

    test('save 失敗不落去重快取，下次同 token 會重試', () async {
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenThrow(Exception('keychain down'));
      await vault.save('tok-1');

      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      await vault.save('tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(2);
    });

    test('審修 F1：save 串行化——後到的新 token 絕不被先到的慢寫超車', () async {
      final firstWriteStarted = Completer<void>();
      final firstWriteGate = Completer<void>();
      when(() => storage.write(key: any(named: 'key'), value: 'tok-old'))
          .thenAnswer((_) {
        firstWriteStarted.complete();
        return firstWriteGate.future;
      });

      final f1 = vault.save('tok-old');
      final f2 = vault.save('tok-new');
      await firstWriteStarted.future;

      // 舊寫還卡著時，新寫不得開始（否則完成順序可倒轉留下 stale token）。
      verifyNever(() => storage.write(key: any(named: 'key'), value: 'tok-new'));

      firstWriteGate.complete();
      await f1;
      await f2;
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-new'))
          .called(1);
    });

    test('審修 F1：clear 與 save 依呼叫順序執行（linking 清 vault 不被舊 save 蓋回）',
        () async {
      final saveStarted = Completer<void>();
      final saveGate = Completer<void>();
      when(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .thenAnswer((_) {
        saveStarted.complete();
        return saveGate.future;
      });

      final f1 = vault.save('tok-1');
      final f2 = vault.clear();
      await saveStarted.future;
      verifyNever(() => storage.delete(key: any(named: 'key')));

      saveGate.complete();
      await f1;
      await f2;
      verify(() => storage.delete(key: any(named: 'key'))).called(1);
    });

    test('syncAuthSession：匿名＋token → save；匿名＋null token → 不動', () async {
      await vault.syncAuthSession(isAnonymous: true, refreshToken: 'tok-1');
      verify(() => storage.write(key: any(named: 'key'), value: 'tok-1'))
          .called(1);

      await vault.syncAuthSession(isAnonymous: true, refreshToken: null);
      await vault.syncAuthSession(isAnonymous: true, refreshToken: '');
      verifyNever(
          () => storage.write(key: any(named: 'key'), value: any(named: 'value')));
    });

    test('syncAuthSession：非匿名 → clear', () async {
      await vault.syncAuthSession(isAnonymous: false, refreshToken: 'tok-x');
      verify(() => storage.delete(key: any(named: 'key'))).called(1);
      verifyNever(
          () => storage.write(key: any(named: 'key'), value: any(named: 'value')));
    });
  });

  group('GuestSignInFlow（先逛逛狀態機）', () {
    late _MockVault flowVault;
    late List<String> calls;

    GuestSignInFlow buildFlow({
      Future<AuthResponse> Function(String)? restore,
    }) {
      return GuestSignInFlow(
        vault: flowVault,
        restoreSession: restore ??
            (token) async {
              calls.add('restore:$token');
              return _response(isAnonymous: true);
            },
        freshSignIn: () async {
          calls.add('fresh');
          return _response(isAnonymous: true);
        },
        discardSession: () async {
          calls.add('discard');
        },
      );
    }

    setUp(() {
      flowVault = _MockVault();
      calls = [];
      when(() => flowVault.read()).thenAnswer((_) async => 'rt-stored');
      when(() => flowVault.clear()).thenAnswer((_) async {});
    });

    test('vault 空 → 不試復活，直接開新匿名帳號', () async {
      when(() => flowVault.read()).thenAnswer((_) async => null);
      await buildFlow().signIn();
      expect(calls, ['fresh']);
      verifyNever(() => flowVault.clear());
    });

    test('復活成功且匿名 → 回傳復活 session，不開新帳、不清 vault', () async {
      final result = await buildFlow().signIn();
      expect(result.user?.isAnonymous, isTrue);
      expect(calls, ['restore:rt-stored']);
      verifyNever(() => flowVault.clear());
    });

    test('審修 F2：復活到非匿名帳 → 退出該 session＋清 vault＋開新匿名帳',
        () async {
      final flow = buildFlow(
        restore: (token) async {
          calls.add('restore:$token');
          return _response(isAnonymous: false);
        },
      );
      final result = await flow.signIn();
      expect(result.user?.isAnonymous, isTrue);
      expect(calls, ['restore:rt-stored', 'discard', 'fresh']);
      verify(() => flowVault.clear()).called(1);
    });

    test('token 真死（AuthException 4xx）→ 清 vault＋開新匿名帳', () async {
      final flow = buildFlow(
        restore: (_) async =>
            throw const AuthException('invalid', statusCode: '400'),
      );
      final result = await flow.signIn();
      expect(result.user?.isAnonymous, isTrue);
      expect(calls, ['fresh']);
      verify(() => flowVault.clear()).called(1);
    });

    test('審修 GLM P1：網路類錯誤（AuthRetryableFetchException）→ 外拋、保 vault、不開新帳',
        () async {
      final flow = buildFlow(
        restore: (_) async =>
            throw AuthRetryableFetchException(message: 'net down'),
      );
      await expectLater(flow.signIn(), throwsA(isA<AuthException>()));
      expect(calls, isEmpty);
      verifyNever(() => flowVault.clear());
    });

    test('審修 GLM P1：AuthException 5xx → 外拋、保 vault', () async {
      final flow = buildFlow(
        restore: (_) async =>
            throw const AuthException('server down', statusCode: '503'),
      );
      await expectLater(flow.signIn(), throwsA(isA<AuthException>()));
      verifyNever(() => flowVault.clear());
    });

    test('審修 GLM P1：非 Auth 例外（如 socket）→ 外拋、保 vault、不開新帳',
        () async {
      final flow = buildFlow(
        restore: (_) async => throw const SocketExceptionLike('net'),
      );
      await expectLater(flow.signIn(), throwsA(isA<SocketExceptionLike>()));
      expect(calls, isEmpty);
      verifyNever(() => flowVault.clear());
    });
  });
}

/// 模擬非 Auth 的傳輸層例外（不引入 dart:io 依賴）。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
}
