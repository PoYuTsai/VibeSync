import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/conversation.dart';

enum ConversationArchiveStatus { active, archived }

class ConversationArchiveEntry {
  const ConversationArchiveEntry._({
    required this.status,
    required this.changedAt,
    this.contentRevision,
  });

  factory ConversationArchiveEntry.active({
    required DateTime changedAt,
    String? contentRevision,
  }) =>
      ConversationArchiveEntry._(
        status: ConversationArchiveStatus.active,
        changedAt: changedAt,
        contentRevision: contentRevision,
      );

  factory ConversationArchiveEntry.archived({
    required DateTime archivedAt,
    String? contentRevision,
  }) =>
      ConversationArchiveEntry._(
        status: ConversationArchiveStatus.archived,
        changedAt: archivedAt,
        contentRevision: contentRevision,
      );

  final ConversationArchiveStatus status;
  final DateTime changedAt;
  final String? contentRevision;

  DateTime? get archivedAt =>
      status == ConversationArchiveStatus.archived ? changedAt : null;
}

abstract class ConversationArchiveStore {
  ConversationArchiveEntry? entryFor(Conversation conversation);

  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  });

  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  });

  Future<void> remove(Conversation conversation);
}

/// 不加 Conversation HiveField：封存狀態放在既有 AES-encrypted settings box。
/// key 同時含 owner scope，避免切換帳號後讀到另一位使用者的狀態。
class HiveConversationArchiveStore implements ConversationArchiveStore {
  HiveConversationArchiveStore(this._boxProvider);

  static const _keyPrefix = 'conversation_archive_v1';
  final Box<dynamic> Function() _boxProvider;

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) {
    try {
      final raw = _boxProvider().get(_keyFor(conversation));
      if (raw is! Map) return null;
      final status = raw['status'];
      final changedAtRaw = raw['changedAt'];
      if (status is! String || changedAtRaw is! String) return null;
      final changedAt = DateTime.tryParse(changedAtRaw);
      if (changedAt == null) return null;
      final contentRevisionRaw = raw['contentRevision'];
      final contentRevision =
          contentRevisionRaw is String && contentRevisionRaw.trim().isNotEmpty
              ? contentRevisionRaw
              : null;
      return switch (status) {
        'active' => ConversationArchiveEntry.active(
            changedAt: changedAt,
            contentRevision: contentRevision,
          ),
        'archived' => ConversationArchiveEntry.archived(
            archivedAt: changedAt,
            contentRevision: contentRevision,
          ),
        _ => null,
      };
    } catch (_) {
      // Box 尚未開啟／壞資料都 fail open 到 active，絕不誤藏對話。
      return null;
    }
  }

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) {
    final preservedRevision =
        analyzedContentRevision ?? entryFor(conversation)?.contentRevision;
    return _write(
      conversation,
      status: 'active',
      changedAt: changedAt ?? DateTime.now(),
      contentRevision: preservedRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) =>
      _write(
        conversation,
        status: 'archived',
        changedAt: archivedAt,
        contentRevision: conversationContentRevision(conversation),
      );

  @override
  Future<void> remove(Conversation conversation) async {
    await _boxProvider().delete(_keyFor(conversation));
  }

  Future<void> _write(
    Conversation conversation, {
    required String status,
    required DateTime changedAt,
    String? contentRevision,
  }) async {
    await _boxProvider().put(_keyFor(conversation), <String, String>{
      'status': status,
      'changedAt': changedAt.toUtc().toIso8601String(),
      if (contentRevision != null) 'contentRevision': contentRevision,
    });
  }

  static String _keyFor(Conversation conversation) {
    final owner = conversation.ownerUserId?.trim();
    final ownerScope = owner == null || owner.isEmpty ? '_legacy' : owner;
    return '$_keyPrefix:$ownerScope:${conversation.id}';
  }
}

/// Durable, privacy-preserving revision of the ordered message input behind
/// the latest restorable analysis snapshot. Markers store only this digest,
/// never conversation text. Metadata-only changes intentionally keep it.
String conversationContentRevision(
  Conversation conversation, {
  int? messageCount,
}) {
  final messages = messageCount == null
      ? conversation.messages
      : conversation.messages.take(messageCount);
  final canonicalMessages = messages
      .map((message) => <Object?>[
            message.id,
            message.content,
            message.isFromMe,
            message.quotedReplyPreview,
            message.quotedReplyPreviewIsFromMe,
          ])
      .toList(growable: false);
  return sha256.convert(utf8.encode(jsonEncode(canonicalMessages))).toString();
}
