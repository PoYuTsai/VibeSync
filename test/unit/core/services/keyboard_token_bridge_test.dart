import 'package:flutter_test/flutter_test.dart';
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

  test('clear revokes access token before metadata', () async {
    final store = _MemoryKeyboardStore();
    final bridge = KeyboardTokenBridge(store: store);

    await bridge.clear();

    expect(
        store.operations.first, 'delete:${KeyboardTokenBridge.accessTokenKey}');
    expect(store.values, isEmpty);
  });

  test('quota signal is consumed only once', () async {
    final store = _MemoryKeyboardStore()
      ..values[KeyboardTokenBridge.quotaExceededKey] = '1';
    final bridge = KeyboardTokenBridge(store: store);

    expect(await bridge.consumeQuotaExceededSignalForTesting(), isTrue);
    expect(await bridge.consumeQuotaExceededSignalForTesting(), isFalse);
    expect(store.values, isEmpty);
  });
}
