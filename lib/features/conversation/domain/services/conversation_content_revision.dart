/// Durable, privacy-preserving revision of the ordered message input behind
/// the latest restorable analysis snapshot. Markers store only this digest,
/// never conversation text. Metadata-only changes intentionally keep it.
///
/// 跨層共用的 domain 概念（screen／application／data 都要比對它）；
/// 歷史 import 路徑 `conversation_archive_store.dart` 以 re-export 相容。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/conversation.dart';

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
