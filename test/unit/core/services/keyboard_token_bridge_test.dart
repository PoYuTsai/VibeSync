import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/core/services/keyboard_token_bridge.dart';

class _MemoryKeyboardStore implements KeyboardCredentialStore {
  final values = <String, String>{};
  final operations = <String>[];

  @override
  Future<String?> read(String key) async {
    operations.add('read:$key');
    return values[key];
  }

  @override
  Future<void> delete(String key) async {
    operations.add('delete:$key');
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    operations.add('deleteAll');
    values.clear();
  }

  @override
  Future<void> write(String key, String value) async {
    operations.add('write:$key');
    values[key] = value;
  }
}

void main() {
  test('sync publishes owner and expiry before access token', () async {
    final store = _MemoryKeyboardStore();
    final bridge = KeyboardTokenBridge(store: store);

    await bridge.sync(
      const KeyboardSessionPayload(
        accessToken: 'token',
        userId: 'owner-1',
        expiresAtSeconds: 1900000000,
      ),
    );

    expect(store.values[KeyboardTokenBridge.accessTokenKey], 'token');
    expect(store.values[KeyboardTokenBridge.userIdKey], 'owner-1');
    expect(store.operations, [
      'write:${KeyboardTokenBridge.userIdKey}',
      'write:${KeyboardTokenBridge.expiresAtKey}',
      'write:${KeyboardTokenBridge.accessTokenKey}',
    ]);
  });

  test('ordinary clear preserves pending replay metadata', () async {
    final store = _MemoryKeyboardStore()
      ..values[KeyboardTokenBridge.accessTokenKey] = 'token'
      ..values['pending_fingerprint'] = 'opaque';
    final bridge = KeyboardTokenBridge(store: store);

    await bridge.clear();

    expect(store.operations, [
      'delete:${KeyboardTokenBridge.accessTokenKey}',
      'delete:${KeyboardTokenBridge.userIdKey}',
      'delete:${KeyboardTokenBridge.expiresAtKey}',
      'delete:${KeyboardTokenBridge.quotaExceededKey}',
    ]);
    expect(store.values, {'pending_fingerprint': 'opaque'});
  });

  test('quota signal is consumed only once', () async {
    final store = _MemoryKeyboardStore()
      ..values[KeyboardTokenBridge.quotaExceededKey] = 'owner-1';
    final bridge = KeyboardTokenBridge(store: store);

    expect(
      await bridge.consumeQuotaExceededSignalForTesting('owner-1'),
      isTrue,
    );
    expect(
      await bridge.consumeQuotaExceededSignalForTesting('owner-1'),
      isFalse,
    );
    expect(store.values, isEmpty);
  });

  test('quota signal from another account is ignored and consumed', () async {
    final store = _MemoryKeyboardStore()
      ..values[KeyboardTokenBridge.quotaExceededKey] = 'owner-1';
    final bridge = KeyboardTokenBridge(store: store);

    expect(
      await bridge.consumeQuotaExceededSignalForTesting('owner-2'),
      isFalse,
    );
    expect(store.values, isEmpty);
  });

  // 18+ 年齡確認（AGE-01）：帳號還沒確認成年，鍵盤拿不到 token、已經有的也清掉，
  // 鍵盤的 AI 回覆跟 App 一起鎖住（伺服器那邊的鍵盤檢查等全開時再接）。
  group('auth events and the age gate', () {
    const at = '2026-10-30T08:00:00.000Z';
    Session session(Map<String, dynamic> appMetadata, {int? expiresAt}) =>
        Session(
          accessToken: 'token',
          tokenType: 'bearer',
          user: User(
            id: 'owner-1',
            appMetadata: appMetadata,
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: at,
          ),
        )..expiresAt = expiresAt ?? 1900000000;
    _MemoryKeyboardStore withToken() => _MemoryKeyboardStore()
      ..values[KeyboardTokenBridge.accessTokenKey] = 'old-token'
      ..values[KeyboardTokenBridge.userIdKey] = 'owner-1';

    test('confirmed adult: token synced', () async {
      final store = _MemoryKeyboardStore();
      await KeyboardTokenBridge(store: store).handleAuthState(
        AuthState(
          AuthChangeEvent.tokenRefreshed,
          session(const {
            'age_gate': {'result': 'adult', 'policy': 1, 'at': at},
          }),
        ),
      );

      expect(store.values[KeyboardTokenBridge.accessTokenKey], 'token');
    });

    for (final (label, metadata) in <(String, Map<String, dynamic>)>[
      ('no age record yet', const {'provider': 'apple'}),
      (
        'recorded as a minor',
        const {
          'age_gate': {'result': 'minor', 'policy': 1, 'at': at},
        },
      ),
    ]) {
      test('$label: no token for the keyboard, existing one cleared', () async {
        final store = withToken();
        await KeyboardTokenBridge(store: store).handleAuthState(
          AuthState(AuthChangeEvent.signedIn, session(metadata)),
        );

        expect(store.values[KeyboardTokenBridge.accessTokenKey], isNull);
        expect(store.values[KeyboardTokenBridge.userIdKey], isNull);
      });
    }

    test('signed out: cleared', () async {
      final store = withToken();
      await KeyboardTokenBridge(store: store)
          .handleAuthState(const AuthState(AuthChangeEvent.signedOut, null));

      expect(store.values[KeyboardTokenBridge.accessTokenKey], isNull);
    });

    test('startup or foreground: synced only for a confirmed adult', () async {
      final adultStore = _MemoryKeyboardStore();
      await KeyboardTokenBridge(store: adultStore).applyCurrentSession(
        session(const {
          'age_gate': {'result': 'adult', 'policy': 1, 'at': at},
        }),
      );
      expect(adultStore.values[KeyboardTokenBridge.accessTokenKey], 'token');

      for (final current in [
        session(const {}),
        session(const {
          'age_gate': {'result': 'minor', 'policy': 1, 'at': at},
        }),
        null,
      ]) {
        final store = withToken();
        await KeyboardTokenBridge(store: store).applyCurrentSession(current);
        expect(store.values[KeyboardTokenBridge.accessTokenKey], isNull);
      }
    });

    test('no session or an expired one: left as it was', () async {
      final store = withToken();
      final bridge = KeyboardTokenBridge(store: store);
      await bridge.handleAuthState(
        const AuthState(AuthChangeEvent.initialSession, null),
      );
      await bridge.handleAuthState(
        AuthState(
          AuthChangeEvent.tokenRefreshed,
          session(const {}, expiresAt: 1000000000),
        ),
      );

      expect(store.operations, isEmpty);
      expect(store.values[KeyboardTokenBridge.accessTokenKey], 'old-token');
    });
  });
}
