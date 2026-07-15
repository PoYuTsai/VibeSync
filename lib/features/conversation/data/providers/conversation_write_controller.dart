// lib/features/conversation/data/providers/conversation_write_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analysis/data/providers/analysis_record_providers.dart';
import '../../../follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../repositories/conversation_archive_store.dart';
import '../repositories/conversation_repository.dart';
import 'conversation_archive_providers.dart';
import 'conversation_providers.dart';

enum ConversationSaveIntent {
  /// 新增／編輯／換邊／刪除訊息：儲存成功後解除封存，避免新內容仍被藏在分析紀錄。
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
    // Reconcile a previously interrupted delete whenever this authenticated
    // write coordinator is (re)created. A live conversation cancels its
    // marker; an absent one finishes record cleanup.
    final ownerUserId = ref.watch(analysisRecordOwnerProvider)?.trim();
    if (ownerUserId == null || ownerUserId.isEmpty) return;
    final recordStore = ref.read(analysisRecordStoreProvider);
    if (!recordStore.hasPendingConversationRemovals(
      ownerUserId: ownerUserId,
    )) {
      return;
    }
    final liveConversationIds = ref
        .read(conversationRepositoryProvider)
        .getAllConversations()
        .map((conversation) => conversation.id)
        .toList(growable: false);
    unawaited(
      recordStore
          .recoverPendingConversationRemovals(
        ownerUserId: ownerUserId,
        liveConversationIds: liveConversationIds,
      )
          .then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Analysis record cleanup recovery failed: $error');
        },
      ),
    );
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
    String? expectedContentRevision,
    DateTime? preservedArchivedAt,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final archiveController =
        ref.read(conversationArchiveControllerProvider.notifier);
    final startedFromExpectedContent =
        intent != ConversationSaveIntent.analysisCompleted ||
            (expectedContentRevision != null &&
                expectedContentRevision == conversationContentRevision(c));
    if (startedFromExpectedContent) {
      await repo.updateConversation(c);
    }
    if (intent == ConversationSaveIntent.contentChanged) {
      // Write the marker after the content save so concurrent saves resolve in
      // persistence order instead of an early active marker being overwritten
      // by an older analysis that finishes later.
      await archiveController.markActive(c);
    } else if (intent == ConversationSaveIntent.analysisCompleted) {
      final hasPersistedSnapshot =
          c.lastAnalysisSnapshotJson?.trim().isNotEmpty == true;
      final analyzedEveryMessage =
          c.lastAnalyzedMessageCount == c.messages.length;
      final analyzedMessageCount = c.lastAnalyzedMessageCount;
      final analyzedMessageCountIsValid = analyzedMessageCount != null &&
          analyzedMessageCount >= 0 &&
          analyzedMessageCount <= c.messages.length;
      final currentContentRevision = conversationContentRevision(c);
      final contentStillMatches = startedFromExpectedContent &&
          expectedContentRevision != null &&
          expectedContentRevision == currentContentRevision;
      if (hasPersistedSnapshot && analyzedEveryMessage && contentStillMatches) {
        await archiveController.markArchived(c);
      } else {
        // Parsed UI without a durable snapshot cannot be restored after an app
        // restart. Partial refreshes and analyses produced from an older
        // message revision must never hide newer content. All cases fail open.
        await archiveController.markActive(
          c,
          analyzedContentRevision: hasPersistedSnapshot &&
                  contentStillMatches &&
                  analyzedMessageCountIsValid
              ? conversationContentRevision(
                  c,
                  messageCount: analyzedMessageCount,
                )
              : null,
        );
      }
    } else if (intent == ConversationSaveIntent.metadataOnly &&
        preservedArchivedAt != null) {
      // Markerless legacy conversations can only be identified before the
      // repository refreshes updatedAt. The archive screen supplies this
      // explicit presentation hint so reassignment preserves its location.
      await archiveController.markArchived(c, archivedAt: preservedArchivedAt);
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
    final ownerUserId = ref.read(analysisRecordOwnerProvider)?.trim();
    if (ownerUserId == null ||
        ownerUserId.isEmpty ||
        c.ownerUserId?.trim() != ownerUserId) {
      throw StateError('Cannot delete a conversation outside the active user.');
    }
    final recordStore = ref.read(analysisRecordStoreProvider);
    final prepared = await recordStore.prepareConversationRemoval(
      ownerUserId: ownerUserId,
      conversationId: c.id,
    );
    if (!prepared) {
      throw StateError('Could not prepare private analysis cleanup.');
    }

    late final ConversationDeleteOutcome deleteOutcome;
    try {
      deleteOutcome = await repo.deleteConversation(c.id);
    } catch (error, stackTrace) {
      try {
        await recordStore.cancelConversationRemoval(
          ownerUserId: ownerUserId,
          conversationId: c.id,
        );
      } catch (cancelError) {
        debugPrint('Analysis cleanup marker cancel failed: $cancelError');
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (!deleteOutcome.deleted) {
      try {
        await recordStore.cancelConversationRemoval(
          ownerUserId: ownerUserId,
          conversationId: c.id,
        );
      } catch (cancelError) {
        debugPrint('Analysis cleanup marker cancel failed: $cancelError');
      }
      throw StateError('Conversation delete was not committed.');
    }
    if (deleteOutcome.deletedOwnerUserId != ownerUserId) {
      // The primary row is already gone, so retain the durable marker for
      // recovery instead of pretending that this was a pre-commit failure.
      throw StateError('Committed conversation owner did not match cleanup.');
    }

    Object? cleanupError = deleteOutcome.cleanupError;
    StackTrace? cleanupStackTrace = deleteOutcome.cleanupStackTrace;
    try {
      await recordStore.removeConversation(
        ownerUserId: ownerUserId,
        conversationId: c.id,
      );
    } catch (error, stackTrace) {
      cleanupError = error;
      cleanupStackTrace = stackTrace;
    }
    try {
      await ref.read(conversationArchiveControllerProvider.notifier).remove(c);
    } catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
    }
    _invalidateConversationDetail(c.id);
    _invalidatePartnerScope(c.partnerId);
    _invalidateLegacyGlobal();
    // 跟進通知以 partnerId 為單位；刪除其中一個獨立片段時，其他片段仍
    // 共用同一個提醒。只有該對象已無任何 conversation 時才取消。
    // best-effort：查詢或通知取消失敗絕不阻擋刪除本身。
    final partnerId = c.partnerId?.trim();
    if (partnerId != null && partnerId.isNotEmpty) {
      try {
        final hasRemainingConversation =
            repo.listByPartner(partnerId).isNotEmpty;
        if (!hasRemainingConversation) {
          await ref
              .read(followUpNotificationServiceProvider)
              .cancelForConversation(partnerId);
        }
      } catch (e) {
        debugPrint('FollowUp cancel on delete failed: $e');
      }
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(
        cleanupError,
        cleanupStackTrace ?? StackTrace.current,
      );
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
