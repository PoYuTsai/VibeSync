// lib/features/conversation/data/providers/conversation_write_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import 'conversation_archive_providers.dart';
import 'conversation_providers.dart';

enum ConversationSaveIntent {
  /// 新增／編輯／換邊／刪除訊息：先解除封存，避免新內容仍被藏在分析紀錄。
  contentChanged,

  /// 成功分析快照已落盤：寫入封存 marker。
  analysisCompleted,

  /// 只改 partnerId 等 metadata：保留既有封存狀態。
  metadataOnly,
}

/// Single invalidation owner for all conversation writes.
///
/// **Narrow contract (HS-A2-1, locked 2026-04-26 by Eric)**:
/// - Cross-partner fan-out is forbidden: writing partner X must NOT
///   invalidate `partnerAggregateProvider(Y)`.
/// - `conversationsByPartnerProvider(partnerId)` and
///   `partnerAggregateProvider(partnerId)` are invalidated for the touched
///   partner(s) only.
/// - `conversationsProvider` (global feed) is also invalidated on every
///   write — this is an A2 transition contract so legacy consumers
///   (`reportDataProvider` watches it) stay fresh. Retired in the post-A2
///   cleanup PR (see plan §「Post-A2 cleanup」).
///
/// All A2 conversation writes (create / update / delete / reassign) MUST
/// go through this controller. Direct `repository.{create,update,delete}
/// Conversation` calls outside this file + the repository + tests are a
/// contract violation; verification gate greps for them.
class ConversationWriteController extends Notifier<void> {
  @override
  void build() {
    // Stateless write coordinator.
  }

  Future<Conversation> create({
    required String name,
    required List<Message> messages,
    String? partnerId,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final c = await repo.createConversation(
      name: name,
      messages: messages,
      partnerId: partnerId,
    );
    await ref
        .read(conversationArchiveControllerProvider.notifier)
        .markActive(c);
    _invalidateConversationDetail(c.id);
    _invalidatePartnerScope(partnerId);
    _invalidateLegacyGlobal();
    return c;
  }

  Future<void> save(
    Conversation c, {
    String? previousPartnerId,
    ConversationSaveIntent intent = ConversationSaveIntent.contentChanged,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    if (intent == ConversationSaveIntent.contentChanged) {
      await ref
          .read(conversationArchiveControllerProvider.notifier)
          .markActive(c);
    }
    await repo.updateConversation(c);
    if (intent == ConversationSaveIntent.analysisCompleted) {
      await ref
          .read(conversationArchiveControllerProvider.notifier)
          .markArchived(c);
    }
    _invalidateConversationDetail(c.id);
    _invalidatePartnerScope(c.partnerId);
    if (previousPartnerId != null && previousPartnerId != c.partnerId) {
      _invalidatePartnerScope(previousPartnerId);
    }
    _invalidateLegacyGlobal();
  }

  Future<void> delete(Conversation c) async {
    final repo = ref.read(conversationRepositoryProvider);
    await repo.deleteConversation(c.id);
    await ref.read(conversationArchiveControllerProvider.notifier).remove(c);
    _invalidateConversationDetail(c.id);
    _invalidatePartnerScope(c.partnerId);
    _invalidateLegacyGlobal();
    // 案4：刪 conversation 後取消該對象待發的 48h 跟進通知。
    // best-effort：通知取消失敗絕不阻擋刪除本身（例如通知層未 wire 的測試環境）。
    try {
      await ref
          .read(followUpNotificationServiceProvider)
          .cancelForConversation(c.partnerId);
    } catch (e) {
      debugPrint('FollowUp cancel on delete failed: $e');
    }
  }

  void _invalidateConversationDetail(String id) {
    ref.invalidate(conversationProvider(id));
  }

  /// Narrow partner-scoped invalidate. Null partnerId = legacy / unmigrated
  /// conversation — no partner-scoped providers to invalidate.
  ///
  /// `dataQualityFlagProvider` (Spec 3 Task 17) is invalidated alongside the
  /// other partner-scoped providers so the data-quality banner re-evaluates
  /// after every save / delete / addNew touching this partner.
  void _invalidatePartnerScope(String? partnerId) {
    if (partnerId == null) return;
    ref.invalidate(conversationsByPartnerProvider(partnerId));
    ref.invalidate(partnerAggregateProvider(partnerId));
    ref.invalidate(dataQualityFlagProvider(partnerId));
  }

  /// A2 transition contract; retired in the post-A2 cleanup PR once
  /// reportDataProvider migrates off the global feed.
  void _invalidateLegacyGlobal() {
    ref.invalidate(conversationsProvider);
  }
}

final conversationWriteControllerProvider =
    NotifierProvider<ConversationWriteController, void>(
  ConversationWriteController.new,
);
