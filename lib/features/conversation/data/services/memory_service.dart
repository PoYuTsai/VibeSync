// lib/features/conversation/data/services/memory_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/message.dart';

/// Service for managing conversation memory and context
/// Handles: context preparation, choice inference, summary generation
class MemoryService {
  /// Maximum rounds to keep as full messages
  static const int maxRecentRounds = 15;

  /// Prepare AI analysis context
  /// Recent 15 rounds complete + older summaries
  String prepareContext(Conversation conversation) {
    final buffer = StringBuffer();

    // Add session context if available
    if (conversation.sessionContext != null) {
      final ctx = conversation.sessionContext!;
      buffer.writeln('【對話情境】');
      buffer.writeln('認識場景: ${_meetingContextToString(ctx.meetingContext)}');
      buffer.writeln('認識多久: ${_durationToString(ctx.acquaintanceDuration)}');
      buffer.writeln('目標: ${_goalToString(ctx.userGoal)}');
      buffer.writeln('---');
    }

    // Add historical summaries if available
    if (conversation.summaries?.isNotEmpty ?? false) {
      buffer.writeln('【歷史摘要】');
      for (final summary in conversation.summaries!) {
        buffer.writeln(summary.content);
        if (summary.keyTopics.isNotEmpty) {
          buffer.writeln('關鍵話題: ${summary.keyTopics.join(", ")}');
        }
        if (summary.sharedInterests.isNotEmpty) {
          buffer.writeln('共同興趣: ${summary.sharedInterests.join(", ")}');
        }
      }
      buffer.writeln('---');
    }

    // Add recent messages
    final recentMessages = conversation.getRecentMessages(maxRecentRounds);
    if (recentMessages.isNotEmpty) {
      buffer.writeln('【最近對話】');
      for (final msg in recentMessages) {
        buffer.writeln('${msg.isFromMe ? "我" : "她"}: ${msg.content}');
      }
    }

    return buffer.toString();
  }

  /// Infer which reply type user chose
  /// Analyzes their reply to guess what user said
  /// Returns null if cannot determine (may need to ask user)
  String? inferUserChoice(
    Message theirReply,
    Map<String, String> previousSuggestions,
  ) {
    final content = theirReply.content.toLowerCase();

    // Score each suggestion based on keyword overlap
    String? bestMatch;
    int bestScore = 0;

    for (final entry in previousSuggestions.entries) {
      final keywords = _extractKeywords(entry.value);
      int score = 0;

      for (final keyword in keywords) {
        if (content.contains(keyword.toLowerCase())) {
          score++;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = entry.key;
      }
    }

    // Require at least 2 keyword matches to be confident
    return bestScore >= 2 ? bestMatch : null;
  }

  /// Extract meaningful keywords from text
  List<String> _extractKeywords(String text) {
    // Remove punctuation, keep Chinese characters and alphanumeric
    final cleaned = text.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ');

    // Split and filter short words
    return cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet()
        .toList();
  }

  /// Generate summary for older messages
  /// Called in background when conversation exceeds threshold
  Future<ConversationSummary> generateSummary(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) async {
    // TODO: Call AI to generate actual summary
    // For MVP, create a placeholder summary
    return ConversationSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      roundsCovered: toRound - fromRound,
      content: _generatePlaceholderSummary(conversation, fromRound, toRound),
      keyTopics: _extractTopicsFromMessages(conversation, fromRound, toRound),
      sharedInterests: [],
      relationshipStage: _guessRelationshipStage(conversation),
      createdAt: DateTime.now(),
    );
  }

  /// Generate a simple placeholder summary
  String _generatePlaceholderSummary(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) {
    final messageCount = (toRound - fromRound) * 2;
    return '對話進行了 $messageCount 則訊息，涵蓋第 $fromRound 到 $toRound 輪。';
  }

  /// Extract key topics from message range
  List<String> _extractTopicsFromMessages(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) {
    // Simple extraction: find frequently used non-trivial words
    final wordCount = <String, int>{};
    final startIndex = fromRound * 2;
    final endIndex = (toRound * 2).clamp(0, conversation.messages.length);

    for (int i = startIndex; i < endIndex && i < conversation.messages.length; i++) {
      final keywords = _extractKeywords(conversation.messages[i].content);
      for (final keyword in keywords) {
        if (keyword.length >= 2) {
          wordCount[keyword] = (wordCount[keyword] ?? 0) + 1;
        }
      }
    }

    // Return top 5 most frequent topics
    final sorted = wordCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(5).map((e) => e.key).toList();
  }

  /// Guess relationship stage based on conversation content
  String _guessRelationshipStage(Conversation conversation) {
    if (conversation.currentRound < 5) {
      return 'initial';
    } else if (conversation.currentRound < 15) {
      return 'getting_to_know';
    } else if (conversation.currentRound < 30) {
      return 'rapport';
    } else {
      return 'established';
    }
  }

  String _meetingContextToString(dynamic context) {
    if (context == null) return '未設定';
    return context.toString().split('.').last;
  }

  String _durationToString(dynamic duration) {
    if (duration == null) return '未設定';
    return duration.toString().split('.').last;
  }

  String _goalToString(dynamic goal) {
    if (goal == null) return '未設定';
    return goal.toString().split('.').last;
  }
}

/// Provider for MemoryService
final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});
