import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/entities/conversation.dart';
import '../repositories/conversation_archive_store.dart';

final conversationArchiveStoreProvider = Provider<ConversationArchiveStore>(
  (_) => HiveConversationArchiveStore(() => StorageService.settingsBox),
);

/// 單純的 rebuild revision；settingsBox 本身不是 reactive。
class ConversationArchiveController extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> markActive(
    Conversation conversation, {
    String? analyzedContentRevision,
  }) async {
    await _bestEffort(
      () => ref.read(conversationArchiveStoreProvider).markActive(
            conversation,
            analyzedContentRevision: analyzedContentRevision,
          ),
    );
  }

  Future<void> markArchived(
    Conversation conversation, {
    DateTime? archivedAt,
  }) async {
    await _bestEffort(
      () => ref.read(conversationArchiveStoreProvider).markArchived(
            conversation,
            archivedAt: archivedAt ?? DateTime.now(),
          ),
    );
  }

  Future<void> remove(Conversation conversation) async {
    await _bestEffort(
      () => ref.read(conversationArchiveStoreProvider).remove(conversation),
    );
  }

  Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
      state++;
    } catch (error) {
      // 封存是呈現層整理；儲存失敗時 fail open 顯示在目前對話，不阻擋核心寫入。
      debugPrint('Conversation archive marker write failed: $error');
    }
  }
}

final conversationArchiveControllerProvider =
    NotifierProvider<ConversationArchiveController, int>(
  ConversationArchiveController.new,
);
