import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/conversation.dart';

enum ConversationArchiveStatus { active, archived }

class ConversationArchiveEntry {
  const ConversationArchiveEntry._({
    required this.status,
    required this.changedAt,
  });

  factory ConversationArchiveEntry.active({required DateTime changedAt}) =>
      ConversationArchiveEntry._(
        status: ConversationArchiveStatus.active,
        changedAt: changedAt,
      );

  factory ConversationArchiveEntry.archived({required DateTime archivedAt}) =>
      ConversationArchiveEntry._(
        status: ConversationArchiveStatus.archived,
        changedAt: archivedAt,
      );

  final ConversationArchiveStatus status;
  final DateTime changedAt;

  DateTime? get archivedAt =>
      status == ConversationArchiveStatus.archived ? changedAt : null;
}

abstract class ConversationArchiveStore {
  ConversationArchiveEntry? entryFor(Conversation conversation);

  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
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
      return switch (status) {
        'active' => ConversationArchiveEntry.active(changedAt: changedAt),
        'archived' => ConversationArchiveEntry.archived(archivedAt: changedAt),
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
  }) =>
      _write(
        conversation,
        status: 'active',
        changedAt: changedAt ?? DateTime.now(),
      );

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) =>
      _write(conversation, status: 'archived', changedAt: archivedAt);

  @override
  Future<void> remove(Conversation conversation) async {
    await _boxProvider().delete(_keyFor(conversation));
  }

  Future<void> _write(
    Conversation conversation, {
    required String status,
    required DateTime changedAt,
  }) async {
    await _boxProvider().put(_keyFor(conversation), <String, String>{
      'status': status,
      'changedAt': changedAt.toUtc().toIso8601String(),
    });
  }

  static String _keyFor(Conversation conversation) {
    final owner = conversation.ownerUserId?.trim();
    final ownerScope = owner == null || owner.isEmpty ? '_legacy' : owner;
    return '$_keyPrefix:$ownerScope:${conversation.id}';
  }
}
