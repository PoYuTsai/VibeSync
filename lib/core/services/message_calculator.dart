// lib/core/services/message_calculator.dart
import '../constants/app_constants.dart';
import '../../features/conversation/domain/entities/message.dart';

/// Service for calculating message count for billing purposes
class MessageCalculator {
  /// Calculate message count from text
  /// Rules:
  /// - Split by newlines
  /// - Filter empty lines
  /// - Every 200 characters = 1 message
  static int countMessages(String text) {
    if (text.trim().isEmpty) return 0;

    // Split by newlines, filter empty lines
    final lines = text
        .split(RegExp(r'\n+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    int total = 0;
    for (final line in lines) {
      final charCount = line.trim().length;
      // Every 200 chars = 1 message, minimum 1 per line
      total += (charCount / AppConstants.maxCharsPerMessage).ceil().clamp(1, 100);
    }

    return total.clamp(1, 1000);
  }

  /// Calculate billed message count from a conversation payload.
  ///
  /// This mirrors the Edge Function logic:
  /// - each message costs at least 1
  /// - every 200 chars in a message counts as 1 extra billed message
  static int countConversationMessages(List<Message> messages) {
    if (messages.isEmpty) return 0;

    var total = 0;
    for (final message in messages) {
      final charCount = message.content.trim().length;
      if (charCount == 0) {
        continue;
      }
      total +=
          (charCount / AppConstants.maxCharsPerMessage).ceil().clamp(1, 100);
    }

    return total.clamp(0, 1000);
  }

  /// Check if text exceeds single analysis limit
  static bool exceedsMaxLength(String text) {
    return text.length > AppConstants.maxTotalChars;
  }

  /// Get preview of message calculation
  static MessagePreview preview(String text) {
    final count = countMessages(text);
    final exceeds = exceedsMaxLength(text);

    return MessagePreview(
      messageCount: count,
      charCount: text.length,
      exceedsLimit: exceeds,
    );
  }

  /// Build a preview for the actual conversation payload that will be sent.
  static MessagePreview previewConversation(List<Message> messages) {
    final trimmedMessages = messages
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .toList();
    final charCount = trimmedMessages.fold<int>(
      0,
      (total, content) => total + content.length,
    );

    return MessagePreview(
      messageCount: countConversationMessages(messages),
      charCount: charCount,
      exceedsLimit: charCount > AppConstants.maxTotalChars,
    );
  }
}

/// Preview result for message calculation
class MessagePreview {
  final int messageCount;
  final int charCount;
  final bool exceedsLimit;

  const MessagePreview({
    required this.messageCount,
    required this.charCount,
    required this.exceedsLimit,
  });
}
