import 'package:flutter/services.dart';

import '../../domain/entities/keyboard_context_snapshot.dart';

abstract class KeyboardContextChannel {
  Future<Object?> invoke(String method, [Object? arguments]);
}

class FlutterKeyboardContextChannel implements KeyboardContextChannel {
  const FlutterKeyboardContextChannel();

  static const MethodChannel _channel = MethodChannel(
    'vibesync/keyboard_context',
  );

  @override
  Future<Object?> invoke(String method, [Object? arguments]) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }
}

enum KeyboardContextPurgeScope { logout, consentRevoked, accountDeletion }

extension on KeyboardContextPurgeScope {
  String get wireName => switch (this) {
        KeyboardContextPurgeScope.logout => 'logout',
        KeyboardContextPurgeScope.consentRevoked => 'consent_revoked',
        KeyboardContextPurgeScope.accountDeletion => 'account_deletion',
      };

  bool get purgePendingReplayIdentity =>
      this == KeyboardContextPurgeScope.accountDeletion;
}

class KeyboardContextPublishResult {
  const KeyboardContextPublishResult({required this.storedRevision});

  final String storedRevision;
}

abstract class KeyboardContextBridge {
  Future<KeyboardContextPublishResult> publish(
    KeyboardContextSnapshot snapshot,
  );

  Future<void> purge(KeyboardContextPurgeScope scope);
}

class MethodChannelKeyboardContextBridge implements KeyboardContextBridge {
  MethodChannelKeyboardContextBridge({
    KeyboardContextChannel channel = const FlutterKeyboardContextChannel(),
  }) : _channel = channel;

  final KeyboardContextChannel _channel;

  @override
  Future<KeyboardContextPublishResult> publish(
    KeyboardContextSnapshot snapshot,
  ) async {
    final response = await _channel.invoke('writeSnapshot', snapshot.toJson());
    if (response is! Map) {
      throw StateError('keyboard context bridge returned an invalid response');
    }
    final revision = response['storedRevision'];
    if (revision is! String || revision != snapshot.revision) {
      throw StateError('keyboard context bridge revision mismatch');
    }
    return KeyboardContextPublishResult(storedRevision: revision);
  }

  @override
  Future<void> purge(KeyboardContextPurgeScope scope) async {
    await _channel.invoke('purgeContext', {
      'scope': scope.wireName,
      'purgePendingReplayIdentity': scope.purgePendingReplayIdentity,
    });
  }
}
