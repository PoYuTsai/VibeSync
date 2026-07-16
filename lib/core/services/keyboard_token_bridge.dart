import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

abstract class KeyboardCredentialStore {
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyboardCredentialStore implements KeyboardCredentialStore {
  const SecureKeyboardCredentialStore();

  static const _storage = FlutterSecureStorage();
  static const _iosOptions = IOSOptions(
    groupId: KeyboardTokenBridge.accessGroup,
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value, iOptions: _iosOptions);

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: key, iOptions: _iosOptions);
}

@immutable
class KeyboardSessionPayload {
  const KeyboardSessionPayload({
    required this.accessToken,
    required this.userId,
    required this.expiresAtSeconds,
  });

  final String accessToken;
  final String userId;
  final int expiresAtSeconds;
}

class KeyboardTokenBridge {
  KeyboardTokenBridge({required KeyboardCredentialStore store})
      : _store = store;

  static const accessGroup = 'group.com.poyutsai.vibesync';
  static const accessTokenKey = 'vibesync_keyboard_access_token';
  static const userIdKey = 'vibesync_keyboard_user_id';
  static const expiresAtKey = 'vibesync_keyboard_expires_at';

  static KeyboardTokenBridge? _instance;
  static StreamSubscription<AuthState>? _authSubscription;

  final KeyboardCredentialStore _store;
  Future<void> _pendingOperation = Future<void>.value();

  static bool get _supportsKeyboardBridge =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> initializeDefault() async {
    if (!_supportsKeyboardBridge) return;
    final bridge =
        KeyboardTokenBridge(store: const SecureKeyboardCredentialStore());
    _instance = bridge;
    await bridge.syncCurrentSession(refreshIfExpired: true);
    await _authSubscription?.cancel();
    _authSubscription = SupabaseService.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        unawaited(bridge._enqueue(bridge.clear));
        return;
      }
      final payload = _payloadFromSession(state.session);
      if (payload != null) {
        unawaited(bridge._enqueue(() => bridge.sync(payload)));
      }
    });
  }

  static Future<void> syncOnForeground() async {
    await _instance?._enqueue(
      () => _instance!.syncCurrentSession(refreshIfExpired: true),
    );
  }

  Future<void> syncCurrentSession({required bool refreshIfExpired}) async {
    Session? session = SupabaseService.client.auth.currentSession;
    if (refreshIfExpired && session?.isExpired == true) {
      try {
        session = (await SupabaseService.client.auth.refreshSession()).session;
      } catch (error) {
        debugPrint('Keyboard token refresh failed: $error');
      }
    }
    final payload = _payloadFromSession(session);
    if (payload == null) {
      await clear();
    } else {
      await sync(payload);
    }
  }

  @visibleForTesting
  Future<void> sync(KeyboardSessionPayload payload) async {
    // Metadata first, access token last: the extension never observes a new
    // token paired with stale owner/expiry metadata.
    await _store.write(userIdKey, payload.userId);
    await _store.write(expiresAtKey, payload.expiresAtSeconds.toString());
    await _store.write(accessTokenKey, payload.accessToken);
  }

  @visibleForTesting
  Future<void> clear() async {
    // Revoke usability first, then remove non-secret metadata.
    await _store.delete(accessTokenKey);
    await _store.delete(userIdKey);
    await _store.delete(expiresAtKey);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _pendingOperation = _pendingOperation.then((_) => operation()).catchError(
      (Object error, StackTrace stackTrace) {
        debugPrint('Keyboard credential sync failed: $error\n$stackTrace');
      },
    );
    return _pendingOperation;
  }

  static KeyboardSessionPayload? _payloadFromSession(Session? session) {
    final expiresAt = session?.expiresAt;
    if (session == null || expiresAt == null || session.isExpired) return null;
    return KeyboardSessionPayload(
      accessToken: session.accessToken,
      userId: session.user.id,
      expiresAtSeconds: expiresAt,
    );
  }
}
