import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/keyboard_context_snapshot.dart';
import '../../domain/services/keyboard_context_snapshot_builder.dart';
import '../services/keyboard_context_bridge.dart';

final keyboardContextSnapshotBuilderProvider =
    Provider<KeyboardContextSnapshotBuilder>((ref) {
  return KeyboardContextSnapshotBuilder();
});

final keyboardContextBridgeProvider = Provider<KeyboardContextBridge>((ref) {
  return MethodChannelKeyboardContextBridge();
});

final keyboardContextSyncCoordinatorProvider =
    Provider<KeyboardContextSyncCoordinator>((ref) {
  return KeyboardContextSyncCoordinator(
    bridge: ref.watch(keyboardContextBridgeProvider),
  );
});

/// An explicit coordinator rather than an eager listener: no snapshot is
/// published until the app has resolved owner, consent and allowlisted inputs.
class KeyboardContextSyncCoordinator {
  const KeyboardContextSyncCoordinator({required KeyboardContextBridge bridge})
      : _bridge = bridge;

  final KeyboardContextBridge _bridge;

  Future<KeyboardContextPublishResult> publish(
    KeyboardContextSnapshot snapshot,
  ) {
    return _bridge.publish(snapshot);
  }

  Future<void> purge(KeyboardContextPurgeScope scope) => _bridge.purge(scope);
}
